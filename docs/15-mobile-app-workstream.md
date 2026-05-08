# Mobile App Workstream Plan

This document turns the patient mobile app requirements into an implementation plan for a React Native app with native iOS and Android modules. It is grounded in the PRD/TRD, device strategy, safety requirements, API model, and v5 product flow.

## 0. Delivery Stance

This workstream is a planning/spec artifact. It does not scaffold the React Native app yet. The first implementation branch should use this document as the source of truth for screen ownership, native bridge boundaries, data contracts, and QA traceability.

Files this workstream owns or feeds:

- `docs/15-mobile-app-workstream.md`: mobile app implementation plan, contracts, and sequencing.
- `tests/mobile-app-permission-test-plan.md`: cross-functional test plan for permission, stale-data, disconnected-device, missed-dose, and emergency simulation behavior.
- Future app implementation files, once scaffolding is approved: `mobile/src/features/*`, `mobile/src/native/*`, `mobile/src/data/*`, and platform native bridges under `ios/` and `android/`.

Assumptions:

- MVP is Android-first per PRD, but this plan keeps iOS parity requirements explicit so HealthKit, iOS notification, and iOS call limitations are not discovered late.
- Backend owns durable audit, risk policy, escalation execution, document processing, and agent orchestration. Mobile owns consent UX, OS permission prompts, local reminders, local emergency fallback, data capture, and sync.
- Mobile never makes policy-only safety decisions locally. Local policy is limited to UI gating, freshness labeling, local reminder state, offline queue eligibility, and simulation/test-mode safeguards.

## 1. Scope and Guardrails

Patient app responsibilities:

- Patient onboarding, health profile, conditions, allergies, care team, and emergency settings.
- Consent center with separate grants for health data, documents, caretaker access, messaging, calls, location, and emergency automation.
- HealthKit on iOS and Health Connect on Android with explicit data-type scoped permissions.
- BLE device pairing UI for medical devices and standard medical profiles.
- Live vitals dashboard where every connected metric shows value, unit, source, observed time, and freshness.
- Medicine schedules with local audible reminders that keep working during temporary backend outages.
- Document/photo upload and extracted-fact review.
- In-app CareAgent chat with source-grounded answers and confirmation cards for risky actions.
- Emergency contacts, escalation policy, manual SOS, and location permission for emergency use.

Platform constraints:

- iOS must not be designed around silent cellular calls or SMS. User-initiated `tel:` and message compose flows require user action. Autonomous calls should be requested through backend-approved cloud telephony.
- Android direct SMS automation must not be a core dependency. Use push, WhatsApp/Telegram, and cloud messaging/calling as primary production routes.
- Native phone-call audio takeover is out of scope. AI voice should use a CareAgent call relay/cloud telephony path.
- Emergency automation is off by default and requires explicit consent, verified contacts, location consent if location is shared, and audit logging.

## 2. Screen Map

### 2.1 Onboarding Stack

- `WelcomeSafetyScreen`: product introduction, AI disclosure, not-a-doctor safety position, emergency limitations.
- `AccountCreateScreen`: email/phone auth handoff and session creation.
- `PatientProfileScreen`: name, DOB, sex, language, address, emergency location notes.
- `ConditionsAllergiesScreen`: conditions, allergies, baseline notes, first risk profile inputs.
- `CareTeamSetupScreen`: family, nurse, doctor, ambulance/hospital contacts, priority order, channel verification status.
- `EmergencySettingsScreen`: local emergency number, manual SOS preferences, automated escalation off by default.
- `ConsentCenterScreen`: purpose-separated consent grants and revocation controls.
- `HealthPermissionSetupScreen`: iOS HealthKit or Android Health Connect permission groups by metric type.
- `DeviceSetupIntroScreen`: HealthKit/Health Connect, BLE, compatibility search, manual/OCR fallback.
- `MedicineSetupScreen`: add first medicine manually or skip; imported prescription schedules require later review.

### 2.2 Main App Navigation

Bottom tabs:

- `HomeTab`
- `VitalsTab`
- `DevicesTab`
- `MedicinesTab`
- `DocumentsTab`
- `CaroTab`

Global surfaces:

- `ManualSOSButton`: persistent high-visibility action from main screens.
- `ActiveAlertBanner`: high/critical alert state with evidence, timestamp, and action.
- `OfflineBanner`: backend unreachable, local reminders still active, sync queued.
- `PermissionRequiredSheet`: contextual OS permission request with plain-language reason.

### 2.3 Home

- `HomeDashboardScreen`: current status, latest key vitals, next dose, device health, alert status, chat entry, SOS.
- `CheckInScreen`: moderate-risk symptom confirmation and recheck prompts.
- `EmergencyProtocolScreen`: active critical incident, escalation status, cancellation path, call/message attempt timeline.

Required states:

- No devices connected.
- Health permissions incomplete.
- Data stale.
- Device disconnected.
- Medicine due or missed.
- Active high/critical alert.
- Offline mode.

### 2.4 Vitals

- `VitalsOverviewScreen`: latest metric cards grouped by cardiovascular, glucose, respiratory, activity, sleep.
- `MetricDetailScreen`: trend chart, latest reading, source, freshness, reliability tier, device/app metadata, risk context.
- `ManualReadingScreen`: manual entry with source labeled as user-entered and lower reliability.

Each metric card must show:

