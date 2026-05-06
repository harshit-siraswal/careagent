# Mobile App Permission and Offline Test Plan

This plan covers mobile-specific permission, freshness, device, medicine, and emergency simulation scenarios that must be validated by mobile, backend, and QA before MVP pilot. It is a planning artifact; it does not add executable tests yet.

## 1. Scope

Required scenario groups:

- Permission denied and partial permission grant.
- Stale data handling.
- Disconnected devices.
- Missed dose behavior while online and offline.
- Emergency simulation without real emergency dispatch.

Shared requirements:

- Every scenario must assert UI state, local state, API payload, audit/event behavior, and retry/idempotency behavior where relevant.
- Emergency simulation tests must use provider sandbox/test contacts only.
- Tests must confirm that iOS does not silently call or send SMS and Android does not require direct SMS automation.

## 2. Fixtures

Use these fixture concepts when executable tests are created:

- Patient: `pat_mobile_001`, adult chronic-care patient with hypertension and diabetes.
- Care team: primary family caretaker, secondary family caretaker, doctor, ambulance/private emergency contact.
- Consents: health data, documents, medicine reminders, missed-dose alerts, messaging, calls, location, emergency automation.
- Devices:
  - `dev_health_store`: HealthKit or Health Connect source.
  - `dev_ble_bp_001`: BLE blood pressure monitor.
  - `dev_ble_hr_001`: BLE heart-rate monitor.
  - `dev_manual_001`: manual/OCR fallback source.
- Medicine schedule: Metformin 500 mg after breakfast at 08:00 local time with missed window of 45 minutes.
- Network states: online, backend unavailable, fully offline.

## 3. Scenario Matrix

| ID | Area | Trigger | Expected result |
| --- | --- | --- | --- |
| MOB-PERM-001 | Health permissions | User denies all HealthKit/Health Connect types | No health sync starts; vitals show unavailable; manual/OCR fallback is visible; consent remains absent or inactive for denied scopes |
| MOB-PERM-002 | Health permissions | User grants heart rate only and denies glucose/BP | Only heart-rate records sync; BP/glucose cards show unavailable with setup CTA; API never receives denied metric codes |
| MOB-PERM-003 | BLE permissions | User denies Bluetooth scan/connect permission | BLE scan is blocked; no device is registered as disconnected; UI shows permission-required state and fallback options |
| MOB-PERM-004 | Notifications | User denies notification permission after creating schedule | Schedule is saved; background/audible reminders show unavailable; user can still mark doses manually |
| MOB-PERM-005 | Location | User denies emergency location permission | SOS/escalation proceeds without location; location payload is omitted; audit/event metadata records location unavailable |
| MOB-PERM-006 | Documents | User denies camera/photos | App offers document picker/channel upload fallback; no crash; no temporary file remains after cancelled upload |
| MOB-STALE-001 | Stale data | Latest HR is older than freshness threshold | `MetricCard` shows stale; Home warns stale data; risk engine cannot treat old reading as current normal |
| MOB-STALE-002 | Background delay | Health-store background delivery is delayed | Foreground refresh pulls new data; last-sync timestamp is visible; stale clears only after new observation |
| MOB-STALE-003 | Manual/OCR | Manual reading is older than expected threshold | Reading shows manual/OCR source, lower reliability, and stale label; critical automation requires policy confirmation |
| MOB-DEVICE-001 | BLE disconnect | Paired BLE device not seen beyond disconnect threshold | Device row shows disconnected; vitals show last value with stale/disconnected state; reconnect CTA appears |
| MOB-DEVICE-002 | Battery unknown | Device does not report battery | Battery displays unknown, not 0%; no low-battery alert is generated |
| MOB-DEVICE-003 | Reconnect | Device reconnects and sends same reading twice | Status returns connected; freshness recalculates; duplicate observation is ignored by idempotency |
| MOB-DOSE-001 | Offline reminder | Reminder fires while backend is unavailable | Local notification/audio fires; user can mark taken/snoozed/skipped; dose event enters sync queue |
| MOB-DOSE-002 | Missed dose | User does not respond before missed window | Dose becomes missed locally; pending caretaker alert indicator appears if offline; alert sends after reconnect only with consent/policy |
| MOB-DOSE-003 | Prescription import | OCR proposes new schedule | No reminder is scheduled until user confirms or edits extracted medicine schedule |
| MOB-EMER-001 | Manual SOS simulation | User starts SOS in simulation mode | Simulated SOS event is created; no real emergency number is called; UI is visibly test mode |
| MOB-EMER-002 | Critical vitals simulation | Simulated HR critical event is submitted | Risk event evidence includes severity, confidence, reason, source, freshness, observed time, and idempotency key |
| MOB-EMER-003 | Duplicate simulation tap | User taps start simulation repeatedly | Only one escalation run is created; no duplicate call/message storm |
| MOB-EMER-004 | iOS call path | Simulation requests call on iOS | Cloud telephony sandbox is used for autonomous test call; device call path opens user-confirmed dialer only |
| MOB-EMER-005 | Android SMS path | Simulation includes messaging fallback | Test does not require direct SMS permission; approved push/WhatsApp/Telegram/cloud channel is used |
| MOB-EMER-006 | Location unavailable | Location denied or timed out during simulation | Escalation proceeds without location; message/call script states location is unavailable |

