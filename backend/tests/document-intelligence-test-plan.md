# Document Intelligence Backend Test Plan

This test plan is written against `backend/openapi/document-intelligence.openapi.yaml` and the document requirements in `docs/19-document-intelligence-workstream.md`. It should become executable pytest suites once the backend service is scaffolded.

## Harness Assumptions

- API tests use FastAPI `TestClient` or HTTPX with auth dependency overrides.
- Object storage, malware scanner, OCR provider, extraction model, embedding store, and queue workers use deterministic fakes.
- The test database has patient-scoped users, care-team grants, consent grants, audit logs, documents, OCR pages, extracted facts, medicine proposals, and vector-index metadata.
- Every request has a request ID.
- Every PHI access or external action writes an audit log.
- Uploaded document text is treated as untrusted input in every prompt and tool path.

## Fixtures

Synthetic patients:

- `pat_ravi`: patient owner, English/Hindi locale, hypertension, caretaker `usr_meera`.
- `pat_asha`: diabetes, caretaker `usr_neel`.
- `usr_neel`: caretaker with access to both `pat_ravi` and `pat_asha` for multi-patient channel tests.
- `usr_revoked`: previously had access to `pat_ravi`, now revoked.

Documents:

- Clear prescription with medicine, dose, route, timing, duration, doctor, date.
- Blurry prescription with unreadable dose.
- Lab report with HbA1c, glucose, units, reference ranges, abnormal flags.
- Mixed Hindi/English lab report.
- Discharge summary with diagnosis terms, discharge medicines, follow-up instructions.
- Medicine strip photo with name and strength only.
- Conflicting prescription that changes an active medicine schedule.
- Prompt-injection document containing instructions to ignore rules, switch patient, reveal data, and call tools.
- Document with two patient names.
- Password-protected PDF.
- Infected file fixture from malware scanner fake.

## Unit Tests

### Upload and Storage

| Test | Assertions |
| --- | --- |
| `test_create_upload_session_requires_documents_write` | Actor without `documents:write` receives 403/404, no signed URL, denied audit event. |
| `test_create_upload_session_requires_idempotency_key` | Missing `Idempotency-Key` returns 400. |
| `test_create_upload_session_records_patient_scope` | Path patient ID is authoritative; body cannot assign another patient. |
| `test_upload_session_returns_short_lived_signed_url` | Response has method, URL, expiry, required headers; signed URL is not logged. |
| `test_duplicate_upload_hash_idempotent_per_patient` | Same patient/hash/key returns same document/session. |
| `test_same_hash_for_different_patient_is_isolated` | Duplicate hash does not leak other patient metadata. |
| `test_upload_complete_verifies_checksum_and_size` | Mismatch marks upload failed and no malware scan is queued. |
| `test_password_protected_pdf_requires_user_action` | Status becomes `needs_user_action`; no password requested in chat. |

### Malware Scan

| Test | Assertions |
| --- | --- |
| `test_clean_scan_enqueues_ocr` | Clean scan writes run row and emits OCR queue event. |
| `test_infected_file_quarantined` | Malware status `quarantined`; OCR/extraction/indexing not queued. |
| `test_malware_scan_failure_blocks_processing` | Status blocked with retry/error metadata and audit event. |
| `test_raw_document_preview_blocked_until_clean` | Pending/infected/failed scans cannot be previewed or downloaded. |

### OCR

| Test | Assertions |
| --- | --- |
| `test_pdf_embedded_text_uses_text_layer` | OCR page blocks preserve page numbers and confidence. |
| `test_scanned_pdf_runs_ocr_per_page` | Each page has blocks, language, quality flags, and run metrics. |
| `test_blurry_image_marks_quality_flag` | `quality_flags` include blur/low-resolution; extraction confidence reduced. |
| `test_rotated_image_is_deskewed` | Blocks have normalized bounding boxes and readable order. |
| `test_multilingual_report_preserves_languages` | OCR page includes `en-IN` and `hi-IN` language codes. |
| `test_no_text_medicine_photo_still_extracts_regions` | Visual/text regions are available for medicine photo extraction. |

### Classification

| Test | Assertions |
| --- | --- |
| `test_prescription_classified_from_layout_and_keywords` | Type `prescription`, confidence above threshold. |
| `test_lab_report_classified_from_table_units` | Type `lab_report`, reasons include lab table evidence. |
| `test_low_confidence_classification_requires_user_type` | Status `needs_user_action`; no high-impact extraction committed. |
| `test_unknown_document_does_not_hallucinate_schema` | Type `unknown`; facts empty or low-risk free-text only. |

