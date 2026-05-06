# Queue and Event Design

CareAgent should use a transactional outbox in PostgreSQL and Redis Streams, SQS, Pub/Sub, or a comparable durable queue for workers. API handlers write domain state and `outbox_events` rows in the same database transaction. A publisher worker moves pending outbox rows to queues and marks them published.

## Migration Coverage Notes

- `001_initial_backend_platform.sql` owns core API state: auth identities, user accounts, patient profiles, patient access grants, consent ledger, contacts, devices, partitioned observations, object-storage document metadata, medicines, risk events, alerts, escalation policies/runs/actions, conversations, agent tool calls, idempotency keys, outbox events, audit logs, and RLS policies.
- `002_health_device_integrations.sql` extends the base with metric catalog, normalization rules, BLE profile catalog, connector definitions, connector accounts, sync runs, freshness/quality assessments, normalization errors, and simulator scenarios.
- `003_channels_calls_escalation.sql` extends the base with provider configs, channel account links, approved message templates, approved call scripts, dispatch attempts, delivery receipts, call events, escalation acknowledgements, and escalation simulation runs.
- The FastAPI migration runner must apply the three files in order and fail startup if the observed database lacks required RLS policies, observation partition indexes, audit immutability trigger, or idempotency/outbox uniqueness constraints.
- A partition maintenance job must create future observation partitions with the same `(patient_id, metric_code, observed_at desc)` and BRIN indexes as the default partition, or use TimescaleDB hypertables with equivalent query plans.

## Queue Names

| Queue | Producers | Consumers | Purpose |
| --- | --- | --- | --- |
| `careagent.observation.ingest` | API, device connectors, channel OCR/manual entry | Observation normalizer | Normalize units, dedupe readings, create partitioned observations. |
| `careagent.risk.evaluate` | Observation worker, medicine worker, device freshness worker | Risk engine | Evaluate deterministic rules and create risk events/alerts. |
| `careagent.document.scan` | Document upload API, storage event webhook | Malware scanner | Scan raw object-storage files before OCR or download. |
| `careagent.document.ocr` | Malware scanner | OCR worker | OCR clean documents and store OCR artifacts. |
| `careagent.document.extract` | OCR worker | Extraction worker | Classify documents and extract facts with provenance. |
| `careagent.document.index` | Extraction review API | RAG/vector indexer | Index approved facts and clean source snippets. |
| `careagent.medicine.schedule` | Schedule API, extraction review API | Reminder planner | Expand schedules into due/missed dose jobs. |
| `careagent.notification.dispatch` | Alert/escalation workers | Channel adapters | Send push, WhatsApp, Telegram, SMS, email. |
| `careagent.voice.dispatch` | Escalation worker | Voice provider adapter | Place test or approved outbound calls. |
| `careagent.escalation.run` | Risk API, risk engine, agent tool server | Escalation engine | Execute idempotent policy state machine. |
| `careagent.agent.tool` | Agent runtime | Tool server | Execute approved tools with policy and audit logging. |
| `careagent.audit.export` | Admin API | Compliance exporter | Export patient-scoped audit logs. |
| `careagent.dead_letter` | All workers | Ops review | Store exhausted jobs with reason and replay metadata. |

## Outbox Contract

Each `outbox_events` row has:

- `topic`: stable event topic, such as `observation.created`.
- `aggregate_type`: table/domain name, such as `observation` or `escalation_run`.
- `aggregate_id`: primary ID of the changed aggregate.
- `patient_id`: present for patient-scoped events.
- `event_key`: optional unique idempotency key.
- `payload_json`: schema-versioned event payload.
- `status`, `attempts`, `next_attempt_at`, `published_at`, `last_error`.

Workers must be idempotent. Reprocessing the same `event_key` must not duplicate risk events, calls, messages, dose events, or document facts.

## Idempotency Boundaries

