# Prompt: Health Device Integrations Workstream

You are responsible for CareAgent device and health-data integrations.

Read:

- `docs/03-device-integration-strategy.md`
- `docs/02-trd.md`
- `docs/06-data-model-and-api.md`

Build or plan:

- Apple HealthKit connector.
- Android Health Connect connector.
- BLE parsers for priority medical profiles.
- Device catalog.
- Device compatibility checker.
- Vendor connector framework.
- Observation normalization.
- Data quality scoring.
- Device simulator for tests.

Initial metrics:

- Heart rate.
- Blood pressure.
- Blood glucose.
- SpO2.
- Body temperature.
- Weight.
- Respiratory rate.
- Steps.
- Sleep.
- Fall detection.

Important constraints:

- Every reading must include source, timestamp, unit, and freshness.
- Device data may be delayed or stale.
- Manual/OCR readings are lower reliability than device readings.
- UI must not claim universal guaranteed compatibility.

Deliver:

- Connector architecture.
- Metric normalization map.
- BLE profile implementation plan.
- Device catalog schema.
- Data quality rules.
- Test fixtures and simulators.