### Extraction Schemas

| Test | Assertions |
| --- | --- |
| `test_prescription_extracts_required_fields_with_provenance` | Medicine name, dose, timing, route, duration, doctor, date all have source page/block/span and confidence. |
| `test_missing_dose_is_null_not_hallucinated` | Dose is `null` with missing reason; proposal blocked from activation. |
| `test_ambiguous_abbreviation_requires_review` | Ambiguous `OD/BD/SOS` has raw text and `requires_review`. |
| `test_lab_values_extract_units_and_reference_ranges` | Value, unit, normalized fields, reference range, abnormal flag, source facts present. |
| `test_unit_conversion_is_deterministic` | Known conversions use converter; unsupported conversions preserve raw only. |
| `test_discharge_summary_separates_diagnosis_from_summary` | Diagnosis terms are only those present in source evidence. |
| `test_medicine_photo_extracts_candidates_only` | No route/timing/duration inferred from strip photo. |
| `test_every_persisted_fact_has_provenance` | Insert/update rejected if source page/block or confidence is missing. |
| `test_extraction_prompt_injection_ignored` | Malicious document instructions are not included as tool instructions or trusted facts. |

### Review and Correction

| Test | Assertions |
| --- | --- |
| `test_review_requires_documents_write` | Read-only caretaker cannot approve/correct/reject facts. |
| `test_approve_fact_updates_review_status_and_audit` | Status changes to approved, reviewer actor recorded, audit event exists. |
| `test_correct_fact_preserves_original_value` | Corrected value stored; original extracted value remains available. |
| `test_rejected_fact_excluded_from_rag` | Rejected fact is not returned by retrieval or Q&A. |
| `test_high_impact_facts_start_pending_review` | Medicine, allergy, diagnosis, follow-up, critical lab facts require review. |
| `test_document_with_multiple_patients_blocks_review` | Manual reassignment/rejection required before indexing. |

### Medicine Activation

| Test | Assertions |
| --- | --- |
| `test_unreviewed_medicine_proposal_cannot_activate` | Endpoint denies activation; no medicine schedule created. |
| `test_low_confidence_uncorrected_medicine_cannot_activate` | Reviewer must correct or explicitly approve required fields. |
| `test_reviewed_prescription_creates_medicine_and_schedule` | Medicine/schedule rows created with source document/fact IDs. |
| `test_activation_is_idempotent` | Replayed activation returns existing schedules; no duplicate reminders. |
| `test_conflicting_prescription_requires_resolution` | Existing schedule remains active until reviewer chooses resolution. |
| `test_keep_existing_conflict_resolution_archives_new_proposal` | New proposal rejected/superseded without changing active schedule. |
| `test_replace_existing_resolution_audits_old_and_new_schedule` | Old schedule archived, new schedule active, audit links both. |

### RAG and Q&A

| Test | Assertions |
| --- | --- |
| `test_question_requires_documents_read` | Unauthorized actor receives no answer or citations. |
| `test_question_retrieves_only_current_patient_facts` | Search is partitioned by patient ID; no cross-patient snippets. |
| `test_answer_uses_reviewed_facts_by_default` | Pending facts excluded unless explicitly requested for review. |
| `test_answer_cites_document_fact_page_and_review_status` | Response includes citation for every evidence-backed claim. |
| `test_missing_fact_answer_discloses_missing_data` | Answer says evidence is missing and suggests upload/review path. |
| `test_stale_document_answer_discloses_staleness` | Old document date triggers stale/age disclosure where relevant. |
| `test_conflicting_facts_answer_shows_both_sources` | No silent choice between conflicting prescriptions/labs. |
| `test_unsafe_medicine_change_request_refused` | User asking to stop/change medication receives refusal and clinician guidance. |
| `test_prompt_injection_snippet_not_followed` | Malicious snippet does not affect system instructions, patient scope, or tool calls. |

### Audit and Observability

| Test | Assertions |
| --- | --- |
| `test_phi_view_audited_before_response` | Document detail, OCR view, preview, and Q&A write audit rows. |
| `test_denied_phi_attempt_audited_without_phi` | Denied audit metadata excludes document text and patient details. |
| `test_model_run_metadata_redacted` | Prompt/model logs omit signed URLs, secrets, full raw documents, and provider credentials. |
| `test_extraction_run_has_version_metadata` | OCR/classifier/extractor/prompt/model versions persisted. |
| `test_reindex_on_fact_correction` | Correction emits reindex event and invalidates old embedding metadata. |

