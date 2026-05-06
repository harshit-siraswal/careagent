# Agent Runtime Selection

## 1. Decision

CareAgent should be Claw-compatible, not framework-locked.

Default direction:

- Prototype: OpenClaw as the channel gateway and agent runner because it is built around multi-channel messaging, including Telegram and WhatsApp-like channels.
- Production hardening: evaluate NVIDIA NemoClaw on top of OpenClaw because it adds sandboxing, network policy, lifecycle controls, and safer always-on execution. Do not treat it as production-ready while NVIDIA's latest docs mark NemoClaw as alpha and not for production.
- Edge/low-resource experiments: evaluate PicoClaw only for constrained-device gateways or local assistant experiments, not for critical healthcare production until maturity and security are proven.
- Production escalation execution: use deterministic backend orchestration, and evaluate Temporal or an equivalent workflow engine for long-running, retryable escalation runs. This is not a Claw runtime, but it is a stronger fit for emergency action durability than an autonomous agent loop.

The backend must expose an `AgentRuntimeAdapter` so agent runtimes can be swapped.

## 2. Why Not Hard-Lock to One Runtime

CareAgent has unusually high safety and compliance requirements:

- It handles health records.
- It may contact caretakers, doctors, and ambulance contacts.
- It may share location.
- It may speak on behalf of a patient.
- It may run long-lived monitoring and escalation workflows.

No agent runtime should be allowed to become the source of truth for medical risk, consent, policy, or audit. The runtime should orchestrate conversations and call approved backend tools. The backend should own safety decisions.

## 3. Runtime Adapter Contract

The adapter should hide runtime-specific details behind a stable interface:

```ts
interface AgentRuntimeAdapter {
  startSession(input: AgentSessionInput): Promise<AgentSession>;
  sendMessage(input: AgentMessageInput): Promise<AgentMessageResult>;
  registerTools(tools: AgentToolDefinition[]): Promise<void>;
  routeChannelEvent(event: ChannelEvent): Promise<RouteResult>;
  getTrace(sessionId: string): Promise<AgentTrace>;
  stopSession(sessionId: string): Promise<void>;
}
```

Required runtime capabilities:

- Channel event routing.
- Tool calling.
- Per-patient authorization context.
- Session persistence.
- Trace/audit export.
- Model/provider routing.
- Human-in-the-loop or policy interruption.
- Runtime-level allowlists and sandboxing where possible.

## 4. Candidate Matrix

| Candidate | Best Fit | Strengths | Concerns | CareAgent Recommendation |
| --- | --- | --- | --- | --- |
| OpenClaw | Multi-channel agent gateway | Self-hosted, channel-focused, WhatsApp/Telegram friendly, multi-agent routing, media support | Personal-agent style runtime; production healthcare needs extra guardrails | Use for prototype and channel gateway, wrapped by backend policy |
| NVIDIA NemoClaw | Safer always-on OpenClaw deployment | Adds OpenShell sandbox, network policy, lifecycle controls, NVIDIA model/tooling integration | Latest docs call it alpha and say not to use in production; NVIDIA stack complexity | Evaluate as a hardening candidate, but do not ship production healthcare workloads on it until status and security review change |
| PicoClaw | Low-resource edge gateway | Go-native, small footprint, Android/low-cost hardware focus, MCP support | Early rapid development; own docs warn not to deploy production before v1.0 | Use only for edge experiments or local gateway pilots |
| LangGraph | Durable stateful workflows | Durable execution, human-in-loop, memory, tracing, low-level control | More engineering work; channel gateway must be built separately | Strong option for risk/escalation workflow orchestration |
| OpenAI Agents SDK | OpenAI-centric managed agent workflows | Few abstractions, tools, handoffs, guardrails, tracing, sessions, voice/realtime support | Stronger if using OpenAI models; less channel-gateway focused | Good for internal agent workflows and voice assistant prototypes |
| Microsoft Semantic Kernel Agent Framework | Enterprise/.NET ecosystem | Multi-agent abstractions, Microsoft stack fit, .NET support | Less natural fit if backend is Python/FastAPI | Consider if enterprise customers require Microsoft stack |
| CrewAI | Multi-agent task teams | Crews and Flows; good for research/back-office automation | Overkill for safety-critical patient actions | Use only for non-critical back-office/research workflows |
| Temporal | Durable workflow engine, not an agent runtime | Crash-resumable workflows, retries, signals, long-running process state | Not Claw-compatible and not a channel gateway | Use for production escalation state machines if backend durability requirements exceed simple queues |

## 5. Recommended Architecture

Use a two-layer agent design.

