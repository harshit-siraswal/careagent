# Caretaker Dashboard Workstream Plan

This document turns prompt 07 into a concrete implementation plan for the CareAgent caretaker dashboard. It is grounded in the PRD, TRD, and data model/API contracts.

## 1. Scope and Guardrails

Dashboard responsibilities:

- Let caretakers, nurses, doctors, and authorized care operators log in with role-based access.
- Manage a multi-patient roster using risk-prioritized operational views.
- Surface alerts, device freshness, medicine adherence, document facts, patient timeline, and care team state.
- Support acknowledge, assign, resolve, and escalate workflows for alerts.
- Support regular patient summaries and on-demand summaries.
- Audit every sensitive view and every alert/care-team action.

Non-negotiable limits:

- A caretaker can access only patients with active patient grants and matching permissions.
- The dashboard must never load broad PHI before patient access is resolved.
- Multi-patient screens must show minimum necessary data. Detailed PHI appears only after selecting an authorized patient.
- Every vital reading shown must include source, observed timestamp, and freshness.
- Emergency escalation actions must be policy-approved and idempotent.
- The interface should be dense, quiet, and operational. Avoid marketing-style hero layouts and decorative cards.

## 2. User Roles and Permissions

Roles:

- `caretaker`: family member or trusted support person.
- `nurse`: care worker who can manage assigned patients and alert queues.
- `doctor`: clinical contact who can view summaries, documents, and escalations where granted.
- `admin`: product/support operator with break-glass controls and mandatory reason/MFA for PHI.

Permission groups:

| Permission | Allows |
| --- | --- |
| `patient:read` | Basic patient profile, non-sensitive roster identity. |
| `observations:read` | Vitals, trends, freshness, device-derived evidence. |
| `devices:read` | Device status, battery, last sync, source reliability. |
| `medicines:read` | Medicine schedules and adherence. |
| `medicines:write` | Mark doses, edit schedules when patient granted. |
| `documents:read` | Documents, OCR status, extracted facts, citations. |
| `documents:write` | Review/correct extracted facts when granted. |
| `alerts:read` | Alert inbox, risk event evidence, escalation timeline. |
| `alerts:write` | Acknowledge, assign, resolve, annotate alerts. |
| `escalation:execute` | Request policy-approved escalation. |
| `care_team:read` | View contacts and assignments. |
| `care_team:write` | Invite, remove, assign, or update permissions. |
| `summaries:request` | Request agent summaries. |

## 3. Information Architecture

Top-level navigation:

- `Roster`: risk-prioritized patient list.
- `Alerts`: shared alert inbox with queue filters.
- `Patients`: patient search and saved cohorts.
- `Summaries`: scheduled and requested updates.
- `Care Team`: members, roles, assignments, invitations.
- `Settings`: channel links, notification preferences, audit-visible account settings.

Patient workspace tabs:

- `Overview`: status, active alerts, latest vitals, next doses, device freshness.
- `Timeline`: alerts, vitals, dose events, documents, messages, calls, care notes.
- `Vitals`: latest and trends with source/freshness.
- `Devices`: connected sources, sync state, reliability, battery.
- `Medicines`: adherence, schedules, missed doses, review flags.
- `Documents`: uploads, extracted facts, review tasks, Q&A.
- `Care Team`: patient-specific contacts, access grants, escalation order.
- `Audit`: user-visible activity relevant to the patient, filtered by permission.

## 4. Screen List

### 4.1 Auth and Account

- `CaretakerLoginScreen`: email/phone/provider login, MFA prompt, session creation.
- `AccessPendingScreen`: explains that patient access requires an invitation/grant.
- `AccountSecurityScreen`: sessions, MFA, channel preferences.

Requirements:

- MFA required for nurses, doctors, admins, and recommended for caretakers.
- Login must not expose patient names until authorization succeeds.
- Session timeout and device/session revocation must be visible.

### 4.2 Roster

- `RiskRosterScreen`: default home for caretakers with multiple patients.
- `RosterFiltersPanel`: risk severity, stale devices, missed dose, active alerts, unreviewed documents, assigned nurse.
- `PatientRosterRow`: patient display name, age range if allowed, risk badge, top reason, latest freshness, next due action.
- `RosterBulkSummaryBar`: count by severity and stale state without exposing detailed PHI.

Sort order:

1. Critical active alerts.
2. High active alerts.
3. Unacknowledged moderate alerts.
4. Missed critical medicines.
5. Stale/disconnected high-priority devices.
6. Pending document review affecting reminders.
7. Routine patients by last updated time.

### 4.3 Alert Inbox

- `AlertInboxScreen`: queue of alerts across authorized patients.
- `AlertDetailDrawer`: evidence, timeline, source freshness, policy action, notes.
- `AssignAlertDialog`: assign to self, nurse, doctor, or care-team member.
- `ResolveAlertDialog`: resolution note, outcome classification, false-positive flag.
- `EscalateAlertDialog`: shows allowed policy actions and simulation/real mode.