## 4. Detailed Expected Evidence

### MOB-PERM-001: Health Permissions Denied

Steps:

1. Start onboarding and select HealthKit or Health Connect.
2. Select heart rate, BP, glucose, SpO2.
3. Deny all OS permission prompts.
4. Return to Home and Vitals.

Assertions:

- `PermissionGate` returns denied for selected metric scopes.
- `LatestVitalCardModel.freshness` is `unavailable` for all denied metrics.
- No `POST /patients/{patient_id}/observations` call is made.
- Consent ledger shows no active health-data grant for denied metric scopes, or records an inactive/denied state depending backend design.
- UI offers manual/OCR/device fallback and does not retry-loop the native prompt.

### MOB-STALE-001: Stale Heart Rate

Steps:

1. Seed cached latest heart-rate reading observed 45 minutes ago from Health Connect.
2. Open Home while online.
3. Pull to refresh with no newer records.

Assertions:

- Home and Vitals show stale label with original observed time and source.
- The reading is visible but does not render as normal/current.
- If a risk event is active, stale HR cannot resolve it.
- API request for latest vitals includes normal auth headers and request ID.

### MOB-DEVICE-001: BLE Device Disconnected

Steps:

1. Pair BLE BP device and read first valid measurement.
2. Simulate device being unreachable beyond configured disconnect threshold.
3. Open Devices and Vitals.

Assertions:

- Device state is `disconnected`, not `permission_required`.
- Last BP reading shows source and observed time with stale/disconnected state.
- Reconnect CTA starts BLE scan only after Bluetooth permission is still valid.
- Mobile sends a `device-events` payload if that endpoint is available.

### MOB-DOSE-001: Offline Reminder

Steps:

1. Create reviewed local medicine schedule with notification permission granted.
2. Put backend into unavailable state before dose time.
3. Wait for reminder and mark taken.
4. Restore backend.

Assertions:

- Native reminder fires locally at scheduled time.
- Dose action is stored in sync queue with stable idempotency key.
- UI shows pending sync while offline.
- `POST /patients/{patient_id}/dose-events` is sent when backend returns.
- Duplicate retries do not duplicate the dose event.

### MOB-EMER-001: Manual SOS Simulation

Steps:

1. Enable emergency simulation mode from safe test entry point.
2. Press Manual SOS and confirm simulation.
3. Observe escalation timeline.

Assertions:

- API call goes to `POST /patients/{patient_id}/emergency-simulations` or equivalent sandbox endpoint.
- Request includes `test_mode=true`, `X-CareAgent-Test-Mode: true`, and idempotency key.
- UI clearly labels simulation/test mode on every active emergency surface.
- No `tel:` deep link to real emergency number is opened automatically.
- No direct SMS permission is requested.
- Escalation timeline uses sandbox provider IDs and test contacts.

## 5. Automation Targets

Mobile unit tests:

- Freshness calculation and precedence.
- Permission-gate logic.
- Consent revocation side effects.
- Dose missed-window calculation.
- Sync queue status transitions.

Mobile component tests:

- `MetricCard` unavailable/stale/disconnected/critical states.
- `PermissionRequiredSheet` copy and retry/settings behavior.
- `DoseCard` due/taken/snoozed/skipped/missed states.
- `SOSButton` normal and simulation modes.
- `EscalationTimeline` successful, failed, offline, and test-mode runs.

Native bridge mocks:

- HealthKit/Health Connect denied, partial, unavailable, and delayed background delivery.
- BLE permission denied, scan timeout, pair failure, disconnect, reconnect, duplicate measurement.
- Notification permission denied and scheduled reminder delivery.
- Location denied, timeout, low accuracy, and successful snapshot.

Backend/API contract tests:

- Denied scopes are rejected server-side.
- Idempotency keys dedupe dose events, observations, SOS events, and simulation starts.
- Emergency simulation cannot dispatch real emergency/provider routes.
- Location omitted payloads are accepted and audited.
- Missed-dose alerts require both consent and escalation policy.

End-to-end simulator tests:

- Onboarding with partial health grant.
- BLE disconnect and reconnect.
- Offline medicine reminder and sync on reconnect.
- Manual SOS simulation.
- Critical vitals simulation with duplicate tap guard.

## 6. Exit Criteria

- All scenario IDs above are mapped to executable tests or documented manual pilot tests.
- No emergency simulation test can reach real emergency services.
- No test depends on silent iOS cellular calls/SMS or Android direct SMS automation.
- Required audit and idempotency evidence is captured for every write path.
- Stale or unavailable data never renders as current normal data.
