# Safety, Compliance, and Risk Requirements

## 1. Safety Position

CareAgent should launch as a health coordination, monitoring, reminder, and escalation assistant. It should not be marketed as a doctor, diagnostic engine, or autonomous treatment system unless the company intentionally pursues medical device regulatory clearance.

The product can:

- Monitor readings.
- Detect rule-defined anomalies.
- Remind and check in.
- Notify caretakers and doctors.
- Summarize records.
- Help users ask better questions.
- Escalate emergencies based on explicit user-configured protocols.

The product must not:

- Independently diagnose.
- Change medication.
- Tell users to ignore clinician advice.
- Guarantee emergency response.
- Hide that an AI is speaking or messaging.

## 2. Human-Centered Escalation

Critical design principle: the agent should reach humans quickly, not try to become the human.

Escalation chain:

1. Patient prompt if feasible.
2. Primary caretaker.
3. Secondary caretaker.
4. Nurse/doctor.
5. Ambulance or emergency service.
6. Repeat/fallback according to local policy.

For high-risk but non-critical readings, the system should ask a confirmation question before escalating when safe:

- "Are you feeling chest pain, dizziness, breathlessness, confusion, or fainting?"
- "Please recheck your BP/glucose if possible."
- "I will notify your caretaker if you do not respond in 2 minutes."

For critical patterns, the system may skip patient confirmation if pre-authorized.

## 3. Emergency Protocol Requirements

Must have:

- Explicit emergency escalation consent.
- Local emergency number configuration.
- Location sharing consent.
- Emergency contact order.
- Call/message templates.
- False alarm cancellation path.
- Event timeline and audit.
- Manual SOS button.

Should have:

- Periodic emergency drill/test mode that does not call real emergency services.
- Region-specific emergency provider logic.
- Caretaker acknowledgement button.
- Automatic event summary after resolution.

India-specific note:

- 112 is the integrated emergency response number. The National Portal also lists 102 as National Ambulance Service. Local/private ambulance contacts may differ and should be configurable.

## 4. Regulatory Considerations

India:

- Digital Personal Data Protection Act, 2023 applies to digital personal data processing.
- ABDM/ABHA design should be consent-based if integrating Indian health records.
- Health data should be treated as highly sensitive even where a specific health privacy law is not the same as HIPAA.
- Telemedicine/clinical advice workflows should involve licensed practitioners.

United States:

- HIPAA may apply if CareAgent acts for covered entities or business associates.
- FDA medical-device software rules may apply depending on intended use, especially if the app diagnoses, treats, or transforms a phone into a medical device.

Global:

- Build with GDPR-style consent, minimization, access control, deletion, and portability principles even if not initially launching in the EU.

## 5. Privacy Requirements

- Collect only what is needed for the selected features.
- Explain each permission in plain language.
- Allow users to revoke health data, location, channel, and caretaker access.
- Support patient data export.
- Support patient deletion where legally allowed.
- Separate medical content from marketing analytics.
- Do not sell health data.
- Do not use patient health records to train models unless there is explicit, separate, legally reviewed consent.

## 6. Security Requirements

- TLS for all network communication.
- Encryption at rest for databases and object storage.
- Field-level encryption for high-risk identifiers where feasible.
- Secrets in a managed secret store.
- RBAC and patient-scoped authorization.
- MFA for caretakers, nurses, doctors, and admins.
- Device/session management.
- Webhook signature verification.
- Audit logs for every PHI access and external action.
- Tamper-resistant escalation logs.
- Backups and disaster recovery.

## 7. AI Safety Requirements

- Ground health answers in uploaded records and recent observations.
- Show sources for report-based answers.
- Say when data is missing or stale.
- Refuse unsafe requests such as "change my BP medicine dose."
- Encourage urgent care for severe symptoms.
- Avoid overconfident language.
- Apply prompt-injection defenses.
- Use deterministic tools for actions.
- Keep the LLM away from raw secrets and broad patient lists.

## 8. Risk Rule Governance

Every risk rule must have:

- Rule ID.
- Medical rationale.
- Target condition/population.
- Inputs and thresholds.
- Required source reliability.
- Severity mapping.
- Escalation action.
- Test cases.
- Reviewer and approval date.
- Version history.

Changes to critical rules must require clinical/safety review and staged rollout.

## 9. Incident Review

Every high or critical escalation should create an incident record:

- Timeline.
- Readings and sources.
- Agent reasoning summary.
- Policy decisions.
- Messages/calls sent.
- Who acknowledged.
- Outcome.
- User/caretaker feedback.
- False positive/negative classification if known.

## 10. References

- FDA device software and mobile medical applications: https://www.fda.gov/medical-devices/digital-health-center-excellence/device-software-functions-including-mobile-medical-applications
- FDA policy guidance: https://www.fda.gov/regulatory-information/search-fda-guidance-documents/policy-device-software-functions-and-mobile-medical-applications
- HHS HIPAA Security Rule summary: https://www.hhs.gov/hipaa/for-professionals/security/laws-regulations/index.html
- India DPDP Act 2023: https://www.indiacode.nic.in/bitstream/123456789/22037/1/a2023-22.pdf
- India ERSS 112: https://112.gov.in/about
- National Portal of India helplines: https://www.india.gov.in/directory/helpline