Alert actions:

- `acknowledge`: records who saw it and stops duplicate notification retries where policy allows.
- `assign`: transfers operational owner without resolving risk.
- `resolve`: requires outcome note and classification.
- `escalate`: starts or resumes policy-approved escalation run.
- `snooze`: allowed only for low/moderate non-emergency alerts if policy permits.

### 4.4 Patient Overview

- `PatientOverviewScreen`: compact status board.
- `ActiveAlertBanner`: high/critical only, pinned at top.
- `LatestVitalsStrip`: metric, value, unit, source, observed time, freshness.
- `DeviceHealthPanel`: disconnected/stale devices, battery, sync lag.
- `MedicineTodayPanel`: due/taken/missed/snoozed counts.
- `DocumentReviewPanel`: pending high-impact extractions.
- `CareTeamPanel`: assigned caretaker/nurse, escalation order, channel verification state.

### 4.5 Timeline

- `PatientTimelineScreen`: chronological events with filters.
- Event types: vitals, risk events, alerts, dose events, documents, extraction reviews, messages, calls, channel receipts, notes, consent changes.
- `TimelineEventRow`: icon, title, short evidence summary, source, actor, timestamp, audit link.

Rules:

- Default to recent 72 hours.
- High/critical events are visually distinct but not alarmist.
- Raw PHI details expand only after row click and audit event.

### 4.6 Devices

- `DeviceStatusScreen`: all connected device sources.
- `DeviceStatusRow`: device/source, status, supported metrics, last seen, last sync, battery, reliability tier.
- `DeviceMetricCoverageTable`: which vitals each source contributes.
- `DisconnectedDeviceAction`: message patient, mark known issue, request re-sync, or open instructions.

Freshness states:

- `live`: within metric-specific live window.
- `recent`: usable but not live.
- `stale`: too old for current safety decisions.
- `disconnected`: source expected data but not reachable.
- `unavailable`: consent missing, no source, or permission denied.
- `unknown`: backend cannot determine status.

### 4.7 Medicines

- `MedicineAdherenceScreen`: today, 7-day, 30-day adherence.
- `DoseEventTable`: due, taken, skipped, snoozed, missed.
- `MedicineSchedulePanel`: active schedules with review status and source document.
- `MissedDoseWorkflow`: acknowledge, message patient, assign follow-up, escalate if policy allows.
- `PrescriptionProposalReview`: extracted schedule confirmation if caretaker has permission.

Rules:

- Dashboard must not recommend dose changes.
- Schedule edits from extracted prescriptions require explicit review and audit.
- Caretaker-marked dose events must show recorded-by actor and channel.

### 4.8 Documents and Extracted Facts

- `DocumentsScreen`: uploaded files, processing state, document type, date, review state.
- `DocumentDetailScreen`: safe preview link, OCR status, extracted facts, citations.
- `ExtractionReviewTable`: fact, value, confidence, source page/snippet, approve/correct/reject.
- `DocumentQuestionPanel`: source-grounded question input with citations.

Rules:

- Pending/rejected facts cannot appear as reviewed patient truth.
- Raw document download/view creates a PHI audit event.
- The UI must show "unreviewed" and confidence for extracted facts.

### 4.9 Care Team Management

- `CareTeamDirectoryScreen`: patient-specific contacts and users.
- `InviteCaretakerDialog`: invite by email/phone, role, permission template, expiry.
- `AccessGrantEditor`: patient-scoped permissions, expiry, revocation.
- `EscalationOrderEditor`: priority order and allowed channels.
- `ChannelVerificationPanel`: WhatsApp/Telegram/voice/email verification.

Rules:

- Only patient, authorized manager, or admin break-glass can grant access.
- Revocation takes effect immediately for active sessions and channel links.
- Permission changes are audited with old/new values.

### 4.10 Summaries

- `SummaryRequestScreen`: daily, weekly, shift handoff, incident summary, document summary.
- `SummaryScheduleScreen`: regular update schedule, channel, recipients, quiet hours.
- `SummaryPreviewDrawer`: AI-generated summary with sources and redaction checks.

Rules:

- Summaries require `summaries:request` and relevant read permissions.
- Outbound summaries require channel consent and approved templates where required.
- Summary generation must disclose missing, stale, and low-confidence data.

## 5. Component Requirements

Shared components:

