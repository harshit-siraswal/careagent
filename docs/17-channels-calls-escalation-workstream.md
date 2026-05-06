# Channels, Calls, and Escalation Workstream Plan

This document turns prompt 05 into an implementation plan for CareAgent channel delivery, programmable voice calls, and policy-driven escalation. It is grounded in the PRD/TRD, agent and channel requirements, safety requirements, and the initial backend schema.

## 1. Scope and Guardrails

This workstream owns:

- WhatsApp production integration through the official WhatsApp Business Cloud API or an approved BSP.
- Telegram Bot API integration.
- Push notification routing through FCM/APNs.
- SMS fallback where lawful and explicitly configured.
- Programmable voice calls through providers such as Twilio, Exotel, or Plivo.
- Contact verification and channel account linking.
- Message template and call script registries.
- Delivery receipts, call status events, acknowledgements, and retry history.
- Escalation run execution and emergency simulation mode.

Non-negotiable guardrails:

- The agent runtime can draft and orchestrate, but the policy engine authorizes high-risk messages, calls, and emergency escalation.
- WhatsApp Web automation, including OpenClaw/PicoClaw/Baileys style channels, is prototype-only unless compliance explicitly approves it.
- Telegram medical commands are disabled until the chat is linked to a verified CareAgent account or contact.
- Every voice call starts with AI identity disclosure and patient authorization language.
- Emergency calls, repeated phone calls, and location sharing require explicit consent, configured policy, risk-event evidence, and audit logging.
- Native iOS cellular calls and SMS cannot be silently automated. Android SMS automation is restricted and must not be a production dependency.

## 2. Channel Architecture

### 2.1 Runtime Flow

1. `RiskEngine`, `AgentRuntimeAdapter`, mobile app, or worker emits an action request.
2. `ActionPolicyService` checks patient scope, consent, risk event, channel opt-in, quiet-hours override, and emergency policy.
3. `CommunicationOrchestrator` chooses a provider adapter and creates a `channel_dispatch_attempt`.
4. Provider adapter sends message, push, SMS, or call with an idempotency key.
5. Webhook ingress verifies provider signature and normalizes provider events.
6. `ReceiptProcessor` updates dispatch status, `messages`, `escalation_actions`, and audit logs.
7. `EscalationRunner` advances the state machine or schedules fallback retries.

### 2.2 Component Boundaries

| Component | Responsibility | Must Not Do |
| --- | --- | --- |
| `ChannelLinkService` | OTP/app-based linking, channel account status, command enablement | Accept medical commands from unverified accounts |
| `TemplateRegistry` | Versioned templates, WhatsApp approval metadata, variable validation | Send unapproved business-initiated WhatsApp text |
| `CallScriptRegistry` | Versioned voice scripts, AI disclosure text, DTMF/speech options | Let LLM-generated speech bypass reviewed scripts |
| `CommunicationOrchestrator` | Provider selection, dispatch creation, fallback scheduling | Make safety decisions |
| `ProviderAdapter` | Provider API calls and webhook normalization | Store secrets in code or logs |
| `EscalationRunner` | Ordered execution, acknowledgements, completion, incident timeline | Create duplicate call storms |
| `EmergencySimulationRunner` | Full-flow dry runs against simulator providers | Call real emergency services |

### 2.3 Provider Abstraction

All providers implement the same backend-facing contract:

```ts
type ProviderSendRequest = {
  patientId: string;
  contactId?: string;
  channel: "push" | "whatsapp" | "telegram" | "sms" | "voice" | "email";
  templateId?: string;
  scriptId?: string;
  locale: string;
  variables: Record<string, string>;
  mediaRefs?: Array<{ type: "image" | "document" | "location"; ref: string }>;
  idempotencyKey: string;
  simulation: boolean;
  policyDecisionId: string;
};

type ProviderSendResult = {
  status: "accepted" | "sent" | "failed" | "simulated";
  providerMessageId?: string;
  providerCallId?: string;
  retryAfterSeconds?: number;
  errorCode?: string;
  safeUserMessage?: string;
};
```

