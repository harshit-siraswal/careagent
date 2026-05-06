# Prompt: Risk Engine Workstream

You are responsible for the CareAgent risk engine and anomaly detection logic.

Read:

- `docs/01-prd.md`
- `docs/02-trd.md`
- `docs/03-device-integration-strategy.md`
- `docs/05-safety-compliance-and-risk.md`
- `docs/09-mvp-acceptance-criteria.md`

Build or plan:

- Risk event schema.
- Configurable patient-specific thresholds.
- Metric freshness rules.
- Trend detection for rapid changes.
- Missing/stale data alerts.
- Source reliability scoring.
- Risk tier mapping.
- Policy hooks for escalation.
- Test dataset and simulations.

Initial risk categories:

- Heart-rate high/low and rapid change.
- Blood-pressure high/low.
- Blood glucose high/low.
- SpO2 low.
- Temperature high/low.
- Fall detected.
- Missed medicine.
- Device disconnected or stale.

Important constraints:

- Do not use the LLM as the sole safety decision-maker.
- Risk events must include evidence and source reliability.
- Critical alerts must be conservative and auditable.
- Rules must be versioned and clinically reviewable.
- Missing data is not the same as normal data.

Deliver:

- Rule design.
- Threshold configuration model.
- Test matrix.
- Example risk events.
- Escalation policy interface.
- False-positive/false-negative review loop.
