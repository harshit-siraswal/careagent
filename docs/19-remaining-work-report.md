# CareAgent Remaining Work Report

Date: 2026-05-08

## Scope Reviewed

This report compares the current `careagent` and `careagent-backend` repositories against the PRD, TRD, product requirements, MVP acceptance criteria, implementation backlog, and the mobile, agent, channel/call, and device workstream documents.

Primary documents reviewed:

- `docs/01-prd.md`
- `docs/02-trd.md`
- `docs/06-data-model-and-api.md`
- `docs/09-mvp-acceptance-criteria.md`
- `docs/12-implementation-backlog.md`
- `docs/14-agent-runtime-selection.md`
- `docs/15-mobile-app-workstream.md`
- `docs/16-agent-runtime-workstream.md`
- `docs/17-channels-calls-escalation-workstream.md`
- `docs/18-health-device-integrations-workstream.md`
- `careagent-backend/README.md`
- `careagent-backend/app`, `migrations`, `openapi`, `templates`, and `tests`

## Executive Status

The project is not release-APK ready.

The frontend repository is currently a planning/design pack. It does not contain a Flutter application scaffold, `pubspec.yaml`, `lib/`, Android project files, iOS project files, or release signing configuration. A release APK cannot be built until the Flutter app is created.

The backend repository has a useful FastAPI contract skeleton, SQL/OpenAPI contracts, risk-engine logic, mock/simulation channel and escalation services, templates, and tests. It is not yet a production backend because persistence, real auth, real providers, OpenClaw/NemoClaw runtime integration, document processing, queues, and deployment wiring are still pending.

## Repository Cleanup Completed

The app repository still contained a `backend/tests` folder even though backend artifacts have moved to `C:\Users\ASUS\Desktop\careagent-backend`.

The only file inside it was mobile/QA-owned, not backend-owned:

- Moved from `backend/tests/mobile-app-permission-test-plan.md`
- Moved to `tests/mobile-app-permission-test-plan.md`

References in `docs/15-mobile-app-workstream.md` were updated. No backend code artifact was found stranded in the app repository.

## Major Gaps Still Left

### 1. Flutter App

Status: not started in repository.

Still needed:

- Scaffold the Flutter project structure with `pubspec.yaml`, `lib/`, `android/`, `ios/`, and test folders.
- Convert the mobile workstream from React Native terminology/contracts to Flutter/Dart implementation details. Current PRD/TRD planning docs still mention React Native, while the current product direction is Flutter.
- Implement app shell, navigation, theme, auth/session handling, patient context, API client, local encrypted settings, and offline sync queue.
- Implement onboarding, profile, consent center, care-team setup, emergency contacts, escalation policy, and safety disclosure screens.
- Implement Health Connect on Android and HealthKit on iOS through platform channels or vetted Flutter plugins.
- Implement BLE scanning, pairing, and parsers for MVP profiles: heart rate, blood pressure, and glucose or pulse oximeter.
- Implement vitals dashboard with source, timestamp, unit, freshness, abnormal/stale/disconnected states, and manual/OCR fallback.
- Implement medicine schedules, local notifications, audible reminders, missed-dose logic, and offline dose-event sync.
- Implement document/photo upload, extraction review UI, document Q&A entry points, and source/citation display.
- Implement in-app CareAgent chat with source cards and confirmation cards for risky actions.
- Implement manual SOS and emergency simulation UI without silent SMS/call behavior.
- Add unit/widget/integration tests for permission gates, freshness, reminders, sync queue, SOS simulation, and critical UI states.
- Configure Android release signing, package id, app name/icons, permissions, and Play-policy sensitive permission review.

### 2. Backend Persistence and Auth

Status: partial contract skeleton.

Current backend routes mostly return in-memory or stub responses. Still needed:

- Wire FastAPI routes to PostgreSQL/Supabase tables from the migrations.
- Replace header-based placeholder auth with the selected auth provider.
- Enforce patient access grants from database rows, not request headers.
- Persist audit logs, idempotency keys, outbox events, observations, documents, medicines, consents, risk events, escalation runs, and messages.
- Add migration deployment and validation into CI/CD.
- Add environment configuration, secrets management, and production settings.

### 3. OpenClaw/NemoClaw Agent Runtime

Status: tool contract and policy scaffolding only.

Still needed:

- Implement `AgentRuntimeAdapter` modules for OpenClaw prototype and NemoClaw production-hardening evaluation.
- Add channel event routing for app, WhatsApp, Telegram, voice, document upload, and backend jobs.
- Build a real tool server wrapping backend APIs with authorization, consent, idempotency, rate limits, redaction, and audit.
- Add conversation persistence, session mapping, trace export, prompt versioning, and PHI-safe memory boundaries.
- Add prompt-injection, patient-isolation, unsafe-medical-request, stale-data, and multi-patient tests.

### 4. Calls, Channels, and Automatic Communication

