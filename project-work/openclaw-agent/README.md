# OpenClaw Agent Work Pack

Last updated: 2026-06-06

This pack defines the CareAgent OpenClaw prototype gateway work. The goal is to deploy OpenClaw as a channel/runtime gateway while keeping health safety, PHI access, tool authorization, consent, escalation, and audit inside the CareAgent backend.

## Current CareAgent State

Already built in `C:\Users\ASUS\Desktop\careagent-backend`:

- `app/agent/runtime.py`: `AgentRuntimeAdapter` protocol, request/response types, mock adapter, secret redaction.
- `app/agent/runtime.py`: Groq adapter for direct in-app AI replies. This is not the OpenClaw gateway adapter.
- `app/services/agent_runtime.py`: environment-driven runtime config builder and adapter factory.
- `app/services/agent_tools.py`: policy-wrapped agent tool contract helpers.
- `app/services/policy.py`: deterministic policy decisions for critical tools.
- `tests/test_agent_runtime_adapter.py`: adapter contract and secret-redaction tests.
- `tests/test_agent_tools_contract.py`: tool contract and policy tests.
- `docs/agent-runtime-configuration.md`: existing backend runtime configuration notes.

Not built yet:

- Networked OpenClaw adapter.
- OpenClaw host deployment.
- Channel ingress mapping from OpenClaw to CareAgent conversations.
- Tool server endpoint or bridge usable by OpenClaw.
- Conversation persistence and PHI-safe trace export.
- Prompt-injection, cross-patient isolation, and stale-data evals.

## Non-Negotiable Boundary

OpenClaw may route messages and request tools. It must not become the medical safety system.

Groq is the selected direct model provider for current in-app assistant replies. The Groq API key belongs only in the CareAgent backend deployment environment. OpenClaw work remains a separate channel/runtime gateway lane and must not receive raw provider keys unless a later, reviewed deployment explicitly requires a gateway token.

Backend owns:

- Firebase-authenticated identity and patient access grants.
- Consent and action policy.
- PHI reads and redaction.
- Risk severity and alert creation.
- Calls, messages, location sharing, escalation, and provider dispatch.
- Audit logs and idempotency.

OpenClaw must not:

- Connect directly to Supabase/Postgres.
- Store raw PHI in unmanaged OpenClaw memory.
- Hold production WhatsApp, voice, SMS, database, or service-role credentials.
- Execute shell, browser, filesystem, or network tools for CareAgent production traffic.
- Send caretaker, doctor, ambulance, WhatsApp, Telegram, SMS, push, or voice messages without backend authorization.

## Pack Files

Read in order:

1. `01-deployment-plan.md`
2. `02-backend-adapter-contract.md`
3. `03-tool-policy-and-safety.md`
4. `04-implementation-tasks.md`

## Sources Checked

- OpenClaw docs: https://docs.openclaw.ai/
- OpenClaw getting started: https://docs.openclaw.ai/start/getting-started
- OpenClaw security: https://docs.openclaw.ai/gateway/security
- OpenClaw channels: https://docs.openclaw.ai/channels
- OpenClaw configuration: https://docs.openclaw.ai/gateway/configuration
