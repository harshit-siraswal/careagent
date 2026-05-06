# Risk Engine Workstream

This document turns prompt 09 into an implementation plan for CareAgent risk rules, anomaly detection, threshold configuration, escalation hooks, and review governance.

The risk engine is deterministic and auditable. LLMs may summarize, translate, or draft user-facing explanations after a risk event exists, but they must not be the sole decision-maker for safety-critical events.

## 1. Scope

Owned capabilities:

- Normalize risk inputs from observations, medicine-dose events, device-connection status, symptoms, and patient profile data.
- Evaluate versioned rules for thresholds, trends, stale data, missing data, and known emergency events such as falls.
- Produce explainable risk events with evidence, source reliability, freshness, and rule version.
- Select a policy action interface for alerting and escalation engines without directly placing calls or messages.
- Support patient-specific thresholds and clinician/caretaker overrides.
- Capture false-positive and false-negative feedback tied to rule versions and fixture scenarios.

Non-goals:

- Diagnosis, prescription, or treatment-plan generation.
- Autonomous emergency dispatch without explicit consent and configured escalation policy.
- Hidden thresholds that cannot be reviewed by clinical/safety reviewers.
- Treating missing or stale data as normal data.

## 2. Runtime Architecture

Risk-engine components:

- `RiskInputBuilder`: loads normalized observations, dose events, device status, symptoms, patient thresholds, active consents, and recent risk history.
- `MetricFreshnessEvaluator`: classifies each metric as `fresh`, `delayed`, `stale`, `missing`, or `future_timestamp`.
- `SourceReliabilityWeighter`: converts data-quality metadata into rule eligibility and confidence adjustments.
- `ThresholdRuleEvaluator`: applies patient-specific thresholds and default rule catalog thresholds.
- `TrendRuleEvaluator`: evaluates rapid changes and repeated abnormal readings over time windows.
- `CorrelationEvaluator`: combines signals such as fall plus no response, low SpO2 plus breathlessness, or abnormal vitals plus missed medicine.
- `RiskEventWriter`: writes idempotent risk events with evidence and rule metadata.
- `EscalationPolicyResolver`: returns the policy action requested by the event; it does not execute the action.
- `RiskReviewService`: stores feedback, incident review outcomes, and rule-tuning recommendations.

Processing flow:

1. `observation.created`, `medicine.dose_missed`, `device.connection_state_changed`, or `symptom.reported` event arrives.
2. `RiskInputBuilder` creates a patient-scoped evaluation bundle.
3. Freshness and quality gates run before threshold rules.
4. Rule evaluators emit zero or more candidate events.
5. Correlation and de-duplication merge related candidates.
6. Severity and confidence are finalized.
7. `RiskEventWriter` persists the event and publishes `risk_event.created`.
8. `EscalationPolicyResolver` emits a requested policy action for high/critical events.
9. Agent/channel services may summarize or notify only after policy approval.

Idempotency:

- Threshold events use `patient_id + rule_id + metric_code + normalized time bucket + evidence hash`.
- Trend events use `patient_id + rule_id + metric_code + window start/end + evidence observation IDs`.
- Fall events use the source event ID when available.
- Stale-data events use `patient_id + device_id + metric_code + stale window`.
- Missed-dose events use `patient_id + schedule_id + scheduled_at + rule_id`.

## 3. Risk Event Schema

Minimum fields:

- `id`
- `patient_id`
- `rule_id`
- `rule_version`
- `severity`: `informational`, `low`, `moderate`, `high`, `critical`
- `confidence`: decimal from `0` to `1`
- `status`: `open`, `acknowledged`, `escalating`, `resolved`, `dismissed`, `suppressed`
- `reason`
- `detected_at`
- `evaluation_window`
- `evidence`
- `source_reliability`
- `freshness`
- `recommended_policy_action`
- `requires_patient_confirmation`
- `requires_policy_approval`
- `suppression_reason` nullable
- `created_from_event_id` nullable
- `audit_log_id`

Evidence item schema:

```json
{
  "type": "observation",
  "observation_id": "obs_spo2_002",
  "metric_code": "spo2",
  "value_numeric": 86,
  "unit": "%",
  "observed_at": "2026-05-06T18:31:30+05:30",
  "source_type": "ble",
  "source_label": "BLE Pulse Oximeter",
  "source_record_id": "ble_plx_002_spo2",
  "reliability_tier": "standard_ble",
  "freshness": "fresh",
  "quality_score": 0.9,
  "quality_flags": ["critical_low_value"]
}
```

Example critical event:

```json
{
  "patient_id": "pat_123",
  "rule_id": "spo2_low_critical_v1",
  "rule_version": "1.0.0",
  "severity": "critical",
  "confidence": 0.91,
  "reason": "SpO2 dropped to 86% from a fresh standard BLE pulse oximeter reading.",
  "detected_at": "2026-05-06T18:31:36+05:30",
  "freshness": "fresh",
  "source_reliability": "standard_ble",
  "requires_patient_confirmation": false,
  "requires_policy_approval": true,
  "recommended_policy_action": "start_emergency_protocol",
  "evidence": [
    {
      "type": "observation",
      "metric_code": "spo2",
      "value_numeric": 86,
      "unit": "%",
      "observed_at": "2026-05-06T18:31:30+05:30",
      "source_type": "ble",
      "source_label": "BLE Pulse Oximeter",
      "quality_score": 0.9
    }
  ]
}
```

