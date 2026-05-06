# Roadmap and Parallel Workstreams

## 1. Phase 0: Validation Prototype

Duration: 2 to 4 weeks.

Goals:

- Demonstrate patient app, caretaker dashboard, and agent chat.
- Connect one health data source.
- Upload one report and answer questions from it.
- Send a WhatsApp/Telegram alert to a caretaker.
- Simulate a critical event and place a test call to a caretaker.

Deliverables:

- Clickable/mobile prototype.
- Backend skeleton.
- Claw-compatible agent with 3 to 5 tools.
- Risk engine v0.
- Document extraction proof of concept.
- Device simulator.

## 2. Phase 1: MVP Pilot

Duration: 8 to 12 weeks.

Goals:

- Patient onboarding and consent.
- HealthKit/Health Connect integration.
- BLE support for first profiles.
- Medicine schedule and audible reminders.
- Caretaker dashboard.
- WhatsApp/Telegram bot.
- Document OCR and structured extraction.
- Risk rules and escalation.
- Cloud voice call to caretaker/doctor.

Exit criteria:

- 20 to 50 pilot users.
- At least 3 device categories tested.
- Alert delivery and acknowledgement measured.
- No high-severity privacy/security issues open.

## 3. Phase 2: Expanded Device and Care Team

Duration: 12 to 20 weeks.

Goals:

- Vendor connector framework.
- Device catalog and compatibility checker.
- More BLE profiles.
- Nurse/team workflow.
- Appointment/test booking integrations.
- Location sharing and emergency drill mode.
- Better trend analytics.
- Multilingual support.

## 4. Phase 3: Production Readiness

Duration: depends on regulatory path.

Goals:

- Compliance review.
- Clinical safety review.
- Incident response process.
- Audit exports.
- HITRUST/SOC2-style controls if enterprise.
- Regulatory classification and claims review.
- High-availability deployment.

## 5. Parallel Workstreams

Workstream 1: Mobile app.

- Owns patient app, permissions, health stores, BLE UX, reminders, emergency UI.

Workstream 2: Backend platform.

- Owns APIs, data model, auth, RBAC, observation storage, documents, queues, audit logs.

Workstream 3: Agent and tools.

- Owns Claw-compatible runtime setup, tool server, prompts, memory, channel routing, safety envelopes.

Workstream 4: Health devices.

- Owns HealthKit/Health Connect, BLE parsers, device catalog, vendor connector framework.

Workstream 5: Channels and calls.

- Owns WhatsApp, Telegram, push, SMS fallback, programmable voice, call scripts.

Workstream 6: Document intelligence.

- Owns OCR, extraction schemas, source grounding, RAG, medicine extraction.

Workstream 7: Caretaker dashboard.

- Owns multi-patient dashboard, alert inbox, patient timeline, team workflows.

Workstream 8: Safety, compliance, and QA.

- Owns consent, policy engine, safety test cases, privacy/security review, incident drills.

## 6. Recommended Build Order

1. Define data model and auth boundaries.
2. Build patient/caretaker account flow.
3. Build observation ingestion and latest vitals API.
4. Build device simulator to unblock risk engine and UI.
5. Build mobile vitals dashboard and caretaker dashboard.
6. Build risk event and alert engine.
7. Build channel adapters.
8. Build Claw-compatible tools around stable APIs.
9. Add document upload and extraction.
10. Add HealthKit/Health Connect and BLE.
11. Add voice call escalation.
12. Run end-to-end emergency simulation.

## 7. Shared Definitions

Patient:

- Person whose health data is monitored.

Caretaker:

- Authorized person who receives updates or manages care.

Risk event:

- Structured anomaly or dangerous pattern detected by rules/data.

Alert:

- User-facing notification created from a risk event.

Escalation:

- Ordered external action sequence triggered by risk.

Observation:

- A single measured, entered, extracted, or imported health data point.

Source reliability tier:

- System classification of how much the product can trust a reading.