Status: mock/simulation layer exists, production providers not wired.

Still needed:

- Choose production providers for WhatsApp, Telegram, push, SMS fallback, and voice calls.
- Implement WhatsApp Business Cloud API or BSP adapter with template approval status and webhooks.
- Implement Telegram Bot API adapter with account linking, commands, media upload, and callback buttons.
- Implement FCM/APNs push routing.
- Implement programmable voice provider adapter, status callbacks, DTMF/speech acknowledgement, and call summaries where consented.
- Add channel linking and verification flows.
- Add delivery receipt processing, retry/fallback workers, quiet-hours rules, and production emergency simulation safeguards.
- Confirm the legal/product position for automated calls in target launch geography.

### 5. Risk Engine and Escalation

Status: backend rule engine and simulation tests exist, production flow incomplete.

Still needed:

- Persist risk rules and patient-specific thresholds.
- Connect observation ingestion to risk evaluation through queue/outbox workers.
- Add clinician/compliance review workflow for high-risk thresholds.
- Persist escalation actions and acknowledgements.
- Add duplicate critical-event suppression against durable idempotency keys.
- Implement caretaker acknowledgement from app, dashboard, WhatsApp, Telegram, and voice callbacks.
- Add incident timeline and incident summary generation.

### 6. Health Device Integrations

Status: migrations/contracts planned, no live connectors.

Still needed:

- Implement Health Connect and HealthKit mobile connectors.
- Implement BLE profile parsers and mobile-native device lifecycle.
- Implement backend observation normalization, raw payload storage, quality scoring, and dedupe.
- Implement device catalog and compatibility checker backed by data.
- Implement device simulator API and fixtures end-to-end.
- Add vendor connector framework for Fitbit, Garmin, Withings, Oura, Dexcom/CGM, Omron, and priority pilot vendors.

### 7. Document Intelligence

Status: API contracts/stubs only.

Still needed:

- Implement secure upload to object storage and malware scan gating.
- Implement OCR worker and document classification.
- Implement prescription, lab report, discharge summary, medicine strip/photo extraction.
- Implement extracted-fact review and correction persistence.
- Implement vector index/RAG retrieval with source references.
- Add prompt-injection defenses for uploaded documents and channel media.

### 8. Caretaker Dashboard

Status: not started in repository.

Still needed:

- Create caretaker web app or dashboard surface.
- Implement multi-patient roster, risk status, latest vitals, medicine adherence, device freshness, alert inbox, patient timeline, document review, escalation notes, and acknowledgement flow.
- Enforce patient-scoped authorization and audit every sensitive view.

### 9. Security, Compliance, and Operations

Status: partially documented, not productionized.

Still needed:

- Encryption at rest strategy for PHI and field-level encryption where required.
- PHI/data-processing review for model providers and OCR providers.
- Webhook signature verification for all external providers.
- Rate limiting, replay protection, abuse controls, and secret rotation.
- Observability for ingestion lag, alert queue lag, provider failures, and call failures.
- CI for backend tests, migration validation, mobile tests, linting, and release builds.
- Privacy copy, AI disclosure copy, data deletion/export, and regulatory classification assessment.

## APK Build Decision

Release APK build was attempted from `C:\Users\ASUS\Desktop\careagent`.

Result: blocked.

Reason: `flutter build apk --release` failed because no `pubspec.yaml` exists in the repository root. This confirms there is no Flutter app scaffold yet.

Before an APK can be built:

1. Create the Flutter app project.
2. Implement or at least wire a buildable MVP shell.
3. Configure Android package, permissions, Gradle, and release signing.
4. Run `flutter analyze`, `flutter test`, and `flutter build apk --release` from the Flutter project root.

## Verification Performed

Backend:

- `python -m compileall app` passed.
- `python -m pytest` passed with 30 tests.

Frontend/planning repo:

- `flutter analyze` returned no issues, but there is no Flutter source tree to analyze meaningfully.
- `flutter build apk --release` failed with `No pubspec.yaml file found`.

## Recommended Next Build Order

1. Decide and document Flutter as the mobile stack, then update the mobile TRD/workstream from React Native to Flutter.
2. Scaffold the Flutter app in the app repository and get a signed debug/release skeleton building.
3. Wire backend persistence/auth so Flutter can use real patient, consent, medicine, vitals, document, risk, and escalation APIs.
4. Build the core Flutter MVP: onboarding, consent, vitals, medicine reminders, documents, chat, and SOS simulation.
5. Implement OpenClaw adapter for prototype agent routing, while keeping policy, consent, calls, and escalation in backend services.
6. Add WhatsApp/Telegram/voice providers in sandbox/test mode before enabling production provider dispatch.
7. Build caretaker dashboard after patient app and backend primitives are stable.
8. Run end-to-end demo: onboarding, connected/simulated vitals, prescription upload, medicine reminder, critical anomaly, WhatsApp/Telegram/push alert, test call, acknowledgement, and audit trail.
