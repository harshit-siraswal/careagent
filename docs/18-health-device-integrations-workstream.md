# Health Device Integrations Workstream

This document turns prompt 04 into concrete backend, mobile, and QA contracts for CareAgent health-device support.

## 1. Scope

This workstream owns ingestion from OS health stores, standard BLE medical profiles, vendor APIs, clinical interoperability feeds, manual entry, and OCR/device-photo fallbacks.

The goal is broad compatibility through clear tiers, not a universal guarantee. The product should always tell users which path is available for a device and whether that path is tested, partially tested, or a fallback.

Non-goals for the first implementation pass:

- Direct support for every vendor cloud.
- Medical diagnosis or treatment recommendations.
- Hidden emergency automation based only on device data.
- Claims that a device is clinically validated unless CareAgent has regulatory and clinical evidence for that exact model and integration path.

## 2. Connector Architecture

### 2.1 Mobile-side connectors

Mobile connectors collect consent, read local sources, preserve raw source metadata, and submit normalized payloads to the backend ingestion API.

Required connector modules:

- `HealthKitConnector`: iOS native module for HealthKit permissions, anchored queries, background delivery where allowed, and HealthKit source attribution.
- `HealthConnectConnector`: Android native module for Health Connect permissions, change-token sync, record reads, and data-origin attribution.
- `BleMedicalConnector`: cross-platform BLE scan, pair, subscribe, parse, reconnect, and stale-device tracking for standard medical profiles.
- `ManualReadingConnector`: user-entered readings with explicit source method, review metadata, and lower default reliability.
- `OcrReadingConnector`: reading extracted from image/document OCR with source image/document reference and review status.

Mobile connector interface:

```ts
interface HealthDataConnector {
  connectorCode: string;
  supportedMetrics(): MetricCapability[];
  requestPermissions(metrics: string[]): Promise<PermissionResult>;
  getPermissionStatus(metrics: string[]): Promise<PermissionResult>;
  syncSince(cursor: SyncCursor | null): Promise<ConnectorSyncBatch>;
  getDeviceStatus(): Promise<DeviceConnectionStatus[]>;
  revoke(): Promise<void>;
}
```

Every connector batch must include:

- `connector_code`
- `patient_id`
- source permission state
- sync cursor before and after the batch
- raw payload references or raw payload JSON
- normalized observation candidates
- source device/app attribution
- observed timestamp and ingestion timestamp

### 2.2 Backend services

Backend components:

- `DeviceCatalogService`: device search, catalog filtering, setup instructions, support requests, validation status.
- `CompatibilityService`: ranks connection options by platform, metric, validation status, and known limitations.
- `ConnectorAccountService`: tracks patient connector authorization, token vault references, sync cursors, and last sync status.
- `ObservationNormalizer`: maps source records to CareAgent metric codes, canonical units, FHIR-inspired JSON, and raw payload links.
- `DataQualityService`: scores freshness, provenance, plausibility, and corroboration.
- `VendorConnectorWorker`: OAuth/API sync framework for Fitbit, Garmin, Withings, Oura, Dexcom, Omron, and future vendors.
- `DeviceSimulator`: emits deterministic observation sequences for tests, demos, and risk-engine fixtures.

Ingestion flow:

1. Connector submits raw payload plus candidate observations.
2. Backend stores `observation_raw_payloads`.
3. `ObservationNormalizer` validates metric code, timestamp, unit, and source metadata.
4. Unit conversions are applied into canonical units.
5. `DataQualityService` assigns freshness, quality score, and quality flags.
6. Observation is persisted.
7. `observation.created` event is emitted.
8. Risk engine consumes only normalized observations with quality metadata.

Idempotency rules:

- HealthKit and Health Connect observations should use source record UUID/client record ID plus source bundle/package as the dedupe key.
- BLE observations should use device ID, profile, characteristic, observed timestamp, and parsed measurement sequence if present.
- Vendor API observations should use vendor sample ID plus account ID.
- Manual and OCR observations should use user/document ID plus local capture ID.

Connector runtime states:

- `available`: connector can be configured on the current platform.
- `permission_required`: connector exists but still needs patient permission.
- `active`: connector has permission and a successful sync or live read.
- `limited`: connector has partial permission, missing metrics, rate-limit pressure, or background restrictions.
- `stale`: connector has not produced expected data within its metric freshness window.
- `disconnected`: BLE/device account is not reachable and no recent sync is available.
- `reauth_required`: OAuth or OS permission changed and the patient must reconnect.
- `revoked`: patient revoked consent; sync and risk use must stop immediately.
- `failed`: connector is unavailable due to persistent parse/API/device errors.

Connector events published to the backend event bus:

- `connector.account_created`
- `connector.permission_changed`
- `connector.sync_started`
- `connector.sync_completed`
- `connector.sync_failed`
- `connector.reauth_required`
- `connector.revoked`
- `device.connection_state_changed`
- `observation.normalization_failed`

## 3. OS Health Store Plans

### 3.1 Apple HealthKit

HealthKit connector responsibilities:

- Request read permissions only for selected metric types.
- Use anchored queries for incremental sync.
- Preserve `HKSourceRevision`, device metadata, sample UUID, start/end timestamps, and metadata keys.
- Support background delivery only for data types and OS behavior that allow it; show freshness warnings when background delivery is delayed.
- Map HealthKit blood pressure as systolic/diastolic readings, preserving correlation metadata when available.
- Map sleep category samples into sleep duration and sleep-stage child observations where available.

Initial HealthKit identifiers:

- `heartRate`
- `bloodPressureSystolic`
- `bloodPressureDiastolic`
- `bloodGlucose`
- `oxygenSaturation`
- `bodyTemperature`
- `bodyMass`
- `respiratoryRate`
- `stepCount`
- `numberOfTimesFallen`
- sleep analysis category data

HealthKit connector acceptance checks:

- Permission-denied state is represented without failing onboarding.
- Each observation includes HealthKit source app/device attribution.
- Coalesced samples are not presented as continuous live telemetry.
- Manual entries inside Apple Health are treated as lower reliability when metadata indicates user entry.

### 3.2 Android Health Connect

Health Connect connector responsibilities:

- Request granular Health Connect permissions by record type.
- Use changes API/change tokens for incremental sync.
- Preserve `metadata.id`, `metadata.clientRecordId`, `metadata.dataOrigin`, recording method where available, and source package.
- Respect Health Connect rate limits and user-controlled permissions.
- Display app/device attribution in the mobile app and caretaker dashboard.

Initial Health Connect record mappings:

- `HeartRateRecord`
- `BloodPressureRecord`
- `BloodGlucoseRecord`
- `OxygenSaturationRecord`
- `BodyTemperatureRecord`
- `WeightRecord`
- `RespiratoryRateRecord`
- `StepsRecord`
- `SleepSessionRecord`

Health Connect connector acceptance checks:

- Permission revocation stops sync and records an audit event.
- Data-origin labels are preserved through latest-vitals responses.
- Sync cursor loss triggers bounded historical resync, not an unbounded scan.
- Records without enough timestamp/unit/source data are rejected into normalization errors.

## 4. BLE Profile Implementation Plan

Priority is based on MVP risk value, profile maturity, and availability of home devices.

| Priority | BLE profile | Service UUID | Key characteristic UUIDs | Metrics | Parser status |
| --- | --- | --- | --- | --- | --- |
| P0 | Heart Rate | `0x180D` | Heart Rate Measurement `0x2A37` | `heart_rate` | Build first |
| P0 | Blood Pressure | `0x1810` | Blood Pressure Measurement `0x2A35` | `blood_pressure_systolic`, `blood_pressure_diastolic`, pulse | Build first |
| P0 | Glucose | `0x1808` | Glucose Measurement `0x2A18`, Record Access Control Point `0x2A52` | `blood_glucose` | Build first or pulse ox alternative |
| P0 | Pulse Oximeter | `0x1822` | PLX Spot-check `0x2A5E`, PLX Continuous `0x2A5F`, PLX Features `0x2A60` | `spo2`, pulse | Build first or glucose alternative |
| P1 | Health Thermometer | `0x1809` | Temperature Measurement `0x2A1C` | `body_temperature` | Build second |
| P1 | Weight Scale | `0x181D` | Weight Measurement `0x2A9D` | `weight` | Build second |
| P2 | Continuous Glucose Monitoring | `0x181F` | CGM Measurement `0x2AA7`, CGM Feature `0x2AA8`, RACP `0x2A52` | `continuous_glucose` | Build after CGM vendor/legal review |

