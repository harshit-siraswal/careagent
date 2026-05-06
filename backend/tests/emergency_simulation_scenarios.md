# Emergency Simulation Test Scenarios

These scenarios validate prompt 05 without contacting real channel providers or emergency services. They should run with `mock_simulator` provider configs and `escalation_policies.simulation_mode = true`.

## Test Harness Requirements

- Use deterministic synthetic risk events.
- Use simulator provider callbacks for push, WhatsApp, Telegram, SMS, and voice.
- Verify every outbound attempt creates an audit event.
- Verify no production provider is called during simulation.
- Verify every test has a stable idempotency key.
- Verify PHI appears only in approved template/script variables.
- Verify provider webhook signatures and replay protection before state changes.
- Verify out-of-order receipts cannot downgrade dispatch state.
- Verify production-only constraints are enforced even when an agent requests a blocked channel.
- Verify every voice script used in a production-like simulation includes AI identity disclosure.

## Scenario Matrix

| Scenario | Purpose | Expected Result |
| --- | --- | --- |
| `critical_hr_primary_ack` | Critical heart-rate event reaches primary caretaker and receives acknowledgement | Run completes as `acknowledged`; no secondary or emergency contact is called |
| `critical_hr_no_ack_fallback` | Primary caretaker does not acknowledge | Fallback reaches secondary caretaker, then doctor; run completes when doctor acknowledges |
| `duplicate_critical_event` | Repeated request uses same idempotency key | Existing escalation run is returned; no duplicate dispatch attempts are created |
| `revoked_voice_consent` | Voice consent was revoked before critical event | Voice steps are skipped with policy-denied reason; non-voice fallback continues |
| `unverified_telegram_ack` | Telegram chat is not verified | Telegram acknowledgement is rejected; run remains awaiting valid acknowledgement |
| `whatsapp_template_not_approved` | Production WhatsApp template is not approved | WhatsApp dispatch is blocked and fallback channel is selected |
| `patient_cancels_after_push` | Patient cancels false alarm after first push | Later actions are cancelled; run records cancellation actor and reason |
| `location_consent_absent` | Escalation tries to include location without consent | Location variables are omitted; dispatch still proceeds if policy allows message without location |
| `simulation_emergency_contact_block` | Policy includes public emergency number in simulation | Emergency call is simulated only; real provider adapter is not invoked |
| `business_initiated_whatsapp_requires_template` | WhatsApp alert starts outside service window | Free-form message is denied; approved template path is used |
| `prototype_whatsapp_web_blocked_production` | Prototype WhatsApp Web adapter is selected in production mode | Dispatch is skipped with `production_provider_required` and fallback continues |
| `voice_script_missing_ai_disclosure` | Voice script registry entry omits AI disclosure | Voice dispatch is rejected before provider call |
| `delivery_receipts_out_of_order` | Provider sends delivered/read before sent callback | Final status stays at highest precedence; duplicate/late callback is audited |
| `hard_failure_no_retry` | Provider reports invalid recipient | No retry is scheduled and next fallback contact/channel is selected |
| `sms_region_policy_denied` | SMS fallback is configured in a restricted region or without lawful basis | SMS action is skipped and audited; voice/WhatsApp fallback continues |
| `telegram_unverified_upload_blocked` | Unverified Telegram chat uploads a medical document | Upload is rejected with verification instructions and no document pipeline job |
| `revoked_emergency_consent_blocks_public_number` | Public emergency number step exists after emergency consent is revoked | Public emergency call is skipped; configured caretakers remain eligible if separately consented |

## Assertions

For every scenario:

- `escalation_runs.status` reaches the expected terminal state.
- `escalation_actions` reflect ordered step execution and skipped steps.
- `channel_dispatch_attempts.simulation = true`.
- `delivery_receipts.signature_valid = true` for simulator callbacks.
- `call_events` record DTMF/speech acknowledgements without storing full raw provider payloads.
- `audit_logs` include policy decision, message/call attempt, provider receipt, and acknowledgement or cancellation.
- `risk_events.status` is updated consistently with escalation outcome.
- `policy_decisions` include consent, verification, template/script approval, and emergency-service approval checks.
- `provider_webhook_events` are deduplicated by provider event ID or deterministic hash.
- `escalation_actions.skip_reason` is populated for every skipped step.

## Negative Tests

- A direct dispatch request without `policy_decision_id` returns `403`.
- A WhatsApp business-initiated production message using a draft template returns `403`.
- A voice call request using a script without AI disclosure is rejected by template/script validation.
- A Telegram `/summary` command from an unlinked chat returns only verification instructions.
- A retry after a hard provider failure does not occur.
- A second emergency-service action in the same run is blocked unless policy explicitly allows repeats.
- A public emergency-number action in simulation mode never invokes a real voice provider.
- A provider callback with an invalid signature creates a security audit event and does not advance state.
- A late lower-precedence receipt cannot move `delivered`, `read`, `answered`, or `acknowledged` back to `sent`.

## Simulation Fixtures

The JSON fixture `backend/tests/emergency_simulation_cases.json` is intentionally provider-neutral. Each case can be executed by:

1. Seeding the patient, contacts, consents, channel links, templates, scripts, and escalation policy listed in `preconditions`.
2. Creating the synthetic `risk_event` with a deterministic idempotency key.
3. Calling `POST /risk-events/{risk_event_id}/escalate` or `POST /patients/{patient_id}/emergency-simulations`.
4. Emitting simulator webhooks from `provider_behaviors` in timestamp order unless a case explicitly tests out-of-order receipts.
5. Checking `expected` and `assertions` without contacting production providers.
