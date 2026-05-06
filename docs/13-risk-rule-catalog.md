# Initial Risk Rule Catalog

This is a product and engineering starting point, not medical advice. Thresholds and escalation actions must be reviewed by qualified clinicians before production use.

## 1. Rule Structure

Each rule must define:

- rule_id
- name
- metric inputs
- patient population
- threshold or pattern
- severity
- required source reliability
- confirmation requirement
- escalation policy
- message/call template
- test cases
- reviewer
- version

## 2. Initial Rule Families

### Heart Rate

Potential patterns:

- Very low heart rate.
- Very high heart rate.
- Rapid drop or rise compared with baseline.
- Heart rate anomaly plus fall event.

Required evidence:

- Recent device reading.
- Source and timestamp.
- Data freshness check.
- Optional corroborating symptoms.

### Blood Pressure

Potential patterns:

- Very high systolic/diastolic.
- Very low systolic/diastolic.
- Repeated abnormal readings.
- Abnormal BP plus symptoms.

Required evidence:

- Reading source.
- Measurement time.
- Whether the device is validated or user-entered.
- Repeat measurement prompt for non-critical cases.

### Blood Glucose

Potential patterns:

- Very low glucose.
- Very high glucose.
- Rapid CGM trend change.
- Repeated missed medicine/insulin-related event.

Required evidence:

- Device or report/manual source.
- Timestamp.
- Unit.
- CGM trend if available.

### SpO2

Potential patterns:

- Low oxygen saturation.
- Repeated low oxygen readings.
- Low SpO2 plus breathlessness symptom.

Required evidence:

- Device source.
- Signal quality if available.
- Timestamp and freshness.

### Temperature

Potential patterns:

- Fever range.
- Very low body temperature.
- Fever plus symptoms or age-risk condition.

Required evidence:

- Source.
- Timestamp.
- Measurement method if available.

### Fall Detection

Potential patterns:

- Fall detected and no patient response.
- Fall detected plus abnormal vitals.

Required evidence:

- Device fall event.
- Patient check-in response or timeout.
- Location if permitted.

### Missed Medicine

Potential patterns:

- Missed dose.
- Repeated missed dose.
- Missed critical medicine class.

Required evidence:

- Reviewed medicine schedule.
- Dose event status.
- Patient confirmation or timeout.

### Device/Data Freshness

Potential patterns:

- Device disconnected.
- No vital data received within expected window.
- Device battery low.

Required evidence:

- Last sync.
- Device expected sync cadence.
- Patient/caretaker notification policy.

## 3. Severity Mapping

Informational:

- Log only or include in summary.

Low:

- Patient check-in or reminder.

Moderate:

- Patient prompt, possible caretaker notification after timeout.

High:

- Immediate caretaker/nurse/doctor notification.

Critical:

- Emergency escalation policy may start if pre-authorized.

## 4. Example Rule JSON

```json
{
  "rule_id": "heart_rate_rapid_drop_v1",
  "name": "Rapid heart-rate drop",
  "metric_inputs": ["heart_rate"],
  "pattern": {
    "type": "delta_within_window",
    "change": "large_drop",
    "window_seconds": 60
  },
  "severity": "critical",
  "required_source_reliability": "device_measured",
  "requires_policy_approval": true,
  "requires_clinical_review": true,
  "message_template": "urgent_vitals_alert_v1",
  "test_cases": [
    "fresh device reading creates risk event",
    "stale reading does not create critical event",
    "manual reading requires confirmation",
    "duplicate readings are idempotent"
  ]
}
```

## 5. Governance

- No critical rule ships without reviewer sign-off.
- Rule changes must be versioned.
- Rules must have synthetic test cases.
- Rules must produce explainable evidence.
- False positives and false negatives must be reviewed and tied back to rule versions.

## 6. Initial MVP Rule Table

Thresholds below are implementation placeholders for engineering tests and demos. They require clinical/safety review before production use and must be configurable per patient.