Provider adapters:

- `WhatsAppCloudAdapter`: production default, supports templates, interactive buttons, media, receipts.
- `WhatsAppBspAdapter`: approved BSP adapter with the same internal contract.
- `PrototypeWhatsAppWebAdapter`: development only, `prototype_only = true`, blocked in production policy.
- `TelegramBotAdapter`: commands, messages, document/image uploads, inline acknowledgement buttons.
- `PushAdapter`: FCM/APNs notification, deep links, emergency audible push where platform permits.
- `SmsAdapter`: fallback-only provider behind region and consent policy.
- `VoiceAdapter`: outbound calls, text-to-speech scripts, DTMF/speech collection, status callbacks.
- `SimulationAdapter`: deterministic provider used by emergency drills and CI tests.

## 3. Contact Verification

Verification is separate from consent. A contact can be technically verified but still not authorized for health alerts.

Required verification methods:

- WhatsApp: app-generated one-time code or signed link sent through verified app session before enabling outbound PHI messages.
- Telegram: `/start` deep link with nonce, followed by app or OTP confirmation.
- Push: device token is bound to authenticated app session.
- SMS/voice: OTP to phone number before use for medical alerts or calls.
- Email: signed verification link before fallback summaries.

Verification states:

- `unverified`: account/contact exists, no medical commands accepted.
- `pending`: challenge issued and not expired.
- `verified`: challenge completed and link can be used if consent allows.
- `failed`: challenge failed or expired.

## 4. Template Library

Templates are stored in `message_templates` and referenced by `escalation_policy_steps.template_id` and `channel_dispatch_attempts.template_id`.

| Template ID | Channels | Use | Variables | Policy Notes |
| --- | --- | --- | --- | --- |
| `medicine_reminder_v1` | push, whatsapp, telegram | Patient dose reminder | `patient_name`, `medicine_name`, `dose`, `scheduled_time`, `confirm_url` | Requires medication reminder consent |
| `missed_dose_caretaker_v1` | push, whatsapp, telegram, sms | Notify caretaker of missed dose | `patient_name`, `medicine_name`, `scheduled_time`, `last_response_time` | Medium-risk communication |
| `daily_summary_caretaker_v1` | push, whatsapp, telegram, email | Regular caretaker summary | `patient_name`, `summary_window`, `key_vitals`, `medicine_adherence`, `device_status` | Business-initiated WhatsApp requires approved template |
| `device_disconnected_v1` | push, whatsapp, telegram | Device stale/disconnected alert | `patient_name`, `device_name`, `last_seen_at`, `reconnect_url` | Avoid emergency language unless risk rule escalates |
| `urgent_vitals_alert_v1` | push, whatsapp, telegram, sms | High-risk caretaker alert | `patient_name`, `risk_reason`, `latest_reading`, `observed_at`, `ack_url` | Requires risk event, consent, audit |
| `critical_escalation_caretaker_v1` | push, whatsapp, telegram, sms | Critical escalation alert | `patient_name`, `risk_reason`, `evidence_summary`, `location_hint`, `ack_url`, `call_in_progress` | Quiet hours may be overridden by policy |
| `doctor_escalation_summary_v1` | whatsapp, telegram, sms, email | Doctor/nurse escalation summary | `patient_name`, `age`, `conditions`, `risk_reason`, `evidence_summary`, `current_actions` | Send minimum necessary PHI |
| `emergency_services_summary_v1` | voice, sms | Emergency service handoff | `patient_name`, `age`, `location_hint`, `risk_reason`, `callback_number` | Requires emergency policy approval and consent |
| `account_verification_v1` | whatsapp, telegram, sms, email | Channel link verification | `code`, `expires_minutes` | Contains no PHI |
| `emergency_simulation_notice_v1` | push, whatsapp, telegram | Drill/test notice | `patient_name`, `scenario_name`, `test_label` | Must clearly mark as simulation |