- `RiskBadge`: severity with deterministic color and label.
- `FreshnessBadge`: live/recent/stale/disconnected/unavailable/unknown.
- `SourcePill`: HealthKit, Health Connect, BLE, vendor, OCR, manual, clinical.
- `AuditAwareLink`: wraps PHI views and logs the access reason.
- `PatientContextSwitcher`: exact patient selection for authorized users.
- `AlertActionBar`: acknowledge, assign, resolve, escalate.
- `EvidenceList`: readings/facts with value, unit, timestamp, source, confidence.
- `EscalationTimeline`: action attempts, receipts, acknowledgements.
- `ReviewStatusBadge`: pending/approved/corrected/rejected/superseded.
- `PermissionDeniedPanel`: no PHI; shows how to request access.
- `EmptyOperationalState`: compact empty states for no alerts/no devices/no documents.
- `ErrorStatePanel`: request ID, retry, support handoff.

State management:

- Server state should be patient-scoped and permission-scoped.
- Cache keys must include actor ID, patient ID, permission set, and selected filters.
- Clear patient-scoped cache on logout, patient switch, permission change, or consent revocation event.
- Avoid storing raw document previews in browser cache.

Accessibility:

- Keyboard reachable alert workflow.
- Visible focus state.
- Non-color severity text labels.
- Tables support screen-reader labels for metric, value, unit, source, and timestamp.

## 6. API Dependencies

Existing or baseline API domains:

- `POST /auth/session`
- `GET /me`
- `GET /patients`
- `GET /patients/{patient_id}`
- `GET /patients/{patient_id}/vitals/latest`
- `GET /patients/{patient_id}/observations`
- `GET /patients/{patient_id}/devices`
- `GET /patients/{patient_id}/medicine-schedule`
- `GET /patients/{patient_id}/dose-events`
- `GET /patients/{patient_id}/documents`
- `GET /patients/{patient_id}/documents/{document_id}`
- `POST /patients/{patient_id}/documents/{document_id}/review`
- `POST /patients/{patient_id}/questions`
- `GET /patients/{patient_id}/alerts`
- `POST /risk-events/{risk_event_id}/acknowledge`
- `POST /risk-events/{risk_event_id}/escalate`
- `GET /escalation-runs/{run_id}`
- `GET /patients/{patient_id}/care-team`
- `POST /patients/{patient_id}/care-team`
- `GET /patients/{patient_id}/consents`

Recommended additions:

- `GET /caretaker/roster`: permission-filtered roster summary with no detailed PHI beyond grant scope.
- `GET /caretaker/alerts`: cross-patient alert inbox for authorized patients.
- `POST /alerts/{alert_id}/assign`: assign alert owner.
- `POST /alerts/{alert_id}/resolve`: close alert with outcome classification.
- `POST /alerts/{alert_id}/snooze`: policy-limited snooze.
- `GET /patients/{patient_id}/timeline`: normalized event feed.
- `GET /patients/{patient_id}/adherence-summary?from=&to=`
- `GET /patients/{patient_id}/document-review-tasks`
- `POST /patients/{patient_id}/summaries`: request source-grounded summary.
- `GET /patients/{patient_id}/summaries`
- `PATCH /patients/{patient_id}/care-team/{member_id}/permissions`
- `POST /patients/{patient_id}/access-grants/{grant_id}/revoke`

Every PHI response must include a request ID, and backend must create an audit log before returning sensitive data.

## 7. RBAC Behavior

Access resolution:

1. Authenticate actor.
2. Load active patient grants for the actor.
3. Match route `patient_id` or roster scope against grants.
4. Intersect role permissions with grant permissions.
5. Check consent state when the view/action depends on patient consent.
6. Audit success or denial.

Leak-prevention rules:

- Unauthorized patient IDs return 404 for resource lookup routes when existence should not be disclosed, or 403 for direct permission-denied flows where patient relationship is known.
- Roster responses include only authorized patients.
- Cross-patient bulk endpoints must not include patient records outside grants even if filter IDs include them.
- URL tampering from patient A to patient B must not return patient B existence, name, or risk status.
- Resource IDs must be checked against path patient ID. Body patient IDs are ignored or rejected.
- Revoked grants invalidate sessions, cache, subscriptions, and WebSocket topics.

Audit events:

- `dashboard.roster_viewed`
- `dashboard.patient_overview_viewed`
- `dashboard.timeline_viewed`
- `dashboard.vitals_viewed`
- `dashboard.devices_viewed`
- `dashboard.medicines_viewed`
- `dashboard.documents_viewed`
- `dashboard.document_preview_viewed`
- `dashboard.alert_acknowledged`
- `dashboard.alert_assigned`
- `dashboard.alert_resolved`
- `dashboard.escalation_requested`
- `dashboard.summary_requested`
- `care_team.permission_changed`
- `care_team.access_revoked`

## 8. Alert Workflow

Alert states:

- `open`: created and visible.
- `acknowledged`: seen by a human; risk may still be active.
- `assigned`: operational owner selected.
- `in_progress`: follow-up underway.
- `escalating`: policy-approved escalation run active.
- `resolved`: closed with outcome.
- `false_positive`: closed and marked false positive.
- `cancelled`: cancelled by patient/policy/operator where allowed.
- `expired`: informational alert no longer actionable.