| Rule ID | Inputs | Default trigger | Freshness requirement | Minimum source | Severity | Confirmation | Policy action |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `heart_rate_low_v1` | `heart_rate` | `< 45 bpm` | fresh, under 15 min | OS aggregator or standard BLE, quality >= 0.75 | high; critical if `< 35 bpm` or symptoms/fall | Skip only for critical pre-authorized fresh device evidence | `notify_care_team_now` or `start_emergency_protocol` |
| `heart_rate_high_v1` | `heart_rate` | `> 130 bpm at rest` | fresh, under 15 min | OS aggregator or standard BLE, quality >= 0.75 | moderate/high; critical if `> 180 bpm` with symptoms | Patient confirmation for non-critical | `prompt_patient_repeat_reading`, then notify |
| `heart_rate_rapid_change_v1` | `heart_rate` history | `>= 35 bpm` rise/drop inside 5 min | all evidence fresh | OS aggregator or standard BLE, quality >= 0.80 | high/critical depending value and symptoms | Required unless severe value/fall is present | `notify_care_team_now` |
| `blood_pressure_high_v1` | `blood_pressure_systolic`, `blood_pressure_diastolic` | systolic `>= 180` or diastolic `>= 120` mmHg | fresh, under 2 hr | standard BLE, OS aggregator, or reviewed manual | high; critical with severe symptoms | Repeat reading or symptom confirmation when safe | `notify_care_team_now` |
| `blood_pressure_low_v1` | BP pair | systolic `< 90` or diastolic `< 60` mmHg | fresh, under 2 hr | standard BLE, OS aggregator, or reviewed manual | moderate/high | Patient confirmation unless fall/syncope symptom | `prompt_patient_repeat_reading` |
| `blood_glucose_low_v1` | `blood_glucose` or `continuous_glucose` | `< 70 mg/dL`; critical `< 54 mg/dL` | fresh, under 2 hr; CGM under 45 min | standard BLE/vendor/OS, reviewed manual allowed for high only | high/critical | Manual/OCR always requires confirmation | `notify_care_team_now` or emergency by policy |
| `blood_glucose_high_v1` | glucose | `> 250 mg/dL`; critical `> 350 mg/dL` with symptoms | fresh, under 2 hr; CGM under 45 min | standard BLE/vendor/OS, reviewed manual allowed for high only | moderate/high | Patient confirmation and repeat if manual | `prompt_patient_repeat_reading` then notify |
| `spo2_low_v1` | `spo2` | `< 92%`; critical `< 88%` | fresh, under 15 min | standard BLE/OS/vendor, quality >= 0.80 | high/critical | Skip only for critical pre-authorized fresh device evidence | `start_high_priority_escalation` or emergency |
| `temperature_high_v1` | `body_temperature` | `>= 38.0 degC`; critical `>= 40.0 degC` | delayed allowed under 8 hr | BLE/OS/manual reviewed | low/moderate/high | Confirmation for high unless severe symptoms | `prompt_patient`, notify if configured |
| `temperature_low_v1` | `body_temperature` | `< 35.0 degC` | delayed allowed under 8 hr | BLE/OS/manual reviewed | high | Confirmation unless symptoms/fall | `notify_care_team_now` |
| `fall_detected_v1` | `fall_detected`, patient response, location consent | fall event and no response within timeout | event under 15 min | vendor/OS fall source, quality >= 0.75 | critical | Prompt patient first if feasible | `start_emergency_protocol` if pre-authorized |
| `missed_medicine_v1` | `MedicineDoseEvent` | status `missed` after grace window | schedule event time | reviewed medicine schedule | low/moderate/high by medicine class/profile | Patient check-in before caretaker notification for non-critical | `notify_caretaker_after_timeout` |
| `device_stale_v1` | device status, expected metric | metric stale beyond configured window | n/a | connector status | low/moderate | No patient health emergency confirmation | `prompt_patient_to_sync_device` |
| `device_disconnected_v1` | device status | disconnected during active monitoring window | n/a | connector status | low/moderate/high for CGM/respiratory watch | No patient health emergency confirmation | `prompt_patient_to_sync_device`, notify caretaker if unresolved |

## 7. Threshold Configuration Requirements

Rule thresholds must be represented as data, not hard-coded constants.

Required fields:

- `rule_id`
- `rule_version`
- `patient_id`
- `metric_code`
- `condition_profile`
- `lower_bound`
- `upper_bound`
- `critical_lower_bound`
- `critical_upper_bound`
- `unit`
- `rapid_change_delta`
- `rapid_change_window_seconds`
- `repeat_count`
- `repeat_window_seconds`
- `minimum_quality_score`
- `minimum_reliability_tier`
- `freshness_warning_seconds`
- `freshness_stale_seconds`
- `confirmation_requirement`
- `cooldown_seconds`
- `enabled`
- `review_status`
- `reviewer`
- `approved_at`

