# Caretaker Dashboard Backend and UI Test Plan

This test plan is written against `docs/20-caretaker-dashboard-workstream.md` and the core backend API contracts. It should become API, component, and end-to-end suites when the caretaker dashboard is scaffolded.

## Harness Assumptions

- API tests use FastAPI `TestClient` or HTTPX.
- UI tests use a browser runner against mocked API fixtures or a seeded local backend.
- Realtime updates use a fake WebSocket/server-sent-events transport.
- Auth provider is mocked while RBAC and patient grant resolution run through real backend policy.
- Every PHI view, alert action, care-team change, and summary request writes an audit event.

## Core Fixtures

Users:

- `usr_patient_ravi`: owner of `pat_ravi`.
- `usr_patient_asha`: owner of `pat_asha`.
- `usr_meera`: caretaker with full access to `pat_ravi`.
- `usr_neel`: caretaker with full access to `pat_asha` and read-only alert access to `pat_ravi`.
- `usr_nurse`: nurse with shift-limited access to both patients.
- `usr_doctor`: document and summary access only for `pat_ravi`.
- `usr_revoked`: previously had access to `pat_ravi`; grant revoked.
- `usr_admin`: admin requiring MFA and break-glass reason for PHI.

Patient data:

- `pat_ravi`: active high alert, stale BP cuff, missed dose, pending prescription review.
- `pat_asha`: no active alerts, fresh glucose device, reviewed lab report.
- `pat_hidden`: no grants for any caretaker test actor.

## API Tests

### Auth and Session

| Test | Assertions |
| --- | --- |
| `test_caretaker_login_resolves_role_and_grants` | `GET /me` returns role, active patient grants, permissions, and no PHI beyond grant summary. |
| `test_mfa_required_for_nurse_doctor_admin` | Privileged roles cannot reach dashboard APIs before MFA. |
| `test_disabled_account_denied` | Disabled account gets 403 and audit event. |
| `test_revoked_grant_not_returned_in_me` | Revoked grant is omitted and subsequent patient calls denied. |

### Roster

| Test | Assertions |
| --- | --- |
| `test_roster_lists_only_authorized_patients` | `usr_meera` sees only `pat_ravi`; `pat_hidden` never appears. |
| `test_roster_minimizes_phi_by_permission` | Read-only/limited grants receive only allowed summary fields. |
| `test_roster_sort_orders_critical_high_missed_stale` | Critical/high alerts outrank missed dose and stale device rows. |
| `test_roster_filter_unauthorized_patient_id_no_leak` | Unauthorized filter ID returns empty/omitted result, not patient existence. |
| `test_roster_audits_view` | `dashboard.roster_viewed` written with actor and visible patient IDs summary. |

### Patient Workspace

| Test | Assertions |
| --- | --- |
| `test_patient_overview_requires_patient_read` | Actor without active grant gets 403/404 and no patient name. |
| `test_latest_vitals_show_source_and_freshness` | Every vital has value, unit, observed time, source, freshness. |
| `test_stale_device_not_presented_as_normal` | Stale BP source displays stale state and is excluded from "current normal" messaging. |
| `test_timeline_requires_scoped_patient` | Timeline events are only for path patient ID. |
| `test_timeline_filters_event_types` | Vitals, alerts, doses, documents, calls, messages, notes filter correctly. |
| `test_document_tab_requires_documents_read` | Doctor with document grant can view docs; caretaker without grant cannot. |
| `test_medicine_tab_requires_medicines_read` | Permission denied panel returned without medicine schedule details. |

### Alert Workflow

| Test | Assertions |
| --- | --- |
| `test_alert_inbox_lists_authorized_alerts_only` | Cross-patient inbox excludes alerts outside grants. |
| `test_acknowledge_alert_requires_alerts_write` | Read-only grant cannot acknowledge. |
| `test_acknowledge_alert_is_idempotent` | Repeated acknowledge returns same state and no duplicate timeline rows. |
| `test_assign_alert_records_owner_and_audit` | Assignment persists actor/owner/timestamp and audit event. |
| `test_resolve_high_alert_requires_note` | High/critical alert resolution without note is rejected. |
| `test_resolve_alert_requires_outcome_classification` | Outcome is true positive, false positive, unknown, or drill. |
| `test_escalate_alert_delegates_to_policy_engine` | Dashboard cannot bypass policy; denied result includes safe reason. |
| `test_escalation_duplicate_click_returns_existing_run` | Double click or retry returns same run/action set. |
| `test_location_omitted_without_consent` | Escalation detail and outbound payload omit location if no consent. |

### Care Team and Access Grants

| Test | Assertions |
| --- | --- |
| `test_invite_requires_care_team_write` | Unauthorized actor cannot invite caretakers. |
| `test_permission_update_audits_old_and_new_values` | Audit metadata records permission diff without secrets. |
| `test_revoke_access_invalidates_sessions_and_subscriptions` | Revoked user receives realtime close event and API denial. |
| `test_expired_shift_grant_denied_after_expiry` | Nurse access expires at expected time. |
| `test_care_team_contact_details_need_permission` | Phone/email/channel IDs hidden without `care_team:read`. |

### Summaries

| Test | Assertions |
| --- | --- |
| `test_summary_request_requires_permission_and_sources` | Actor must have summary permission plus underlying read permissions. |
| `test_summary_discloses_missing_stale_data` | Generated summary includes stale/missing sections from fixtures. |
| `test_outbound_summary_requires_channel_consent` | WhatsApp/Telegram/email dispatch denied without opt-in/template. |
| `test_summary_cites_documents_and_vitals` | Summary includes source refs for document and observation claims. |