- Metric label.
- Value and unit.
- Source label, such as Apple Health, Health Connect, BLE BP Monitor, manual entry, OCR.
- Observed time and freshness status.
- Abnormal/stale/disconnected state.

Freshness labels:

- `Live`: direct BLE or foreground reading within metric-specific live window.
- `Recent`: within acceptable monitoring window.
- `Stale`: older than metric-specific threshold.
- `Disconnected`: source expected data but device/app is not reachable.
- `Unavailable`: no consent, no source, or no data.

### 2.5 Devices

- `DevicesScreen`: connected sources, last sync, data types, battery, reliability, emergency-use toggles.
- `DeviceCatalogScreen`: search devices and categories; copy says "Connect smart watches, fitness bands, and many medical devices."
- `ConnectHealthStoreScreen`: Apple Health or Health Connect status and scoped permission management.
- `BleScanScreen`: nearby BLE medical devices, profile detection, signal status.
- `BlePairingScreen`: pair, read first measurement, name device, choose metrics.
- `DeviceDetailScreen`: connection state, last seen, last sync, metrics, battery, known limitations.
- `UnsupportedDeviceFallbackScreen`: manual entry, photo OCR, CSV/document upload, request support.

### 2.6 Medicines

- `MedicineTodayScreen`: due doses, taken/snooze/skip actions, missed status.
- `MedicineScheduleScreen`: all active schedules and reminder settings.
- `MedicineEditorScreen`: name, strength, dose, route, timing, food instructions, duration.
- `PrescriptionImportReviewScreen`: extracted medicines and schedules requiring confirm/edit/reject before activation.
- `DoseHistoryScreen`: taken, skipped, snoozed, missed, recorded source.
- `ReminderSettingsScreen`: audible reminder voice/sound, snooze window, missed-dose policy.

### 2.7 Documents

- `DocumentsScreen`: uploads, recent documents, extraction status.
- `DocumentUploadScreen`: camera, photo library, file picker, WhatsApp/Telegram handoff instructions.
- `ExtractionReviewScreen`: extracted facts with confidence, source snippet/page, confirm/edit/reject.
- `DocumentDetailScreen`: source file preview, extracted medicines/labs/instructions, Q&A entry.

### 2.8 CareAgent Chat

- `CaroChatScreen`: in-app chat, suggested actions, message history.
- `SourceAnswerCard`: citations to reviewed documents or recent observations.
- `ToolConfirmationCard`: confirm before notifications, calls, escalation changes, contact changes, or sensitive sharing.
- `UploadFromChatSheet`: report/photo upload from chat.

Chat must refuse unsafe medical instructions, disclose missing/stale data, and route urgent symptoms to emergency guidance.

### 2.9 Safety and Settings

- `ConsentCenterScreen`: view, grant, revoke, and audit consent categories.
- `EmergencyContactsScreen`: contact list, priority order, verification state, preferred channel.
- `EscalationPolicyScreen`: severity triggers, contact order, allowed channels, patient confirmation timeout, emergency enabled, location sharing.
- `LocationEmergencyUseScreen`: location permission, last known status, emergency-only explanation.
- `ChannelsScreen`: WhatsApp/Telegram linking and status.
- `AuditActivityScreen`: user-visible history for consent changes, uploads, reminders, and escalation actions.

## 3. Component Structure

Suggested app structure:

```text
src/
  app/
    navigation/
    providers/
    config/
  features/
    onboarding/
    consent/
    healthPermissions/
    devices/
    vitals/
    medicines/
    documents/
    chat/
    emergency/
    channels/
    settings/
  native/
    healthkit/
    healthConnect/
    bleMedical/
    reminders/
    location/
    files/
    push/
  data/
    api/
    cache/
    syncQueue/
    models/
  safety/
    freshness/
    permissions/
    localPolicy/
  ui/
    components/
    tokens/
    accessibility/
  test/
    mocks/
    fixtures/
```

Core shared components:

- `MetricCard`: value, unit, source, freshness, abnormal state.
- `FreshnessBadge`: live/recent/stale/disconnected/unavailable.
- `SourcePill`: HealthKit, Health Connect, BLE, vendor, OCR, manual, clinical.
- `DeviceStatusRow`: connection, last sync, battery, supported metrics.
- `ConsentToggleCard`: consent purpose, scope, status, expiry, revoke.
- `PermissionGate`: local consent plus OS permission state.
- `SOSButton`: manual emergency action with confirmation and test mode support.
- `EscalationTimeline`: action attempts, status, acknowledgements, timestamps.
- `DoseCard`: scheduled time, medicine, taken/snooze/skip/missed.
- `AudibleReminderPreview`: test reminder sound/voice locally.
- `DocumentUploadTile`: capture/upload entry point and progress.
- `ExtractionFactRow`: extracted value, confidence, source, review action.
- `ChatMessageList`: source cards and tool confirmation cards.
- `OfflineQueueBanner`: pending dose events, observations, documents, chat messages.

State and storage:

- Use server state caching for API resources.
- Use encrypted local storage for auth tokens, patient-scoped local settings, active medicine schedules, reminder definitions, and emergency contact cache.
- Use a durable local sync queue for dose events, BLE observations, document uploads, and audit-relevant user actions created offline.
- Avoid storing raw medical documents longer than required locally; clear temporary upload files after successful sync.

### 3.1 Feature Module Responsibilities

