# Risk Engine Test Matrix

This matrix maps the MVP risk rules to deterministic tests, simulator fixtures, and expected escalation-policy requests. Threshold values are for engineering verification and must be reviewed before production.

## 1. Test Inputs

Primary fixture:

- `backend/tests/fixtures/device-simulator-scenarios.json`

Required test harness modes:

- `dry_run`: generate observations and expected outcomes without persistence.
- `ingest`: submit observations through normalization and data-quality services.
- `replay`: run scenario offsets against a frozen clock for rule regression tests.

Shared assertions:

- Risk events include rule ID, rule version, severity, confidence, reason, detected timestamp, evidence, source reliability, freshness, and recommended policy action.
- Manual/OCR evidence cannot start emergency escalation without confirmation.
- Stale readings create stale/missing-data events, not live deterioration events.
- Duplicate risk candidates inside cooldown windows are suppressed with an idempotency key.
- LLM summaries are never required for rule pass/fail decisions.

## 2. Scenario Matrix

| Scenario | Primary rules | Expected outcome | False-positive/negative guard |
| --- | --- | --- | --- |
| `fresh_normal_day_health_connect` | all threshold rules | No risk events; observations accepted with fresh quality. | Prevent false positives from normal wearable data. |
| `critical_spo2_drop_ble` | `spo2_low_v1` | Critical event, policy action `start_emergency_protocol`, no confirmation when pre-authorized. | Catches false negatives for fresh low SpO2. |
| `manual_glucose_low_reliability` | `blood_glucose_low_v1` | High event, patient confirmation required, policy action `prompt_patient_repeat_reading`. | Prevents emergency escalation from single manual reading. |
| `stale_watch_data_no_emergency` | `heart_rate_low_v1`, `device_stale_v1` | Low stale-data event; no critical heart-rate event. | Prevents stale abnormal reading false critical. |
| `fall_detected_vendor_event` | `fall_detected_v1` | Critical fall event and emergency policy request when no response is simulated. | Catches missed fall events from vendor source. |
| `heart_rate_rapid_drop_critical` | `heart_rate_rapid_change_v1`, `heart_rate_low_v1` | Critical/high-priority escalation candidate from fresh BLE trend evidence. | Catches rapid-change false negatives. |
| `hypertensive_bp_repeat_required` | `blood_pressure_high_v1` | High event, repeat-reading prompt required because source is manual. | Prevents over-escalation from manually entered BP. |
| `cgm_disconnected_stale_alert` | `device_disconnected_v1`, `device_stale_v1` | High device alert for active CGM monitoring; not normal glucose. | Prevents missing-data false normal. |
| `ocr_spo2_low_needs_review_no_emergency` | `spo2_low_v1` | Moderate event requiring review/recheck; no emergency escalation. | Prevents OCR misread false critical. |

## 3. Rule-Specific Unit Tests

### Heart Rate

- Fresh `heart_rate < critical_lower_bound` from standard BLE creates high/critical event.
- Fresh `heart_rate > critical_upper_bound` from OS aggregator creates high event with symptom prompt.
- Rapid drop/rise over configured window creates `heart_rate_rapid_change_v1`.
- Stale abnormal heart rate creates `device_stale_v1`, not `heart_rate_low_v1`.
- Duplicate readings with same dedupe key do not create duplicate events.

### Blood Pressure

- Grouped systolic/diastolic readings preserve shared group ID.
- `systolic >= 180` or `diastolic >= 120` creates high event.
- Manual BP crossing threshold requires repeat-reading confirmation.
- BP payload with systolic less than diastolic is rejected by normalization.
- kPa values convert to mmHg before rule evaluation.

### Glucose

- `blood_glucose < 70 mg/dL` creates high event; `< 54 mg/dL` creates critical candidate if source and policy allow.
- `blood_glucose > 250 mg/dL` creates moderate/high event; `> 350 mg/dL` plus symptoms creates critical candidate.
- `mmol/L` converts to `mg/dL` before thresholds.
- Unreviewed manual/OCR glucose caps confidence and requires confirmation.
- Stale CGM creates device stale alert, not normal glucose.

### SpO2

- Fresh SpO2 below high/critical thresholds creates expected severity.
- Fraction input converts to percent.
- Low signal-quality flag lowers confidence or requires repeat.
- OCR low value pending review cannot start emergency escalation.
- Stale low SpO2 creates stale monitoring event, not critical respiratory event.

### Temperature

- Fever threshold creates low/moderate event depending value and patient profile.
- Critical fever requires confirmation/symptom handling unless policy says otherwise.
- degF converts to degC before thresholds.
- Body site/method metadata is preserved in evidence where available.

### Fall Detection

- Fall event creates patient prompt when feasible.
- No response before timeout creates critical event and policy request.
- Fall plus abnormal vitals increases confidence.
- Duplicate vendor fall event ID is idempotent.
- Fall events outside freshness window are ignored for emergency policy and logged for review.

### Medicine

- Missed dose after grace window creates low/moderate event.
- Repeated missed doses increase severity by configured medicine class/profile.
- Unreviewed extracted medicine schedule cannot produce high-risk missed-dose escalation.
- Patient confirmation of dose taken resolves or suppresses pending missed-dose event.

### Device Freshness

- Disconnected active device creates device alert.
- Reauth-required connector creates patient reconnect prompt and audit event.
- Missing expected metric creates `missing_expected_metric`, not normal data.
- Low battery can raise moderate device alert for CGM/respiratory-risk monitoring.

## 4. Escalation Interface Tests

- High event returns `notify_care_team_now` only when caretaker alert consent is active.
- Critical event returns `start_emergency_protocol` only when emergency consent and policy are active.
- Missing location consent removes location from policy request and message context.
- Patient quiet hours do not suppress critical policy requests when emergency override is enabled.
- Idempotency key prevents duplicate voice-call/caretaker-action storms for the same risk event.
- Policy request includes `ai_disclosure_required=true` for voice and outbound messages.

## 5. Review Loop Tests

- Reviewer can mark event `false_positive` and link it to rule version and evidence.
- Reviewer can create a `false_negative` record from an incident or fixture replay.
- Any critical-rule threshold change requires `pending_review` then `approved`.
- A proposed rule update must reference at least one fixture scenario.
- Review classification updates safety KPIs without modifying original event evidence.

## 6. Minimum CI Gates

- JSON fixture parses successfully.
- OpenAPI YAML parses successfully.
- Every scenario has a unique `scenario_code`.
- Every expected risk event has a `rule_id`, `severity`, and `recommended_policy_action`.
- Every observation has metric code, unit, observed timestamp, source label, reliability tier, and source record ID unless the scenario explicitly tests rejection.
- Risk-rule unit tests cover threshold, trend, stale data, missing data, conflicting data, manual/OCR confirmation, and duplicate suppression.