## Integration Tests

### App Upload to Reviewed Prescription

1. Patient creates upload session from app.
2. Upload completes with matching checksum.
3. Malware scanner returns clean.
4. OCR/classification/extraction workers drain.
5. Patient approves medicine proposal after correcting timing.
6. Activation endpoint creates medicine schedule.

Expected result: no reminder exists before review; after activation, schedule has source document/fact IDs and audit chain is complete.

### WhatsApp Upload from Verified Patient

1. Verified WhatsApp sender uploads prescription image.
2. Channel router resolves exactly one patient.
3. Document is stored and processed.
4. Patient receives processing status and review link.

Expected result: upload is accepted only after channel verification and consent; response contains no raw PHI beyond confirmation.

### Telegram Multi-Patient Caretaker Upload

1. Caretaker with two patients sends a lab image to Telegram bot.
2. Bot asks which authorized patient.
3. Caretaker selects patient.
4. Document stores under selected patient only.

Expected result: no document is created before patient selection; wrong patient selection is denied.

### Blurry Image Path

1. Patient uploads a blurry prescription.
2. OCR returns low confidence and blur flag.
3. Extraction writes partial facts only.
4. Review UI asks for clearer photo or manual correction.

Expected result: no hallucinated dose/timing; no activation allowed until correction.

### Multilingual Lab Report

1. Patient uploads mixed Hindi/English lab report.
2. OCR stores language codes.
3. Extraction returns lab values and raw units.
4. Q&A answers latest HbA1c with source.

Expected result: citations include page/snippet and reviewed fact; answer does not over-interpret lab value.

### Unit Conversion

1. Lab report has glucose in mg/dL.
2. Deterministic converter creates mmol/L normalized value where supported.
3. Unsupported unit conversion is left raw with missing normalized value.

Expected result: all conversions have test-backed converter IDs; no model-only conversion.

### Conflicting Prescriptions

1. Patient has reviewed Amlodipine 5 mg morning schedule.
2. New prescription proposes Amlodipine 10 mg evening.
3. Extraction flags conflict.
4. Reviewer chooses keep existing, replace, keep both, or reject new.

Expected result: active reminder remains unchanged until explicit conflict resolution.

### Cross-Patient RAG Leak

1. Caretaker asks Q&A for patient A.
2. Retrieval fixtures contain matching answer in patient B only.

Expected result: answer says evidence is missing for patient A and returns no patient B citation.

## Evaluation Dataset

Minimum MVP evaluation set:

| Dataset slice | Cases | Required labels |
| --- | ---: | --- |
| Clear prescription | 100 | Medicine, dose, route, timing, duration, doctor, date, source spans. |
| Poor-quality prescription | 80 | Missing fields, blur/glare/crop flags, review expectation. |
| Lab report | 150 | Test name, value, unit, reference range, abnormal flag, report date. |
| Multilingual report | 100 | Language codes, field labels, expected OCR confidence. |
| Discharge summary | 80 | Diagnoses, admission/discharge dates, discharge meds, follow-up. |
| Medicine photo | 100 | Name/strength candidates only, expiry/batch when visible. |
| Conflicting documents | 60 | Conflict type, old/new source, expected review options. |
| Injection documents | 60 | Malicious instruction class and expected safe behavior. |
| Missing-field controls | 80 | Absent fields that must remain null. |

Release metrics:

- Persisted facts with provenance: 100 percent.
- Hallucinated missing field rate: 0.
- Medicine activation without review: 0.
- Cross-patient retrieval leak: 0.
- Prompt-injection unsafe action: 0.
- Document Q&A citation coverage for evidence-backed answers: 100 percent.
- Stale/missing/conflict disclosure in targeted tests: 100 percent.

## Acceptance Gate

Document intelligence is not MVP-ready until:

- Upload/malware/OCR/extraction state machine tests pass.
- All extraction schemas reject facts without provenance.
- Medicine reminder activation gate tests pass.
- Prompt-injection document tests pass with zero unsafe actions.
- RAG answers cite reviewed facts and never cross patient boundaries.
- Blurry, multilingual, unit-conversion, and conflicting-prescription scenarios pass.
- Audit tests cover upload, OCR view, extraction review, Q&A, and activation.