WhatsApp-specific rules:

- `business_initiated = true` templates must map to approved WhatsApp template names before production use.
- Free-form WhatsApp messages are allowed only inside the service window and only after policy allows the action.
- Templates with PHI must avoid unnecessary diagnosis language and include a concise acknowledgement link/button.

## 5. Call Script Library

Scripts are stored in `call_scripts` and referenced by voice `channel_dispatch_attempts.script_id`.

### `critical_caretaker_call_v1`

Opening:

> This is CareAgent, an AI health assistant calling with authorization from {{patient_name}}.

Body:

> CareAgent detected a critical health alert for {{patient_name}}. {{evidence_summary}}. Please press 1 to acknowledge, 2 to repeat this message, or 3 to request a connection to the patient if configured.

Safety notes:

- Never claim to be the patient or a clinician.
- Do not diagnose. Describe observed facts and configured escalation action.
- If no response, mark the call as unacknowledged and continue policy fallback.

### `doctor_escalation_call_v1`

Opening:

> This is CareAgent, an AI assistant calling with authorization from {{patient_name}} or their authorized caretaker.

Body:

> A health escalation is active. {{patient_name}} has the following event: {{risk_reason}}. Latest evidence: {{evidence_summary}}. Please press 1 to acknowledge receiving this alert or 2 to repeat.

### `ambulance_contact_call_v1`

Opening:

> This is CareAgent, an AI assistant calling under a preconfigured emergency policy for {{patient_name}}.

Body:

> The patient may need urgent help. Location information: {{location_hint}}. Event details: {{risk_reason}}. Callback number: {{callback_number}}. Press 1 to confirm this message was received.

### `emergency_simulation_call_v1`

Opening:

> This is a CareAgent emergency drill. This is not a real emergency.

Body:

> The test scenario is {{scenario_name}}. Press 1 to acknowledge the drill or 2 to repeat.

## 6. Escalation State Machine

Escalation run statuses:

- `pending`: run created after policy approval, no provider action attempted yet.
- `running`: at least one action is being executed.
- `awaiting_ack`: message/call delivered or answered, waiting for human acknowledgement.
- `acknowledged`: a verified caretaker/doctor/contact acknowledged.
- `completed`: terminal success, including acknowledgement or policy-defined no-more-actions.
- `failed`: terminal failure with no successful dispatch or acknowledgement.
- `cancelled`: patient/caretaker/system cancelled under policy.

Action statuses:

- `pending`: action planned but not attempted.
- `attempting`: provider request in progress.
- `sent`: provider accepted message or call request.
- `delivered`: provider confirmed delivery.
- `answered`: voice call was answered.
- `acknowledged`: recipient acknowledged through button, DTMF, speech, or dashboard.
- `failed`: provider or policy failure.
- `skipped`: action was bypassed due to consent, verification, quiet hours, or simulation rule.
- `cancelled`: action cancelled after run cancellation.

Transitions:

1. `risk_event.created` with high/critical severity triggers policy evaluation.
2. Policy may ask the patient for confirmation if severity and rule allow delay.
3. If policy approves, create `escalation_run` with a unique idempotency key.
4. Expand enabled `escalation_policy_steps` into `escalation_actions`.
5. Attempt step order sequentially unless a policy step is marked parallel in `payload_template`.
6. On delivery/answer, move run to `awaiting_ack` until `timeout_seconds`.
7. On acknowledgement, mark action and run `acknowledged`, then `completed`.
8. On timeout/failure, schedule retry attempts, then move to the next contact/channel.
9. If all steps exhaust without acknowledgement, mark `failed` or `completed` with `outcome = no_ack_policy_exhausted`, depending on policy.
10. Cancellation is allowed only from authorized patient/caretaker/dashboard flows and must preserve the incident timeline.

