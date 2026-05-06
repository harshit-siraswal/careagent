# Channels Provider Runbook

This runbook describes how CareAgent should configure and operate WhatsApp, Telegram, push, SMS, voice, and simulator providers for the channels and escalation workstream.

## Provider Modes

| Mode | Purpose | Allowed Providers | External Emergency Calls |
| --- | --- | --- | --- |
| `local` | Developer testing | Simulation, local push mocks, prototype WhatsApp Web with allowlist | No |
| `staging` | Integration testing | Simulation, provider sandboxes, test WhatsApp/Telegram bots, test voice numbers | No |
| `production` | Real users | WhatsApp Cloud API or approved BSP, Telegram Bot API, FCM/APNs, approved SMS/voice providers | Only after policy and compliance approval |

Production must block `prototype_whatsapp_web` and any provider account marked `prototype_only = true`.

## Secrets and Accounts

- Store provider credentials in the managed secret store; reference them by `provider_account_id`.
- Keep separate provider accounts for staging and production.
- Rotate webhook secrets after suspected exposure and at least on a scheduled security cadence.
- Do not log provider access tokens, raw phone numbers, Telegram chat IDs, or WhatsApp IDs. Store normalized references or salted hashes where possible.
- Limit provider dashboards to operators with a business need and MFA.

## Webhook Ingress Checklist

Every provider webhook handler must:

1. Verify provider signature or token before parsing PHI-bearing payloads.
2. Reject replayed callbacks using timestamp tolerance and `provider_event_id`.
3. Normalize payloads into `delivery_receipts` or inbound channel messages.
4. Store raw payloads only in restricted object storage with a redacted summary in the database.
5. Apply monotonic status precedence so stale callbacks cannot downgrade state.
6. Emit audit events for accepted, rejected, invalid-signature, and replayed callbacks.

## WhatsApp Operations

- Production uses official WhatsApp Business Cloud API or an approved BSP.
- Business-initiated messages outside the service window must use approved provider templates.
- Template lifecycle is tracked as `draft`, `pending_provider_approval`, `approved`, `rejected`, `paused`, `disabled`, or `superseded`.
- PHI-bearing templates require compliance review before provider submission.
- Prototype WhatsApp Web automation is local/demo only and must never carry production PHI.

## Telegram Operations

- Users and contacts must link Telegram through `/start` nonce plus OTP or app confirmation.
- Until verified, the bot responds only with verification instructions and accepts no medical commands or uploads.
- Telegram uploads go through malware scanning, document classification, prompt-injection controls, and patient-scope authorization before extraction.

## Push Operations

- FCM/APNs tokens bind to authenticated app sessions and are invalidated on logout, token rotation, or suspected compromise.
- Push delivery is not treated as human acknowledgement. Acknowledgement requires an app/dashboard action or a verified channel callback.
- Mobile OS constraints still apply; server push cannot silently place cellular calls or send SMS.

## SMS and Voice Operations

- SMS is fallback-only, region-gated, consent-gated, and provider-based. Do not depend on silent iOS SMS or broad Android SMS automation.
- Voice calls use cloud telephony or controlled VoIP, not native cellular call audio takeover.
- Every voice script must begin with CareAgent AI identity disclosure and authorization language.
- Call recording/transcription is disabled unless separate consent and regional/provider approval are active.
- Default critical call limit is two attempts per contact per escalation run unless compliance approves otherwise.

## Emergency Simulation

- Emergency simulations must set `block_production_providers = true`.
- Public emergency numbers and ambulance contacts are simulated unless an explicitly approved production incident policy is active.
- Simulator callbacks must be signed with the staging simulation webhook secret.
- Simulation reports must show expected steps, actual steps, skipped reasons, provider invocations, and audit-log completeness.

## Incident Review Artifacts

For every high or critical run, operators should be able to retrieve:

- Risk event evidence snapshot and policy decision ID.
- Ordered escalation plan and action statuses.
- Dispatch attempts, provider IDs, normalized receipts, and retry decisions.
- Acknowledgement actor, method, timestamp, and verification status.
- Cancellation reason or terminal failure reason.
- Proof that emergency actions had consent, configured policy, and event evidence.
