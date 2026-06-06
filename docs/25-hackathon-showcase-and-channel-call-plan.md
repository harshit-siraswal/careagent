# Hackathon Showcase and Channel/Call MVP Plan

Date: 2026-06-06

## Purpose

This document resets the near-term product direction from a thin shell to a
hackathon-ready MVP demo. The app should show a complete care story with
synthetic data while the backend keeps production guardrails for real
WhatsApp, Telegram, and voice dispatch.

## Demo Story

Primary patient:

- Ravi Sharma, 68, Noida.
- Conditions: type 2 diabetes, hypertension, post-stent follow-up.
- Current incident: heart rate 132 bpm and SpO2 91% from recent device data.
- Reviewed records: prescription, WhatsApp lab photo, discharge summary.
- Active schedule: Metformin, Telmisartan, Atorvastatin, Aspirin review.

Demo flow:

1. Sign in and acknowledge the safety notice.
2. Home shows synthetic patient state, consent count, vitals, alerts, contacts,
   medicines, documents, and channel runbook.
3. Open Vitals and show source-labelled abnormal readings.
4. Open Documents and show reviewed/OCR facts with source provenance.
5. Open Medicines and show dose state plus caretaker notification policy.
6. Open Channels and show WhatsApp, Telegram, push, SMS, and voice readiness.
7. Open SOS and start the multi-channel simulation.
8. Open Alerts and acknowledge the critical alert.

## Multi-Contact Escalation Ladder

Default MVP ladder:

| Step | Channel | Recipient | Expected behaviour |
| --- | --- | --- | --- |
| 1 | Push | Patient | Ask for confirmation and show evidence. |
| 2 | WhatsApp | Primary caretaker | Send approved urgent template with ack link/button. |
| 3 | Telegram | Secondary caretaker | Send bot message with inline acknowledge/escalate buttons. |
| 4 | Voice call | Primary caretaker | AI-disclosed test call with DTMF 1 acknowledgement. |
| 5 | Voice call | Doctor | Minimum-necessary clinical summary if caretaker does not ack. |
| 6 | Voice call | Private ambulance contact | Disabled until explicit policy/provider/legal approval. |

Rules:

- Every dispatch attempt needs a stable idempotency key.
- No duplicate call storms: default maximum is 1 to 2 voice attempts per
  contact per incident.
- Acknowledgement does not mark the patient healthy; it only records human
  receipt.
- Location sharing stays disabled unless separate consent and policy approve it.
- Public emergency number calling is not part of the first demo unless legal
  and provider approval are confirmed.

## WhatsApp MVP Plan

Production path:

- Use WhatsApp Business Cloud API directly or an approved BSP.
- Keep browser/Web automation prototype-only.

Backend requirements:

- Store contact channel links with verification status.
- Store approved template names and locale mapping.
- Verify webhook signatures.
- Normalize delivery, read, failed, and reply events.
- Support button/link acknowledgement.
- Enforce consent, quiet-hours override policy, and rate limits.

Templates needed:

- `critical_escalation_caretaker_v1`
- `urgent_vitals_alert_v1`
- `missed_dose_caretaker_v1`
- `daily_summary_caretaker_v1`
- `account_verification_v1`

Inputs needed from your side:

- WhatsApp Business Account or BSP choice.
- Phone number ID and business display phone.
- Approved template names and languages.
- Webhook public URL and verify token.
- Whether demo recipients can use real phone numbers.

## Telegram MVP Plan

Production path:

- Use Telegram Bot API with webhook delivery.

Backend requirements:

- Generate signed deep links with nonce: `/start careagent_<nonce>`.
- Link Telegram chat ID to a verified patient/caretaker contact.
- Reject medical commands from unverified chats.
- Support inline buttons for acknowledge, call doctor, and escalate.
- Verify webhook source and rate-limit commands.

Bot commands:

- `/summary`
- `/vitals`
- `/medicines`
- `/ack <incident_id>`
- `/upload`
- `/help`

Inputs needed from your side:

- Telegram bot token.
- Bot username.
- Webhook URL domain.
- Demo Telegram accounts for patient/caretaker testing.

## Voice Call MVP Plan

Provider options:

- Exotel: strong India fit and local telephony path.
- Twilio: mature APIs and easier global testing.
- Plivo: alternative programmable voice/SMS provider.

Recommended first decision:

- Pick Exotel if India production calling is the first target.
- Pick Twilio if fastest hackathon test-call setup matters more than local
  deployment fit.

Backend requirements:

- Store versioned call scripts.
- Reject scripts without AI disclosure.
- Place test calls through provider adapter.
- Receive call status callbacks.
- Capture DTMF or speech acknowledgement.
- Persist call attempt, answer, timeout, retry, and ack statuses.
- Never call public emergency services in simulation mode.

Minimum script opening:

```text
This is CareAgent, an AI assistant calling with authorization from Ravi Sharma.
```

Inputs needed from your side:

- Voice provider choice.
- Caller ID / virtual number.
- Provider credentials.
- Whether calls should use TTS or pre-recorded audio first.
- Maximum retry policy per contact.
- Whether private ambulance contacts are allowed in MVP.

## Backend Work Needed

Already present:

- Provider-agnostic channel domain models.
- Mock provider adapters.
- Escalation engine.
- Simulation runner.
- Idempotency and policy checks in tests.

Still needed for real MVP:

- Persistent channel link tables wired to API routes.
- Dispatch worker/outbox queue.
- WhatsApp, Telegram, and voice webhook routes with signature checks.
- Provider-specific adapters behind the existing channel contract.
- Contact verification endpoints in the mobile app.
- Incident timeline returned to patient app and caretaker dashboard.

## Frontend Work Needed

Completed in this pass:

- Synthetic patient demo data.
- Multiple contacts and care roles.
- Rich vitals, medicines, documents, chat, alerts, channels, and SOS runbook.
- Mobile app-bar polish for long signed-in emails.

Next frontend work:

- Add a one-tap "Run demo" sequence that advances the incident timeline.
- Add a caretaker-facing dashboard preview.
- Add provider setup forms for WhatsApp, Telegram, and voice test calls.
- Add QR/deep-link screen for Telegram linking.
- Add WhatsApp template status and webhook health screen.

## Groq and Agent Work

The app should continue to use the backend as the policy boundary. Groq can
generate summaries, draft messages, and explain evidence, but the backend must
authorize every tool call, channel send, and voice call before dispatch.

Required Groq-backed demo behaviours:

- Explain why the alert fired.
- Summarize recent vitals and reviewed documents.
- Draft WhatsApp/Telegram alert text with AI disclosure.
- Draft call summary from approved script variables.
- Refuse diagnosis, medication changes, or emergency-service replacement.
