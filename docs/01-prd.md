# CareAgent Product Requirements Document

## 1. Product Summary

CareAgent is an agentic health companion for patients, elderly users, chronic-care users, and their caretakers. It monitors live health signals, understands medical documents and medicine schedules, answers health-record questions, reminds users to take medicines, and escalates risk to caretakers, doctors, or emergency services using app notifications, WhatsApp, Telegram, SMS, and voice calls where permitted.

The product should feel like an always-available caretaker, but it must be governed like safety-critical health software. It can assist, alert, summarize, and coordinate. It must not claim to diagnose, prescribe, or replace clinical judgment.

## 2. Target Users

Primary patient/user:

- Elderly people living alone or semi-independently.
- Chronic-condition patients such as diabetes, hypertension, cardiac-risk, respiratory-risk, renal-care, and post-surgery users.
- Users who need medication adherence support and regular monitoring.

Caretaker:

- Family member managing one or more patients.
- Nurse, attendant, home-care operator, or assisted-living manager.
- Doctor or clinic coordinator who receives escalation summaries.

Admin/operator:

- Product/support team managing device compatibility, escalation templates, safety policies, and audit investigations.

## 3. Goals

- Detect important health anomalies quickly from connected devices and reported symptoms.
- Notify the right person with the right urgency and context.
- Automate routine follow-through: medicine reminders, report extraction, appointment reminders, caretaker updates, and check-ins.
- Provide a unified patient profile across app, WhatsApp, Telegram, documents, and device data.
- Support nearly all practical categories of consumer and medical devices through compatibility tiers.
- Make every autonomous action consented, logged, reversible where possible, and explainable.

## 4. Non-Goals

- No autonomous diagnosis or treatment plan generation as a regulated clinician replacement.
- No bypassing app-store, WhatsApp, Telegram, telecom, or healthcare rules.
- No hidden access to calls, SMS, WhatsApp, or health data.
- No guarantee that emergency services will dispatch solely from an AI-triggered call.
- No direct integration with every device on day one. The product must use a tiered compatibility model and expand coverage over time.

## 5. Core User Stories

Patient onboarding:

- As a patient, I can create an account, add basic profile details, conditions, allergies, medicines, emergency contacts, doctors, and preferred hospitals.
- As a patient, I can give explicit consent for health data, messaging, location sharing, caretaker access, and emergency escalation.
- As a patient, I can pair devices or connect health stores such as Apple HealthKit and Android Health Connect.

Device monitoring:

- As a patient, I can connect fitness bands, smart watches, and medical devices.
- As a patient, I can see live or recent readings such as heart rate, blood pressure, SpO2, glucose, temperature, respiratory rate, weight, sleep, steps, ECG availability, fall detection, and device battery/connectivity.
- As a caretaker, I can see whether a patient's devices are connected, stale, disconnected, or producing abnormal readings.

Anomaly and escalation:

- As a patient, I get asked for confirmation or symptoms when a non-critical anomaly is detected.
- As a caretaker, I receive regular updates and urgent alerts based on the patient's risk level.
- As a caretaker, I receive the patient's location and latest relevant readings during urgent events if the patient consented.
- As a patient, I can authorize the agent to call a caretaker, doctor, ambulance, or emergency number when risk reaches configured thresholds.

Communication channels:

- As a patient, I can talk to CareAgent through the app, WhatsApp, and Telegram.
- As a patient or caretaker, I can upload a report, medicine strip photo, prescription, or voice note from WhatsApp/Telegram/app.
- As a caretaker, I can ask for a daily or weekly patient summary through WhatsApp/Telegram/app.
- As an admin, I can configure message templates for WhatsApp/Telegram/SMS/call scripts.

Calls and speaking on behalf:

- As a patient, I can authorize CareAgent to place calls through an approved channel when risk is high.
- As a patient, I can set what CareAgent is allowed to say on my behalf.
- As a caretaker or doctor, when CareAgent calls me, I receive a concise spoken summary, latest readings, location if permitted, and callback options.
- As a product, the system must disclose that an AI assistant is speaking and must not impersonate the patient as a human.