Workflow:

1. Risk engine creates risk event and alert.
2. Alert inbox receives real-time update.
3. Caretaker opens detail, causing audit event.
4. Caretaker acknowledges with optional note.
5. Caretaker assigns to self or team member if follow-up is needed.
6. If high/critical or patient not responding, caretaker requests escalation.
7. Policy engine approves or denies escalation based on risk, consent, contacts, channel rules, and idempotency.
8. Escalation timeline tracks messages, calls, receipts, and acknowledgements.
9. Caretaker resolves with outcome classification and notes.
10. Incident review is created for high/critical events.

Rules:

- `acknowledge` cannot hide unresolved critical events.
- `resolve` requires a note for high/critical alerts.
- `escalate` must show whether action is simulation or live.
- Duplicate clicks must return the same escalation run.
- Location can be shown/shared only if consented and available.

## 9. Required States

Empty states:

- No patients: show invite/access request path.
- No alerts: show quiet operational state and last refresh time.
- No devices: show device connection guidance without claiming all devices.
- No medicines: show no active schedules and upload/add options if permission allows.
- No documents: show upload/review entry points if permission allows.

Loading states:

- Skeleton roster rows with no fake PHI.
- Alert inbox loading by severity tabs.
- Patient workspace loading with patient name only after auth resolution.
- Long document preview loading with explicit audit reason.

Error states:

- Permission denied: no patient details, request access or switch account.
- Consent revoked: explain data no longer visible.
- Stale data: show last known reading but mark stale and do not imply current normal.
- Provider/channel failure: show failed action and fallback options.
- Backend outage: show cached data with freshness, block risky writes, allow manual emergency contact info if available.

High-risk states:

- Critical banner pinned on roster and patient workspace.
- Alert actions remain visible while scrolling.
- Evidence list shows reading value, unit, observed time, source, confidence, and freshness.
- Escalation timeline updates live.
- False alarm/cancel options visible only where policy permits.

## 10. Access Isolation Test Plan

Core isolation fixtures:

- Patient `pat_ravi` with caretaker `usr_meera`.
- Patient `pat_asha` with caretaker `usr_neel`.
- Caretaker `usr_neel` also has limited read access to `pat_ravi`.
- Nurse `usr_nurse` has shift-limited access to both.
- Doctor `usr_doctor` has document and summary access only.
- Revoked caretaker `usr_revoked` has historical audit entries but no active access.

Tests:

| Scenario | Expected result |
| --- | --- |
| Caretaker with one grant opens roster | Only that patient appears. |
| Caretaker tampers URL to another patient | 403/404, no PHI, denied audit event. |
| Caretaker filters roster by unauthorized patient ID | Unauthorized patient omitted with no existence leak. |
| Multi-patient caretaker opens alert inbox | Only authorized patient alerts appear with minimum required fields. |
| Revoked grant while dashboard is open | WebSocket/cache cleared, patient workspace closes, further API calls denied. |
| Doctor with document-only grant opens vitals tab | Permission denied, no vitals PHI. |
| Nurse shift expires | Access denied after expiry and active subscriptions close. |
| Resource ID belongs to patient B but route uses patient A | Request denied; no resource details returned. |
| Browser back after logout | Cached PHI not visible. |
| Two tabs on different patients | Cache keys remain separated and actions use the selected patient ID. |

## 11. Build Order

1. Auth shell, role-aware route guards, and `GET /me` patient grant resolution.
2. Roster endpoint and `RiskRosterScreen` with minimum necessary PHI.
3. Alert inbox and alert detail workflow: acknowledge, assign, resolve.
4. Patient overview with latest vitals, source, freshness, and active alert banner.
5. Patient timeline endpoint and event feed.
6. Devices and medicine adherence tabs.
7. Documents and extracted facts tab with review permissions.
8. Care team management and access grant editor.
9. Summary request and scheduled updates.
10. WebSocket or server-sent events for roster/alert/timeline updates.
11. Full RBAC isolation tests, audit assertions, and revoked-access cache invalidation.
12. Emergency simulation mode in dashboard.

## 12. Open Questions

- Is the first dashboard a web app only, or should caretaker mobile use the same API surface?
- Which roles can approve extracted medicine schedules in MVP?
- Can family caretakers edit care team permissions, or only patients/admins?
- What patient fields are allowed in cross-patient roster rows for each role?
- Should doctors receive a separate portal or a constrained caretaker dashboard role?
- What SLA should drive alert inbox refresh and escalation notification timing?

## 13. Sources Read

- `prompts/00-master-context.md`
- `prompts/07-caretaker-dashboard-prompt.md`
- `docs/01-prd.md`
- `docs/02-trd.md`
- `docs/06-data-model-and-api.md`