BLE parser requirements:

- Parse flags before values.
- Support SI and common display units.
- Preserve device timestamp if present; otherwise use mobile receipt time and mark `timestamp_source=mobile_received_at`.
- Preserve measurement status flags, sensor status, battery level, and device information service data when available.
- Reject packets with impossible lengths, unsupported flags, or invalid numeric ranges.
- Do not silently reinterpret vendor-specific characteristics as medical profile data.

BLE simulator requirements:

- Emit canonical raw GATT packets for each supported parser.
- Emit malformed packets for parser negative tests.
- Emit stale/disconnected device scenarios.
- Emit repeated measurements to test dedupe behavior.
- Allow deterministic time offsets for risk-engine tests.

## 5. Metric Normalization Map

Canonical units are internal storage units. UI may localize display units, but risk rules should evaluate canonical units.

| Metric code | Canonical unit | Accepted units | HealthKit | Health Connect | BLE | Freshness target |
| --- | --- | --- | --- | --- | --- | --- |
| `heart_rate` | `bpm` | `bpm`, `count/min` | `heartRate` | `HeartRateRecord` | Heart Rate Measurement | 5 min warning, 15 min stale |
| `blood_pressure_systolic` | `mmHg` | `mmHg`, `kPa` | `bloodPressureSystolic` | `BloodPressureRecord.systolic` | Blood Pressure Measurement | 30 min warning, 2 hr stale |
| `blood_pressure_diastolic` | `mmHg` | `mmHg`, `kPa` | `bloodPressureDiastolic` | `BloodPressureRecord.diastolic` | Blood Pressure Measurement | 30 min warning, 2 hr stale |
| `blood_glucose` | `mg/dL` | `mg/dL`, `mmol/L` | `bloodGlucose` | `BloodGlucoseRecord` | Glucose Measurement | 30 min warning, 2 hr stale |
| `continuous_glucose` | `mg/dL` | `mg/dL`, `mmol/L` | vendor/app mediated | vendor/app mediated | CGM Measurement | 15 min warning, 45 min stale |
| `spo2` | `%` | `%`, `fraction` | `oxygenSaturation` | `OxygenSaturationRecord` | PLX Measurement | 5 min warning, 15 min stale |
| `body_temperature` | `degC` | `degC`, `degF` | `bodyTemperature`, `basalBodyTemperature` | `BodyTemperatureRecord` | Temperature Measurement | 2 hr warning, 8 hr stale |
| `weight` | `kg` | `kg`, `lb`, `g` | `bodyMass` | `WeightRecord` | Weight Measurement | 7 day warning, 30 day stale |
| `respiratory_rate` | `breaths/min` | `breaths/min` | `respiratoryRate` | `RespiratoryRateRecord` | profile-specific/vendor | 15 min warning, 1 hr stale |
| `step_count` | `count` | `count` | `stepCount` | `StepsRecord` | none for MVP | 1 day warning, 2 day stale |
| `sleep_duration` | `min` | `min`, `hr`, `s` | sleep analysis category | `SleepSessionRecord` | none for MVP | 1 day warning, 2 day stale |
| `fall_detected` | `boolean` | `boolean`, `count` | `numberOfTimesFallen` or vendor/app event | vendor/app mediated | vendor-specific only | immediate warning, 15 min stale |

Unit conversion rules:

- `mmol/L` glucose to `mg/dL`: multiply by `18.0182`.
- `kPa` blood pressure to `mmHg`: multiply by `7.50062`.
- `degF` to `degC`: subtract `32`, multiply by `5/9`.
- `lb` to `kg`: multiply by `0.45359237`.
- fraction SpO2 to percent: multiply by `100`.
- hours to minutes: multiply by `60`; seconds to minutes: divide by `60`.

Compound metrics:

- Blood pressure should create separate systolic and diastolic observations with a shared `raw_payload_id` and group ID in `fhir_json`.
- Pulse supplied inside blood pressure or pulse oximeter payloads can create a `heart_rate` observation with source detail `derived_from_same_measurement`.
- Sleep stage records should attach stage detail in `fhir_json.component` or a future child-observation table.

Normalized observation contract:

```json
{
  "patient_id": "pat_123",
  "metric_code": "spo2",
  "value_numeric": 86,
  "value_text": null,
  "canonical_unit": "%",
  "observed_at": "2026-05-06T18:31:30+05:30",
  "ingested_at": "2026-05-06T18:31:35+05:30",
  "timestamp_source": "device_reported_at",
  "source_type": "ble",
  "source_label": "BLE Pulse Oximeter",
  "source_record_id": "ble_plx_002_spo2",
  "device_id": "dev_ox_100",
  "connector_account_id": "conn_ble_123",
  "reliability_tier": "standard_ble",
  "freshness": "fresh",
  "quality_score": 0.9,
  "quality_flags": ["critical_low_value"],
  "raw_payload_id": "raw_456",
  "dedupe_key": "dev_ox_100:plx:2a5e:2026-05-06T18:31:30+05:30",
  "fhir_json": {
    "resourceType": "Observation",
    "status": "final",
    "code": {
      "text": "SpO2"
    },
    "valueQuantity": {
      "value": 86,
      "unit": "%"
    }
  }
}
```

Normalizer rejection reasons:

- `missing_required_source`: no source type, source label, source record ID, or device/app attribution where required.
- `missing_timestamp`: no reliable observed timestamp.
- `future_timestamp`: observed timestamp is more than 5 minutes ahead of ingestion time.
- `unsupported_metric`: metric is not in the supported metric registry.
- `unsupported_unit`: unit cannot be converted to the canonical unit.
- `implausible_value`: value is outside device/profile plausible limits.
- `malformed_raw_payload`: parser could not decode the raw record.
- `duplicate_observation`: dedupe key already exists; suppress or link to original.

## 6. Device Catalog Schema

The catalog is global reference data. Patient-owned devices still live in `devices`.

Required catalog fields:

- brand
- model
- category
- support tier
- connection methods
- supported platforms
- supported metrics
- setup instructions
- latency expectation
- known limitations
- validation status
- regulatory notes
- active/inactive status
- regional availability
- catalog owner and review timestamp
- support evidence links: vendor docs, BLE certification notes, internal QA run, clinical-validation record if any

Validation statuses:

- `untested`
- `community_tested`
- `internally_tested`
- `clinically_validated`
- `deprecated`

Compatibility checker output should return ranked options:

1. OS health store path when likely available and supported by the user's platform.
2. Standard BLE path when the model/profile is known or the user can scan a matching profile.
3. Vendor connector path when CareAgent has an implemented connector.
4. FHIR/clinical record import when device data usually arrives through a clinic/lab portal.
5. Manual/OCR fallback.
6. Request-support path.

The UI must phrase results as compatibility tiers, for example:

- "Supported through Apple Health if this device syncs to Apple Health."
- "Direct Bluetooth support for standard Blood Pressure profile is planned/tested."
- "Manual/photo entry available. Automated sync is not confirmed for this model."

Catalog example:

```json
{
  "brand": "Example",
  "model": "BLE BP 200",
  "category": "blood_pressure_monitor",
  "support_tier": "standard_ble",
  "connection_methods": ["ble", "manual", "ocr"],
  "supported_platforms": ["ios", "android"],
  "supported_metrics": ["blood_pressure_systolic", "blood_pressure_diastolic", "heart_rate"],
  "latency_expectation": "near_real_time_when_phone_is_nearby",
  "freshness_targets": {
    "blood_pressure_systolic": {
      "warning_after_seconds": 1800,
      "stale_after_seconds": 7200
    }
  },
  "validation_status": "internally_tested",
  "known_limitations": [
    "Requires pairing before each household user switches profiles",
    "Pulse value is optional in BLE payload"
  ],
  "risk_use_allowed": true,
  "risk_use_notes": "Allowed for high/critical BP rules after safety review of parser and QA fixtures."
}
```