Example suppressed stale-data event:

```json
{
  "patient_id": "pat_123",
  "rule_id": "heart_rate_low_v1",
  "severity": "low",
  "confidence": 0.52,
  "reason": "Heart-rate reading is abnormal but stale; create a device freshness alert, not a live emergency.",
  "freshness": "stale",
  "recommended_policy_action": "prompt_patient_to_sync_device",
  "suppression_reason": "stale_data_not_live_deterioration",
  "evidence": [
    {
      "metric_code": "heart_rate",
      "value_numeric": 42,
      "unit": "bpm",
      "observed_at": "2026-05-06T17:50:00+05:30",
      "freshness": "stale"
    }
  ]
}
```

## 4. Threshold Configuration Model

Thresholds are resolved in this order:

1. Rule hard safety bounds that prevent unsafe escalation from invalid data.
2. Patient-specific clinician-approved thresholds.
3. Patient-specific caretaker/patient preferences inside allowed ranges.
4. Condition profile defaults, such as diabetes, hypertension, cardiac risk, respiratory risk, elderly fall risk.
5. Global catalog defaults marked `requires_clinical_review=true`.

Threshold config fields:

- `threshold_config_id`
- `patient_id`
- `metric_code`
- `rule_family`
- `lower_bound`
- `upper_bound`
- `rapid_change_delta`
- `rapid_change_window_seconds`
- `repeat_count`
- `repeat_window_seconds`
- `severity_overrides`
- `freshness_override_seconds`
- `minimum_quality_score`
- `minimum_reliability_tier`
- `confirmation_requirement`
- `enabled`
- `effective_from`
- `effective_until`
- `created_by`
- `reviewer`
- `review_status`: `draft`, `pending_review`, `approved`, `rejected`, `retired`
- `version`

Example:

```json
{
  "patient_id": "pat_diabetes_123",
  "metric_code": "blood_glucose",
  "rule_family": "glucose_threshold",
  "lower_bound": 70,
  "upper_bound": 250,
  "critical_lower_bound": 54,
  "critical_upper_bound": 350,
  "unit": "mg/dL",
  "minimum_quality_score": 0.75,
  "minimum_reliability_tier": "standard_ble",
  "confirmation_requirement": {
    "manual_or_ocr": "patient_confirmation_required",
    "standard_ble": "skip_confirmation_for_critical_if_pre_authorized"
  },
  "review_status": "approved",
  "version": "1.0.0"
}
```

Guardrails:

- Manual/OCR observations cannot start emergency escalation without confirmation unless paired with severe symptoms or corroborating higher-quality data.
- Stale observations can create stale-device alerts but cannot create critical live-deterioration events.
- Critical threshold changes require clinical/safety reviewer approval and staged rollout.
- Rule output must include the exact config version used.

## 5. Freshness And Missing Data Rules

Freshness comes from the metric definition and can be overridden only by reviewed patient config.

Default examples:

| Metric | Warning after | Stale after | Missing-data behavior |
| --- | ---: | ---: | --- |
| Heart rate | 5 min | 15 min | Prompt patient to sync/check device when expected monitoring is active. |
| Blood pressure | 30 min | 2 hr | Ask for repeat reading if abnormal or overdue during monitoring window. |
| Blood glucose | 30 min | 2 hr | Alert for missing scheduled glucose check if configured. |
| Continuous glucose | 15 min | 45 min | High priority stale sensor alert for insulin-dependent profile. |
| SpO2 | 5 min | 15 min | Alert if respiratory-risk patient loses monitoring unexpectedly. |
| Temperature | 2 hr | 8 hr | Missing is informational unless fever watch is active. |
| Weight | 7 days | 30 days | Missing is low/moderate for heart-failure monitoring profiles. |
| Steps/sleep | 1 day | 2 days | Summary/freshness warning only in MVP. |
| Fall detection | immediate | 15 min | Fall event is event-based; missing fall data is device-status only. |

Missing data is represented as `missing_expected_metric`, not as a normal reading.

## 6. Rule Evaluation Design

Rule types:

- `single_threshold`: one fresh value crosses a configured bound.
- `compound_threshold`: systolic and diastolic, fall plus no response, symptom plus vital.
- `delta_within_window`: rapid change from baseline or recent value.
- `repeat_abnormal`: repeated abnormal readings in a time window.
- `stale_data`: expected metric is delayed or stale.
- `missing_data`: expected scheduled reading never arrived.
- `medicine_adherence`: missed or repeated missed doses.
- `device_status`: disconnected, low battery, parser errors, or reauth required.

Evaluation gates:

1. Patient consent allows health monitoring for the metric/source.
2. Rule is active for the patient and rule version.
3. Evidence is normalized into canonical units.
4. Evidence is fresh enough for the rule type.
5. Evidence meets minimum quality and source reliability.
6. De-duplication suppresses duplicate alerts inside cooldown windows.
7. Severity mapping and policy action are resolved.