Layer 1: Channel/runtime layer.

- OpenClaw/NemoClaw/PicoClaw handles incoming channel messages and agent turns.
- It converts app, WhatsApp, Telegram, and voice events into agent tasks.

Layer 2: Health safety control plane.

- Backend policy engine owns consent and action approval.
- Risk engine owns anomaly detection.
- Escalation engine owns call/message execution.
- Audit system records every read and action.

This means the agent can ask to call a doctor, but only the backend can approve and execute that call.

## 6. Better Option for Safety-Critical Workflows

For critical escalation, the best option is not a fully autonomous agent runtime. It is deterministic orchestration plus agent assistance.

Recommended:

- Use a deterministic workflow/state machine for risk and escalation.
- Use the agent only for summarization, natural language interaction, and tool requests.
- Consider LangGraph or a workflow engine for durable human-in-loop state.
- Keep emergency escalation in backend code with idempotency, audit logs, and policy approvals.

This is safer than letting any Claw-style runtime directly decide emergency actions.

## 7. Evaluation Criteria

Before choosing a production runtime, test:

- Can it enforce tool allowlists per patient/session?
- Can it export traces without leaking PHI?
- Can it run with network egress restrictions?
- Can it persist sessions safely?
- Can it pause for backend policy decisions?
- Can it support WhatsApp/Telegram media uploads?
- Can it survive process restarts without duplicate calls?
- Can it support model/provider routing?
- Can it be deployed in the target cloud/on-prem environment?
- Can security review inspect and lock down its plugins/skills?

## 8. Sources Checked

- OpenClaw overview: https://docs.openclaw.ai/index
- OpenClaw agent runtime: https://docs.openclaw.ai/concepts/agent
- PicoClaw GitHub: https://github.com/sipeed/picoclaw
- NVIDIA NemoClaw latest developer guide: https://docs.nvidia.com/nemoclaw/latest/index.html
- NVIDIA Agent Intelligence Toolkit: https://docs.nvidia.com/nemo/agent-toolkit/1.1/
- LangGraph overview: https://docs.langchain.com/oss/python/langgraph/overview
- OpenAI Agents SDK: https://openai.github.io/openai-agents-python/
- Microsoft Semantic Kernel Agent Framework: https://learn.microsoft.com/en-us/semantic-kernel/frameworks/agent/
- CrewAI introduction: https://docs.crewai.com/en/introduction
- Temporal docs: https://docs.temporal.io/

## 9. Scored Recommendation Matrix

Scores are relative to CareAgent's needs: patient-scoped tool calling, channel routing, auditability, deployment safety, and emergency workflow durability. A high score does not mean the runtime may approve medical risk decisions.

| Candidate | Channel routing | Tool control | Audit/trace fit | Workflow durability | Deployment maturity for CareAgent | Overall call |
| --- | --- | --- | --- | --- | --- | --- |
| OpenClaw | High | Medium | Medium | Medium | Medium | Prototype channel gateway |
| NVIDIA NemoClaw | High | Medium | Medium | Medium | Low until alpha label changes | Security evaluation track |
| PicoClaw | Medium | Medium | Low | Low | Low for healthcare | Edge prototype only |
| LangGraph | Low | High | High with LangSmith or custom tracing | High | Medium | Durable agent workflow option |
| OpenAI Agents SDK | Low | High | High | Medium | High if OpenAI PHI processing is approved | Internal agent/eval/voice option |
| Semantic Kernel Agent Framework | Low | High | Medium | Medium | Medium where Microsoft stack is required | Enterprise alternative |
| CrewAI | Low | Medium | Medium | Medium | Medium for non-critical automation | Back-office only |
| Temporal | Low | High for deterministic activities | High with custom audit | Very high | High | Production escalation workflow engine |

## 10. Prototype Choice

Prototype with:

- OpenClaw as the channel gateway for app/WebChat-style testing, Telegram, and prototype WhatsApp-style flows.
- CareAgent `AgentToolServer` as the only tool surface exposed to the runtime.
- Backend policy middleware before every write, communication, call, location, or escalation action.
- Official WhatsApp Business Cloud API/BSP adapters for any healthcare demo that leaves a private prototype environment.
- OpenAI Agents SDK as an optional eval harness for prompt, tool-policy, and simulated-patient tests.

Prototype exit criteria:

- Every runtime tool call produces an `AgentToolCall` and `AuditLog` record.
- Cross-patient fixtures produce zero leaks.
- Prompt-injection fixtures produce zero unauthorized tool attempts.
- Critical escalation simulation produces no duplicate call/message actions under retry.

