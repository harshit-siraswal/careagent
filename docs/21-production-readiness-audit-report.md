# CareAgent Production Readiness Audit Report

Date: 2026-05-11

Prepared for: CareAgent project team

Prepared by: Codex repository audit

## 1. Executive Summary

CareAgent is not production ready. The repositories contain a credible planning pack, a Flutter client shell, a FastAPI backend, Supabase/Postgres schema work, and automated tests. However, the current implementation is still a controlled pilot/skeleton rather than a production healthcare application.

Overall readiness rating: Red - do not launch with real users, real PHI, real emergency automation, or real provider dispatch.

The most important blockers are:

1. Android release build currently fails because `android/app/google-services.json` does not contain a Firebase client for `app.careagent.patient`.
2. The active frontend is still mostly a placeholder shell, with core product flows not implemented: onboarding, consent, vitals, device sync, medicines, document intelligence, caretaker dashboard, chat, channels, and emergency workflow.
3. Backend production authentication and authorization are incomplete. Firebase token validation exists, but the first signed-in patient cannot create a patient profile under the production Firebase actor path because no `patient:write` permission or grant exists yet.
4. Backend can silently run with in-memory storage if `DATABASE_URL` is absent, which would lose all data on restart.
5. Database/RLS integration is incomplete. The Supabase deployment notes require backend-set transaction variables, but the Postgres repository opens autocommit connections and never sets those variables.
6. Migration tooling is out of date. `scripts/apply_migrations.ps1` applies only migrations `001` to `003`, while the active repo contains migrations through `008`.
7. Provider integrations are not production implementations. Channels use mock adapters, the agent runtime is mock/stubbed, documents return an `s3://` placeholder upload target, and webhook endpoints are missing.
8. No CI/CD pipeline is present for either active repo.
9. Security and operational hardening are not complete: public OpenAPI/docs are enabled by default, there is no trusted-host middleware, no rate limiting, no request size limits, no observability stack, no production incident runbook, and no store/compliance evidence.

The current code is suitable for contract iteration and controlled local/pilot demos only after replacing the incorrect Firebase Android config. It is not suitable for production health monitoring, PHI processing, caretaker alerting, or emergency escalation.

## 2. Scope

Primary folders reviewed:

| Folder | Role | Audit disposition |
| --- | --- | --- |
| `C:\Users\ASUS\Desktop\careagent` | Active Flutter app, design docs, planning pack | Active frontend repo |
| `C:\Users\ASUS\Desktop\careagent-backend` | Active consolidated FastAPI backend | Active backend repo |

Related folders reviewed:

| Folder | Finding |
| --- | --- |
| `C:\Users\ASUS\Desktop\careagent-backend-api` | Older split workstream. Its app, migrations, OpenAPI, tests, and docs are represented in the consolidated backend. Do not deploy separately. |
| `C:\Users\ASUS\Desktop\careagent-backend-channels` | Older split channels workstream. Templates and tests are represented in the consolidated backend. Do not deploy separately. |
| `C:\Users\ASUS\Desktop\careagent-backend-risk-agent` | Older split risk/agent workstream. Risk and agent files are represented in the consolidated backend. Do not deploy separately. |
| `C:\Users\ASUS\Desktop\careagent-backend-supabase` | Older split Supabase workstream. Supabase scripts/config are represented in the consolidated backend. Do not deploy separately. |
| `C:\Users\ASUS\Desktop\careagent_agents` | Parallel workstream copies and planning/design artifacts. Not a deployment source. |
| `C:\Users\ASUS\Desktop\careagent_remote_check` | Minimal README only. Not a deployment source. |

## 3. Validation Performed

| Check | Result |
| --- | --- |
| `flutter analyze` in `careagent` | Passed, no analyzer issues |
| `flutter test --no-pub` in `careagent` | Passed, 4 tests |
| `flutter build web --release --no-pub` in `careagent` | Passed, built `build\web`; emitted a Cupertino icon-font warning |
| `flutter build apk --release --no-pub` in `careagent` | Failed at `:app:processReleaseGoogleServices`; no Firebase client for `app.careagent.patient` |
| `python -m compileall app` in `careagent-backend` | Passed |
| `python -m pytest` in `careagent-backend` | Passed, 41 tests |
| Backend route vs OpenAPI comparison | Missing channel/webhook/device integration routes remain |
| CI discovery | No `.github` workflow found in active frontend or backend repo |

