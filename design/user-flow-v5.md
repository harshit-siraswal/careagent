# CareAgent User Flow v5

Design stance: Apple-style native health guardian with a friendly medical robot mascot named Caro.

This flow is grounded in the PRD/TRD and avoids placing every feature on the dashboard. Features are grouped by when the user needs them.

## 1. Patient Setup Journey

Purpose: build trust, gather safety-critical context, and prevent accidental automation.

Screens:

- Welcome and safety disclosure.
- Health profile: age, conditions, allergies, language, care priorities.
- Consent setup: health data, reports, care-team access, emergency automation.
- Device catalog: HealthKit/Health Connect, BLE, vendor APIs, OCR/manual fallback.
- Care contacts: family, nurse, doctor, ambulance, verification and order.
- Guardian policy: automatic calls, AI speaking scope, location sharing, emergency limits.

Why:

- Emergency automation must not be a hidden default.
- Contacts and channels need verification before critical alerts.
- Device support should promise broad compatibility tiers, not "all devices guaranteed."

## 2. Daily Patient Loop

Purpose: make routine care easy for elderly and chronic-care users.

Screens:

- Dashboard: current guardian status, key vitals, agent access.
- Vitals detail: full readings, source, freshness, trends.
- Medicines: due dose, audible reminder, taken/snooze actions.
- Reports: uploaded documents and extraction status.
- Review facts: confirm/edit/reject extracted medicines and lab values.
- Ask Caro: source-grounded Q&A and safe action confirmations.

Why:

- The dashboard stays calm and high-level.
- Detailed device and report review live in their own flows.
- Medicine schedules are not created from OCR until reviewed.

## 3. Device and Data Quality Flow

Purpose: support nearly all practical device categories while exposing data reliability.

Screens:

- Device catalog.
- Add device.
- Connected devices.
- Vitals detail.
- Alerts for stale or disconnected data.

Key UI rules:

- Show last sync, source, battery, reliability, and freshness.
- Let users choose whether a source can be used for emergency escalation.
- Provide manual/photo fallback for unsupported devices.

## 4. Agent and Channel Flow

Purpose: let users interact through app, WhatsApp, Telegram, and voice without unsafe automation.

Screens:

- Ask Caro.
- Channels.
- WhatsApp/Telegram thread examples.
- Voice call.
- Guardian policy.

Key UI rules:

- Routine messages require confirmation unless configured.
- Critical alerts can use approved templates only after consent and policy approval.
- Calls must disclose AI identity and patient authorization.

## 5. Risk and Emergency Flow

Purpose: turn live data into conservative, auditable human escalation.

Screens:

- Alerts inbox.
- Quick check-in for moderate risk.
- Emergency protocol for critical risk.
- Voice call script and response options.
- Patient detail incident timeline for caretakers.

Risk behavior:

- Informational: log only.
- Low: patient prompt.
- Moderate: prompt patient, notify caretaker if no response or configured.
- High: notify caretaker/nurse/doctor.
- Critical: start emergency protocol, call contacts, share location only if permitted, and log all actions.

## 6. Caretaker Flow

Purpose: allow one caretaker or nurse to manage multiple patients without losing triage priority.

Screens:

- Care team roster: risk-ranked patients.
- Alert inbox: acknowledge, assign, call, message, escalate.
- Patient detail: current status, incident timeline, evidence, call script.
- Update rules: daily/weekly summaries, missed dose alerts, stale device alerts, quiet hours.

Why:

- Caretakers need a queue, not a patient-only app view.
- Every alert must show severity, evidence, source, timestamp, and next action.
- Regular summaries are separate from urgent escalation.

## 7. Mascot Usage

Caro uses the supplied visual direction: a soft white healthcare robot with a dark visor, cyan eyes, antenna, and stethoscope.

Usage:

- Large on welcome/setup.
- Small in dashboard, chat, reminders, channels, and policy screens.
- Present but not overused on dense clinical screens.
- Emergency states use stronger red UI while Caro remains calm and trustworthy.
