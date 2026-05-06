# CareAgent Technical Requirements Document

## 1. Architecture Summary

CareAgent should be built as an event-driven health monitoring and agent-action system.

High-level services:

- Mobile app: React Native or native Android/iOS modules for health data, BLE, reminders, permissions, and emergency UI.
- Caretaker dashboard: web app for multi-patient monitoring and alert management.
- API backend: FastAPI service exposing account, patient, device, document, medicine, alert, and escalation APIs.
- Agent runtime: Claw-compatible gateway and agent runtime, initially OpenClaw/NemoClaw or equivalent, with custom CareAgent tools.
- Health ingestion: connectors for HealthKit, Health Connect, BLE, vendor APIs, FHIR, CSV, and OCR/manual entry.
- Risk engine: deterministic rules plus model-assisted summarization, not model-only safety decisions.
- Notification and communication: push notifications, WhatsApp, Telegram, SMS fallback, email fallback, and cloud voice calling.
- Data stores: relational database for core entities, time-series storage for vitals, object storage for documents, vector index for retrieval, audit log store.

## 2. Recommended Stack

MVP:

- Mobile: React Native with native modules for HealthKit, Health Connect, BLE, local notifications, background tasks, location, and audio reminder playback.
- Backend: FastAPI, PostgreSQL, Redis, object storage, background worker queue.
- Time-series: PostgreSQL partitioning or TimescaleDB.
- Auth: Firebase Auth, Auth0, or Cognito. Keep auth provider replaceable.
- Push: Firebase Cloud Messaging and Apple Push Notification service.
- Agent: Claw-compatible gateway plus custom tool server.
- WhatsApp: official WhatsApp Business Cloud API or BSP for production; OpenClaw WhatsApp Web channel acceptable only for prototype/personal testing.
- Telegram: Telegram Bot API.
- Calls: Twilio/Exotel/Plivo or region-specific programmable voice provider.
- OCR/document AI: cloud OCR or local OCR pipeline plus LLM extraction.
- RAG: pgvector or managed vector database.

Production hardening:

- Separate PHI database/project from analytics.
- Per-tenant encryption keys.
- Immutable audit logs.
- Queue-based action dispatch with idempotency keys.
- Policy engine for autonomous actions.
- Observability: structured logs, metrics, traces, alerting, synthetic tests.

## 3. Core Components

### 3.1 Mobile App

Responsibilities:

- Patient onboarding and consent.
- Device pairing and health permissions.
- BLE scanning/pairing for supported medical profiles.
- Read HealthKit/Health Connect records.
- Local medicine reminders and audible alarms.
- Emergency screen and manual SOS.
- In-app chat with CareAgent.
- Document upload and photo capture.
- Background sync where OS allows.

Technical requirements:

- Must degrade gracefully when background execution is limited.
- Must display data freshness for every vital.
- Must persist critical local settings required for reminders.
- Must never silently enable location, calls, SMS, microphone, health data, or contacts.

Platform notes:

- Android can use `ACTION_CALL` with `CALL_PHONE` permission for direct calling, but app-store review and user consent still matter.
- Android SMS automation through `SEND_SMS` is highly restricted by Google Play and should not be a core dependency.
- iOS `tel:` links require user confirmation before dialing. iOS SMS compose requires user action to send.
- Autonomous calling on iOS should use cloud telephony or VoIP, not the user's cellular phone line.

### 3.2 Caretaker Dashboard

Responsibilities:

- Multi-patient roster.
- Risk-ranked patient list.
- Alert inbox with acknowledgement and assignment.
- Patient timeline.
- Device status and data freshness.
- Medicine adherence view.
- Document and extracted-data review.
- Escalation policy management if authorized.

Technical requirements:

- Role-based access control.
- Least-privilege patient access.
- Audit every view of sensitive records.
- Support nurse/team workflows in later phases.

### 3.3 Claw-Compatible Agent Runtime

CareAgent should use a Claw-compatible agent gateway and tool-calling orchestration layer where practical. OpenClaw is the default prototype candidate because of its channel gateway model. NVIDIA NemoClaw is a strong production candidate when sandboxing, network policy, and agent security controls are required. PicoClaw can be considered for ultra-lightweight edge gateways, but should be treated carefully until it reaches production maturity.

The backend must define an `AgentRuntimeAdapter` so OpenClaw, PicoClaw, NemoClaw, LangGraph, OpenAI Agents SDK, or another runtime can be swapped without rewriting patient APIs, risk policy, channel adapters, or audit logging.

Agent responsibilities:

- Receive messages from app, WhatsApp, Telegram.
- Normalize user intent.
- Retrieve patient context with permissions.
- Use approved tools to answer questions or initiate workflows.
- Generate caretaker summaries, call scripts, and patient-friendly explanations.
- Ask for confirmation when action policy requires it.

Required custom tools:

- `get_patient_profile(patient_id)`
- `get_recent_vitals(patient_id, metric, window)`
- `get_device_status(patient_id)`
- `get_medicine_schedule(patient_id)`
- `log_medicine_taken(patient_id, medicine_id, time)`
- `search_medical_documents(patient_id, query)`
- `create_alert(patient_id, severity, reason, evidence)`
- `request_patient_confirmation(patient_id, prompt, timeout)`
- `send_channel_message(contact_id, channel, template_id, variables)`
- `place_voice_call(contact_id, script_id, variables)`
- `start_escalation_protocol(patient_id, risk_event_id)`
- `book_appointment_request(patient_id, provider, reason, preferred_time)`

Agent boundaries:

- The LLM may draft, summarize, classify, and ask follow-up questions.
- The deterministic policy engine must authorize calls, emergency escalation, and high-risk messages.
- The LLM must not independently decide to contact emergency services without policy approval.
- Every tool call must be logged with inputs, outputs, actor, model, and policy decision.

### 3.4 Risk Engine

Inputs:

- Vitals observations.
- Device freshness and reliability.
- Patient profile: age, conditions, thresholds, baseline, allergies.
- Medicines and missed doses.
- Symptoms reported through chat or voice.
- Historical trends.
- Care plan rules configured by clinician/caretaker.

Outputs:

- Risk event with severity, confidence, reason, evidence, recommended action, and escalation policy.

Decision structure:

- Deterministic rules for numeric thresholds and emergency states.
- Trend detection for rapid changes.
- Multi-signal correlation where possible.
- LLM summarization only after rule-based event creation.
- Human confirmation flow where risk is not critical.

Example risk event:

```json
{
  "patient_id": "pat_123",
  "severity": "critical",
  "confidence": 0.94,
  "reason": "Heart rate dropped from 72 to 38 bpm within 40 seconds",
  "evidence": [
    {
      "metric": "heart_rate",
      "value": 38,
      "unit": "bpm",
      "source": "watch_ble",
      "observed_at": "2026-05-06T18:12:40+05:30"
    }
  ],
  "policy_action": "start_emergency_protocol"
}
```

### 3.5 Health Data Ingestion

Data ingestion must support:

- Batch imports.
- Streaming/near-real-time BLE readings.
- Pull from phone health stores.
- Vendor webhook/API sync.
- Manual/OCR readings.

Every observation must include:

- Patient.
- Metric code.
- Value and unit.
- Timestamp.
- Source device/app.
- Source reliability tier.
- Ingestion method.
- Raw payload reference.
- Normalized FHIR-inspired representation.
- Whether the value was user-entered, device-measured, OCR-extracted, or clinically sourced.

### 3.6 Document Intelligence

Pipeline:

1. Upload file or image.
2. Virus/malware scan.
3. OCR.
4. Document classification.
5. Structured extraction.
6. Unit normalization.
7. Confidence scoring.
8. User/caretaker review for key data.
9. Store source and extracted facts.
10. Index for retrieval.

Extraction schemas:

- Prescription.
- Lab report.
- Discharge summary.
- Medicine strip/photo.
- Doctor note.
- Diagnostic imaging report.

Safety requirements:

- Never hide extraction uncertainty.
- Ask review for medicine schedule before enabling reminders.
- Answer questions with cited sources.
- Avoid diagnosis/prescription unless clinician-reviewed data supports it.

### 3.7 Communication Service

Supported channels:

- Push notification.
- In-app chat.
- WhatsApp.
- Telegram.
- SMS fallback where lawful.
- Voice call.
- Email fallback for non-urgent summaries.

Required capabilities:

- Contact verification.
- Opt-in tracking.
- Template approval/status for WhatsApp.
- Delivery receipts.
- Retry and fallback policies.
- Quiet hours and override rules.
- Emergency override with consent.
- Message/call script versioning.

### 3.8 Escalation Engine

Escalation must be policy-driven, idempotent, and auditable.

Inputs:

- Risk event.
- Patient consent.
- Patient location status.
- Contact list and priority.
- Communication channel availability.
- Local emergency number and country/state context.

Outputs:

- Ordered action plan.
- Executed action attempts.
- Completion status.

Example flow:

1. Critical event generated.
2. Policy checks consent and configured emergency protocol.
3. Send push and audible prompt to patient if feasible.
4. Call primary caretaker.
5. Send WhatsApp/Telegram summary to primary and secondary caretakers.
6. If no acknowledgement in configured timeout, call doctor/ambulance/emergency number.
7. Share live location if consented and available.
8. Keep retrying until a human acknowledges or policy timeout ends.
9. Produce incident summary.

## 4. Data Model

Core entities:

- UserAccount
- PatientProfile
- CareTeamMember
- ConsentGrant
- ContactEndpoint
- Device
- DeviceConnection
- Observation
- ObservationRawPayload
- Medicine
- MedicineSchedule
- MedicineDoseEvent
- MedicalDocument
- ExtractedMedicalFact
- RiskRule
- RiskEvent
- Alert
- EscalationPolicy
- EscalationRun
- EscalationAction
- Conversation
- Message
- AgentToolCall
- AuditLog

## 5. API Domains

Auth/account:

- `POST /auth/session`
- `GET /me`
- `POST /patients`
- `GET /patients/{id}`
- `POST /patients/{id}/care-team`
- `POST /patients/{id}/consents`

Devices:

- `GET /device-catalog`
- `POST /patients/{id}/devices`
- `GET /patients/{id}/devices`
- `POST /patients/{id}/observations`
- `GET /patients/{id}/observations`
- `GET /patients/{id}/vitals/latest`

Documents:

- `POST /patients/{id}/documents`
- `GET /patients/{id}/documents`
- `GET /patients/{id}/documents/{document_id}`
- `POST /patients/{id}/documents/{document_id}/review`
- `POST /patients/{id}/questions`

Medicines:

- `POST /patients/{id}/medicines`
- `GET /patients/{id}/medicine-schedule`
- `POST /patients/{id}/dose-events`

Alerts/escalation:

- `GET /patients/{id}/alerts`
- `POST /patients/{id}/risk-events`
- `POST /risk-events/{id}/acknowledge`
- `POST /risk-events/{id}/escalate`
- `GET /escalation-runs/{id}`

Agent:

- `POST /agent/messages`
- `POST /webhooks/whatsapp`
- `POST /webhooks/telegram`
- `POST /webhooks/voice`

## 6. Security Requirements

- Encrypt data in transit with TLS.
- Encrypt PHI at rest.
- Use field-level encryption for especially sensitive data where feasible.
- Use RBAC and patient-specific access grants.
- Support revocation of caretaker access.
- Log every data access, tool call, alert, message, call, and escalation.
- Separate analytics from PHI.
- Do not send raw documents to LLM providers without explicit data-processing review.
- Redact unnecessary identifiers before model calls.
- Apply prompt-injection defenses for uploaded documents and channel messages.
- Use rate limits and abuse controls on external channels.

## 7. Reliability Requirements

- Critical alert path target: under 60 seconds from qualifying event to first outbound attempt in normal conditions.
- Data freshness visible at all times.
- Escalation actions idempotent to avoid duplicate emergency calls.
- Background jobs retry with exponential backoff.
- Offline local medicine reminders continue without server connectivity.
- System health dashboard for ingestion lag, alert queue lag, message failures, and call failures.

## 8. Compliance and Safety Requirements

- Consent ledger for health data, caretaker access, messaging, calls, location sharing, and emergency automation.
- Clear user-facing disclaimers.
- AI disclosure on calls and messages.
- Audit trails suitable for incident review.
- Medical review board or clinical advisor sign-off before high-risk thresholds are used in production.
- Regulatory classification assessment before public launch.

## 9. Testing Requirements

- Unit tests for risk rules, normalization, consent policy, escalation policy, and extraction schemas.
- Integration tests for WhatsApp, Telegram, push, voice, and BLE mocks.
- Simulator tests for mobile permission denial and background limitations.
- Synthetic patient scenarios for false positive and false negative alert behavior.
- Security tests for prompt injection, document malware, unauthorized patient access, and replayed webhooks.
- Load tests for simultaneous alerts.
- Incident drills for emergency escalation.

## 10. Known Technical Risks

- Mobile OS background restrictions may delay live data ingestion.
- Wearable data can be stale, noisy, or unavailable.
- BLE interoperability varies across device vendors.
- WhatsApp Business rules can block free-form outbound messages outside allowed windows.
- App-store review may reject broad SMS/call automation permissions.
- Cloud telephony emergency support varies by country.
- LLM extraction can hallucinate or misread reports without review and source grounding.