Resolution order:

1. Hard safety bounds from the rule implementation.
2. Patient-specific clinician-approved threshold.
3. Condition-profile threshold.
4. Global default threshold.

Patient/caretaker preferences may make notification earlier or quieter inside safety-approved bounds, but they must not disable critical event creation when the patient has active monitoring and emergency policy enabled.

## 8. Source Reliability And Freshness Rules

Reliability classes:

- `clinical`: FHIR/clinical source, base quality `0.95`.
- `standard_ble`: direct standard BLE medical profile, base quality `0.90`.
- `os_aggregator`: HealthKit/Health Connect with source attribution, base quality `0.85`.
- `vendor_api`: signed vendor API/webhook, base quality `0.80`.
- `manual_or_ocr`: reviewed manual/OCR value, base quality `0.55` to `0.60`; unreviewed cap `0.40`.
- `simulator`: test/demo only, never production risk evidence.

Freshness handling:

- Fresh abnormal data can create health risk events.
- Delayed abnormal data can create high-risk prompts or repeat-reading requests, depending on rule.
- Stale abnormal data can create freshness/device alerts, not critical live-deterioration events.
- Future timestamps are rejected or capped at low confidence.
- Missing expected data is a separate stale/missing-data rule outcome.

## 9. Example Risk Events

### Critical SpO2 Event

```json
{
  "rule_id": "spo2_low_v1",
  "rule_version": "1.0.0",
  "patient_id": "pat_123",
  "severity": "critical",
  "confidence": 0.91,
  "reason": "SpO2 is 86% from a fresh standard BLE pulse oximeter reading.",
  "recommended_policy_action": "start_emergency_protocol",
  "requires_policy_approval": true,
  "requires_patient_confirmation": false,
  "evidence": [
    {
      "metric_code": "spo2",
      "value_numeric": 86,
      "unit": "%",
      "source_type": "ble",
      "freshness": "fresh",
      "quality_score": 0.9,
      "observed_at": "2026-05-06T18:31:30+05:30"
    }
  ]
}
```

### Manual Glucose Event With Confirmation

```json
{
  "rule_id": "blood_glucose_low_v1",
  "rule_version": "1.0.0",
  "patient_id": "pat_123",
  "severity": "high",
  "confidence": 0.6,
  "reason": "Manual glucose entry is 58 mg/dL and needs patient confirmation before escalation.",
  "recommended_policy_action": "prompt_patient_repeat_reading",
  "requires_policy_approval": true,
  "requires_patient_confirmation": true,
  "evidence": [
    {
      "metric_code": "blood_glucose",
      "value_numeric": 58,
      "unit": "mg/dL",
      "source_type": "manual",
      "freshness": "fresh",
      "quality_score": 0.6
    }
  ]
}
```

### Device Stale Event

```json
{
  "rule_id": "device_stale_v1",
  "rule_version": "1.0.0",
  "patient_id": "pat_123",
  "severity": "low",
  "confidence": 0.5,
  "reason": "Heart-rate monitoring is stale for the active watch connector.",
  "recommended_policy_action": "prompt_patient_to_sync_device",
  "suppression_reason": "missing_or_stale_data_is_not_normal_data",
  "evidence": [
    {
      "metric_code": "heart_rate",
      "freshness": "stale",
      "last_observed_at": "2026-05-06T17:50:00+05:30"
    }
  ]
}
```

## 10. False Positive And False Negative Review

Every high/critical event and sampled moderate event should support review classification:

- `true_positive`
- `false_positive`
- `false_negative`
- `severity_too_high`
- `severity_too_low`
- `insufficient_evidence`
- `duplicate`
- `data_quality_issue`

Review loop:

1. Store the event, rule version, evidence IDs, escalation outcome, acknowledgement, and reviewer feedback.
2. Link the review to a simulator scenario when one exists.
3. Add a fixture before changing thresholds or rule logic.
4. Run the full risk test matrix against old and proposed rule versions.
5. Require safety review for any critical-rule behavior change.
6. Roll out new rule versions behind a feature flag.

KPIs:

- False-critical alert rate by rule and source.
- Missed-critical alert rate from simulator and incident reviews.
- Duplicate suppression rate.
- Time from qualifying evidence to first outbound policy request.
- Percentage of high/critical events with complete evidence and audit trail.
