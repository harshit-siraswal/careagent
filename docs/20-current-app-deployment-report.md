# CareAgent Current App and Deployment Report

Date: 2026-05-11

## Scope Checked

Primary repositories:

- `C:\Users\ASUS\Desktop\careagent`
- `C:\Users\ASUS\Desktop\careagent-backend`

Related folders checked:

- `C:\Users\ASUS\Desktop\careagent-backend-api`
- `C:\Users\ASUS\Desktop\careagent-backend-channels`
- `C:\Users\ASUS\Desktop\careagent-backend-risk-agent`
- `C:\Users\ASUS\Desktop\careagent-backend-supabase`
- `C:\Users\ASUS\Desktop\careagent_agents`
- `C:\Users\ASUS\Desktop\careagent_remote_check`

## Executive Summary

CareAgent is still not a production-ready app. The frontend now has a Flutter shell, but most user-facing product surfaces are placeholders. The backend has a useful FastAPI contract skeleton with tests, risk logic, mock channel dispatch, and escalation simulation, but it is not connected to durable persistence, real auth, real channel providers, object storage, queues, or the agent runtime.

The GitHub language screenshot showing mostly HTML does not mean the production app is HTML. The tracked HTML is mainly design prototype output in `design/*.html`. The actual app code is Flutter/Dart, but there is very little Dart application code compared with the design files, so GitHub Linguist reports HTML as dominant.

Current deployment status:

- Backend can be deployed to Render only as a skeleton API unless persistence/auth/provider work is completed.
- Frontend cannot be treated as a finished Vercel web app yet. There is no `web/` Flutter target and no Vercel config.
- The current frontend auth direction has changed from Supabase to Firebase in uncommitted files. That needs a deliberate product/backend decision because the backend contracts and Supabase migrations still assume Supabase Auth.

## Why GitHub Shows Mostly HTML

Tracked source size in `careagent` currently includes:

| Extension | Tracked files | Bytes |
| --- | ---: | ---: |
| `.html` | 4 | 168267 |
| `.dart` | 2 | 54220 |
| `.kt` | 1 | 130 |

The HTML files are:

- `design/apple-careagent-flow.html`
- `design/interface-concepts-apple.html`
- `design/interface-concepts-v2.html`
- `design/interface-concepts.html`

These are design prototypes, not the deployed application. If you want GitHub to show the repo as Dart, either move design prototypes to a separate design/docs repo or add `.gitattributes` rules such as:

```gitattributes
design/*.html linguist-documentation
design/screenshots/** linguist-documentation
generated/** linguist-generated
```

That cleanup will change language stats, but it will not reduce the real product work left.

## Folder Findings

| Folder | Finding |
| --- | --- |
| `careagent` | Active Flutter frontend and planning/design repo. Current app is a shell with auth UI and placeholder screens. |
| `careagent-backend` | Active consolidated backend repo. Contains FastAPI app, migrations, OpenAPI, templates, docs, and tests. |
| `careagent-backend-api` | Older split API workstream. Its files appear represented in the consolidated backend repo. Do not deploy this separately. |
| `careagent-backend-channels` | Older split channels/escalation workstream. Its code/templates appear represented in the consolidated backend repo. Do not deploy separately. |
| `careagent-backend-risk-agent` | Older split risk/agent workstream. Its risk and agent helper code appears represented in the consolidated backend repo. Do not deploy separately. |
| `careagent-backend-supabase` | Older split Supabase migration/scripts workstream. Its deployment artifacts appear represented in the consolidated backend repo. Do not deploy separately. |
| `careagent_agents` | Parallel workstream copies/planning material. Large duplicated docs/design assets; not a deployment source. |
| `careagent_remote_check` | Only a minimal README. Not a deployment source. |

## Current Frontend State

Implemented:

- Flutter project scaffold with Android files.
- Safety notice gate.
- Firebase Auth controller in `lib/main.dart`.
- Google sign-in, email/password sign-in, account creation, password reset, and email verification UI.
- Placeholder navigation for Home, Onboarding, Consent, Vitals, Medicines, Documents, Chat, and SOS.
- Basic widget tests.

Important current issues:

- The app is mostly still one large `lib/main.dart`; it needs feature modules, services, models, and API boundaries.
- `lib/config/firebase_options.dart` is untracked and uses `--dart-define` values for web Firebase config.
- `android/app/google-services.json` is untracked and points to the Studyspace Firebase project, not a CareAgent-owned Firebase project.
- `android/app/build.gradle.kts` currently sets `applicationId = "me.studyshare.android"` while the app label says CareAgent. That is not suitable for a production CareAgent package.
- Backend docs, migrations, and auth bridge still assume Supabase Auth, while current frontend code uses Firebase Auth. Choose one auth provider before building deeper features.
- There is no `web/` folder, so the Flutter web target is not ready for Vercel.
- Current code does not call the backend API yet.

Verification run:

- `dart analyze lib test` passed.
- `flutter test --no-pub` passed.

## Major Frontend Work Still Left

1. Decide final auth architecture: Firebase Auth or Supabase Auth. Then align backend token validation, user identity mapping, RLS/session handling, and mobile/web config.
2. Create a CareAgent-owned Android package ID and Firebase/Supabase client config. Do not ship Studyspace package IDs or credentials.
3. Add a real frontend architecture: routes, feature folders, API client, auth token injection, typed models, error handling, and state management.
4. Implement onboarding: patient profile, language, age/risk context, care team, emergency contacts, consent setup, and disclosure acceptance persistence.
5. Implement consent center with backend-backed grants, revocation, audit trail, and separate controls for health data, documents, channels, calls, location, and caretaker access.
6. Implement backend-connected vitals: latest values, freshness, source, unit, abnormal states, stale/disconnected states, and manual entry.
7. Implement Health Connect on Android and, if iOS remains in scope, HealthKit. Add permission flows and background sync constraints.
8. Implement BLE/device integration: scanning, pairing, connection lifecycle, metric parsers, device catalog, and simulator support.
9. Implement medicines: schedules, local notifications, dose events, missed dose handling, offline queue, and prescription review before activation.
10. Implement documents: upload, scan status, extraction review, correction, source citations, and document Q&A.
11. Implement in-app CareAgent chat backed by the agent runtime/tool API with source cards, refusal rules, and confirmation cards for risky actions.
12. Implement channels and caretaker flows: WhatsApp/Telegram linking, alert inbox, acknowledgement, escalation timeline, and caretaker dashboard or web surface.
13. Implement SOS/emergency simulation with strict test-mode labeling and no real emergency dispatch until consent/provider/legal gates are complete.
14. Add release hardening: app icons, package name, signing, permissions, CI, crash/error reporting, privacy text, and store policy review.

## Current Backend State

Implemented:

- FastAPI app under `app/`.
- Routes for auth/session, patients, consents, devices, observations, documents, medicines, risk, escalation, agent messages/tools, and audit logs.
- In-memory repository for patients, consents, observations, medicines, schedules, and dose events.
- Risk evaluation rules and tests.
- Agent runtime config scaffold with only a mock adapter implemented.
- Mock channel dispatch, templates, call script rendering, and escalation simulation engine.
- SQL migrations for Supabase/Postgres schema and RLS design.
- OpenAPI contracts and backend docs.

Not production-ready:

- Auth is placeholder bearer/header auth, not real Supabase/Firebase JWT validation.
- Patient authorization is header-driven, not database-backed grants.
- Audit events are appended to request state, not persisted.
- Data is in memory, so it resets on process restart.
- No DB driver or ORM/data access layer is installed.
- No object storage upload, malware scan, OCR, vector/RAG, queue/outbox workers, webhook processors, or production providers.
- No Render deployment files are present yet: no `render.yaml`, `Dockerfile`, `Procfile`, `runtime.txt`, or `requirements.txt`.

Verification run:

- `python -m compileall app` passed.
- `python -m pytest` passed: 40 tests.

## Major Backend Work Still Left

1. Add production configuration management and a settings module.
2. Add database access using Supabase/Postgres and wire routes to migrations.
3. Validate the chosen auth provider's JWTs and map auth users to backend `user_accounts` / `auth_identities`.
4. Enforce patient access from `patient_access_grants`, not headers.
5. Persist audit logs, idempotency keys, outbox events, observations, documents, medicines, consents, risk events, escalation runs, dispatch attempts, and agent calls.
6. Implement transaction-scoped RLS variables for Supabase/Postgres access.
7. Implement document object storage, malware scan gating, OCR, extraction review, and retrieval.
8. Implement outbox/queue workers for observation ingestion, risk evaluation, provider dispatch, retries, and escalation state transitions.
9. Implement production provider adapters for push, WhatsApp, Telegram, SMS fallback, and voice.
10. Add webhook endpoints with signature verification, replay protection, idempotency, and audit.
11. Implement real agent runtime adapters or an OpenClaw gateway integration. Keep policy, consent, PHI access, and escalation authority in the backend.
12. Add CI/CD for tests, linting, OpenAPI validation, migration validation, and deployment smoke checks.