## 7. Vendor Connector Framework

Connector definition fields:

- `connector_code`
- display name
- kind: `os_health_store`, `standard_ble`, `vendor_api`, `clinical_fhir`, `manual`, `ocr`, `simulator`
- auth type: `local_permission`, `oauth2`, `api_key`, `none`
- supported metrics
- supported platforms
- consent scopes
- token vault requirements
- sync mode: batch, incremental, webhook, streaming
- expected latency
- production status
- docs URL

Patient connector account fields:

- patient ID
- connector code
- status
- external account hash
- token vault reference
- sync cursor
- last successful sync
- last error code/message
- revoked timestamp

Connector safety requirements:

- Store secrets only in a vault, not in the relational table.
- Hash external account IDs before storage unless a clear support need exists.
- Audit connect, disconnect, permission change, sync failure, and data access events.
- Do not allow vendor webhooks to create observations without signature verification and idempotency.

## 8. Data Quality Rules

Every observation must include:

- source type
- source label or device/app attribution
- observed timestamp
- ingestion timestamp
- unit
- freshness status
- reliability tier
- confidence/quality score
- raw payload reference when available

Freshness classification:

- `fresh`: observed age is within metric warning threshold.
- `delayed`: observed age is beyond warning threshold but below stale threshold.
- `stale`: observed age is beyond stale threshold.
- `future_timestamp`: observed timestamp is more than 5 minutes in the future.
- `unknown`: no reliable observed timestamp is available; reject for risk rules unless manually reviewed.

Base quality scores:

- Clinical/FHIR source: `0.95`
- Standard BLE medical profile: `0.90`
- OS health store with source attribution: `0.85`
- Vendor API: `0.80`
- Manual entry reviewed by user: `0.60`
- OCR reading reviewed by user: `0.55`
- Manual/OCR not reviewed: `0.40`
- Simulator: accepted only in test/demo environments

Quality penalties:

- Stale reading: `-0.20`
- Future timestamp: reject or cap at `0.20`
- Missing source app/device attribution: `-0.15`
- Implausible numeric range: reject or cap at `0.10`
- Low battery or sensor status warning: `-0.05`
- Manual/OCR value not reviewed: `-0.15`
- Duplicate or near-duplicate reading: suppress duplicate and link to existing observation
- Conflicts with fresher higher-quality source: keep but lower risk weight

Risk-engine use:

- Critical alerts may use high-quality direct device readings with lower confirmation requirements.
- Manual/OCR readings should not trigger emergency escalation without confirmation unless paired with symptoms or corroborating device data.
- Stale readings can trigger stale-device alerts but should not be treated as live deterioration.
- Risk evidence should include source, age, unit, value, and quality flags.

Quality scoring algorithm:

1. Start with the source-type base score.
2. Reject observations missing metric, unit, observed timestamp, source type, or patient scope.
3. Convert to canonical unit and reject unsupported conversions.
4. Apply plausible-range checks before risk rules run.
5. Calculate observed age from `ingested_at - observed_at` and assign freshness.
6. Apply penalties for stale data, missing attribution, low battery, sensor status warnings, and unreviewed manual/OCR sources.
7. Add corroboration flags when another source reports the same abnormal pattern inside the configured window.
8. Persist both the final score and the explainable factors so risk events can cite them.

Plausible input ranges for normalization, not clinical thresholds:

| Metric code | Reject below | Reject above | Notes |
| --- | ---: | ---: | --- |
| `heart_rate` | 20 bpm | 240 bpm | Values outside this range require parser/manual review. |
| `blood_pressure_systolic` | 50 mmHg | 280 mmHg | Must preserve cuff/status flags where available. |
| `blood_pressure_diastolic` | 30 mmHg | 180 mmHg | Systolic must be greater than diastolic for grouped BP readings. |
| `blood_glucose` | 20 mg/dL | 600 mg/dL | CGM sensor-status warnings lower quality. |
| `spo2` | 50% | 100% | Signal quality or perfusion flags must be kept when available. |
| `body_temperature` | 30 degC | 45 degC | Preserve body site/method if available. |
| `respiratory_rate` | 4 breaths/min | 80 breaths/min | Vendor-derived values require source explanation. |
| `weight` | 1 kg | 350 kg | Pediatric support needs separate review. |

