# MVP Epics and Acceptance Criteria

## Epic 1: Patient Onboarding and Consent

Acceptance criteria:

- Patient can create an account and profile.
- Patient can add conditions, allergies, emergency address, doctors, caretakers, and ambulance contacts.
- Patient can grant and revoke separate consents for health data, documents, caretaker access, messaging, calls, location, and emergency automation.
- Revoking consent blocks future access/actions and creates an audit event.
- The app explains that CareAgent is not a replacement for medical care.

## Epic 2: Caretaker Login and Multi-Patient Management

Acceptance criteria:

- Caretaker can log in separately from patient.
- Caretaker can see only patients who granted access.
- Caretaker can manage multiple patients from one dashboard.
- Patient list shows risk status, latest key vitals, medicine adherence, and device freshness.
- Caretaker can acknowledge, resolve, or escalate alerts.
- Viewing sensitive patient data creates an audit event.

## Epic 3: Health Data and Device Support

Acceptance criteria:

- Patient can connect HealthKit on iOS and Health Connect on Android.
- Patient can pair at least two direct BLE medical-device profiles in MVP.
- App can ingest simulated readings for testing.
- Every reading shows metric, value, unit, timestamp, source, and freshness.
- Stale/disconnected device states are visible to patient and caretaker.
- Unsupported devices can still be handled through manual or OCR entry.
- Device compatibility checker communicates tiers without claiming guaranteed support for every model.

## Epic 4: Medicine Management and Audible Reminders

Acceptance criteria:

- Patient can create medicine schedules manually.
- Patient can import a proposed schedule from a prescription extraction after review.
- App plays an audible reminder at configured times.
- Patient can mark dose taken, skipped, snoozed, or missed.
- Missed-dose logic can notify caretaker based on consent and policy.
- Reminders continue locally during temporary network loss.

## Epic 5: Medical Document Upload and Q&A

Acceptance criteria:

- Patient/caretaker can upload PDF/image documents from app.
- WhatsApp and Telegram uploads are accepted after account verification.
- OCR extracts text from reports, prescriptions, and medicine photos.
- Structured extraction captures medicines, dose, timing, lab values, units, dates, doctor, and follow-up instructions.
- Extracted facts have confidence and source provenance.
- User can correct extracted facts.
- Agent answers questions from approved documents with citations or source references.
- Agent says when information is missing, unclear, or stale.

## Epic 6: Claw-Compatible Agent

Acceptance criteria:

- The selected Claw-compatible runtime receives messages from app, WhatsApp, and Telegram.
- Agent resolves patient identity and authorization before using tools.
- Agent supports the required MVP tools: profile, recent vitals, device status, medicine schedule, document search, alert creation, message send, voice call, escalation start.
- Tool calls are audited.
- Agent refuses unsafe medical instructions and routes urgent symptoms to emergency guidance.
- Agent does not leak data across patients or caretakers.

## Epic 7: WhatsApp and Telegram Channels

Acceptance criteria:

- Patient/caretaker can link WhatsApp and Telegram to a CareAgent account.
- Channels support chat, document/photo upload, medicine confirmation, summary request, and alert receipt.
- WhatsApp production path uses official Cloud API/BSP or a documented approved provider.
- OpenClaw/PicoClaw WhatsApp Web style channels, if used, are marked prototype-only.
- Channel messages are rate-limited and logged.
- Business-initiated WhatsApp messages use approved templates where required.

## Epic 8: Risk Engine and Alerts

Acceptance criteria:

- System supports informational, low, moderate, high, and critical risk tiers.
- Numeric threshold rules are configurable per patient.
- Risk events include severity, confidence, reason, evidence, timestamp, and source.
- Risk engine handles stale data separately from abnormal data.
- High and critical risk events create alerts for caretakers based on policy.
- False-positive feedback can be captured.
- Unit tests cover threshold, trend, stale data, missing data, and conflicting data cases.

## Epic 9: Calls and Emergency Escalation

Acceptance criteria:

- Patient can configure escalation contacts and order.
- Patient can enable/disable automated calls and location sharing.
- System can place a test call to a caretaker through a programmable voice provider.
- Call script discloses AI identity and patient authorization.
- Escalation run tracks each attempted action and status.
- Duplicate critical events do not create duplicate emergency call storms.
- Emergency simulation mode can test the whole flow without calling real emergency services.

## Epic 10: Audit, Security, and Compliance Baseline

Acceptance criteria:

- All API requests are authenticated.
- Patient-scoped authorization is enforced.
- PHI is encrypted in transit and at rest.
- Every PHI view and external action is audited.
- Webhooks verify signatures or shared secrets.
- Documents are scanned before processing.
- Prompt-injection tests are included for uploaded documents and channel messages.
- Admin actions are logged.

## MVP Demo Scenario

End-to-end demo:

1. Patient signs up and adds two caretakers, one doctor, and one ambulance contact.
2. Patient connects Health Connect/HealthKit or a simulated wearable.
3. Patient uploads a prescription photo through WhatsApp.
4. Agent extracts medicines and proposes a schedule.
5. Patient approves schedule.
6. App plays medicine reminder.
7. Simulated heart-rate anomaly creates a critical risk event.
8. Caretaker receives WhatsApp/Telegram/push alert.
9. CareAgent places a test voice call with an AI disclosure and health summary.
10. Caretaker acknowledges alert.
11. Dashboard shows the incident timeline and audit trail.