## 7. Failure and Retry Behavior

Retry rules:

- Every outbound attempt uses a stable idempotency key: `escalation:{run_id}:step:{step_order}:attempt:{n}`.
- Retry provider 5xx, network timeouts, and rate-limit errors with exponential backoff plus jitter.
- Do not retry hard failures such as invalid recipient, revoked consent, unverified account, or blocked provider template.
- Stop retries for a step after `retry_count`; then advance to the configured fallback contact/channel.
- Critical voice actions must not create call storms. Default maximum is 2 attempts per contact per run unless clinical/compliance policy approves more.
- Emergency service calls are disabled in simulation and require separate production approval.

Fallback chain:

1. Push patient/caretaker if app token is verified.
2. WhatsApp approved template if opted in and template is approved.
3. Telegram message if verified and consented.
4. SMS fallback if lawful, consented, and configured.
5. Voice call to primary caretaker.
6. Voice call to secondary caretaker.
7. Doctor/nurse call or message.
8. Ambulance/private emergency contact if explicitly configured.
9. Public emergency number only if policy, region, provider, and consent are approved.

## 8. API Surface

Primary endpoints are specified in `backend/openapi/channels-calls-escalation.openapi.yaml`.

Required domains:

- `POST /patients/{patient_id}/channel-links`
- `POST /patients/{patient_id}/channel-links/{link_id}/verify`
- `GET /patients/{patient_id}/channel-links`
- `POST /patients/{patient_id}/channel-messages`
- `POST /webhooks/whatsapp`
- `POST /webhooks/telegram`
- `POST /webhooks/voice`
- `POST /risk-events/{risk_event_id}/escalate`
- `GET /escalation-runs/{run_id}`
- `POST /escalation-runs/{run_id}/acknowledge`
- `POST /patients/{patient_id}/emergency-simulations`
- `GET /emergency-simulations/{simulation_id}`

## 9. Backend Files

Create or modify:

- `backend/migrations/003_channels_calls_escalation.sql`
- `backend/openapi/channels-calls-escalation.openapi.yaml`
- `backend/tests/emergency_simulation_scenarios.md`
- `backend/tests/emergency_simulation_cases.json`

Future implementation modules:

- `backend/app/channels/link_service.py`
- `backend/app/channels/template_registry.py`
- `backend/app/channels/provider_adapters/base.py`
- `backend/app/channels/provider_adapters/whatsapp_cloud.py`
- `backend/app/channels/provider_adapters/telegram.py`
- `backend/app/channels/provider_adapters/push.py`
- `backend/app/channels/provider_adapters/voice.py`
- `backend/app/channels/provider_adapters/simulation.py`
- `backend/app/escalation/runner.py`
- `backend/app/escalation/state_machine.py`
- `backend/app/escalation/simulation.py`

## 10. Tests

End-to-end simulation coverage:

- Critical heart-rate anomaly reaches push, WhatsApp/Telegram, and voice call without real external providers.
- No acknowledgement causes fallback to the next contact and then doctor/ambulance contact.
- Duplicate risk-event escalation returns the existing run and does not create duplicate actions.
- Revoked voice consent skips calls and records policy-denied action outcomes.
- Unverified Telegram chat cannot issue `/medicines`, `/summary`, or acknowledgement commands.
- WhatsApp unapproved template blocks production dispatch and selects the next fallback.
- Patient cancellation stops later attempts while preserving sent receipts and audit logs.
- Location sharing is included only when consented and available.

## 11. Open Questions

- Which production WhatsApp path will be used first: direct Cloud API or a BSP?
- Which programmable voice provider is preferred for India launch: Exotel, Twilio, Plivo, or another local provider?
- Will public emergency-number calling be allowed in MVP, or only configured private ambulance contacts and caretakers?
- What is the clinical/compliance-approved maximum repeat-call policy for critical events?
- Which locales are required for first-release templates and voice scripts?
