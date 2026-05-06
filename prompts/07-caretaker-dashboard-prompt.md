# Prompt: Caretaker Dashboard Workstream

You are responsible for the CareAgent caretaker dashboard.

Read:

- `docs/01-prd.md`
- `docs/02-trd.md`
- `docs/06-data-model-and-api.md`

Build or plan:

- Caretaker login.
- Multi-patient roster.
- Risk-prioritized patient list.
- Alert inbox.
- Patient timeline.
- Device status view.
- Medicine adherence view.
- Documents and extracted facts view.
- Care team management.
- Summary request and regular updates.

Important constraints:

- A caretaker can only access patients who granted access.
- Every sensitive view must be audited.
- The dashboard must show freshness and source for vitals.
- Alerts must have acknowledge, assign, resolve, and escalate actions.
- Avoid clutter. This is an operational dashboard for repeated daily use.

Deliver:

- Information architecture.
- Screen list.
- Component requirements.
- API dependencies.
- RBAC behavior.
- Alert workflow.
- Empty, loading, error, and high-risk states.
- Tests for multi-patient access isolation.
