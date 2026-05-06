# Implementation Backlog

## 1. Foundation

- Create monorepo structure.
- Set up backend service.
- Set up mobile app.
- Set up caretaker dashboard.
- Set up database and migrations.
- Set up auth provider.
- Set up CI.
- Set up environment configuration.
- Set up audit log library.

## 2. Patient and Care Team

- Patient profile CRUD.
- Caretaker invite flow.
- Contact verification.
- Doctor and ambulance contact storage.
- Role-based access control.
- Patient access grants.
- Consent ledger.

## 3. Health Observations

- Observation schema and API.
- Latest vitals API.
- Time-series query helpers.
- Observation ingestion event.
- Device simulator.
- Unit normalization.
- Data freshness rules.

## 4. Device Support

- HealthKit native module.
- Health Connect native module.
- BLE scan and pairing.
- BLE Heart Rate parser.
- BLE Blood Pressure parser.
- BLE Glucose or Pulse Oximeter parser.
- Device catalog schema.
- Compatibility checker UI.
- Manual reading entry.
- OCR reading entry.

## 5. Risk Engine

- Risk rule schema.
- Patient-specific thresholds.
- Risk event creation.
- Stale device alert.
- Missed medicine alert.
- Critical event idempotency.
- Test fixtures.
- Risk rule admin config.

## 6. Medicines

- Medicine CRUD.
- Schedule generation from manual input.
- Schedule proposal from extraction.
- Local reminder scheduling.
- Audible reminder playback.
- Dose event recording.
- Missed dose worker.
- Caretaker missed-dose notification.

## 7. Documents

- Secure upload API.
- Object storage integration.
- Malware scan hook.
- OCR worker.
- Document classification.
- Prescription extraction.
- Lab report extraction.
- Fact review API.
- RAG index.
- Source-cited Q&A.

## 8. Agent

- Claw-compatible agent runtime setup.
- Tool server.
- Agent system prompt.
- Tool schemas.
- Patient authorization middleware.
- In-app chat route.
- WhatsApp route.
- Telegram route.
- Tool audit logging.
- Prompt-injection tests.

## 9. Channels

- Push notification service.
- WhatsApp Cloud API or BSP adapter.
- Telegram Bot API adapter.
- Channel account linking.
- Message template registry.
- Delivery receipt handling.
- Rate limiting.
- Channel failure fallback.

## 10. Voice and Escalation

- Voice provider abstraction.
- Outbound call API.
- Call script registry.
- DTMF/speech acknowledgement.
- Escalation policy schema.
- Escalation run state machine.
- Retry/fallback logic.
- Emergency simulation mode.
- Incident summary generation.

## 11. Caretaker Dashboard

- Login.
- Patient roster.
- Alert inbox.
- Patient detail.
- Vitals timeline.
- Medicine adherence.
- Device status.
- Document review.
- Care team management.

## 12. Security and Compliance

- PHI encryption review.
- Webhook signature verification.
- Audit exports.
- Admin access controls.
- Consent revocation tests.
- Security logging.
- Data deletion/export.
- Privacy copy.
- AI disclosure copy.

## 13. QA and Demo

- End-to-end MVP demo scenario.
- Permission-denied tests.
- Stale data tests.
- Device disconnected tests.
- False alert simulation.
- Unauthorized caretaker access tests.
- WhatsApp/Telegram upload tests.
- Voice call test mode.
- Incident review report.