## 4. Repository Disposition

The active shipping sources should be:

1. Frontend: `C:\Users\ASUS\Desktop\careagent`
2. Backend: `C:\Users\ASUS\Desktop\careagent-backend`

The split backend folders should be archived or clearly marked read-only. A script comparison found no files in the split workstream `app`, `migrations`, `openapi`, `templates`, `tests`, `docs`, `scripts`, or `supabase` directories that are missing from the consolidated backend. Keeping all copies active creates a high risk of applying fixes to the wrong folder.

## 5. Critical Findings

### C-01. Android release build is blocked by incorrect Firebase client configuration

Severity: Critical

Evidence:

- `C:\Users\ASUS\Desktop\careagent\android\app\build.gradle.kts:24` sets `applicationId = "app.careagent.patient"`.
- `C:\Users\ASUS\Desktop\careagent\android\app\google-services.json:2-5` points to the `studyspace-kiet` Firebase project.
- `C:\Users\ASUS\Desktop\careagent\android\app\google-services.json:12`, `:20`, `:28`, `:64`, and `:72` reference `me.mystudyspace.android` or `me.studyshare.android`, not `app.careagent.patient`.
- `flutter build apk --release --no-pub` failed with `No matching client found for package name 'app.careagent.patient'`.

Impact:

The Android app cannot produce a release APK. Even if forced, it would be using non-CareAgent Firebase configuration.

Required remediation:

1. Create a CareAgent-owned Firebase project/client for `app.careagent.patient`.
2. Register the correct release and debug SHA fingerprints.
3. Replace the local `google-services.json`.
4. Rotate or restrict the existing Studyspace Firebase API key if it was exposed outside its intended app.
5. Add CI that runs `flutter build apk --release` before any release branch can ship.

### C-02. Production Firebase auth cannot bootstrap a first patient profile

Severity: Critical

Evidence:

- Production defaults to Firebase auth when `ENVIRONMENT=production`: `C:\Users\ASUS\Desktop\careagent-backend\app\core\config.py:18-20`.
- The Firebase actor path derives permissions only from persistent grants: `C:\Users\ASUS\Desktop\careagent-backend\app\core\security.py:176-183`.
- New Firebase accounts are created as role `patient` without patient grants: `C:\Users\ASUS\Desktop\careagent-backend\app\services\care_data.py:652-667`.
- `POST /patients` requires `patient:write`: `C:\Users\ASUS\Desktop\careagent-backend\app\api\routes.py:117-120`.
- `require_permission()` denies a plain `patient` role unless explicit permission exists: `C:\Users\ASUS\Desktop\careagent-backend\app\core\security.py:139-149`.

Impact:

A newly authenticated production user cannot create their first patient profile. This blocks onboarding and all downstream patient-scoped flows.

Required remediation:

Define and implement a bootstrap authorization path. Recommended approach:

1. Allow an authenticated user with no existing patient profile to create exactly one self-owned patient profile.
2. In the same transaction, create the owner grant and any default patient permissions.
3. Add tests for first-profile creation, duplicate prevention, patient-scope denial, inactive account denial, and revoked-grant denial.
4. Re-run the pilot frontend flow against production auth mode.

### C-03. Backend can start with volatile in-memory storage in production

Severity: Critical

Evidence:

- `DATABASE_URL` defaults to empty: `C:\Users\ASUS\Desktop\careagent-backend\app\core\config.py:17`.
- Repository selection falls back to `InMemoryCareRepository()` when no database URL exists: `C:\Users\ASUS\Desktop\careagent-backend\app\services\care_data.py:1552-1555`.
- Render marks `DATABASE_URL` as `sync: false`, requiring manual configuration: `C:\Users\ASUS\Desktop\careagent-backend\render.yaml:24-25`.

