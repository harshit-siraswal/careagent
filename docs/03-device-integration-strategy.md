# Medical Device Integration Strategy

## 1. Goal

CareAgent must support all practical categories of health and medical devices, including fitness bands, smart watches, and diagnosis/monitoring devices. Since no product can directly support every device model on day one, the product must offer near-universal support through layered compatibility tiers.

## 2. Device Categories

Consumer wearables:

- Smart watches.
- Fitness bands.
- Rings.
- Sleep trackers.
- Smart scales.

Medical and home diagnostic devices:

- Blood pressure monitors.
- Glucometers.
- Continuous glucose monitors.
- Pulse oximeters.
- Thermometers.
- ECG patches and portable ECG devices.
- Heart-rate monitors.
- Weight scales.
- Respiratory rate monitors.
- Peak flow meters.
- Spirometers.
- Insulin pumps and connected pens where APIs allow.

Clinical and facility systems:

- Lab systems.
- Hospital patient portals.
- FHIR servers.
- ABDM/ABHA-connected records where available.
- Diagnostic centers.

Fallback sources:

- Manual entry.
- CSV import.
- Photo of a device screen.
- Photo/PDF of medical report.
- WhatsApp/Telegram upload.

## 3. Compatibility Tiers

Tier 1: OS health stores.

- iOS: Apple HealthKit.
- Android: Health Connect.
- Purpose: support broad wearable ecosystems indirectly through data already synced to the phone.
- Best for: Apple Watch, many Android watches, fitness bands, sleep apps, workout apps, scales, and data shared by vendor apps.

Tier 2: Standard BLE profiles.

- Use Bluetooth Low Energy GATT profiles where devices implement standards.
- Target profiles: Heart Rate, Blood Pressure, Glucose, Health Thermometer, Pulse Oximeter, Weight Scale, Continuous Glucose Monitoring where available.
- Best for: direct pairing with home medical devices without cloud dependency.

Tier 3: Vendor APIs and SDKs.

- Build direct connectors for high-priority vendors.
- Examples: Garmin, Fitbit, Withings, Oura, WHOOP, Samsung Health, Dexcom, Abbott, Omron, iHealth, Beurer, Accu-Chek, Contour, and local India-focused device vendors.
- Best for: richer data, historical sync, better device metadata, and users whose data is not exposed through OS stores.

Tier 4: Clinical interoperability.

- HL7 FHIR APIs and files.
- ABDM/ABHA-oriented consent records for India where product strategy supports it.
- Lab report imports.
- Best for: clinical-grade reports, prescriptions, diagnoses, discharge summaries, and longitudinal records.

Tier 5: Manual/OCR fallback.

- Manual entry forms.
- Photo OCR of readings and reports.
- CSV import.
- WhatsApp/Telegram uploads.
- Best for unsupported devices, non-connected medical devices, and low-tech users.

## 4. Device Catalog

CareAgent must maintain a device catalog with:

- Brand.
- Model.
- Device category.
- Supported metrics.
- Supported platforms.
- Connection method: HealthKit, Health Connect, BLE, vendor API, FHIR, manual/OCR.
- Setup instructions.
- Data latency expectations.
- Known limitations.
- Validation status: untested, community-tested, internally tested, clinically validated.
- Regulatory notes.

The app should expose a compatibility checker:

- "Search your device."
- "Connect through Apple Health/Health Connect."
- "Connect directly by Bluetooth."
- "Upload readings manually/photo."
- "Request support for this device."

## 5. Normalized Metrics

Initial metric support:

- Heart rate.
- Blood pressure: systolic, diastolic, pulse.
- Blood glucose.
- Continuous glucose values.
- SpO2.
- Body temperature.
- Respiratory rate.
- Weight.
- Steps.
- Sleep duration and sleep stages where available.
- ECG availability and PDF/file references.
- Fall detection events.
- Activity/workouts.
- Medicine dose events.

Each metric must have:

- Standard internal code.
- Display name.
- Accepted units.
- Unit conversion.
- Normal range strategy.
- Patient-specific thresholds.
- Device reliability tier.
- Data freshness requirement.

## 6. Data Quality Rules

Each observation must be classified:

- Measured by device.
- Entered by user.
- Extracted from document.
- Imported from clinical record.
- Derived by algorithm.

Each observation must include confidence/reliability signals:

- Source method.
- Device model.
- Battery status if available.
- Timestamp from device and ingestion timestamp.
- Whether data is stale.
- Whether value is out of device's plausible range.
- Whether multiple signals corroborate the event.

Risk rules must treat data differently based on source reliability. For example, a critical action from a direct medical-grade device can have a lower confirmation requirement than a single OCR/manual reading.

## 7. MVP Device Scope

Android MVP:

- Health Connect.
- BLE Heart Rate.
- BLE Blood Pressure.
- BLE Glucose or Pulse Oximeter.
- Manual/OCR readings.

iOS MVP:

- HealthKit.
- BLE Heart Rate.
- BLE Blood Pressure.
- BLE Glucose or Pulse Oximeter.
- Manual/OCR readings.

Pilot vendor priorities should be chosen from actual target users' devices. Do not build a broad vendor connector set before measuring device ownership.

## 8. UI Requirements

Device connection screen:

- Connected devices.
- Last sync time.
- Data types received.
- Battery and signal status where available.
- "Data may be delayed" warning for vendor/cloud sync.
- "Use for emergency escalation" toggle per metric/source.

Live patient screen:

- Latest vital values.
- Trend and freshness.
- Source label.
- Anomaly status.
- Device disconnected/stale warning.

Caretaker dashboard:

- Device status per patient.
- Missing device data alerts.
- Risk-priority views.

## 9. Developer Workstreams

Workstream A: HealthKit and Health Connect.

- Build permissions, record reads, background delivery where allowed, sync cursor, and metric normalization.

Workstream B: BLE medical profiles.

- Build BLE scan/pair/read flows, profile parsers, reconnection, stale-data handling, and simulator mocks.

Workstream C: Vendor connector framework.

- Build OAuth/API connector abstraction, refresh tokens, data sync workers, and mapping.

Workstream D: Device catalog.

- Build catalog schema, admin management, compatibility checker, and request-support flow.

Workstream E: Data quality and safety.

- Build reliability scoring, plausible ranges, stale-data rules, and risk-engine integration.

## 10. References

- Android Health Connect: https://developer.android.com/health-and-fitness/health-connect
- Health Connect data types: https://developer.android.com/health-and-fitness/health-connect/data-types
- Apple HealthKit: https://developer.apple.com/documentation/healthkit
- Apple HealthKit data types: https://developer.apple.com/documentation/healthkit/data-types
- Bluetooth specifications: https://www.bluetooth.com/specifications/specs/
- HL7 FHIR Observation: https://hl7.org/fhir/observation