Documents and medical memory:

- As a patient, I can upload prescriptions, lab reports, discharge summaries, medicine photos, and hospital slips.
- As a patient, I can ask: "What medicines do I take after breakfast?", "What was my last HbA1c?", or "What did the doctor say about BP?"
- As a caretaker, I can view extracted medicines, conditions, allergies, test values, abnormal flags, and source documents.
- As a patient, I can correct extracted data, and corrected data becomes the source of truth.

Medicine reminders:

- As a patient, I can set medicine schedules manually or import them from prescriptions.
- As a patient, the app can sound an alarm or speak a reminder at dose time.
- As a caretaker, I can receive missed-dose alerts based on patient consent and configured risk.

Caretaker dashboard:

- As a caretaker, I can manage multiple patients from one account.
- As a caretaker, I can filter patients by risk, missed medicine, stale data, urgent alerts, and upcoming appointments.
- As a caretaker, I can add notes, assign a nurse, acknowledge alerts, and request an agent summary.

## 6. Feature Requirements

### 6.1 Patient App

Must have:

- Patient profile and consent center.
- Device connection center with compatibility status.
- Live vitals dashboard.
- Medicine schedule and audible reminders.
- Document upload and extracted data review.
- Agent chat with source-cited answers.
- Emergency contacts and escalation policy setup.
- Location permission setup for emergency use.

Should have:

- Voice interface.
- Appointment/test booking workflow.
- Device battery and sync health.
- Health trend charts.
- Offline local reminder fallback.

### 6.2 Caretaker App/Web

Must have:

- Login and role-based access.
- Multi-patient list with risk status.
- Patient timeline: vitals, medicines, alerts, documents, messages, calls.
- Alert acknowledgement and escalation notes.
- Regular update configuration.

Should have:

- Team/nurse assignment.
- Shift handoff summaries.
- Exportable reports.
- Escalation simulation/test mode.

### 6.3 Agent Channels

Must have:

- In-app chat.
- WhatsApp integration for text, media/document upload, and alert delivery.
- Telegram integration for text, media/document upload, and alert delivery.
- Channel identity mapping between phone number/chat ID and CareAgent account.
- Consent and verification before accepting medical data from a channel.

Should have:

- Voice note ingestion.
- Multilingual support.
- Channel-specific rate limiting and fallback.
- Family/care team group workflows.

### 6.4 Calls, Messages, and Escalation

Must have:

- Escalation contact book: family, nurse, doctor, ambulance, hospital, local emergency number.
- Risk-tiered action engine.
- Approved scripts for each risk tier.
- Automated call through cloud telephony or permitted device APIs.
- Message delivery receipts where available.
- Fallback chain if a contact does not answer.
- Complete audit log of each attempted action.

Must disclose:

- "This is CareAgent, an AI assistant acting with patient authorization."
- Patient identity, risk reason, latest readings, timestamp, location if permitted, and callback instructions.

Should have:

- Two-way voice call dialog.
- Caretaker callback handling.
- Call summaries and transcripts where legally consented.
- Emergency false-positive handling.

### 6.5 Health Data and Device Support

Must have:

- Support for Apple HealthKit on iOS.
- Support for Android Health Connect on Android.
- Direct BLE support for standard medical profiles where feasible.
- Vendor integration framework for Fitbit, Garmin, Withings, Oura, WHOOP, Samsung Health, Dexcom/CGM vendors, Omron/BP vendors, and other priority devices.
- Device registry with support tier, metric types, sync method, data freshness, and validation status.
- Normalized health observation model using FHIR-inspired structure.

Should have:

- FHIR import/export.
- ABDM/ABHA-oriented design for India where applicable.
- CSV/manual entry fallback.
- Photo/OCR fallback for devices that show readings but lack APIs.

### 6.6 Document Intelligence

Must have:

- Upload via app, WhatsApp, Telegram.
- OCR for images and PDFs.
- Extraction of medicine name, dose, timing, instructions, duration, doctor, date, lab values, units, reference ranges, diagnosis terms, allergies, and follow-up instructions.
- Human review/correction screen.
- Source linking for every extracted fact.
- RAG-based Q&A over approved extracted data and source documents.

Should have:

- Medicine interaction warnings routed as "ask your doctor/pharmacist" unless using validated clinical databases.
- Longitudinal lab trend tracking.
- Multilingual OCR for Indian languages.

## 7. Device Compatibility Requirement

The product must support "nearly all" device categories through five tiers:

1. OS aggregator support: HealthKit and Health Connect for smart watches, fitness bands, and health apps already synced to the phone.
2. Standard BLE medical profiles: heart rate, blood pressure, glucose, thermometer, pulse oximeter, weight scale, and other Bluetooth SIG-supported health profiles.
3. Vendor APIs/SDKs: direct integrations for high-demand devices and brands.
4. Clinical interoperability: FHIR/HL7 records, lab reports, hospital systems, and ABDM-style consent-based records where available.
5. Manual/OCR fallback: photo, PDF, CSV, and manual entry for unsupported devices.

The UI must not claim "all devices guaranteed." It should say "Connect smart watches, fitness bands, and many medical devices" with a compatibility checker.

## 8. Risk Tiers

Informational:

- Data logged and included in regular summaries.

Low:

- User receives guidance and a check-in prompt.

Moderate:

- User receives prompt. Caretaker may be notified if no response or if configured.

High:

- Caretaker/nurse/doctor is notified immediately through app and WhatsApp/Telegram. Call may be placed based on consent.

Critical:

- Emergency protocol starts: call primary caretaker, call configured doctor/ambulance/emergency number, send location and latest readings if permitted, continue retry/fallback chain, and log all actions.

Every tier must include confidence, data source, timestamp, and reason. Critical automation must be conservative, auditable, and configurable by medical review.

## 9. Success Metrics

Patient value:

- Medicine adherence improvement.
- Time from anomaly detection to caretaker notification.
- Percentage of alerts acknowledged.
- Reduction in stale device data.
- Patient/caretaker retention.

Safety:

- False-critical alert rate.
- Missed-critical alert rate from test datasets.
- Escalation action success rate.
- Time to reach first human contact.
- Audit completeness.

Product:

- Connected devices per patient.
- Documents processed per patient.
- WhatsApp/Telegram active usage.
- Caretaker patients managed per account.
- Crash-free sessions and background job reliability.

## 10. MVP Scope

MVP should include:

- Patient app on Android first, then iOS.
- Caretaker web dashboard.
- Claw-compatible agent service, initially OpenClaw/NemoClaw or equivalent, with in-app chat plus WhatsApp/Telegram adapter.
- Health Connect/HealthKit integration.
- BLE support for 2 or 3 high-value device profiles: heart rate, blood pressure, glucose or pulse oximeter.
- Document upload, OCR, medicine extraction, and report Q&A.
- Medicine reminders with local notification and audible alarm.
- Risk engine v1 with configurable thresholds and caretaker escalation.
- Cloud telephony call-out to caretaker/doctor in test mode.

MVP should not include:

- Full autonomous emergency dispatch without safety review.
- Claiming clinical diagnosis.
- Full support for every wearable vendor.
- Silent SMS from the user's phone.
- Native phone-call audio takeover.

## 11. Open Questions

- Primary launch geography: India only, United States, or both?
- Medical-device regulatory strategy: wellness assistant, remote patient monitoring support, or regulated medical device?
- Which conditions are first: diabetes, cardiac, hypertension, elderly fall-risk, post-surgery, respiratory?
- Which device brands must be supported in the first pilot?
- Should ambulance integration use 112/102/manual ambulance contacts, private ambulance APIs, or hospital partners?
- Should doctors have a portal in v1 or only receive summaries?