## Render Backend Deployment

Deploy source:

- Use `C:\Users\ASUS\Desktop\careagent-backend`.
- Do not deploy `careagent-backend-api`, `careagent-backend-channels`, `careagent-backend-risk-agent`, or `careagent-backend-supabase` as separate Render services unless you intentionally split services later.

Files/directories to include in the Render repo:

- `app/` - FastAPI application code.
- `pyproject.toml` - Python package/dependency metadata.
- `templates/` - message and call templates used by channel/escalation tests and future dispatch.
- `migrations/` - database schema source of truth.
- `openapi/` - API contracts.
- `supabase/config.toml` - Supabase project reference.
- `scripts/` - migration apply/validation helpers.
- `tests/` and `docs/` - not required at runtime, but should stay in the repo for CI and deployment review.

Do not deploy generated caches:

- `__pycache__/`
- `.pytest_cache/`
- local `.env` files
- build artifacts

Suggested Render web service settings for the current skeleton:

```text
Runtime: Python
Root directory: repository root
Build command: python -m pip install --upgrade pip && python -m pip install -e .
Start command: python -m uvicorn app.main:app --host 0.0.0.0 --port $PORT
Health check path: /health
```

Minimum Render environment variables for the current skeleton:

| Variable | Required now? | Purpose |
| --- | --- | --- |
| `PYTHON_VERSION=3.12.3` | Recommended | Match the local tested Python runtime. |
| `AGENT_RUNTIME_ADAPTER=mock` | Recommended | Keeps runtime in deterministic no-network mode. |
| `AGENT_RUNTIME_PROVIDER=mock` | Recommended | Avoids implying a real agent provider is wired. |
| `AGENT_RUNTIME_TIMEOUT_SECONDS=30` | Optional | Used by future runtime adapters. |

Environment variables needed once production backend work starts:

| Variable | Purpose |
| --- | --- |
| `ENVIRONMENT=production` | Runtime environment flag for settings/logging once implemented. |
| `LOG_LEVEL=info` | Runtime logging level once implemented. |
| `DATABASE_URL` | App database connection string for Postgres/Supabase once persistence is wired. |
| `SUPABASE_DB_URL` | Migration script connection string; currently used by `scripts/apply_migrations.ps1` and `scripts/validate_migrations.ps1`. |
| `SUPABASE_URL` | Supabase project API URL if backend uses Supabase services. |
| `SUPABASE_PROJECT_REF=kgkfrrffrjfltswwcsmw` | Project reference used in docs/config. |
| `SUPABASE_SERVICE_ROLE_KEY` | Server-only Supabase admin/storage operations if used. Never expose this in Flutter/Vercel public code. |
| `SUPABASE_JWKS_URL` or `SUPABASE_JWT_SECRET` | JWT verification, depending on final Supabase Auth validation approach. |
| `FIREBASE_PROJECT_ID` | Needed if the frontend stays on Firebase Auth and backend validates Firebase tokens. |
| `FIREBASE_SERVICE_ACCOUNT_JSON` | Server-only Firebase Admin credentials if Firebase Auth is selected. |
| `CORS_ALLOWED_ORIGINS` | Add the Vercel frontend URL and local dev origins once API calls are enabled. |
| `DOCUMENT_STORAGE_BUCKET` | Bucket name for uploaded medical documents. |
| `OPENCLAW_API_KEY`, `NEMOCLAW_API_KEY`, or `NVIDIA_API_KEY` | Future agent runtime provider key, depending on selected adapter. |
| `AGENT_RUNTIME_API_KEY_ENV` | Name of the env var containing the selected agent provider key. |
| `AGENT_RUNTIME_ENDPOINT_URL` | Future OpenClaw/NVIDIA/custom endpoint. |
| `WHATSAPP_ACCESS_TOKEN` | Future WhatsApp provider token. |
| `WHATSAPP_PHONE_NUMBER_ID` | Future WhatsApp sender phone number ID. |
| `WHATSAPP_WEBHOOK_VERIFY_TOKEN` | Future WhatsApp webhook verification token. |
| `WHATSAPP_APP_SECRET` | Future WhatsApp webhook signature verification. |
| `TELEGRAM_BOT_TOKEN` | Future Telegram provider token. |
| `TELEGRAM_WEBHOOK_SECRET` | Future Telegram webhook validation secret. |
| `FCM_SERVICE_ACCOUNT_JSON` | Future push notification provider credentials if using Firebase Cloud Messaging. |
| `SMS_PROVIDER_API_KEY` | Future SMS fallback provider credential. |
| `VOICE_PROVIDER_API_KEY` | Future programmable voice provider credential. |