| Operation | Boundary | Stored replay response |
| --- | --- | --- |
| Document upload session | `Idempotency-Key` plus patient and request hash; `medical_documents(patient_id, sha256)` prevents duplicate raw objects per patient. | Existing document metadata and a fresh signed upload URL when the original upload is incomplete. |
| Observation batch | Optional `Idempotency-Key` or `source_batch_id`; fallback hash uses patient, source, metric codes, and observed window. | Accepted/rejected counts and one `observation.created` event. |
| Dose event | Header or body idempotency key plus patient, schedule, scheduled time, and status. | Existing dose event. |
| Risk event | Required `Idempotency-Key`; `risk_events(patient_id, idempotency_key)` is unique. | Existing risk event and related alert references. |
| Escalation start | Required `Idempotency-Key`; `escalation_runs(idempotency_key)` and `(risk_event_id, policy_id)` are unique. | Existing run and action timeline without duplicate dispatch attempts. |
| Outbound dispatch | `channel_dispatch_attempts.idempotency_key`; escalation actions use run, step, and attempt. | Existing provider attempt status. |
| Webhook event | Provider config plus provider event/message/call ID and replay window. | Existing receipt/call event processing result. |

Idempotency rows store a request hash. A replay with the same key and a different request hash must return 409 and audit `outcome = denied` or `error` according to the route policy.

## Standard Event Envelope

```json
{
  "event_id": "uuid",
  "topic": "observation.created",
  "schema_version": 1,
  "occurred_at": "2026-05-06T18:32:00+05:30",
  "patient_id": "uuid",
  "actor": {
    "type": "system",
    "id": "observation-worker"
  },
  "idempotency_key": "patient_metric_source_timestamp_hash",
  "payload": {}
}
```

## Event Topics

| Topic | Key payload | Queue | Idempotency key |
| --- | --- | --- | --- |
| `patient.created` | `patient_id`, `account_id` | None or analytics-safe queue | `patient:{patient_id}:created` |
| `patient.access_granted` | `patient_id`, `grantee_user_account_id`, `permissions` | `careagent.audit.export` if needed | `grant:{grant_id}` |
| `consent.updated` | `patient_id`, `consent_grant_id`, `event_type`, `consent_type`, `status_after` | Policy cache invalidation | `consent_ledger:{ledger_id}` |
| `device.connected` | `patient_id`, `device_id`, `connection_id`, `supported_metrics` | `careagent.risk.evaluate` | `device:{connection_id}:connected` |
| `device.disconnected` | `patient_id`, `device_id`, `last_seen_at` | `careagent.risk.evaluate` | `device:{device_id}:disconnected:{last_seen_at}` |
| `observation.created` | `patient_id`, `observation_ids`, `metric_codes`, `observed_window` | `careagent.risk.evaluate` | Source batch ID or hash. |
| `observation.anomaly_detected` | `patient_id`, `metric`, `severity`, `evidence` | `careagent.risk.evaluate` | `anomaly:{patient_id}:{rule}:{window}` |
| `medicine.dose_due` | `patient_id`, `schedule_id`, `scheduled_at` | `careagent.notification.dispatch` | `dose_due:{schedule_id}:{scheduled_at}` |
| `medicine.dose_missed` | `patient_id`, `schedule_id`, `scheduled_at` | `careagent.risk.evaluate` | `dose_missed:{schedule_id}:{scheduled_at}` |
| `document.uploaded` | `patient_id`, `document_id`, `object_bucket`, `object_key`, `sha256` | `careagent.document.scan` | `document_upload:{document_id}` |
| `document.scan_completed` | `patient_id`, `document_id`, `malware_scan_status` | `careagent.document.ocr` only when clean | `document_scan:{document_id}:{status}` |
| `document.ocr_completed` | `patient_id`, `document_id`, `ocr_artifact_ref` | `careagent.document.extract` | `document_ocr:{document_id}:{ocr_run_id}` |
| `document.extraction_completed` | `patient_id`, `document_id`, `fact_ids` | `careagent.document.index` after review | `document_extract:{document_id}:{run_id}` |
| `document.download_requested` | `patient_id`, `document_id`, `malware_scan_status`, `allowed` | None; audit-only unless analytics-safe export is enabled | `document_download:{request_id}` |
| `risk_event.created` | `patient_id`, `risk_event_id`, `severity`, `confidence`, `reason` | `careagent.escalation.run` for high/critical | `risk:{patient_id}:{rule}:{window}` |
| `alert.created` | `patient_id`, `alert_id`, `risk_event_id`, `severity` | `careagent.notification.dispatch` | `alert:{alert_id}` |
| `alert.acknowledged` | `patient_id`, `alert_id`, `acknowledged_by` | `careagent.escalation.run` | `alert_ack:{alert_id}` |
| `escalation.started` | `patient_id`, `risk_event_id`, `escalation_run_id`, `policy_id` | `careagent.escalation.run` | `escalation:{risk_event_id}:{policy_id}` |
| `escalation.action_attempted` | `escalation_run_id`, `action_id`, `channel`, `target_contact_id` | Channel-specific dispatch queue | `escalation_action:{action_id}:{attempt}` |
| `escalation.acknowledged` | `escalation_run_id`, `acknowledged_by`, `channel` | `careagent.notification.dispatch` | `escalation_ack:{run_id}` |
| `agent.message_received` | `patient_id`, `conversation_id`, `message_id`, `channel` | Agent runtime | `message:{message_id}` |
| `agent.tool_called` | `patient_id`, `tool_call_id`, `tool_name`, `policy_decision` | Tool-specific worker if async | `tool_call:{tool_call_id}` |

