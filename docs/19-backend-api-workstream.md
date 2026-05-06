# Backend API Workstream Plan

This workstream owns the CareAgent backend contract: FastAPI routes, PostgreSQL data model, patient-scoped RBAC, consent ledger, PHI audit, object-storage document handling, observation ingestion, risk/alert/escalation APIs, agent tool APIs, queues, and tests.

## Non-Negotiable Invariants

- Every authenticated route resolves `user_accounts.id`, role, MFA state, request ID, and patient scope before accessing PHI.
- Role checks are insufficient alone. Non-patient actors need an active `patient_access_grants` row with the route permission.
- Every PHI read/write, denied PHI attempt with known patient scope, agent tool call, webhook side effect, message, call, and escalation action writes `audit_logs`.
- Consent is checked after RBAC and before side effects for health data, caretaker access, messaging, calls, location sharing, document processing, and emergency automation.
- Escalation starts, risk-event creation, document upload sessions, outbound dispatches, provider webhooks, and replayable worker side effects are idempotent.
- Raw documents use direct object-storage upload. OCR, extraction, raw download, and LLM access remain blocked until malware scan is clean.
- Observations are high-volume time-series data. Writes are batched, normalized, partitioned by time or stored in TimescaleDB, indexed for latest-vitals queries, and emitted through the outbox.

## Migration Coverage

| Migration | Coverage | Implementation notes |
| --- | --- | --- |
| `backend/migrations/001_initial_backend_platform.sql` | Core auth identities, accounts, patient profiles, care team, patient grants, consents/ledger, contacts, devices, observations, documents, medicines, risk, alerts, escalation, conversations, messages, agent tool calls, idempotency, outbox, audit logs, RLS, audit immutability. | Make this the first migration in the eventual Alembic/Flyway runner. Add startup health checks that fail if RLS or audit immutability is missing. |
| `backend/migrations/002_health_device_integrations.sql` | Metric catalog, normalization rules, BLE profiles, connector definitions/accounts, sync runs, freshness/quality assessments, normalization errors, device simulator. | Apply after `001_`; workers use these tables before writing normalized observations. |
| `backend/migrations/003_channels_calls_escalation.sql` | Channel providers, channel account links, approved templates/scripts, dispatch attempts, receipts, call events, acknowledgements, escalation simulations. | Apply after `001_`; escalation workers must use these tables for audited dispatch and simulation-safe drills. |

Schema gaps to resolve when scaffolding the service:

- Add a migration-runner manifest so independent SQL files have explicit revision IDs.
- Add monthly observation partition creation or TimescaleDB hypertable setup with equivalent indexes.
- Add seed data for minimum message templates, call scripts with AI disclosure, risk rules, and simulation providers.
- Add database roles for API, worker, and admin support paths so RLS is not bypassed accidentally.

## API Route List

Auth/account:

- `POST /auth/session`
- `GET /me`
- `POST /patients`
- `GET /patients`
- `GET /patients/{patient_id}`
- `PATCH /patients/{patient_id}`
- `GET /patients/{patient_id}/care-team`
- `POST /patients/{patient_id}/care-team`

Consent:

- `GET /patients/{patient_id}/consents`
- `POST /patients/{patient_id}/consents`
- `POST /patients/{patient_id}/consents/{consent_id}/revoke`

Devices and observations:

- `GET /device-catalog`
- `GET /patients/{patient_id}/devices`
- `POST /patients/{patient_id}/devices`
- `GET /patients/{patient_id}/observations`
- `POST /patients/{patient_id}/observations`
- `GET /patients/{patient_id}/vitals/latest`

Documents:

- `GET /patients/{patient_id}/documents`
- `POST /patients/{patient_id}/documents`
- `GET /patients/{patient_id}/documents/{document_id}`
- `POST /patients/{patient_id}/documents/{document_id}/download`
- `GET /patients/{patient_id}/documents/{document_id}/status`
- `POST /patients/{patient_id}/documents/{document_id}/review`
- `POST /patients/{patient_id}/questions`

Medicines:

- `GET /patients/{patient_id}/medicines`
- `POST /patients/{patient_id}/medicines`
- `GET /patients/{patient_id}/medicine-schedule`
- `POST /patients/{patient_id}/medicine-schedule`
- `POST /patients/{patient_id}/dose-events`

Risk and escalation:

- `GET /patients/{patient_id}/risk-events`
- `POST /patients/{patient_id}/risk-events`
- `GET /patients/{patient_id}/alerts`
- `POST /risk-events/{risk_event_id}/acknowledge`
- `POST /risk-events/{risk_event_id}/escalate`
- `GET /patients/{patient_id}/escalation-policies`
- `POST /patients/{patient_id}/escalation-policies`
- `GET /escalation-runs/{escalation_run_id}`

Agent, webhooks, and audit:

- `POST /agent/messages`
- `POST /agent/tools/{tool_name}`
- `POST /webhooks/whatsapp`
- `POST /webhooks/telegram`
- `POST /webhooks/voice`
- `GET /patients/{patient_id}/audit-logs`

Route extensions for health device connectors and channel/call operations live in the extension OpenAPI files under `backend/openapi/`.

## Request and Response Contracts

- `AuthSessionRequest` accepts a provider token and returns a CareAgent bearer token, current user, MFA state, role, and patient grants.
- Patient and care-team schemas carry patient profile data, linked contact endpoints, role labels, active grants, and permission arrays.
- Consent schemas append ledger entries for grant, update, revoke, and expiry. The latest grant state is never updated without preserving the ledger.
- Observation ingestion accepts up to 1000 readings per batch. Each reading includes metric, value, unit, observed timestamp, source type, reliability tier, confidence, optional device ID, and raw payload reference.
- Document upload init returns metadata plus a signed upload target. Document detail and list endpoints do not expose object bucket, object key, stored file URI, or signed URLs.
- Document download returns a short-lived signed URL only for clean scans and includes an audit log ID.
- Medicine schemas keep schedules reviewable before reminders arm; extracted medicine schedules start pending until reviewed.
- Risk events include severity, confidence, reason, source evidence, rule ID, status, and idempotency. High and critical events create alerts and may enqueue escalation.
- Escalation policies include ordered steps, channels, retry/timeout behavior, emergency/location flags, and simulation mode. Escalation runs return action timelines.
- Agent tool calls always include `patient_id`, actor/request context, authorization scope, reason, input, policy decision, result, and audit ID.

## Implementation Components

Suggested FastAPI package layout:

- `backend/app/main.py`: app factory, request ID middleware, auth dependencies, error shape.
- `backend/app/auth/`: provider-token verification, `auth_identities` resolution, session token minting.
- `backend/app/security/`: role gate, patient-scope resolver, permission checker, consent checker, MFA and break-glass policy.
- `backend/app/audit/`: audit writer, metadata redactor, hash-chain utility, append-only checks.
- `backend/app/idempotency/`: request hash reservation/replay middleware and route helpers.
- `backend/app/patients/`, `consents/`, `devices/`, `observations/`, `documents/`, `medicines/`, `risk/`, `escalation/`, `agent_tools/`: domain routers and services.
- `backend/app/storage/`: object-storage signed upload/download service and malware-scan gate.
- `backend/app/events/`: transactional outbox writer, publisher, queue envelope schemas.
- `backend/workers/`: observation normalization, risk evaluation, document scan/OCR/extract/index, medicine reminder planning, escalation state machine, notification/voice dispatch, webhook receipt processing, audit export.

## Edge Cases

- Resource ID belongs to patient B while path says patient A: return 403 or 404 per leak-prevention policy, never patient B PHI.
- Caretaker grant is active but consent for the data class is revoked: RBAC passes, consent gate denies, audit `outcome = denied`.
- Same idempotency key with different request hash: return 409 and do not replay or perform side effects.
- Same risk event and policy with a different escalation key: return the existing run and audit replay metadata.
- Malware scan pending/infected/quarantined: deny download, OCR, extraction, indexing, and LLM use.
- Observation timestamps are future, stale, duplicated, or unit-incompatible: normalize or reject per metric catalog and record rejection counts without raw payload leakage.
- Critical escalation in non-production or drill mode: simulation mode must prevent real emergency providers.
- Admin PHI access without MFA or reason: deny and audit.

## Test Coverage

Use `backend/tests/backend-contract-test-plan.md` as the executable backlog. The minimum acceptance gate is:

- OpenAPI annotations match the authorization matrix and audit catalogue.
- Migrations apply in order and prove RLS, idempotency constraints, observation indexes, object-storage document fields, and audit immutability.
- RBAC matrix tests cover all patient-scoped routes and denied cross-patient attempts.
- Every PHI endpoint has success and denied audit assertions.
- Document upload/download tests prove malware-scan gating and signed URL redaction.
- Observation ingestion load tests prove partitioned writes and latest-vitals query plans.
- Escalation tests prove idempotent start, no duplicate calls/messages, consent gating, AI disclosure, location gating, and complete incident timeline.
- Webhook tests prove signature verification, replay handling, and media-upload scan enqueueing.

## Open Questions

- Which auth provider should be first for MVP: Firebase Auth, Auth0, Cognito, or a thin internal test provider?
- Which launch geography drives emergency templates and default phone numbers first: India, United States, or both?
- What PHI retention and deletion policy should apply to raw payloads, normalized observations, raw documents, OCR artifacts, and audit logs?
- Which queue backend should MVP choose: Redis Streams, SQS, Pub/Sub, or another durable queue?
- Should doctors have write access to medicines/escalation policies in MVP, or only read and acknowledge?
