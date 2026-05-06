# Prompt: Mobile App Workstream

You are responsible for the CareAgent patient mobile app.

Read:

- `docs/00-source-brief.md`
- `docs/01-prd.md`
- `docs/02-trd.md`
- `docs/03-device-integration-strategy.md`
- `docs/05-safety-compliance-and-risk.md`

Build or plan the mobile app with these responsibilities:

- Patient onboarding.
- Consent center.
- HealthKit on iOS and Health Connect on Android.
- BLE device pairing UI for medical devices.
- Live vitals dashboard with data freshness.
- Medicine schedule and audible reminders.
- Document/photo upload.
- In-app CareAgent chat.
- Emergency contacts and escalation settings.
- Manual SOS.
- Location permission for emergency use.

Important constraints:

- Do not assume iOS can silently call or send SMS.
- Do not make direct SMS automation a core Android dependency.
- Health permissions must be explicit and data-type scoped.
- Local medicine reminders must work even if the backend is temporarily unavailable.
- Every connected metric must show source and freshness.

Deliver:

- Screen map.
- Component structure.
- Native module requirements.
- Permission flows.
- Offline/background behavior.
- API calls needed.
- Test cases for permission denied, stale data, disconnected devices, missed dose, and emergency simulation.
