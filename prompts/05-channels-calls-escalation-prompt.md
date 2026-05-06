# Prompt: Channels, Calls, and Escalation Workstream

You are responsible for WhatsApp, Telegram, push, SMS fallback, voice calls, and escalation execution.

Read:

- `docs/04-agent-and-channel-requirements.md`
- `docs/05-safety-compliance-and-risk.md`
- `docs/02-trd.md`

Build or plan:

- WhatsApp integration.
- Telegram bot integration.
- Push notification service.
- Programmable voice calling.
- Contact verification.
- Message templates.
- Call scripts.
- Delivery receipts.
- Retry/fallback chain.
- Escalation run tracking.

Important constraints:

- Use official WhatsApp Business Cloud API or approved BSP for production.
- OpenClaw/PicoClaw WhatsApp Web style channels are prototype-only unless compliance accepts them.
- WhatsApp may require approved templates for business-initiated messages.
- Telegram requires account verification before accepting medical commands.
- Voice calls must disclose AI identity.
- Emergency calls require explicit consent and policy approval.
- iOS cannot silently place normal cellular calls. Android SMS automation is restricted.

Deliver:

- Channel architecture.
- Template library.
- Call script library.
- Escalation state machine.
- Provider abstraction.
- Failure/retry behavior.
- End-to-end emergency simulation tests.