Impact:

A misconfigured production deployment can pass health checks while losing all patients, consents, observations, documents, audit events, and escalations on restart.

Required remediation:

1. In production, fail fast if `DATABASE_URL` is missing.
2. Add a startup readiness check that verifies database connectivity and required migrations.
3. Split `test`, `development`, `staging`, and `production` settings explicitly.
4. Add a deployment smoke test that creates and reads a durable record in staging.

### C-04. Supabase RLS integration is incomplete

Severity: Critical

Evidence:

- Deployment notes state backend request handling must set `app.user_id` and `app.role` inside the transaction before accessing patient-scoped tables: `C:\Users\ASUS\Desktop\careagent-backend\docs\supabase-deployment.md:59-64`.
- The Postgres repository opens autocommit connections: `C:\Users\ASUS\Desktop\careagent-backend\app\services\care_data.py:1318-1324`.
- No `set_config`, `app.user_id`, or `app.role` setting was found in the backend Python code.

Impact:

Depending on the database role used, production will either bypass the intended RLS model or fail RLS-protected queries. Both outcomes are unacceptable for PHI.

Required remediation:

1. Decide the database access model: restricted app role with RLS, or backend service role plus strict application authorization. For PHI, prefer defense-in-depth with a restricted role and RLS.
2. Introduce request-scoped transactions.
3. Set `app.user_id`, `app.role`, and any required patient/grant context before PHI queries.
4. Add integration tests against a real local Supabase/Postgres instance with RLS enabled.
5. Prohibit use of the `postgres` superuser connection string by the runtime app.

### C-05. Migration application script omits current migrations

Severity: Critical

Evidence:

- The repo contains migrations `001` through `008`.
- `C:\Users\ASUS\Desktop\careagent-backend\scripts\apply_migrations.ps1:19-23` applies only `001_initial_backend_platform.sql`, `002_health_device_integrations.sql`, and `003_channels_calls_escalation.sql`.
- `C:\Users\ASUS\Desktop\careagent-backend\README.md:10-14` documents later migrations `004` through `008`.
- `C:\Users\ASUS\Desktop\careagent-backend\docs\supabase-deployment.md:12-20` lists only `001` through `006`, also missing `007` and `008`.

Impact:

Fresh environments will miss security/performance fixes and auth bridge migrations. This can create mismatched schemas between local, staging, and production.

Required remediation:

1. Update migration tooling to apply all current migrations in order.
2. Add migration history and idempotent environment validation.
3. Add CI validation that fails when a migration file exists but is not in the apply sequence.
4. Update deployment documentation to match the active migration set.

## 6. High Findings

### H-01. The active Flutter app is mostly a pilot shell, not the product described in the PRD

Evidence:

- The frontend has only four Dart source files under `lib/`.
- `C:\Users\ASUS\Desktop\careagent\lib\main.dart` is a large monolithic file of about 2,000 lines.
- Placeholder screens are used for key product surfaces: `C:\Users\ASUS\Desktop\careagent\lib\main.dart:1614-1628`.
- Product sections explicitly describe future functionality for onboarding, consent, vitals, medicines, documents, chat, and SOS: `C:\Users\ASUS\Desktop\careagent\lib\main.dart:1845-2080`.
- MVP acceptance criteria require consent revocation, health-device connection, medicine reminders, OCR, source-cited answers, channel support, alerts, emergency simulation, and PHI audit: `C:\Users\ASUS\Desktop\careagent\docs\09-mvp-acceptance-criteria.md:8-113`.

Impact:

The current app can demonstrate navigation and selected pilot backend calls, but it cannot perform the product's primary user workflows.

Required remediation:

Refactor into feature modules and implement the MVP flows in this order: account/onboarding, consent, durable patient profile, vitals/manual entry, device sync, medicine schedules/reminders, documents, alerts, caretaker access, chat/tool confirmations, emergency simulation.

### H-02. Auth architecture is split between Firebase and Supabase

Evidence:

- Frontend uses Firebase Auth packages: `C:\Users\ASUS\Desktop\careagent\pubspec.yaml:13-15`.
- Backend production config defaults to Firebase: `C:\Users\ASUS\Desktop\careagent-backend\.env.example:3`.
- Backend docs and migrations still include Supabase Auth bridge material: `C:\Users\ASUS\Desktop\careagent-backend\README.md:13-14`, `C:\Users\ASUS\Desktop\careagent-backend\docs\supabase-google-auth.md:83-97`.

Impact:

Identity mapping, JWT validation, RLS, user lifecycle, and mobile/web redirect behavior are not governed by one final architecture.

Required remediation:

Make a written auth decision for MVP: Firebase Auth or Supabase Auth. Then remove or clearly quarantine the unused path, update migration docs, update frontend config, update backend token validation, and add end-to-end auth tests.

### H-03. Release signing is not configured

Evidence:

- Android release build signs with debug config: `C:\Users\ASUS\Desktop\careagent\android\app\build.gradle.kts:31-35`.

Impact:

The Android artifact is not suitable for Play Store/internal production distribution.

Required remediation:

Add release signing through secure CI secrets or a local release keystore workflow. Document key custody, rotation, and Play App Signing setup.

### H-04. Backend public docs and OpenAPI remain enabled by default

Evidence:

- `FastAPI(...)` is created without disabling `docs_url`, `redoc_url`, or `openapi_url`: `C:\Users\ASUS\Desktop\careagent-backend\app\main.py:12-16`.
- Runtime introspection showed `/openapi.json`, `/docs`, and `/redoc` are registered.

Impact:

For a public healthcare API, this expands reconnaissance surface. It may be acceptable for staging, but production should deliberately protect or disable these routes.

Required remediation:

Disable or protect docs in production. Keep them enabled only in development/staging behind authentication or network restrictions.

### H-05. Backend request hardening is incomplete

Evidence:

- CORS allows credentials with all methods and headers: `C:\Users\ASUS\Desktop\careagent-backend\app\main.py:17-22`.
- No trusted-host middleware, rate limiting, body size limits, or abuse controls were found.
- Settings read CORS origins as simple comma-separated strings without production validation: `C:\Users\ASUS\Desktop\careagent-backend\app\core\config.py:23-31`.

Impact:

The backend lacks baseline controls against host-header abuse, accidental permissive CORS, brute force, oversized request bodies, and noisy automation.

Required remediation:

Add production settings validation, trusted hosts, strict CORS allowlist, request size limits at edge and app, rate limits on auth/document/agent/escalation routes, and abuse monitoring.

### H-06. OpenAPI contracts exceed implemented routes

Evidence:

Automated route/spec comparison found missing implemented routes:

- Core OpenAPI missing in app: `/webhooks/telegram`, `/webhooks/voice`, `/webhooks/whatsapp`.
- Channels OpenAPI missing in app: channel links, channel messages, emergency simulations, and webhook routes.
- Health-device OpenAPI missing in app: device catalog detail, compatibility check, support requests, connector accounts, and simulator runs.

Impact:

Client teams can build against contracts that the backend does not serve.

Required remediation:

Add a CI contract check that compares FastAPI routes to OpenAPI contracts. Either implement the missing routes or mark them as future contracts outside the production API.

### H-07. Agent runtime and agent tool execution remain stubbed

Evidence:

- Mock adapter returns a deterministic no-network response: `C:\Users\ASUS\Desktop\careagent-backend\app\agent\runtime.py:154-177`.
- Agent message route returns a stub response: `C:\Users\ASUS\Desktop\careagent-backend\app\api\routes.py:487-492`.
- Agent tool route returns `status: stubbed`: `C:\Users\ASUS\Desktop\careagent-backend\app\api\routes.py:495-499`.

Impact:

The product cannot provide source-grounded assistance, tool confirmations, real policy-mediated tool execution, or model/provider observability.

Required remediation:

Implement the selected agent gateway, persistent conversations, prompt/tool versioning, policy decision logging, PHI redaction, source citations, refusal tests, and human confirmation cards.

