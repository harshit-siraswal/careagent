# Agent Runtime Selection

## 1. Decision

CareAgent should be Claw-compatible, not framework-locked.

Default direction:

- Prototype: OpenClaw as the channel gateway and agent runner because it is built around multi-channel messaging, including Telegram and WhatsApp-like channels.
- Production hardening: evaluate NVIDIA NemoClaw on top of OpenClaw because it adds sandboxing, network policy, lifecycle controls, and safer always-on execution.
- Edge/low-resource experiments: evaluate PicoClaw only for constrained-device gateways or local assistant experiments, not for critical healthcare production until maturity and security are proven.

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
| NVIDIA NemoClaw | Safer always-on OpenClaw deployment | Adds OpenShell sandbox, network policy, lifecycle controls, NVIDIA model/tooling integration | Early preview; NVIDIA stack complexity | Strong production candidate for sandboxed OpenClaw |
| PicoClaw | Low-resource edge gateway | Go-native, small footprint, Android/low-cost hardware focus, MCP support | Early rapid development; own docs warn not to deploy production before v1.0 | Use only for edge experiments or local gateway pilots |
| LangGraph | Durable stateful workflows | Durable execution, human-in-loop, memory, tracing, low-level control | More engineering work; channel gateway must be built separately | Strong option for risk/escalation workflow orchestration |
| OpenAI Agents SDK | OpenAI-centric managed agent workflows | Few abstractions, tools, handoffs, guardrails, tracing, sessions, voice/realtime support | Stronger if using OpenAI models; less channel-gateway focused | Good for internal agent workflows and voice assistant prototypes |
| Microsoft Semantic Kernel Agent Framework | Enterprise/.NET ecosystem | Multi-agent abstractions, Microsoft stack fit, .NET support | Less natural fit if backend is Python/FastAPI | Consider if enterprise customers require Microsoft stack |
| CrewAI | Multi-agent task teams | Crews and Flows; good for research/back-office automation | Overkill for safety-critical patient actions | Use only for non-critical back-office/research workflows |

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
- NVIDIA NemoClaw overview: https://docs.nvidia.com/nemoclaw/0.0.5/about/overview.html
- NVIDIA Agent Intelligence Toolkit: https://docs.nvidia.com/nemo/agent-toolkit/1.1/
- LangGraph overview: https://docs.langchain.com/oss/python/langgraph/overview
- OpenAI Agents SDK: https://openai.github.io/openai-agents-python/
- Microsoft Semantic Kernel Agent Framework: https://learn.microsoft.com/en-us/semantic-kernel/frameworks/agent/
- CrewAI introduction: https://docs.crewai.com/en/introduction