## 11. Production Choice

Production should not be "one autonomous runtime owns CareAgent." Production should be:

- A stable `AgentRuntimeAdapter` boundary.
- Official channel providers for WhatsApp, Telegram, push, and voice.
- A backend-owned policy engine, risk engine, escalation engine, audit store, and consent ledger.
- Deterministic orchestration for escalation runs, with Temporal or equivalent workflow infrastructure if queues plus database state are not enough.
- A swappable conversational runtime. OpenClaw can remain the channel gateway if security review approves its deployment mode. NemoClaw can become the hardened OpenClaw deployment only after its alpha/not-for-production status changes and CareAgent security review validates it.

For an MVP pilot, the safest production-leaning path is OpenClaw for low/medium-risk channel conversations plus backend-owned official channel adapters and deterministic escalation. Use LangGraph or Temporal for long-running escalation state, not for medical decision authority.

## 12. Runtime Adapter Interface

The adapter must keep all runtime-specific choices out of patient APIs:

```ts
interface AgentRuntimeAdapter {
  startSession(input: AgentSessionInput): Promise<AgentSession>;
  sendMessage(input: AgentMessageInput): Promise<AgentMessageResult>;
  registerTools(tools: AgentToolDefinition[]): Promise<void>;
  routeChannelEvent(event: ChannelEvent): Promise<RouteResult>;
  getTrace(sessionId: string): Promise<AgentTrace>;
  stopSession(sessionId: string): Promise<void>;
}
```

Adapter invariants:

- The backend resolves exactly one active `patient_id` before PHI retrieval.
- Tool definitions are registered with action class, input schema, output schema, and policy gates.
- The runtime never receives provider credentials, contact phone numbers, raw patient lists, or webhook secrets.
- Runtime traces are redacted before export outside PHI-approved storage.
- Any adapter can be disabled per channel, per patient, or per action class without changing patient APIs.

## 13. Security Risks

Key risks and required mitigations:

| Risk | Mitigation |
| --- | --- |
| Runtime prompt injection from uploaded reports or channel messages | Label untrusted content, retrieve snippets only, never build tool instructions from retrieved text, test malicious fixtures |
| Cross-patient data leakage for caretakers | Router provides one patient scope at a time; tool server recomputes authorization; mixed-patient PHI summaries denied |
| Unauthorized calls/messages/location sharing | Policy engine checks consent, risk event, confirmation, rate limits, template, and idempotency before dispatch |
| WhatsApp Web automation compliance risk | Prototype-only unless compliance approves; production uses WhatsApp Business Cloud API/BSP |
| Runtime trace PHI leakage | Redact traces, store PHI traces only in approved audit storage, disable vendor telemetry where required |
| Duplicate emergency actions after retries or restarts | Use idempotency keys and deterministic escalation run state |
| Runtime supply-chain/plugin risk | Pin versions, review plugins, use allowlists, egress policy, sandboxing where available |

## 14. Integration Plan

1. Define `AgentRuntimeAdapter` and runtime-neutral event/tool types.
2. Add `backend/openapi/agent-runtime-tools.openapi.yaml` as the source contract for tool registration.
3. Implement `AgentToolServer` policy middleware before runtime-specific adapters.
4. Build read-only profile, vitals, device, medicine, and document tools.
5. Add low-risk medicine logging with confirmation and idempotency.
6. Add official channel adapters and map OpenClaw channel events into the CareAgent router.
7. Add high-risk communication, call, and escalation tools in simulation mode.
8. Add prompt-injection, patient-isolation, policy-denial, and duplicate-escalation tests.
9. Evaluate NemoClaw sandbox and network policy in a non-production environment.
10. Decide whether escalation state remains in backend queues or moves to Temporal/LangGraph based on durability test results.

## 15. Migration Plan

The selected runtime can change later if:

- The `AgentRuntimeAdapter` contract stays stable.
- Tool schemas remain versioned and backward compatible.
- Prompt versions are stored with every conversation and trace.
- Channel identity and patient scope live in CareAgent, not the runtime memory store.
- Runtime sessions map to CareAgent conversation IDs.
- New runtime adapters pass the same simulated-patient eval set before receiving production traffic.

Migration steps:

1. Run the new adapter in shadow mode on redacted historical conversations.
2. Register the same tool schemas in read-only mode.
3. Compare tool requests, refusals, source citations, and policy outcomes.
4. Enable low-risk channels for a small cohort.
5. Enable write/communication tools only after audit parity and zero-leak tests pass.
6. Keep rollback by routing conversations back to the previous adapter through `runtime_name` flags.