### H-08. Channels, calls, and emergency communication are simulation-only

Evidence:

- Default channel adapters are mock simulators for push, WhatsApp, Telegram, SMS, email, and voice: `C:\Users\ASUS\Desktop\careagent-backend\app\services\channels.py:206-214`.
- Webhook routes are missing from the active app.

Impact:

No production caretaker messages, receipts, acknowledgements, fallback retries, or voice calls can be delivered.

Required remediation:

Add production provider adapters, verified channel linking, webhook signature verification, replay protection, provider receipt handling, retry/fallback workers, and emergency simulation isolation.

### H-09. Document upload and intelligence are placeholders

Evidence:

- Document init creates an `s3://` URI and returns it as the upload URL: `C:\Users\ASUS\Desktop\careagent-backend\app\services\care_data.py:1027-1058`.
- OCR and extraction are initialized as blocked: `C:\Users\ASUS\Desktop\careagent-backend\app\services\care_data.py:1036-1038`.
- Frontend document action is labeled placeholder: `C:\Users\ASUS\Desktop\careagent\lib\main.dart:1335-1343`.

Impact:

The app cannot accept real medical documents, scan for malware, perform OCR/extraction, review facts, or answer questions from source documents.

Required remediation:

Implement signed upload URLs, object storage, malware scanning, OCR, extraction, review/correction, source links, vector/RAG indexing, and prompt-injection defenses.

### H-10. Backend database access is not production grade

Evidence:

- Each repository operation opens a new psycopg connection with `autocommit=True`: `C:\Users\ASUS\Desktop\careagent-backend\app\services\care_data.py:1318-1324`.
- No connection pool, request transaction scope, retry policy, or structured database error handling was found.

Impact:

Production traffic will suffer avoidable latency and connection pressure, and multi-step writes are not atomic.

Required remediation:

Add a connection pool, request-scoped transaction management, explicit isolation for multi-write workflows, retry policy for transient failures, and query timing instrumentation.

## 7. Medium Findings

### M-01. Frontend API client lacks production resiliency

Evidence:

- The client uses raw `Map<String, dynamic>` payloads rather than typed domain models: `C:\Users\ASUS\Desktop\careagent\lib\core\careagent_api.dart:30-215`.
- Requests have no timeout or retry policy: `C:\Users\ASUS\Desktop\careagent\lib\core\careagent_api.dart:217-265`.
- JSON decode assumes object responses: `C:\Users\ASUS\Desktop\careagent\lib\core\careagent_api.dart:255-257`.

Impact:

Network hangs, schema drift, non-object error bodies, and offline conditions will produce poor user-facing behavior.

Required remediation:

Introduce typed DTOs, bounded timeouts, retry/backoff where safe, normalized error envelopes, offline-aware UX, and telemetry.

### M-02. Safety notice acceptance is not persisted

Evidence:

- `_acceptedSafetyNotice` is process-local state only: `C:\Users\ASUS\Desktop\careagent\lib\main.dart:429-447`.

Impact:

The app cannot prove user disclosure acceptance or versioned safety notice history.

Required remediation:

Persist disclosure acceptance with text version, timestamp, locale, actor, and audit record. Re-prompt when safety text changes.

### M-03. Backend audit coverage is incomplete

Evidence:

- Audit events are accumulated in request state and persisted after route handling: `C:\Users\ASUS\Desktop\careagent-backend\app\core\audit.py:52-56`, `C:\Users\ASUS\Desktop\careagent-backend\app\main.py:25-30`.
- Failed authorization attempts and unhandled validation failures are not clearly audited.

Impact:

The audit trail will miss important denied/failed events, which is material for PHI systems.

Required remediation:

Audit auth failures, patient-scope denials, validation failures on sensitive routes, webhook rejections, provider failures, and background worker actions. Add tests for negative-path audit events.

### M-04. No production observability stack is present

Evidence:

- No structured logging, metrics, tracing, crash reporting, error aggregation, uptime checks, or alerting configuration was found.

Impact:

Production incidents, failed escalations, queue backlogs, provider failures, and auth errors will be difficult to detect and resolve.

Required remediation:

Add structured JSON logs with request IDs, metrics, trace IDs, health/readiness endpoints, Sentry or equivalent error capture, provider dashboards, and escalation-specific alerts.

### M-05. Dependency and build reproducibility are incomplete

Evidence:

- Backend has version ranges in `pyproject.toml` but no lockfile: `C:\Users\ASUS\Desktop\careagent-backend\pyproject.toml:6-18`.
- Vercel build script clones Flutter `stable` at build time: `C:\Users\ASUS\Desktop\careagent\scripts\vercel_build.sh:4-6`.
- `flutter analyze` reported 11 packages with newer versions incompatible with current constraints.

Impact:

Builds can drift over time and dependency security posture is not formally controlled.

Required remediation:

Pin Flutter SDK version, add backend lockfile workflow, add dependency review, and run scheduled dependency updates with tests.

### M-06. Product/legal readiness is not evidenced

Evidence:

- Safety docs call out health-data sensitivity, emergency boundaries, ABDM/HIPAA/GDPR-style requirements, and privacy controls: `C:\Users\ASUS\Desktop\careagent\docs\05-safety-compliance-and-risk.md:66-109`.
- No privacy policy artifact, data retention policy, deletion/export workflow, clinical review signoff, store policy evidence, or incident runbook was found in active app code.

Impact:

The application cannot responsibly handle real health data or emergency flows without legal/compliance review.

Required remediation:

Complete privacy policy, terms, consent text, data retention/deletion/export process, clinical safety review, escalation disclaimers, emergency provider review, and store compliance checklist.

## 8. Positive Findings

1. The backend has meaningful domain contracts, schemas, migrations, and tests.
2. Backend tests passed locally: 41 tests.
3. Flutter analyzer and widget tests passed locally.
4. Flutter web release build completed.
5. Supabase migrations include RLS policies and security/performance hardening work.
6. The product docs explicitly acknowledge high-risk areas: consent, emergency automation, audit, PHI, provider compliance, stale data, and model safety.
7. The active backend consolidated the older split workstreams, reducing deployment complexity if the duplicates are archived.

## 9. Production Readiness Scorecard

| Domain | Rating | Reason |
| --- | --- | --- |
| Product completeness | Red | Most user-facing MVP workflows remain placeholders |
| Android release readiness | Red | Release APK fails due Firebase client mismatch; release signing uses debug |
| Web deployment readiness | Amber | Web build passes, but app is still pilot shell and config-dependent |
| Backend API readiness | Amber/Red | Tests pass, but production auth/bootstrap, missing routes, mocks, and RLS integration block launch |
| Data persistence | Red | DB repo exists, but fallback to memory and RLS/transaction gaps remain |
| Auth and authorization | Red | Mixed Firebase/Supabase direction and first-profile bootstrap failure |
| Security baseline | Red | Missing production guards, rate limits, docs protection, CI, and negative-path audit |
| Device integrations | Red | Health Connect/BLE/vendor connectors not implemented |
| Medicines/reminders | Red | Placeholder frontend; backend CRUD exists but no real reminders/offline behavior |
| Documents/OCR/RAG | Red | Placeholder upload target, no OCR, no storage, no retrieval |
| Agent runtime | Red | Mock/stub only |
| Channels/calls/escalation | Red | Mock dispatch only; webhooks missing |
| Observability/operations | Red | No monitoring, logging standard, alerts, runbooks, or CI/CD |
| Compliance/legal | Red | Requirements documented, but implementation evidence missing |

## 10. Priority Remediation Roadmap

### Phase 0 - Repository and release hygiene, 1 to 3 days

1. Archive or mark read-only the split backend workstream folders.
2. Replace Studyspace Firebase Android config with a CareAgent-owned config.
3. Configure release signing.
4. Update migration scripts and docs to include migrations `001` through `008`.
5. Add `.github` workflows for frontend analyze/test/build and backend compile/test.
6. Add production settings validation so missing `DATABASE_URL`, invalid CORS, and missing auth config fail at startup.

