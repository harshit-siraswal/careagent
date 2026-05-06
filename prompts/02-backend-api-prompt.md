# Prompt: Backend API and Data Platform Workstream

You are responsible for the CareAgent backend.

Read:

- `docs/01-prd.md`
- `docs/02-trd.md`
- `docs/06-data-model-and-api.md`
- `docs/05-safety-compliance-and-risk.md`

Build or plan:

- Auth integration.
- Patient, caretaker, doctor, nurse, and admin roles.
- Patient-scoped RBAC.
- Consent ledger.
- Device and observation APIs.
- Document upload and extraction status APIs.
- Medicine schedule and dose events.
- Risk events and alerts.
- Escalation policies and runs.
- Agent tool APIs.
- Audit logging.

Important constraints:

- Every endpoint must enforce patient scope and role permissions.
- Every PHI access must create an audit event.
- Escalation endpoints must be idempotent.
- Raw documents must go to object storage with malware scanning and access controls.
- Observation storage must handle time-series volume.

Deliver:

- Database schema/migrations.
- API route list.
- Request/response schemas.
- Authorization matrix.
- Queue/event design.
- Audit events.
- Unit and integration tests.