### Audit

| Test | Assertions |
| --- | --- |
| `test_phi_views_audited_before_response` | Overview, vitals, medicines, documents, OCR preview, timeline all write audit rows. |
| `test_denied_access_audited_without_phi` | Denied logs have actor/patient/resource IDs as allowed but no PHI payload. |
| `test_browser_request_id_in_audit` | Audit rows link to request ID for UI support/debugging. |
| `test_admin_break_glass_requires_reason` | Admin PHI access denied without reason and MFA context. |

## UI Component Tests

### Roster Components

| Component | Tests |
| --- | --- |
| `PatientRosterRow` | Shows risk badge, top reason, freshness, next action; truncates long names without layout shift. |
| `RiskBadge` | Provides text label and non-color severity distinction. |
| `RosterFiltersPanel` | Applies severity, stale device, missed dose, and document review filters. |
| `PermissionDeniedPanel` | Shows no patient PHI and clear access request path. |

### Patient Workspace

| Component | Tests |
| --- | --- |
| `LatestVitalsStrip` | Every metric renders value, unit, source, timestamp, freshness. |
| `FreshnessBadge` | Renders live/recent/stale/disconnected/unavailable/unknown states. |
| `DeviceStatusRow` | Unknown battery renders unknown, not zero. |
| `MedicineTodayPanel` | Counts due/taken/snoozed/skipped/missed correctly. |
| `ExtractionReviewTable` | Shows fact, confidence, source page/snippet, review actions by permission. |
| `TimelineEventRow` | Does not expand PHI until selected and audited. |

### Alert Workflow Components

| Component | Tests |
| --- | --- |
| `AlertActionBar` | Acknowledge, assign, resolve, escalate enabled only by state/permission. |
| `AlertDetailDrawer` | Evidence includes value, unit, source, observed timestamp, freshness, confidence. |
| `EscalationTimeline` | Shows pending/running/failed/acknowledged actions and provider receipt states. |
| `ResolveAlertDialog` | Requires note and outcome for high/critical alerts. |

## End-to-End Tests

### Multi-Patient Isolation

1. Log in as `usr_meera`.
2. Open roster.
3. Confirm only `pat_ravi` appears.
4. Manually navigate to `pat_asha` URL.
5. Try API fetch for `pat_asha` documents and alerts.

Expected result: UI shows permission denied without PHI; APIs deny and audit.

### Revoked Access While Open

1. Log in as caretaker and open patient workspace.
2. Backend revokes grant.
3. Realtime event arrives.
4. UI clears patient cache and closes workspace.
5. Browser back does not reveal cached PHI.

Expected result: all follow-up API calls denied; no PHI remains visible.

### High Alert Handling

1. Log in as caretaker with `alerts:write`.
2. Open alert inbox with high heart-rate alert.
3. Open detail, acknowledge, assign to self.
4. Request escalation.
5. Fake policy approves simulation mode.
6. Resolve with true-positive note.

Expected result: one escalation run, complete timeline, required audit events, no duplicate calls/messages.

### Device Stale Workflow

1. Open patient overview with stale BP cuff.
2. Verify stale badge and last observed time.
3. Use device action to message patient to resync if consent allows.
4. Provider fake fails.
5. UI shows failure and fallback.

Expected result: stale reading is never presented as current; message respects channel consent.

### Medicine Missed Dose

1. Open medicine adherence view.
2. Confirm missed dose row with source and scheduled time.
3. Acknowledge missed-dose alert.
4. Request patient check-in.

Expected result: action requires consent and creates audit/action events.

### Document Review

1. Open pending prescription extraction.
2. Correct medicine timing.
3. Approve schedule proposal.
4. Activate reviewed schedule.

Expected result: schedule is created only after review; source facts and audit chain are present.

### Summary Request

1. Request daily summary for patient with stale device and pending document.
2. Preview generated summary.
3. Send to WhatsApp in simulation.

Expected result: summary cites sources, discloses stale/pending data, uses approved channel template.

## Realtime and Cache Tests

| Test | Expected result |
| --- | --- |
| `test_realtime_alert_update_scoped_to_grants` | Unauthorized client never receives patient alert event. |
| `test_patient_switch_clears_previous_patient_cache` | No stale PHI appears after switching patients. |
| `test_permission_change_invalidates_query_cache` | Reduced permission hides newly disallowed tabs/fields immediately. |
| `test_websocket_reconnect_resubscribes_authorized_topics_only` | Reconnect does not subscribe to old revoked topics. |
| `test_two_tabs_keep_patient_context_separate` | Actions include correct patient ID per tab. |

## Accessibility and Visual Regression

| Test | Expected result |
| --- | --- |
| `test_keyboard_alert_workflow` | User can acknowledge, assign, resolve without mouse. |
| `test_severity_not_color_only` | Severity is readable by text/icon/ARIA labels. |
| `test_compact_roster_no_overlap_mobile_width` | Long patient names/reasons truncate or wrap without overlap. |
| `test_high_alert_banner_persistent` | Critical action controls remain reachable when scrolling. |
| `test_loading_skeleton_no_fake_phi` | Loading state does not display placeholder patient names/readings. |

## Acceptance Gate

The caretaker dashboard is not MVP-ready until:

- Roster, alert inbox, and patient workspace enforce patient grants.
- Every sensitive view and alert action has audit assertions.
- Revoked/expired grants clear UI cache and realtime subscriptions.
- Alert workflow handles acknowledge, assign, resolve, and escalate idempotently.
- Vitals and device views always show source and freshness.
- Empty, loading, error, stale, and high-risk states have UI tests.
- Cross-patient URL/resource tampering returns no PHI.
