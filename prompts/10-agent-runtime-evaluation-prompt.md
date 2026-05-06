# Prompt: Agent Runtime Evaluation Workstream

You are responsible for evaluating the agent runtime for CareAgent.

Read:

- `docs/14-agent-runtime-selection.md`
- `docs/02-trd.md`
- `docs/04-agent-and-channel-requirements.md`
- `docs/05-safety-compliance-and-risk.md`
- `docs/09-mvp-acceptance-criteria.md`

Evaluate:

- OpenClaw.
- NVIDIA NemoClaw.
- PicoClaw.
- LangGraph.
- OpenAI Agents SDK.
- Semantic Kernel Agent Framework.
- CrewAI.
- Any stronger current option you can justify with primary sources.

Important constraints:

- CareAgent is a health coordination and escalation product.
- The runtime must not own medical risk decisions.
- Calls, messages, location sharing, and emergency escalation must go through backend policy.
- The selected runtime must support tool restrictions, auditing, channel routing, and safe deployment.
- WhatsApp Web style automation is prototype-only unless compliance approves it.

Deliver:

- Recommendation matrix.
- Prototype choice.
- Production choice.
- Runtime adapter interface.
- Security risks.
- Integration plan.
- Migration plan if the selected runtime changes later.
