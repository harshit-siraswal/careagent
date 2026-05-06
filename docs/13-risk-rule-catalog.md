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
