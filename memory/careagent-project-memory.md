# CareAgent Project Memory

Last updated: 2026-05-06

## Product Identity

CareAgent is an agentic health manager for patients, elderly users, chronic-care users, and caretakers. The in-app assistant is named Caro. The product tagline is "Your health. Managed. Automatically."

CareAgent is not positioned as a doctor. It is a health coordination, monitoring, reminder, document-intelligence, and escalation assistant.

## Core Product Jobs

- Monitor health data from wearables, fitness bands, smart watches, and medical devices.
- Support near-universal device coverage through compatibility tiers: HealthKit, Health Connect, BLE medical profiles, vendor APIs, FHIR/ABDM-style records, manual entry, CSV, OCR, and photo fallback.
- Detect abnormal or dangerous health numbers through deterministic risk rules.
- Notify caretakers, nurses, family members, doctors, and ambulance contacts based on risk.
- Work through the app, WhatsApp, Telegram, and voice calls where allowed.
- Upload, extract, analyze, and answer questions about prescriptions, lab reports, hospital slips, discharge summaries, and medicine photos.
- Remind the patient to take medicine with an audible in-app sound or spoken reminder.
- Let caretakers log in and manage multiple patients.
- Store doctor, ambulance, nurse, and family contacts.
- Allow the agent to speak on behalf of the patient only with disclosure, consent, and policy approval.

## Agent Runtime Direction

The project should be Claw-compatible, not locked to one agent runtime.

Prompt 03 output is captured in `docs/16-agent-runtime-workstream.md`. It defines the CareAgent system prompt, tool schemas, tool-call policy table, conversation routing, example transcripts, prompt-injection defenses, simulated-patient tests, and the runtime adapter contract.

Candidates:

- OpenClaw for prototype channel gateway and agent flow.
- NVIDIA NemoClaw for production hardening if sandboxing, network policy, and lifecycle controls are needed.
- PicoClaw for low-resource/edge experiments, not critical production until maturity is proven.
- LangGraph for durable deterministic workflow orchestration.
- OpenAI Agents SDK for OpenAI-centric tool, voice, tracing, and guardrail workflows.

Architecture rule:

- The agent runtime can orchestrate and explain.
- The backend policy engine must approve safety-critical actions.
- The risk engine must make deterministic anomaly decisions.
- The escalation engine must execute messages, calls, retries, and audit logging.

## Safety Rules

- Do not diagnose, prescribe, or change medicine.
- Do not impersonate the patient as a human.
- Disclose AI identity in messages and calls.
- Do not promise every device model is directly supported.
- Do not silently access calls, SMS, WhatsApp, location, health data, contacts, or microphone.
- iOS cannot silently place normal phone calls or send SMS.
- Android SMS/call-log permissions are restricted.
- Production WhatsApp automation should use official WhatsApp Business Cloud API or an approved BSP.
- Critical escalation requires explicit consent, configured policy, evidence, idempotency, and audit trail.

## MVP Surfaces

Patient app:

- Home health status.
- Live vitals and freshness.
- Device connection center.
- Medicine schedule and audible reminders.
- Document upload and extracted data review.
- Agent chat.
- Emergency contacts and SOS.

Caretaker dashboard:

- Multi-patient roster.
- Risk-ranked patient list.
- Alert inbox.
- Patient timeline.
- Device freshness.
- Medicine adherence.
- Document review.

Channels:

- In-app chat.
- WhatsApp chat, uploads, reminders, summaries, alerts.
- Telegram chat, uploads, reminders, summaries, alerts.
- Programmable voice calls for caretaker/doctor/ambulance contacts.

## Design Direction Memory

Design stance: Apple-style AI health guardian.

The product must feel like a premium iOS health app. Use Apple design language: SF-style typography, large title hierarchy, translucent cards, subtle glass surfaces, soft gradients, restrained shadows, native tab bars, rounded metric cards, and crisp icon buttons. The visual reference is an iOS dashboard with a Health Guardian AI card, health overview tiles, connected devices, recent insights, and bottom tab navigation.

Mascot:

- Caro should be an Apple-like soft AI orb/guardian, not a cartoon animal.
- The mascot should feel like a glowing assistant avatar: circular or softly rounded, dark center, luminous blue/mint eyes, radial halo.
- Animation should be subtle: breathing glow, eye pulse, small halo shimmer, urgent color transition.
- It should feel premium and calm, not childish.

Visual language:

- iOS white/blue-gray background.
- Frosted cards with subtle borders.
- Black/near-black text.
- iOS blue as primary action.
- Health semantic accents: red heart, blue BP, purple SpO2, green temperature, teal ECG, orange respiratory.
- Green online/normal indicators.
- Red only for true alerts.
- Avoid childish mascot shapes, heavy outlines, oversized cartoon UI, beige/cream theme, and dense card clutter.

Interface principles:

- Operational first screen, not a landing page.
- Source and freshness must be visible for health readings.
- Stale data must never look normal.
- Risk status must show reason, timestamp, and source.
- Critical alerts must look clearly different from routine updates.
- Elderly users need large tap targets, simple labels, and low cognitive load.

## Current Design Flow

The active design file is `design/apple-careagent-flow.html`.

Current version: Apple flow v5.

It contains 24 PRD/TRD-driven screens:

- Patient setup: welcome, health profile, consent setup, device catalog.
- Daily care: dashboard, vitals, connected devices, add device, medicines.
- Records and agent: reports, extraction review, Ask Caro, channels, WhatsApp/Telegram flow.
- Safety: care contacts, guardian policy, alerts, quick check-in, emergency protocol, voice call.
- Caretaker: roster, alert inbox, patient incident detail, regular update rules.

Mascot direction:

- Use the supplied healthcare robot reference as inspiration.
- Current reusable asset: `design/assets/caro-mascot.svg`.
- Caro should appear large during setup and small in assistant/reminder/channel contexts.
- Avoid overusing the mascot in dense clinical or caretaker triage screens.

## Source Docs

Use these as project source of truth:

- `README.md`
- `docs/00-source-brief.md`
- `docs/01-prd.md`
- `docs/02-trd.md`
- `docs/03-device-integration-strategy.md`
- `docs/04-agent-and-channel-requirements.md`
- `docs/05-safety-compliance-and-risk.md`
- `docs/11-ui-product-spec.md`
- `docs/14-agent-runtime-selection.md`
- `docs/15-mobile-app-workstream.md`
- `docs/16-agent-runtime-workstream.md`
