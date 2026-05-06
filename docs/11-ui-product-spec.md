# UI Product Spec

## 1. Product Surfaces

CareAgent has four major surfaces:

- Patient mobile app.
- Caretaker dashboard.
- WhatsApp/Telegram conversational surface.
- Voice call surface.

The app and dashboard should be operational, not marketing-led. The user should land directly in health status, alerts, medicines, and agent access.

## 2. Patient Mobile App Screens

### 2.1 Onboarding

Screens:

- Welcome and safety disclosure.
- Account creation.
- Patient profile.
- Conditions and allergies.
- Care team contacts.
- Emergency settings.
- Consent center.
- Device connection setup.
- Medicine setup.

Key requirements:

- Consent must be separated by purpose.
- Emergency automation must not be enabled by default.
- Contact verification should be required before critical alerts.

### 2.2 Home

Primary content:

- Current status: normal, check-in needed, alert, urgent.
- Latest key vitals with source and freshness.
- Next medicine dose.
- Device connection health.
- CareAgent chat input.
- SOS button.

States:

- No devices connected.
- Data stale.
- Medicine due.
- High-risk alert active.
- Offline mode.

### 2.3 Devices

Primary content:

- Connected devices.
- Add device.
- Connect Apple Health/Health Connect.
- Search compatibility catalog.
- Manual/OCR fallback.
- Per-device metrics, last sync, battery, and reliability.

Key copy:

- "Connect smart watches, fitness bands, and many medical devices."
- Avoid "supports every device."

### 2.4 Medicines

Primary content:

- Today's schedule.
- Add medicine.
- Import from prescription.
- Audible reminder settings.
- Dose history.
- Missed-dose rules.

Actions:

- Taken.
- Snooze.
- Skip with reason.
- Ask CareAgent.

### 2.5 Documents

Primary content:

- Upload document/photo.
- Recently uploaded.
- Extraction status.
- Extracted facts requiring review.
- Ask questions about records.

Review pattern:

- Show extracted fact.
- Show source snippet/image location.
- Let user confirm, edit, reject.

### 2.6 Alerts and Timeline

Primary content:

- Active alerts.
- Past risk events.
- Escalation actions.
- Caretaker acknowledgements.
- Incident summaries.

### 2.7 Agent Chat

Primary content:

- Chat history.
- Suggested actions: "Show latest vitals", "What medicines are due?", "Upload report", "Notify caretaker".
- Source cards for document answers.
- Confirmation cards before risky actions.

## 3. Caretaker Dashboard Screens

### 3.1 Patient Roster

Primary content:

- Risk-ranked list of patients.
- Latest key reading.
- Device freshness.
- Missed medicine status.
- Open alerts.
- Search/filter by status.

### 3.2 Patient Detail

Primary content:

- Current status.
- Vitals timeline.
- Medicine adherence.
- Device status.
- Documents and extracted facts.
- Alerts and incident timeline.
- CareAgent summary.

### 3.3 Alert Inbox

Primary content:

- Active alerts.
- Severity.
- Evidence.
- Source and timestamp.
- Acknowledge, assign, call, message, escalate.

### 3.4 Care Team

Primary content:

- Family contacts.
- Nurses.
- Doctors.
- Ambulance/hospital contacts.
- Contact priority.
- Channel verification.
- Permissions.

## 4. WhatsApp/Telegram UX

Supported interactions:

- Ask questions.
- Upload report/photo.
- Confirm medicine taken.
- Request summary.
- Receive alerts.
- Acknowledge alerts.
- Ask for device status.

Examples:

```text
Patient: What medicine do I take after breakfast?
CareAgent: From your reviewed prescription dated 2026-04-30: Metformin 500 mg, 1 tablet after breakfast. Please follow your doctor's advice and do not change dose without consulting them.
```

```text
CareAgent: This is an urgent CareAgent alert for Ravi Sharma. Heart rate dropped to 38 bpm at 11:42 PM from Watch BLE. Please acknowledge: Reply 1 if you are with the patient, 2 to call doctor, 3 to escalate.
```

## 5. Voice Call UX

Call opening:

```text
This is CareAgent, an AI assistant calling with authorization from Ravi Sharma.
```

Call must include:

- Patient identity.
- Reason.
- Latest evidence.
- Action requested.
- Acknowledgement path.

Voice call must avoid:

- Long medical history.
- Diagnosis.
- Pretending to be the patient.

## 6. Accessibility

Requirements:

- Large text mode.
- High-contrast mode.
- Voice-first medicine reminders.
- Simple SOS action.
- Local language support.
- Caretaker-assisted setup.
- Minimal typing for elderly users.

## 7. Design Safety

- Critical alerts must look clearly different from routine updates.
- Emergency action buttons require confirmation except manual SOS.
- Risk status must show timestamp and data source.
- Stale data must never look normal.
- AI-generated content must be labelled when relevant.