- `features/onboarding`: profile creation, conditions/allergies capture, care-team bootstrap, emergency setup, and first-run completion state.
- `features/consent`: `ConsentCenterScreen`, consent ledger views, revoke flows, consent text versions, and in-context grant prompts.
- `features/healthPermissions`: platform health-store availability, metric selection, OS permission state, and health sync status.
- `features/devices`: catalog search, HealthKit/Health Connect source registration, BLE scan/pair/read flows, device detail, disconnected/stale state, and unsupported fallback.
- `features/vitals`: latest vitals, trend views, manual readings, source/freshness rendering, and abnormal/stale UI states.
- `features/medicines`: manual schedule CRUD, imported prescription review handoff, local reminder scheduling, dose actions, and missed-dose pending sync.
- `features/documents`: camera/photo/file upload, temporary file cleanup, extraction status, and extracted fact review.
- `features/chat`: in-app conversation, grounded answer cards, tool confirmation cards, upload-from-chat, and unsafe-request handling.
- `features/emergency`: emergency contacts, escalation policy editor, manual SOS, simulation mode, location sharing, escalation timeline, cancellation, and offline fallback.
- `data/api`: typed API clients, auth/session handling, request IDs, idempotency keys, retry policy, and response normalization.
- `data/syncQueue`: durable queue for offline-created observations, dose events, document uploads, SOS/risk events, and audit-relevant user actions.
- `safety/freshness`: deterministic source freshness calculation and display state. This must not depend on LLM output.
- `safety/permissions`: reusable checks combining CareAgent consent, OS permission state, feature flag, and patient role.

### 3.2 Mobile Data Contracts

The app should define typed models before screen implementation. Suggested TypeScript-style contracts:

```ts
type FreshnessState = "live" | "recent" | "stale" | "disconnected" | "unavailable";
type SourceType = "healthkit" | "health_connect" | "ble" | "vendor_api" | "fhir" | "ocr" | "manual";
type ReliabilityTier = "clinical" | "medical_device" | "consumer_device" | "manual" | "ocr" | "unknown";

type MobileObservationDraft = {
  localId: string;
  patientId: string;
  deviceId?: string;
  metricCode: string;
  valueNumeric?: number;
  valueText?: string;
  unit: string;
  observedAt: string;
  sourceType: SourceType;
  reliabilityTier: ReliabilityTier;
  confidence?: number;
  rawPayloadRef?: string;
  idempotencyKey: string;
};

type LatestVitalCardModel = {
  metricCode: string;
  label: string;
  value?: string;
  unit?: string;
  sourceLabel?: string;
  sourceType?: SourceType;
  observedAt?: string;
  freshness: FreshnessState;
  abnormalFlag?: "low" | "high" | "critical" | "none";
  reliabilityTier?: ReliabilityTier;
  deviceStatus?: "connected" | "disconnected" | "permission_required" | "sync_delayed";
};

type LocalDoseSchedule = {
  scheduleId: string;
  medicineId: string;
  displayName: string;
  dose: string;
  route?: string;
  scheduledTimes: string[];
  timezone: string;
  reminderSoundId: string;
  missedDoseAfterMinutes: number;
  reviewStatus: "manual" | "extraction_pending_review" | "reviewed";
};

type DoseEventDraft = {
  localId: string;
  scheduleId: string;
  scheduledAt: string;
  status: "taken" | "skipped" | "snoozed" | "missed";
  recordedAt: string;
  sourceChannel: "mobile_app";
  idempotencyKey: string;
};

type EmergencySimulationRequest = {
  patientId: string;
  scenario: "manual_sos" | "critical_vitals" | "missed_dose_escalation";
  evidence: MobileObservationDraft[];
  includeLocation: boolean;
  idempotencyKey: string;
  testMode: true;
};
```

Local storage rules:

- `MobileObservationDraft.rawPayloadRef` can point to a short-lived encrypted local blob or native health-store cursor; do not keep raw document images in the sync queue after upload succeeds.
- `LatestVitalCardModel.freshness` is calculated on-device from cached data and recalculated after every foreground resume, pull-to-refresh, source status event, and clock/timezone change.
- `DoseEventDraft.idempotencyKey` should be stable across app restarts so retries do not duplicate dose events.
- `EmergencySimulationRequest.testMode` must be non-optional and enforced by the API client when calling simulation endpoints.

## 4. Native Module Requirements

### 4.1 iOS

- HealthKit bridge:
  - Request read authorization by data type.
  - Read heart rate, BP where available, glucose, SpO2, temperature, respiratory rate, weight, steps, sleep, ECG references where available.
  - Use anchored queries/background delivery where iOS allows, but treat delivery as opportunistic.
  - Preserve source revision, device, sample timestamp, and unit.
- BLE bridge:
  - CoreBluetooth scanning, pairing, reconnect, GATT reads/notifications.
  - Parsers for Heart Rate, Blood Pressure, Glucose or Pulse Oximeter, Thermometer/Weight as later profiles.
  - Foreground-first UX; background reconnection is best-effort and must not be promised.
- Local reminders:
  - `UNUserNotificationCenter` scheduled notifications with custom sound.
  - Foreground audio playback with `AVAudioSession`.
  - Do not assume critical alert entitlement.
- Location:
  - CoreLocation with emergency-use explanation.
  - Prefer while-in-use permission for MVP; collect current/last known location only during SOS/escalation if consented.
- Files/media:
  - Camera, photo library, document picker.
