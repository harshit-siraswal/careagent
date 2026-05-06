# Master Context Prompt

Use this prompt at the start of every separate implementation context.

You are working on CareAgent, an agentic health manager. CareAgent monitors live health data, understands medical documents and medicine schedules, answers patient/caretaker questions, reminds patients to take medicine, and escalates risk to caretakers, doctors, ambulance contacts, or emergency services using the mobile app, WhatsApp, Telegram, push notifications, and voice calls where permitted.

Core concept:

- Use a Claw-compatible agent runtime for channel gateway and tool orchestration. Candidates include OpenClaw, PicoClaw, NVIDIA NemoClaw, or a better runtime if evaluation shows a stronger fit.
- The mobile app is the primary patient surface.
- WhatsApp and Telegram must support chat, uploads, summaries, reminders, and alerts where possible.
- Caretakers must have their own login and manage multiple patients.
- The product must support fitness bands, smart watches, and nearly all medical-device categories through compatibility tiers: HealthKit, Health Connect, BLE medical profiles, vendor APIs, FHIR/ABDM-style records, manual entry, and OCR/photo fallback.
- The agent may act on behalf of the user only within explicit consent and policy boundaries.
- The product must not diagnose, prescribe, impersonate a human, or bypass platform rules.
- The backend must expose an agent-runtime abstraction so the core health, risk, audit, and escalation systems do not depend on one specific agent framework.

Read these docs first:

- `docs/00-source-brief.md`
- `docs/01-prd.md`
- `docs/02-trd.md`
- Your specific workstream prompt in `prompts/`

Non-negotiable safety constraints:

- Safety-critical decisions are policy-engine decisions, not LLM-only decisions.
- Every health data access and external action must be audited.
- Health answers must be grounded in patient data with source references where possible.
- Emergency calls/messages require explicit consent, configured policy, and event evidence.
- iOS cannot silently place normal phone calls or SMS. Android SMS/call-log permissions are restricted. Use cloud telephony/channel APIs for production automation.

Expected output from your workstream:

- Concrete implementation plan.
- APIs/components/files to create or modify.
- Data contracts.
- Edge cases.
- Tests.
- Open questions or assumptions.
