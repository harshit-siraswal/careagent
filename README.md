# CareAgent Planning Pack

This workspace contains the product and technical planning pack generated from:

- `C:\Users\ASUS\Downloads\Agentic-Health-Manager.pptx`
- The expanded product requirements about Claw-compatible agent runtimes, WhatsApp/Telegram/app support, automated calls/messages, caretaker login, medicine/report intelligence, emergency escalation, and near-universal device support.

## Start Here

Read in this order:

1. `docs/00-source-brief.md`
2. `docs/01-prd.md`
3. `docs/02-trd.md`
4. `docs/03-device-integration-strategy.md`
5. `docs/14-agent-runtime-selection.md`
6. `docs/07-roadmap-and-workstreams.md`
7. The relevant prompt from `prompts/`

## Document Map

- `docs/00-source-brief.md` - extracted deck understanding and updated product direction.
- `docs/01-prd.md` - product requirements, user stories, scope, risk tiers, MVP.
- `docs/02-trd.md` - technical architecture, components, APIs, reliability, testing.
- `docs/03-device-integration-strategy.md` - support strategy for fitness bands, smart watches, and medical devices.
- `docs/04-agent-and-channel-requirements.md` - Claw-compatible agent runtime, WhatsApp, Telegram, voice/call, and action policy requirements.
- `docs/05-safety-compliance-and-risk.md` - safety posture, consent, emergency, privacy, compliance, and AI-risk rules.
- `docs/06-data-model-and-api.md` - core data model, API examples, event topics, and audit events.
- `docs/07-roadmap-and-workstreams.md` - phased roadmap and parallel execution streams.
- `docs/08-architecture-diagrams.md` - architecture diagrams and event flows.
- `docs/09-mvp-acceptance-criteria.md` - epics and acceptance criteria for MVP delivery.
- `docs/10-agent-runtime-prompts.md` - reusable runtime prompt templates.
- `docs/11-ui-product-spec.md` - patient app, caretaker dashboard, channel, and voice UX requirements.
- `docs/12-implementation-backlog.md` - implementation backlog by domain.
- `docs/13-risk-rule-catalog.md` - initial risk rule catalog and governance.
- `docs/14-agent-runtime-selection.md` - OpenClaw, PicoClaw, NVIDIA NemoClaw, and alternative agent runtime evaluation.
- `docs/15-mobile-app-workstream.md` - mobile app implementation plan that still needs Flutter alignment.
- `docs/16-agent-runtime-workstream.md` - Claw-compatible agent runtime implementation plan, prompts, tools, policies, flows, tests, and adapter contract.
- `docs/17-channels-calls-escalation-workstream.md` - WhatsApp, Telegram, push, SMS fallback, voice calls, provider abstraction, escalation state machine, templates, scripts, and simulation tests.
- `docs/18-health-device-integrations-workstream.md` - HealthKit, Health Connect, BLE, device catalog, normalization, data quality, and simulator contracts.
- `docs/19-remaining-work-report.md` - current implementation gap report across the app and backend repositories.

## Backend Workstream Artifacts

Backend artifacts now live in the dedicated backend repository:

- Local path: `C:\Users\ASUS\Desktop\careagent-backend`
- GitHub: `https://github.com/harshit-siraswal/careagent-backend`
- Supabase project: `careagent-backend` / `kgkfrrffrjfltswwcsmw` in `ap-south-1`

Use that repo for backend API code, SQL migrations, OpenAPI contracts, channel/escalation contracts, and backend tests.

## Parallel Context Windows

Use `prompts/00-master-context.md` plus one specific workstream prompt:

- `prompts/01-mobile-app-prompt.md`
- `prompts/02-backend-api-prompt.md`
- `prompts/03-agent-runtime-prompt.md`
- `prompts/04-health-device-integrations-prompt.md`
- `prompts/05-channels-calls-escalation-prompt.md`
- `prompts/06-document-intelligence-prompt.md`
- `prompts/07-caretaker-dashboard-prompt.md`
- `prompts/08-safety-compliance-qa-prompt.md`
- `prompts/09-risk-engine-prompt.md`
- `prompts/10-agent-runtime-evaluation-prompt.md`

Each workstream is written so it can be copied into a separate context window without needing the whole project history.

## Key Product Decision

CareAgent should support "nearly all" devices through compatibility tiers, not by promising direct support for every device model:

1. HealthKit and Health Connect.
2. Standard BLE medical profiles.
3. Vendor APIs and SDKs.
4. FHIR/ABDM-style health records.
5. Manual entry, CSV, OCR, and photo fallback.

## Key Safety Decision

OpenClaw, PicoClaw, NVIDIA NemoClaw, or another selected runtime should orchestrate and explain, but safety-critical actions must be approved by deterministic backend policy. Calls, messages, location sharing, and emergency escalation require explicit consent, audit logging, and platform-compliant execution.
