# Data Model and API Contracts

## 1. Data Model Principles

- Patient data must be patient-scoped.
- Every medical fact must preserve provenance.
- Every autonomous action must preserve audit history.
- Every observation must preserve source, timestamp, unit, and data quality.
- The model should be FHIR-inspired without requiring full FHIR compliance in MVP.
- The design should allow later FHIR import/export.

## 2. Core Tables

### UserAccount

- id
- email
- phone
- auth_provider_id
- role: patient, caretaker, nurse, doctor, admin
- status
- created_at
- updated_at

### PatientProfile

- id
- account_id
- full_name
- date_of_birth
- sex
- primary_language
- address
- emergency_location_notes
- conditions
- allergies
- baseline_notes
- primary_doctor_contact_id
- created_at
- updated_at

### CareTeamMember

- id
- patient_id
- user_account_id nullable
- contact_id
- role: family, nurse, doctor, ambulance, hospital, other
- priority_order
- permissions
- active
- created_at

### ConsentGrant

- id
- patient_id
- subject_user_id
- consent_type
- scope
- channel nullable
- granted_to nullable
- status: active, revoked, expired
- granted_at
- expires_at nullable
- revoked_at nullable
- consent_text_version

### ContactEndpoint

- id
- display_name
- relationship
- phone
- whatsapp_id
- telegram_id
- email
- preferred_channel
- verified_status
- quiet_hours
- created_at

### Device

- id
- patient_id
- catalog_device_id nullable
- display_name
- brand
- model
- category
- connection_method
- supported_metrics
- reliability_tier
- active
- created_at

### DeviceConnection

- id
- device_id
- platform
- external_account_id nullable
- status
- last_sync_at
- last_seen_at
- battery_level nullable
- error_code nullable
- created_at

### Observation

- id
- patient_id
- device_id nullable
- metric_code
- value_numeric nullable
- value_text nullable
- unit
- observed_at
- ingested_at
- source_type: healthkit, health_connect, ble, vendor_api, fhir, ocr, manual
- reliability_tier
- confidence
- raw_payload_id nullable
- abnormal_flag
- trend_flag

### Medicine

- id
- patient_id
- name
- normalized_name nullable
- strength
- form
- instructions
- source_document_id nullable
- active
- created_at

### MedicineSchedule

- id
- medicine_id
- patient_id
- dose
- route
- scheduled_times
- start_date
- end_date nullable
- with_food nullable
- special_instructions
- review_status

### MedicineDoseEvent

- id
- schedule_id
- patient_id
- scheduled_at
- status: due, taken, skipped, missed, snoozed
- recorded_by
- recorded_at
- source_channel

### MedicalDocument

- id
- patient_id
- uploaded_by
- file_uri
- file_type
- document_type
- original_filename
- ocr_status
- extraction_status
- created_at

### ExtractedMedicalFact

- id
- document_id
- patient_id
- fact_type
- label
- value
- unit nullable
- effective_date nullable
- confidence
- source_page nullable
- source_text_span nullable
- review_status
- corrected_value nullable

### RiskEvent

- id
- patient_id
- severity
- confidence
- reason
- evidence_json
- status
- detected_at
- acknowledged_at nullable
- resolved_at nullable
- rule_id nullable

### EscalationPolicy

- id
- patient_id
- name
- severity_trigger
- contact_order
- allowed_channels
- patient_confirmation_timeout_seconds
- emergency_enabled
- location_sharing_enabled
- active

### EscalationRun

- id
- risk_event_id
- patient_id
- policy_id
- status
- started_at
- completed_at nullable
- outcome

### EscalationAction

- id
- escalation_run_id
- action_type
- target_contact_id
- channel
- template_id
- payload_json
- status
- attempted_at
- completed_at nullable
- provider_message_id nullable
- provider_call_id nullable

### AuditLog

- id
- actor_type
- actor_id
- patient_id nullable
- action
- resource_type
- resource_id
- ip_address nullable
- user_agent nullable
- metadata_json
- created_at

## 3. Observation Metric Codes

Initial codes:

- heart_rate
- blood_pressure_systolic
- blood_pressure_diastolic
- blood_glucose
- continuous_glucose
- spo2
- body_temperature
- respiratory_rate
- weight
- step_count
- sleep_duration
- fall_detected
- ecg_attachment
- medicine_dose

## 4. API Examples

### Create Observation

```http
POST /patients/{patient_id}/observations
Content-Type: application/json
```

```json
{
  "metric_code": "spo2",
  "value_numeric": 88,
  "unit": "%",
  "observed_at": "2026-05-06T18:32:00+05:30",
  "source_type": "ble",
  "device_id": "dev_123",
  "raw_payload": {
    "profile": "pulse_oximeter",
    "measurement_status": "valid"
  }
}
```

### Latest Vitals

```http
GET /patients/{patient_id}/vitals/latest
```

```json
{
  "patient_id": "pat_123",
  "readings": [
    {
      "metric_code": "heart_rate",
      "value": 78,
      "unit": "bpm",
      "observed_at": "2026-05-06T18:31:00+05:30",
      "source": "Apple Health",
      "freshness": "fresh"
    }
  ]
}
```

### Start Escalation

```http
POST /risk-events/{risk_event_id}/escalate
Content-Type: application/json
```

```json
{
  "requested_by": "policy_engine",
  "policy_id": "pol_critical_default",
  "idempotency_key": "risk_evt_123_critical_v1"
}
```

## 5. Agent Tool Contract

All tools must receive:

- patient_id
- actor_id or system actor
- request_id
- authorization scope
- reason

All tools must return:

- status
- result
- audit_log_id
- safe_user_message nullable
- error_code nullable

Example:

```json
{
  "tool": "send_channel_message",
  "input": {
    "patient_id": "pat_123",
    "contact_id": "contact_primary",
    "channel": "whatsapp",
    "template_id": "urgent_vitals_alert_v1",
    "variables": {
      "patient_name": "Ravi Sharma",
      "risk_reason": "Heart rate dropped to 38 bpm",
      "latest_reading": "38 bpm at 11:42 PM",
      "location": "Shared in app"
    },
    "reason": "critical_risk_escalation"
  }
}
```

## 6. Event Topics

Suggested event topics:

- `patient.created`
- `consent.updated`
- `device.connected`
- `device.disconnected`
- `observation.created`
- `observation.anomaly_detected`
- `medicine.dose_due`
- `medicine.dose_missed`
- `document.uploaded`
- `document.extraction_completed`
- `risk_event.created`
- `escalation.started`
- `escalation.action_attempted`
- `escalation.acknowledged`
- `agent.message_received`
- `agent.tool_called`

## 7. Audit Events

Audit must capture:

- Login/logout.
- Patient profile viewed.
- Health data viewed.
- Document viewed/downloaded.
- Agent answer generated.
- Tool called.
- Consent granted/revoked.
- Message sent.
- Call placed.
- Emergency protocol started.
- Alert acknowledged.
- Threshold/rule changed.
