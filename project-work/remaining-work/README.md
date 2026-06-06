# Remaining Work Execution Queue

Last updated: 2026-06-06

This queue converts the latest CareAgent docs into actionable implementation lanes. It intentionally does not replace the numbered docs. It points agents and developers to the next concrete project work.

## Current Priority Order

| Priority | Lane | Active repo | Why it is next | Exit criteria |
| --- | --- | --- | --- | --- |
| P0 | Firebase and first patient bootstrap | `careagent`, `careagent-backend` | The pilot slice needs a real authenticated user and durable patient profile. | New Firebase user can create/load one patient profile, owner grant is durable, tests cover duplicate bootstrap. |
| P0 | Consent and safety notice persistence | `careagent`, `careagent-backend` | Consent is required before health data, channels, calls, or agent tools become trustworthy. | Consent grant/revoke is persisted and audited; frontend shows current state after restart. |
| P0 | Manual vitals to risk event | `careagent`, `careagent-backend` | This is the shortest meaningful health-monitoring vertical slice. | Manual observation is saved, latest vitals displays it, abnormal reading can create deterministic risk event and alert. |
| P0 | Simulation-only escalation | `careagent`, `careagent-backend` | Emergency behavior must be proven without real provider dispatch. | Escalation policy/run/acknowledgement are idempotent, audited, and marked simulation-only. |
| P1 | Groq-backed in-app AI reply hardening | `careagent-backend`, `careagent` | The app will use Groq for AI replies, but provider access must remain server-side and policy-bound. | Backend Groq config is deployed with `GROQ_API_KEY`; chat UI handles loading/errors; no Groq key appears in Flutter or public env. |
| P1 | OpenClaw prototype agent gateway | `careagent-backend`, OpenClaw host | App/channel chat needs a real runtime boundary while backend policy stays in control. | OpenClaw can route a test message to backend adapter/tool server with no PHI leakage and no unauthorized actions. |
| P1 | Typed Flutter API client and feature modules | `careagent` | Current app shell is too centralized for production feature work. | `lib/main.dart` is split into clear modules and API DTOs cover pilot slice calls. |
| P1 | Documents and medicine MVP | `careagent`, `careagent-backend` | Product value needs prescriptions, reminders, and source-backed document answers. | Upload/review/reminder flows work in sandbox and are audited. |
| P2 | Real channel providers | `careagent-backend` | WhatsApp, Telegram, push, SMS, and voice need official/sandbox adapters before pilot. | Webhooks, signatures, retries, receipts, and test-mode dispatch are covered. |
| P2 | Caretaker dashboard | New or existing web surface | Caretaker workflows depend on stable patient, alert, and audit primitives. | Verified caretaker can view assigned patients, acknowledge alerts, and see audit-safe timelines. |

## Work Rules

- Build the pilot slice first. Do not expand breadth before account, patient, consent, vitals, risk, escalation simulation, and audit survive restart.
- Keep Firebase Auth as MVP identity and Supabase/Postgres as durable data unless the architecture decision is deliberately changed.
- Keep the backend as the authority for PHI access, consent, risk, calls, messages, location, escalation, and audit.
- Keep `GROQ_API_KEY` in the backend deployment environment only. Flutter must call CareAgent backend APIs, never Groq directly.
- Keep OpenClaw behind `AgentRuntimeAdapter`; do not give it direct database access or real provider credentials.
- Use simulation-only behavior until product, legal, compliance, and engineering approve real calls/messages.

## Progress Notes

2026-06-06:

- Frontend safety notice acknowledgement now persists by version through platform preferences and is covered by a restart widget test.
- Backend patient bootstrap now exposes owned patient scope through `/me` and lets the same actor reload the created profile without sending a patient header in local/test auth mode.
- Backend duplicate patient bootstrap remains blocked with `patient_profile_already_exists`.
- Remaining Firebase bootstrap work: verify the same create/load behavior with real CareAgent-owned Firebase credentials in production auth mode.
- Frontend pilot workspace now loads backend consent state after patient load and can grant or revoke the MVP pilot consent.
- Remaining consent work: build the full consent center, add consent update flows, verify restart behavior against a configured backend, and handle revocation side effects in policy caches/workers.
- Backend now has a Groq `AgentRuntimeAdapter` for in-app AI replies, selected with `AGENT_RUNTIME_ADAPTER=groq`, `AGENT_RUNTIME_PROVIDER=groq`, and backend-only `GROQ_API_KEY`.
- Remaining Groq work: persist conversations, add source-grounded retrieval/citations, minimize PHI in prompts, build frontend chat states, and add safety/prompt-injection evals.
- Backend observation ingestion now runs deterministic risk evaluation and creates risk events/alerts for abnormal readings.
- Frontend pilot workspace now submits a manual vital, refreshes latest vitals, and surfaces generated risk/alert state from the backend response.
- Remaining manual-vitals work: replace raw maps with typed DTOs, add patient-threshold configuration, persist the flow under real Supabase/Firebase production mode, and move risk evaluation into durable worker/outbox processing.

## Source Docs

- `docs/24-ai-system-architecture-and-project-handbook.md`
- `docs/19-remaining-work-report.md`
- `docs/20-current-app-deployment-report.md`
- `docs/21-production-readiness-audit-report.md`
- `docs/09-mvp-acceptance-criteria.md`
- `docs/12-implementation-backlog.md`