- Push:
  - APNs/FCM for backend alerts, chat, extraction completion, escalation updates.
- Calling/messaging:
  - User-initiated `tel:` or message compose only.
  - Autonomous calls/messages must go through backend cloud telephony/channel providers.

### 4.2 Android

- Health Connect bridge:
  - Runtime permission request by record type.
  - Read heart rate, blood pressure, blood glucose, oxygen saturation, temperature, respiratory rate, weight, steps, sleep, exercise/fall-related records where supported.
  - Maintain sync cursor and normalized observation mapping.
- BLE bridge:
  - Bluetooth scan/connect permissions for Android 12+.
  - Location permission only where OS version requires it for BLE scanning.
  - GATT profile parsers and reconnect policy.
- Local reminders:
  - Local notification channel for medicine reminders.
  - AlarmManager/WorkManager strategy for reliable scheduling, with Android exact-alarm policy handled explicitly when needed.
  - Foreground playback for audible reminder preview and active in-app reminder.
- Location:
  - Fused Location Provider for emergency-only current location snapshot when consented.
- Files/media:
  - Camera, media picker, storage access framework/document picker.
- Push:
  - FCM notification routing.
- Calling/messaging:
  - Prefer cloud telephony/channel provider.
  - `ACTION_DIAL` for user-confirmed calls.
  - `ACTION_CALL` only if product/legal review approves and user grants permission.
  - Direct SMS automation is not a core dependency.

### 4.3 Native Bridge Interfaces

Define narrow native bridge APIs so permission, parsing, and platform-specific limits stay isolated from React components.

```ts
interface HealthStoreNative {
  checkAvailability(): Promise<{ available: boolean; platform: "ios" | "android"; reason?: string }>;
  requestPermissions(metricCodes: string[]): Promise<Record<string, "granted" | "denied" | "unavailable">>;
  getPermissionState(metricCodes: string[]): Promise<Record<string, "granted" | "denied" | "unavailable" | "unknown">>;
  syncSince(cursor: string | null, metricCodes: string[]): Promise<{ observations: MobileObservationDraft[]; nextCursor: string }>;
  enableBackgroundDelivery(metricCodes: string[]): Promise<{ enabled: string[]; unsupported: string[] }>;
}

interface BleMedicalNative {
  requestPermissions(): Promise<"granted" | "denied" | "blocked">;
  startScan(profileFilters: string[]): Promise<void>;
  stopScan(): Promise<void>;
  pairDevice(nativeDeviceId: string): Promise<{ deviceId: string; profiles: string[] }>;
  readLatest(deviceId: string): Promise<MobileObservationDraft[]>;
  subscribe(deviceId: string): Promise<void>;
  getConnectionState(deviceId: string): Promise<{ status: string; lastSeenAt?: string; batteryLevel?: number }>;
  forgetDevice(deviceId: string): Promise<void>;
}

interface ReminderNative {
  requestNotificationPermission(): Promise<"granted" | "denied" | "blocked">;
  scheduleDoseReminder(schedule: LocalDoseSchedule): Promise<{ nativeReminderIds: string[] }>;
  cancelDoseReminder(scheduleId: string): Promise<void>;
  playReminderPreview(soundId: string): Promise<void>;
  openNotificationSettings(): Promise<void>;
}

interface EmergencyNative {
  requestLocationPermission(): Promise<"granted" | "denied" | "blocked">;
  getEmergencyLocationSnapshot(): Promise<{ latitude: number; longitude: number; accuracyMeters: number; capturedAt: string } | null>;
  openDialer(phoneNumber: string): Promise<void>;
}
```

Native bridge requirements:

- Return permission state separately from device connection state. A denied BLE permission is `permission_required`, not `disconnected`.
- Include observed timestamps from the device/health store and ingestion timestamps from the app.
- Treat background delivery as best effort. The UI must show the last successful sync and never promise continuous monitoring.
- Avoid direct call/SMS bridges except user-confirmed dialer/message compose paths and product-reviewed Android exceptions.

### 4.4 Platform Entitlements and Manifest Items

iOS:

- HealthKit entitlement plus `NSHealthShareUsageDescription` with data-type-specific explanation.
- Bluetooth usage descriptions for scan/pair flows.
- Location usage description scoped to emergency/SOS use.
- Camera, photo library, microphone only if a voice-note feature is enabled, and document picker support.
- Push notification registration through APNs/FCM.
- Background modes only where justified: HealthKit background delivery, BLE if medically necessary and approved, background fetch/processing as opportunistic sync.

Android:

- Health Connect permissions declared only for supported record types.
- `BLUETOOTH_SCAN` and `BLUETOOTH_CONNECT` for Android 12+ BLE flows.
- Location permission only for emergency location and OS versions where BLE scanning requires it.
- `POST_NOTIFICATIONS` for Android 13+ reminders and alerts.
- Exact alarm permission only if the chosen reminder implementation requires it and Play policy review accepts the use case; otherwise use notification scheduling and WorkManager fallbacks.
- Camera/media/document picker permissions through current Android scoped storage APIs.

## 5. Permission Flows

Permission handling uses two layers:

1. CareAgent consent ledger: what the user authorizes CareAgent to do.
2. OS permission: what iOS/Android grants technically.

The app must not request broad OS permissions during welcome. Ask in context, explain the purpose, and store/update the matching `ConsentGrant`.

### 5.1 Health Data

Flow:

1. User selects Apple Health or Health Connect.
2. App shows metric groups: heart, BP, glucose, oxygen, temperature, respiratory, weight, steps, sleep, ECG/files where available.
3. User chooses data types for CareAgent use.
4. App creates/updates health-data consent with explicit scope.
5. Native permission prompt requests only selected data types.
6. App syncs only granted data types and shows denied/unavailable data separately.

Denied behavior:

- Do not retry-loop permission prompts.
- Show setup CTA and allow manual/OCR fallback.
- Do not show missing metrics as normal.

### 5.2 BLE Devices

Flow:

1. User chooses Add Bluetooth Device.
2. App explains Bluetooth permissions and supported medical profiles.
3. Request Bluetooth permission and location only when OS version requires it.
4. Scan, pair, read first measurement, save device, upload observation with source metadata.
5. User chooses whether each metric/source can be used for emergency escalation.

Denied behavior:

- Show manual/photo fallback and compatibility search.
- Device stays `permission_required`, not disconnected.

### 5.3 Medicine Reminders

Flow:

1. User creates or approves a medicine schedule.
2. App requests notification permission before enabling reminders.
3. App schedules local reminders immediately and stores them locally.
4. App offers sound/voice preview.
5. Dose events sync to backend when available.

Denied behavior:

- Schedule remains visible.
- App clearly marks audible reminders unavailable.
- User can still mark taken/skipped manually.

### 5.4 Location for Emergency Use

Flow:

1. User enables location sharing for emergency escalation.
2. App explains location is used only for SOS/critical escalation unless future consent changes.
3. Request OS location permission.
4. Store location-sharing consent separately from emergency automation consent.

Denied behavior:

- Manual SOS and escalation still work.
- Messages/calls omit location and state location unavailable.
- Audit records that location was not shared.

### 5.5 Documents, Camera, and Photos

Flow:

1. Request camera/photo/file access at upload time.
2. Upload via signed backend path or multipart API.
3. Show OCR/extraction status.
4. Require review before extracted medicine schedules become active reminders.

Denied behavior:

- Keep document picker alternatives where available.
- Allow channel upload through WhatsApp/Telegram after account verification.

### 5.6 Calls, SMS, WhatsApp, and Telegram

Flow:

1. User links channels and verifies contacts.
2. User grants messaging/calling consent by channel and target role.
3. Escalation policy determines allowed channels.
4. Backend executes cloud WhatsApp/Telegram/voice attempts with audit logs.

Denied or unavailable behavior:

- Fall back to approved next channel in policy.
- Manual device call opens dialer with user confirmation.
- No silent iOS calls/SMS.
- No direct SMS automation dependency on Android.

### 5.7 Consent and Permission Matrix

| Capability | CareAgent consent | OS permission | Local behavior if denied | Backend behavior if denied |
| --- | --- | --- | --- | --- |
| HealthKit/Health Connect reads | `health_data` scoped by metric code and source | HealthKit or Health Connect record type | Show unavailable/partial data, manual/OCR fallback | Reject sync for unconsented scopes and audit denial |
| BLE pairing and reads | `health_data` plus device/source registration | Bluetooth scan/connect; location only where required | Block scanning, keep source `permission_required` | No device registered unless first measurement/source metadata exists |
| Medicine reminders | `medicine_reminders` and optional `missed_dose_alerts` | Notifications; exact alarm only if used | Schedule visible, audible/background reminders unavailable | Store schedule, suppress missed-dose outbound alert without consent |
| Documents/photos | `documents` and extraction consent | Camera/photos/files as needed | Offer file picker/channel upload fallback | Do not process extraction beyond granted scope |
| Location in emergency | `location_sharing_emergency` | Location while-in-use for MVP | SOS/escalation proceeds without location | Omit location, audit unavailable status |
| WhatsApp/Telegram alerts | `messaging` scoped by channel and contact role | No OS permission for cloud channel | Link status shown, local app cannot send directly | Provider sends only to verified opted-in endpoints |
| Voice calls | `voice_calls` and emergency policy | User-confirmed dialer only on device | Open dialer manually; no silent cellular call | Cloud telephony only after policy approval and audit |

### 5.8 Revocation Flow

When a user revokes consent:

1. Persist `ConsentGrant.status=revoked` through the API before updating UI state.
2. Stop local sync jobs and cancel queued items that require the revoked scope.
3. Unschedule local reminders only when medicine reminder consent is revoked; do not delete medicine schedules.
4. Mark affected UI surfaces as unavailable or permission required.
5. Ask backend to disable device/source emergency-use toggles when health/source consent is revoked.
6. Create local audit queue entry if offline, then sync the revocation event as soon as the backend is reachable.

## 6. Offline and Background Behavior

### 6.1 Local-First Medicine Reminders

- Medicine schedules and reminder definitions are stored locally after creation/approval.
- Scheduled local notifications are created immediately.
- Dose actions taken offline are stored in the local sync queue and sent with idempotency keys when network returns.
- If the backend is unavailable, reminders still fire and the user can mark taken/snoozed/skipped.
- Missed-dose caretaker notification is sent when online if consent and policy allow; the app must show when the missed-dose alert is pending sync.

### 6.2 Vitals and Device Sync