Do not add production provider secrets until the matching code exists. For now, adding real WhatsApp/Telegram/voice keys to Render would not make those channels work.

## Vercel Frontend Deployment

Deploy source:

- Use `C:\Users\ASUS\Desktop\careagent` only if the target is a Flutter web build.
- Current repo is primarily Android-first and has no `web/` target. Add Flutter web support before creating the Vercel project.

Files/directories needed for a source-based Flutter web deploy:

- `pubspec.yaml`
- `pubspec.lock`
- `lib/`
- `web/` after running `flutter create --platforms=web .`
- `test/` optional for CI
- A Vercel build setup or script that installs Flutter in the Linux build environment.

Files not needed in the deployed Vercel output:

- `design/`
- `docs/`
- `memory/`
- `prompts/`
- `android/`
- `generated/`
- screenshots and PowerPoint scratch files

If deploying prebuilt static output, only deploy:

- `build/web/`

Current Vercel blockers:

- No `web/` folder.
- No `vercel.json`.
- No backend API base URL in the Flutter app.
- Current Firebase web config requires dart defines, but no Vercel build script exists to pass them into `flutter build web`.
- Current Android Firebase config is Studyspace-owned and should not be treated as CareAgent production config.

Vercel environment variables needed for the current Firebase web code:

| Variable | Purpose |
| --- | --- |
| `FIREBASE_API_KEY` | Firebase web API key. Public client config, but still keep it in Vercel env for build hygiene. |
| `FIREBASE_APP_ID` | Firebase web app ID. |
| `FIREBASE_MESSAGING_SENDER_ID` | Firebase sender ID. |
| `FIREBASE_PROJECT_ID` | Firebase project ID. |
| `FIREBASE_AUTH_DOMAIN` | Usually `<project>.firebaseapp.com`. |
| `FIREBASE_STORAGE_BUCKET` | Optional now; needed if web uses Firebase Storage later. |

Future frontend env variable to add before backend integration:

| Variable | Purpose |
| --- | --- |
| `CAREAGENT_API_BASE_URL` | Render backend API URL, for example `https://<service>.onrender.com`. The app code does not read this yet. |

Suggested Vercel build direction after adding web support:

```text
Framework preset: Other
Build command: install Flutter, run flutter pub get, then flutter build web --release with required --dart-define values
Output directory: build/web
```

For a simpler first preview, build locally with `flutter build web --release` and deploy the generated `build/web` folder through the Vercel CLI. For a repeatable Git-backed deploy, add a real build script.

## Recommended Next Order

1. Decide auth: Firebase or Supabase. This is the top architecture decision because it affects mobile login, backend auth validation, RLS, Vercel env vars, and Render env vars.
2. Create CareAgent-owned app credentials and package IDs. Stop using Studyspace package IDs for a CareAgent production build.
3. Add repository hygiene: `.gitattributes` for design HTML, ignore generated artifacts, and decide whether design files stay in the app repo.
4. Add Vercel web support only if a web frontend is required. Otherwise treat Vercel as a later caretaker dashboard target, not the Android app host.
5. Add Render deployment config for the backend skeleton after deciding whether to use direct Render settings or a committed `render.yaml`.
6. Build the backend persistence/auth layer before building more frontend screens against fake data.
7. Split Flutter code out of one large `main.dart` into features and wire a typed API client.
8. Implement the first end-to-end vertical slice: login, create/load patient profile, grant consent, submit manual vitals, evaluate risk, show alert, start simulation escalation, acknowledge alert, and write audit logs.