Exit criteria:

- Android release build passes.
- Backend cannot start in production without durable database and auth settings.
- CI is required for merges/releases.

### Phase 1 - Auth, database, and patient bootstrap, 3 to 7 days

1. Finalize Firebase vs Supabase auth architecture.
2. Implement first patient bootstrap with owner grant creation.
3. Implement request-scoped database transactions and RLS session variables.
4. Add connection pooling.
5. Add production/staging integration tests against Postgres/Supabase.
6. Add negative authorization/audit tests.

Exit criteria:

- A real user can sign in, create one patient profile, grant/revoke consent, and read/write only authorized patient data.
- Audit logs persist across restarts.

### Phase 2 - MVP vertical slice, 1 to 3 weeks

1. Refactor Flutter into feature modules with typed API models.
2. Implement backend-connected onboarding and consent.
3. Implement manual vitals with freshness/source display.
4. Implement medicine CRUD and local reminder fallback.
5. Implement document signed upload, malware scan state, OCR/extraction placeholders, and review UI.
6. Implement risk event creation from observations and alert display.
7. Implement emergency simulation end to end without real provider calls.

Exit criteria:

- The documented MVP demo scenario can be executed end to end in staging with durable data and audit logs.

### Phase 3 - Provider and agent productionization, 2 to 5 weeks

1. Implement selected agent runtime adapter and policy-mediated tool execution.
2. Implement provider adapters for push, WhatsApp, Telegram, SMS fallback, and voice.
3. Implement webhook signature verification, receipt handling, idempotency, replay protection, and retries.
4. Implement caretaker dashboard or caretaker-facing app surface.
5. Add observability, incident alerts, and support runbooks.

Exit criteria:

- Provider sandbox tests pass.
- No real emergency call path can activate without explicit consent, verified contacts, and policy approval.
- Provider failures are observable and retried according to documented policy.

### Phase 4 - Compliance and launch readiness, 2 to 4 weeks

1. Complete privacy policy, terms, data retention, deletion/export, and consent text.
2. Complete clinical/safety review of risk thresholds, emergency disclaimers, and unsafe-agent refusals.
3. Complete security review: secrets, RLS, dependency scanning, penetration test scope, mobile storage, API abuse controls.
4. Complete Play Store/internal distribution review.
5. Run staging pilot with synthetic data, then limited real-user pilot only after legal approval.

Exit criteria:

- Production readiness review signed off by engineering, product, safety/clinical, security, and legal/compliance owners.

## 11. Immediate Action List

Recommended next ten tasks:

1. Replace `android/app/google-services.json` with the correct CareAgent Firebase client and rerun `flutter build apk --release --no-pub`.
2. Change production settings so missing `DATABASE_URL` is fatal.
3. Update `scripts/apply_migrations.ps1` to include migrations `004` through `008`.
4. Implement first-patient bootstrap and owner grant creation.
5. Add a GitHub Actions workflow for Flutter analyze/test/web build/APK build.
6. Add a GitHub Actions workflow for backend compile/pytest and migration list validation.
7. Add FastAPI production guards: disable/protect docs, trusted hosts, strict CORS validation, request size limits, and rate limits.
8. Add Postgres pooling and transaction-scoped RLS variables.
9. Convert the pilot frontend flow from raw maps to typed API models with timeouts.
10. Decide and document Firebase vs Supabase as the single MVP auth system.

## 12. Audit Conclusion

CareAgent has the right architectural direction and a useful amount of backend contract work, but it is still in pilot engineering stage. The code should not be considered production ready until release configuration, durable auth/data paths, RLS, CI/CD, core product workflows, provider integrations, document processing, observability, and compliance evidence are complete.

The most efficient path is to harden one end-to-end MVP vertical slice first: sign in, create patient, grant consent, record manual vitals, create risk event, run emergency simulation, notify a verified caretaker in sandbox, and persist a complete audit trail. Once that vertical slice is stable in staging, expand to device integrations, document intelligence, and real provider channels.