- HealthKit/Health Connect reads run on foreground entry, pull-to-refresh, periodic background tasks where allowed, and native background delivery where available.
- BLE direct monitoring is foreground-first. Reconnection/background behavior is best-effort and visible in UI.
- Local BLE observations queue offline and sync later.
- Every observation uses device/source timestamp plus ingestion timestamp.
- Freshness is calculated from `observed_at`, expected source cadence, and source reliability.

### 6.3 Backend Outage

- Home shows `OfflineBanner`.
- Cached latest vitals are visible but must retain original freshness labels.
- Chat can draft/send only when backend is reachable; pending user messages may queue if product chooses, but medical advice should not be generated locally in MVP.
- Documents can be staged locally for upload with clear pending state.
- Emergency screen shows local contacts and user-confirmed dialer actions if escalation API is unavailable.

### 6.4 Emergency and SOS

- Manual SOS always opens a local emergency surface.
- Online path: create risk/SOS event, capture location if permitted, start escalation through backend, show escalation timeline.
- Offline path: show configured emergency contacts and local emergency number, open user-confirmed dialer, mark cloud escalation unavailable, queue incident/audit sync.
- Emergency simulation mode must never call real emergency services and must visually label itself as test mode.

### 6.5 Sync Queue Contract

Queueable item types:

- `observation.create`
- `dose_event.create`
- `document.upload`
- `risk_event.create`
- `sos_event.create`
- `location_snapshot.create`
- `audit_event.create`

Each queue item must include:

- `local_id`
- `patient_id`
- `type`
- `payload`
- `required_consent_scopes`
- `idempotency_key`
- `created_at`
- `attempt_count`
- `last_attempt_at`
- `status`: `queued`, `syncing`, `synced`, `blocked_by_consent`, `failed_retryable`, or `failed_terminal`

Rules:

- Retry with exponential backoff and jitter, but surface emergency/SOS sync failures immediately.
- Before each retry, re-check consent and OS permission where relevant.
- Do not retry document uploads after local temp files are removed; mark terminal and ask the user to re-upload.
- Preserve dose-event idempotency across app reinstall only if the user restores the same encrypted backup/session. Otherwise the server remains the final duplicate guard.

### 6.6 Freshness Threshold Defaults

Thresholds are configuration, not hard-coded constants. MVP defaults for UI labeling:

| Metric/source | Live | Recent | Stale |
| --- | --- | --- | --- |
| Direct BLE heart rate/SpO2 | <= 2 min | <= 15 min | > 15 min |
| HealthKit/Health Connect heart rate/SpO2 | Not guaranteed live | <= 30 min | > 30 min |
| Blood pressure | Not live | <= 12 hours | > 12 hours |
| Blood glucose/CGM | <= 5 min for CGM | <= 4 hours | > 4 hours |
| Temperature | Not live | <= 24 hours | > 24 hours |
| Weight | Not live | <= 7 days | > 7 days |
| Steps/sleep | Not live | Current day or last sleep session | Previous day/session without update |

Risk UI rule:

- Stale data can still be shown, but it must not clear an active alert or imply that the patient is currently normal.
- Disconnected expected sources should show the last value only with a disconnected/stale state and reconnect action.

## 7. API Calls Needed

### 7.1 Account, Patient, Consent

- `POST /auth/session`: create/refresh authenticated session.
- `GET /me`: current account, roles, linked patient.
- `POST /patients`: create patient profile.
- `GET /patients/{patient_id}`: load profile.
- `PATCH /patients/{patient_id}`: update profile, conditions, allergies, baseline, emergency notes.
- `POST /patients/{patient_id}/care-team`: add caretaker/doctor/ambulance/hospital contact.
- `GET /patients/{patient_id}/care-team`: list care team contacts.
- `PATCH /patients/{patient_id}/care-team/{member_id}`: update contact priority, permissions, active status.
- `POST /patients/{patient_id}/consents`: grant or update scoped consent.
- `GET /patients/{patient_id}/consents`: display current consent ledger.
- `POST /patients/{patient_id}/consents/{consent_id}/revoke`: revoke consent and audit.

### 7.2 Devices and Observations

- `GET /device-catalog?query=&platform=&metric=&connection_method=`: compatibility search.
- `GET /patients/{patient_id}/devices`: list connected sources.
- `POST /patients/{patient_id}/devices`: register HealthKit, Health Connect, BLE, manual, OCR, or vendor source.
- `PATCH /patients/{patient_id}/devices/{device_id}`: rename, deactivate, update emergency-use toggle.
- `POST /patients/{patient_id}/observations`: upload normalized readings from HealthKit, Health Connect, BLE, manual, or OCR.
- `GET /patients/{patient_id}/observations?metric=&from=&to=&source_type=`: history/trends.
- `GET /patients/{patient_id}/vitals/latest`: home and vitals latest cards.
- `POST /patients/{patient_id}/device-events`: recommended addition for mobile-originated connected/disconnected/permission-required events.

### 7.3 Medicines

- `POST /patients/{patient_id}/medicines`: create medicine.
- `GET /patients/{patient_id}/medicine-schedule`: fetch active schedule.
- `POST /patients/{patient_id}/medicine-schedules`: recommended addition for local schedule creation.
- `PATCH /patients/{patient_id}/medicine-schedules/{schedule_id}`: update schedule/reminder settings.
- `POST /patients/{patient_id}/dose-events`: taken/skipped/snoozed/missed, with offline idempotency key.
- `GET /patients/{patient_id}/dose-events?from=&to=`: dose history.

### 7.4 Documents