Confidence calculation:

- Start from highest evidence quality score.
- Add up to `0.05` for corroborating source inside the window.
- Add up to `0.05` for patient symptom confirmation.
- Subtract `0.10` for delayed data.
- Subtract `0.15` for manual/OCR evidence.
- Cap at `0.65` when patient confirmation is required but not received.
- Cap at `0.50` when the event is stale-data only.

## 7. Severity Mapping

Informational:

- Normal data logged.
- Minor stale data outside active monitoring.
- Included in summaries only.

Low:

- Patient prompt, device sync reminder, or repeat-reading request.
- No caretaker alert unless configured.

Moderate:

- Patient prompt with timeout.
- Caretaker can be notified after no response, repeated abnormality, or configured condition profile.

High:

- Immediate caretaker/nurse/doctor notification through allowed channels.
- Voice call may be requested if enabled for the policy.
- Patient confirmation may still be requested if not time-critical.

Critical:

- Emergency protocol may start only when explicit consent, policy configuration, and qualifying evidence exist.
- Event must include source reliability, freshness, rule version, and audit trail.
- Patient confirmation may be skipped only for pre-authorized critical patterns.

## 8. Escalation Policy Interface

The risk engine returns a policy request. The escalation engine executes the plan after consent and policy checks.

```json
{
  "risk_event_id": "risk_evt_123",
  "patient_id": "pat_123",
  "requested_action": "start_emergency_protocol",
  "severity": "critical",
  "policy_selector": {
    "minimum_severity": "critical",
    "condition_profile": "respiratory_risk",
    "requires_location": true,
    "requires_voice_call": true
  },
  "required_consents": [
    "emergency_escalation",
    "caretaker_alerts",
    "voice_call",
    "location_sharing"
  ],
  "allowed_channels": ["push", "whatsapp", "telegram", "voice_call"],
  "patient_confirmation": {
    "required": false,
    "timeout_seconds": 0,
    "reason": "fresh critical SpO2 from standard BLE source"
  },
  "message_context": {
    "template_id": "urgent_vitals_alert_v1",
    "ai_disclosure_required": true,
    "summary_variables": {
      "risk_reason": "SpO2 dropped to 86%",
      "latest_reading": "86% at 6:31 PM",
      "source": "BLE Pulse Oximeter"
    }
  },
  "idempotency_key": "risk_evt_123:spo2_low_critical_v1"
}
```

Recommended actions:

- `log_only`
- `prompt_patient`
- `prompt_patient_repeat_reading`
- `notify_caretaker_after_timeout`
- `notify_care_team_now`
- `start_high_priority_escalation`
- `start_emergency_protocol`
- `prompt_patient_to_sync_device`
- `suppress_duplicate`

## 9. Review Loop

Every high or critical event must be reviewable.

Feedback sources:

- Patient: false alarm, symptom confirmation, reading corrected, device issue.
- Caretaker: acknowledged, dismissed, escalated externally, no action needed.
- Clinician/safety reviewer: true positive, false positive, false negative, severity wrong, evidence insufficient.
- System: duplicate suppressed, stale data, parser error, missing consent, escalation failed.

Review fields:

- `risk_event_id`
- `rule_id`
- `rule_version`
- `scenario_code` nullable
- `classification`: `true_positive`, `false_positive`, `false_negative`, `severity_too_high`, `severity_too_low`, `insufficient_evidence`, `duplicate`, `data_quality_issue`
- `reviewer_role`
- `notes`
- `recommended_change`
- `requires_rule_update`
- `requires_fixture_update`
- `created_at`

Operational loop:

1. Review all high/critical events during pilot.
2. Tag false positives/negatives to exact rule versions and evidence sources.
3. Add or update simulator scenarios before changing the rule.
4. Run the risk test matrix against old and proposed rule versions.
5. Stage rollout behind a rule version flag.
6. Monitor false-critical and missed-critical metrics after rollout.

## 10. Implementation Phases

MVP v1:

- Single-threshold rules for heart rate, blood pressure, glucose, SpO2, temperature, fall, missed medicine, and stale devices.
- Per-patient threshold config model with review status.
- Simulator-backed unit tests and fixture replays.
- Risk event writer with evidence and idempotency.
- Escalation policy request contract.

MVP v1.1:

- Rapid-change and repeat-abnormal rules.
- Correlation for symptom plus vital and fall plus no response.
- Review dashboard data model.
- Rule version rollout controls.

Later:

- Condition-profile packages reviewed by clinicians.
- Vendor-specific data-quality adapters.
- Population-level analytics over de-identified alert outcomes, subject to privacy review.

## 11. Open Questions

- Which clinical advisor reviews initial threshold defaults?
- Which pilot conditions receive patient-specific thresholds first: diabetes, hypertension, cardiac risk, respiratory risk, or elderly fall risk?
- Should doctors be first-class reviewers in v1 or should safety reviewers operate through admin tools?
- What is the acceptable false-critical alert rate for each pilot population?
- Which jurisdictions allow emergency provider calls versus caretaker/doctor-only escalation in MVP?
