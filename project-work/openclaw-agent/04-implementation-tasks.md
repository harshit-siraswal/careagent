# OpenClaw Implementation Tasks

Last updated: 2026-06-06

## Milestone 1 - Documentation And Config Alignment

- [x] Create OpenClaw project-work pack.
- [x] Confirm backend already has mock `AgentRuntimeAdapter`.
- [x] Confirm backend has agent tool policy helpers.
- [ ] Update backend `docs/agent-runtime-configuration.md` if adapter implementation details change.
- [ ] Update `docs/24-ai-system-architecture-and-project-handbook.md` after a real OpenClaw adapter lands.

Done when:

- Project-work pack names the exact backend files to change.
- README links to this pack.

## Milestone 2 - Local OpenClaw Gateway

- [ ] Install Node 24 or supported Node 22.19+.
- [ ] Install OpenClaw.
- [ ] Run onboarding.
- [ ] Confirm gateway status.
- [ ] Open dashboard at `http://127.0.0.1:18789/`.
- [ ] Run `openclaw security audit`.
- [ ] Save non-secret setup notes in this pack if the local steps differ.

Done when:

- OpenClaw can respond to a dashboard test message.
- No PHI or CareAgent credentials are present in OpenClaw state.

## Milestone 3 - Backend Adapter Skeleton

- [ ] Add OpenClaw transport abstraction.
- [ ] Add `OpenClawAgentRuntimeAdapter`.
- [ ] Add factory support for `AGENT_RUNTIME_ADAPTER=openclaw`.
- [ ] Add request/response mapping helpers.
- [ ] Add fail-closed error handling.
- [ ] Keep `mock` as default.

Done when:

- `python -m pytest tests/test_agent_runtime_adapter.py` passes.
- New OpenClaw adapter tests pass without a live gateway.
- Secret redaction tests still pass.

## Milestone 4 - Tool Server Bridge

- [ ] Define OpenClaw-facing tool schema from `AGENT_TOOL_NAMES`.
- [ ] Route each tool request through `build_tool_request`.
- [ ] Evaluate every request with `authorize_tool_request`.
- [ ] Audit allowed and denied tool calls.
- [ ] Return redacted, source-aware tool output.
- [ ] Deny unknown or malformed tool calls.

Done when:

- Read tools require the correct scopes.
- Critical tools require consent, emergency policy, simulation mode where applicable, and idempotency.
- Tests cover denied and allowed paths.

## Milestone 5 - Conversation And Channel Routing

- [ ] Define channel event envelope for app/WebChat/Telegram/WhatsApp prototype.
- [ ] Resolve channel sender to actor and patient before runtime call.
- [ ] Persist conversation/message records in CareAgent database.
- [ ] Store OpenClaw session IDs only as routing metadata.
- [ ] Add unknown-sender and multi-patient isolation tests.

Done when:

- One verified sender can complete a test conversation.
- Unknown sender cannot access patient tools.
- A caretaker with multiple patients cannot accidentally leak patient A into patient B.

## Milestone 6 - Private Staging Deployment

- [ ] Run OpenClaw on private VM/container.
- [ ] Restrict gateway to private network or tailnet.
- [ ] Configure backend endpoint URL to private gateway.
- [ ] Disable broad OpenClaw tools for CareAgent traffic.
- [ ] Add monitoring for adapter timeouts and failures.
- [ ] Run security audit and record findings.

Done when:

- Backend can reach OpenClaw.
- Public internet cannot reach OpenClaw.
- Staging round trip works with test data only.

## Milestone 7 - Safety And Evals

- [ ] Add prompt-injection tests for document and channel text.
- [ ] Add stale-data response tests.
- [ ] Add cross-patient leakage tests.
- [ ] Add critical-action consent denial tests.
- [ ] Add duplicate escalation idempotency tests.
- [ ] Add trace redaction tests.

Done when:

- Tests fail closed on unsafe requests.
- Redacted traces do not contain credentials, raw documents, broad vitals history, or provider secrets.

## Milestone 8 - Production Decision

- [ ] Decide whether OpenClaw remains prototype-only or moves toward production hardening.
- [ ] Evaluate NemoClaw or another sandbox/network-policy wrapper.
- [ ] Select official production providers for WhatsApp, Telegram, push, SMS, and voice.
- [ ] Complete legal/compliance review for automated messages and calls.
- [ ] Add runbooks and rollback steps for provider incidents.

Done when:

- There is a written production go/no-go decision.
- Real provider dispatch is never reachable through OpenClaw directly.