- `POST /patients/{patient_id}/documents`: create upload or submit multipart file, depending backend design.
- `GET /patients/{patient_id}/documents`: list documents.
- `GET /patients/{patient_id}/documents/{document_id}`: detail and extraction state.
- `POST /patients/{patient_id}/documents/{document_id}/review`: confirm/edit/reject extracted facts.
- `POST /patients/{patient_id}/questions`: source-grounded record Q&A.
- `POST /patients/{patient_id}/documents/upload-url`: recommended addition for signed direct uploads.

### 7.5 Agent Chat

- `POST /agent/messages`: send app chat message and receive agent response/tool confirmation.
- `GET /patients/{patient_id}/conversations`: recommended addition for conversation list.
- `GET /patients/{patient_id}/conversations/{conversation_id}/messages`: recommended addition for chat history.
- `POST /agent/tool-confirmations`: recommended addition for approving pending risky tool calls.

### 7.6 Alerts, Escalation, SOS, Location

- `GET /patients/{patient_id}/alerts`: active and historical alerts.
- `POST /patients/{patient_id}/risk-events`: mobile-created local risk/SOS event or simulated event.
- `POST /risk-events/{risk_event_id}/acknowledge`: acknowledge alert.
- `POST /risk-events/{risk_event_id}/escalate`: start escalation with idempotency key.
- `GET /escalation-runs/{run_id}`: escalation timeline.
- `POST /patients/{patient_id}/sos-events`: recommended addition for manual SOS intent.
- `POST /patients/{patient_id}/location-snapshots`: recommended addition for emergency-only location upload.
- `POST /patients/{patient_id}/emergency-simulations`: recommended addition for test mode without real emergency dispatch.

### 7.7 Mobile API Requirements

All mobile write requests should send:

- `Authorization: Bearer <token>`
- `X-Request-ID`: generated per API attempt for tracing.
- `Idempotency-Key`: required for observations, dose events, SOS/risk events, escalation starts, and emergency simulations.
- `X-Device-Install-ID`: stable app installation identifier, rotated on logout/delete.
- `X-CareAgent-Test-Mode: true`: required for emergency simulation and provider sandbox flows.

Observation upload payload:

```json
{
  "metric_code": "blood_pressure_systolic",
  "value_numeric": 168,
  "unit": "mmHg",
  "observed_at": "2026-05-06T18:32:00+05:30",
  "source_type": "ble",
  "device_id": "dev_123",
  "reliability_tier": "medical_device",
  "confidence": 0.98,
  "raw_payload": {
    "profile": "blood_pressure",
    "measurement_status": "valid",
    "native_device_id_hash": "sha256:..."
  }
}
```

Dose event payload:

```json
{
  "schedule_id": "sched_123",
  "scheduled_at": "2026-05-06T08:00:00+05:30",
  "status": "missed",
  "recorded_at": "2026-05-06T08:45:00+05:30",
  "source_channel": "mobile_app",
  "client_context": {
    "offline_created": true,
    "native_reminder_id": "ios_notif_abc"
  }
}
```

Manual SOS payload:

```json
{
  "trigger": "manual_sos",
  "patient_confirmation": "explicit_button_press",
  "location_snapshot_id": "loc_123",
  "client_context": {
    "offline_started": false,
    "app_state": "foreground"
  }
}
```

Emergency simulation payload:

```json
{
  "scenario": "critical_vitals",
  "test_mode": true,
  "evidence": [
    {
      "metric_code": "heart_rate",
      "value_numeric": 38,
      "unit": "bpm",
      "observed_at": "2026-05-06T18:32:00+05:30",
      "source_type": "ble",
      "freshness": "live"
    }
  ],
  "expected_channels": ["push", "whatsapp", "voice_call_test"],
  "forbidden_channels": ["real_emergency_number", "device_sms"]
}
```

## 8. Test Cases

### 8.1 Permission Denied

- HealthKit/Health Connect all denied:
  - Expected: no health data sync, vitals show unavailable, onboarding offers manual/OCR fallback, no metric appears normal.
- Partial health permission grant:
  - Expected: only granted metric types sync and display; denied metrics show unavailable with setup CTA.
- BLE permission denied:
  - Expected: scan disabled, device not registered as disconnected, fallback options shown.
- Notification permission denied:
  - Expected: medicine schedule saved, audible/background reminders marked unavailable, user can still manually record doses.
- Location permission denied:
  - Expected: SOS works without location, escalation payload omits location, audit notes location unavailable.
- Camera/photos denied:
  - Expected: upload alternatives shown, no crash, permission can be retried from settings.

### 8.2 Stale Data

- Latest heart-rate observation older than freshness threshold:
  - Expected: `MetricCard` shows stale, Home status warns data is stale, risk engine does not treat old value as current normal.
- Health store background delivery delayed:
  - Expected: foreground refresh updates data, last sync remains visible, stale state clears only after new observation.
- OCR/manual reading older than expected:
  - Expected: lower reliability and stale label shown; critical automation requires stronger confirmation unless policy allows.

### 8.3 Disconnected Devices

- BLE device paired but not seen beyond disconnect threshold:
  - Expected: Devices shows disconnected, Vitals shows last reading with stale/disconnected source, reconnect CTA visible.
- Battery level unavailable:
  - Expected: battery field shows unknown, not zero.
- Device reconnects and sends new reading:
  - Expected: device status returns connected, freshness recalculates, observation sync is idempotent.