## Observation Volume Design

Observation writes can be high volume and bursty. The ingestion path should:

1. Accept batches up to the OpenAPI limit.
2. Validate metric code, unit, source type, observed timestamp, and patient scope.
3. Store large raw payloads in object storage and small raw payloads in `observation_raw_payloads.payload_json`.
4. Normalize units before inserting `observations`.
5. Insert into monthly partitions or TimescaleDB hypertables.
6. Use indexes on `(patient_id, metric_code, observed_at desc)` and BRIN on `observed_at`.
7. Emit one `observation.created` event per accepted batch, not one event per reading unless a rule needs immediate processing.
8. Keep latest-vitals cache optional; source of truth remains partitioned observations.
9. Avoid loading unbounded patient time ranges in API handlers. Require `limit` and time-window defaults; larger analytics windows should read rollups.
10. Track ingestion lag, outbox lag, and partition write latency as SLO metrics. Critical-alert rules should use the newest normalized readings and stale-source flags.

Recommended retention:

- Raw payloads: short retention unless needed for provenance or incident review.
- Normalized observations: product/compliance retention policy.
- Aggregates: daily/hourly rollups for trend dashboards.

## Document Pipeline

Raw documents never pass through the API server body in production. The API creates metadata and a signed object-storage upload URL. Storage events or explicit completion calls enqueue `document.uploaded`.

Processing gates:

1. `malware_scan_status = pending`: raw download, OCR, extraction, and LLM access are blocked.
2. `malware_scan_status = infected`: object is quarantined, extraction is blocked, user receives safe failure state.
3. `malware_scan_status = clean`: OCR may start.
4. Extracted facts remain `review_status = pending` until patient/caretaker/clinician review.
5. RAG indexing uses approved facts and source snippets, not unreviewed raw documents unless explicitly allowed by policy.

## Escalation State Machine

`POST /risk-events/{risk_event_id}/escalate` reserves `idempotency_keys` and creates or returns the unique `(risk_event_id, policy_id)` `escalation_runs` row.

State transitions:

```text
pending -> running -> awaiting_ack -> acknowledged -> completed
pending -> running -> failed
pending -> cancelled
running -> cancelled
awaiting_ack -> failed
```

Rules:

- A repeated request with the same `Idempotency-Key` returns the stored response.
- A repeated request for the same `risk_event_id + policy_id` returns the existing run even if the header key differs, and writes an audit metadata note.
- Each action uses `escalation_run_id + step_order + attempt_number` as its uniqueness boundary.
- Voice calls and emergency-service steps require active emergency consent and an active policy with `emergency_enabled = true`.
- Location variables are omitted unless both consent and policy allow location sharing.
- Simulation mode must be true for drills and non-production environments.

## Retry and Dead Letter Policy

Use exponential backoff with jitter for transient failures. Suggested defaults:

- Malware scan/OCR/extraction: 5 attempts over 30 minutes.
- Notifications: 5 attempts over 10 minutes, then fallback channel if policy allows.
- Voice calls: policy-defined retry count; never exceed configured escalation steps.
- Agent tools: no automatic retry for side-effect tools unless idempotency key is present.

Dead-lettered jobs must include `event_id`, `topic`, `patient_id`, redacted payload, error code, attempts, and replay instructions. Dead-letter review is an admin action and must be audited.