## 9. API Surface

Minimum endpoints owned by this workstream:

- `GET /device-catalog`
- `GET /device-catalog/{catalog_device_id}`
- `POST /device-compatibility/check`
- `POST /device-support-requests`
- `POST /patients/{patient_id}/connector-accounts`
- `GET /patients/{patient_id}/connector-accounts`
- `DELETE /patients/{patient_id}/connector-accounts/{account_id}`
- `POST /patients/{patient_id}/observations`
- `POST /patients/{patient_id}/simulator/runs`

OpenAPI contracts are started in `backend/openapi/health-device-integrations.yaml`.

## 10. Test Fixtures And Simulators

Fixture goals:

- Normal fresh day of Health Connect vitals.
- Critical SpO2 drop from BLE pulse oximeter.
- Manual glucose reading with lower reliability.
- Stale watch data that should create a stale-data warning, not an emergency event.
- Fall detection event from vendor/OS source.
- Malformed BLE packets for parser rejection tests.

Fixture file:

- `backend/tests/fixtures/device-simulator-scenarios.json`

Simulator behavior:

- Can emit observations directly into the ingestion API.
- Can emit raw payloads plus expected normalized observations.
- Can freeze a scenario clock for deterministic tests.
- Can mark itself as `source_type=simulator`.
- Must be disabled in production unless an explicit demo/test environment flag is present.

Scenario schema requirements:

- `scenario_code`, `display_name`, `source_type`, `connector_code`, and `supported_metrics`.
- Optional patient context: age band, known conditions, baseline values, and active thresholds.
- Observation list with `offset_seconds`, metric, value, unit, observed timestamp, source label, reliability tier, source record ID, optional group ID, raw payload, and expected quality.
- Expected risk events with severity, rule ID or reason substring, confirmation requirement, policy action, and whether escalation should be suppressed.
- Expected non-events for false-negative regression tests, such as stale abnormal values that must not create critical alerts.
- Malformed packet list with characteristic UUID, payload, and expected parser error.

The simulator must support three modes:

- `dry_run`: return generated observations and expected outcomes without persistence.
- `ingest`: submit observations through the ingestion endpoint and emit normal events.
- `replay`: run with deterministic offsets against a frozen scenario clock for risk-engine regression tests.

## 11. Edge Cases

- User revokes HealthKit/Health Connect permission after onboarding.
- Same wearable syncs through both OS health store and vendor API.
- Device timestamp is missing, local, or timezone-free.
- Vendor API backfills old data after outage.
- Manual entry conflicts with device reading.
- OCR reads `98` as `88` for SpO2.
- Blood pressure arrives without pulse or with only one component.
- BLE device sends measurement in unsupported units.
- Phone receives BLE data late after being offline.
- Caretaker views stale vitals without noticing age.
- User switches phone platform and connector history must be preserved.

## 12. Assumptions And Open Questions

Assumptions:

- PostgreSQL remains the system of record for catalog, connector accounts, raw payload pointers, and quality assessments.
- Observation time-series partitioning stays in PostgreSQL or TimescaleDB for MVP.
- Native mobile modules will own HealthKit, Health Connect, and BLE permission UX.
- Vendor connector secrets will use a vault outside the application database.

Open questions:

- Which pilot devices do target users already own?
- Which glucose/SpO2 path should be the third BLE P0 profile for MVP?
- Which vendor APIs are allowed in the first pilot region?
- Will CareAgent pursue any clinical-validation claims for specific devices?
- Should continuous glucose support be vendor-first rather than BLE-first because of device ecosystem constraints?
- What country-specific regulatory review is required before displaying emergency-use toggles for device readings?

## 13. Primary References

- Android Health Connect data types: https://developer.android.com/health-and-fitness/health-connect/data-types
- Apple HealthKit quantity type identifiers: https://developer.apple.com/documentation/healthkit/hkquantitytypeidentifier
- Bluetooth specifications index: https://www.bluetooth.com/specifications/specs/
- HL7 FHIR Observation: https://hl7.org/fhir/observation.html