### 8.4 Missed Dose

- Reminder fires while backend is offline:
  - Expected: local audible/notification reminder appears, user can mark taken/snoozed/skipped, event queues locally.
- User does not respond before missed-dose window:
  - Expected: dose becomes missed locally, UI shows pending caretaker alert if offline, alert sends when online if consent/policy allow.
- Prescription extraction proposes schedule:
  - Expected: no reminder is scheduled until user confirms or edits extracted medicine details.

### 8.5 Emergency Simulation

- Manual SOS in simulation mode:
  - Expected: creates simulated SOS event, no real emergency number is called, provider test contact used, screen clearly labels test mode.
- Critical vitals simulation:
  - Expected: risk event includes severity, confidence, reason, evidence, source, freshness, and timestamp.
- Escalation idempotency:
  - Expected: repeated taps or duplicate events do not create duplicate call/message storms.
- iOS call path:
  - Expected: autonomous test call uses backend cloud telephony; device cellular call path requires visible user confirmation.
- Android SMS path:
  - Expected: test does not require direct SMS permission; channel/cloud message fallback is used.
- Location unavailable:
  - Expected: escalation proceeds without location and message/call script says location is not available.

### 8.6 Test Execution Matrix

- Unit tests:
  - `calculateFreshness` thresholds, disconnected-state precedence, permission-gate decisions, consent revocation effects, dose missed-window calculations, and idempotency-key generation.
- Component tests:
  - `MetricCard`, `PermissionGate`, `ConsentToggleCard`, `DoseCard`, `SOSButton`, `EscalationTimeline`, and `OfflineQueueBanner` in all required states.
- Native module tests:
  - HealthKit/Health Connect permission denied/partial-grant mocks, BLE scan denied/disconnected/reconnected mocks, notification denied mocks, and location unavailable mocks.
- Integration tests:
  - API client request headers, offline queue retry, stale vitals rendering after cached `/vitals/latest`, dose event sync after network return, and emergency simulation with provider sandbox.
- End-to-end simulator tests:
  - Full onboarding with partial health grants, document upload denial fallback, local reminder while offline, BLE disconnect/reconnect, and manual SOS simulation.

The detailed cross-functional test plan lives in `tests/mobile-app-permission-test-plan.md` so backend, QA, and mobile implementation can share the same scenario IDs.

## 9. MVP Build Order

1. App shell, auth, patient profile, and local encrypted settings.
2. Consent center and permission gate framework.
3. Home, latest vitals cards, source/freshness model, and `/vitals/latest` integration.
4. Medicine schedule, local reminders, audible playback, and offline dose queue.
5. Device center with HealthKit/Health Connect permission flow and simulated readings.
6. BLE scan/pair/read UI and first medical profile parsers.
7. Documents upload and extraction review.
8. In-app CareAgent chat with source cards and tool confirmations.
9. Emergency contacts, escalation policy, manual SOS, and emergency simulation.
10. Background sync hardening, stale/disconnected tests, and end-to-end pilot drill.

## 10. Implementation File Plan

When app scaffolding is approved, create or modify:

- `mobile/src/app/navigation/AppNavigator.tsx`: onboarding stack, authenticated tabs, emergency modal stack.
- `mobile/src/app/providers/*`: auth, API client, patient context, network state, sync queue, notification handlers.
- `mobile/src/features/onboarding/*`: onboarding screens, profile forms, care-team setup, first-run flow.
- `mobile/src/features/consent/*`: consent center, consent API hooks, revoke flow, consent text versions.
- `mobile/src/features/healthPermissions/*`: health-store picker, metric-scope selector, permission state hooks.
- `mobile/src/features/devices/*`: catalog, health-store connection, BLE scan/pair/detail, unsupported fallback.
- `mobile/src/features/vitals/*`: dashboard cards, metric detail, trend chart, manual reading.
- `mobile/src/features/medicines/*`: schedule editor, local reminder adapter, dose history, imported prescription review.
- `mobile/src/features/documents/*`: upload flows, extraction status, review screen.
- `mobile/src/features/chat/*`: Caro chat, source answer cards, tool confirmations.
- `mobile/src/features/emergency/*`: contacts, policy editor, SOS, emergency protocol, simulation.
- `mobile/src/native/*`: TypeScript bridge facades for HealthKit, Health Connect, BLE, reminders, location, files, push.
- `mobile/ios/*` and `mobile/android/*`: native bridge implementations and platform permission declarations.
- `mobile/src/test/*`: mocks, fixtures, component tests, native bridge mocks, and e2e scenario fixtures.

Do not place risk threshold decisions, escalation authorization, or agent tool execution in the mobile app. Mobile may request, display, confirm, and queue; backend policy decides and audits.

## 11. Open Questions

- Launch geography affects emergency number defaults, local privacy copy, and cloud telephony provider choice. The plan assumes configurable India/US-style region settings rather than a hard-coded country.
- Exact-alarm usage on Android needs product/legal review before choosing `SCHEDULE_EXACT_ALARM`; the fallback is normal notifications plus WorkManager/foreground app reminders.
- iOS critical alerts require an entitlement and should not be assumed for MVP medicine reminders or emergency alerts.
- Pilot device list should be selected from target users' actual devices before vendor API work begins.
- Whether chat messages created while offline should queue for later sending is a product decision; MVP should not generate local medical advice offline.
