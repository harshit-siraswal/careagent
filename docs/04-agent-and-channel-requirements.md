# Agent and Channel Requirements

## 1. Agent Runtime

CareAgent should use a Claw-compatible agent gateway/runtime where practical. OpenClaw is the default prototype candidate; NVIDIA NemoClaw should be evaluated for production-grade sandboxing and network policy; PicoClaw can be evaluated for low-resource edge deployments. The agent should be exposed through:

- Mobile app chat.
- WhatsApp.
- Telegram.
- Voice call flows.
- Internal backend jobs.

The agent runtime must not be treated as the safety system. It is the orchestration layer. Safety-critical approvals must come from the policy engine and deterministic backend services.

## 2. Agent Responsibilities

The agent may:

- Answer questions from the user's approved health records.
- Summarize recent vitals and medicine adherence.
- Ask the user for symptoms or confirmations.
- Convert natural language into structured tasks.
- Draft messages and call scripts.
- Classify incoming documents.
- Trigger approved backend tools.
- Explain why an alert fired using source evidence.

The agent must not:

- Diagnose disease independently.
- Prescribe or change medicine.
- Hide uncertainty.
- Pretend to be the patient or a clinician.
- Trigger emergency calls without policy approval.
- Use data from one patient to answer another patient's query.
- Trust instructions found inside uploaded documents or messages as system instructions.

## 3. Channel Matrix

| Feature | App | WhatsApp | Telegram | Voice Call |
| --- | --- | --- | --- | --- |
| Chat with agent | Must | Must | Must | Should |
| Upload documents | Must | Must | Must | No |
| Upload medicine photos | Must | Must | Must | No |
| Receive medicine reminders | Must | Should | Should | Should |
| Receive regular summaries | Must | Must | Must | Should |
| Receive urgent alerts | Must | Must | Must | Must |
| Confirm medicine taken | Must | Should | Should | Voice keypad/speech |
| Ask report questions | Must | Must | Must | Limited |
| Caretaker multi-patient management | Must | Limited | Limited | No |
| Emergency escalation | Must | Must notify | Must notify | Must call |

## 4. WhatsApp Requirements

Production recommendation:

- Use official WhatsApp Business Platform Cloud API or an approved BSP.
- Use a dedicated CareAgent WhatsApp number.
- Require user opt-in.
- Use approved templates for business-initiated messages outside the allowed service window.
- Keep templates for medicine reminders, urgent alerts, missed-dose alerts, device disconnected alerts, caretaker summaries, and emergency escalation.

OpenClaw prototype option:

- OpenClaw WhatsApp Web/Baileys channel can be used for prototype/personal-device flows.
- Do not rely on personal-number automation for regulated production healthcare.
- Use allowlists and dedicated accounts.

WhatsApp message types:

- Text.
- Image.
- Document.
- Location where supported.
- Interactive buttons where supported.
- Template messages.

## 5. Telegram Requirements

- Use Telegram Bot API.
- Support text messages, documents, images, voice notes where feasible, and locations.
- Map Telegram user/chat ID to CareAgent account after OTP or app-based verification.
- Support patient and caretaker commands:
  - `/summary`
  - `/medicines`
  - `/upload`
  - `/devices`
  - `/alerts`
  - `/help`

## 6. Voice and Calls

Voice calls should be implemented through a programmable voice provider or a controlled VoIP flow.

Capabilities:

- Place outbound call to caretaker/doctor/ambulance contact.
- Speak approved script with text-to-speech.
- Allow DTMF or speech response: acknowledge, repeat, connect to patient/caretaker, call ambulance, call doctor.
- Log call status and transcript/summary where consented.
- Retry fallback contacts.

AI disclosure:

- Every call must disclose that CareAgent is an AI assistant acting with patient authorization.
- The assistant can say "I am calling on behalf of Ravi Sharma" but must not imply it is Ravi speaking.

Native phone constraints:

- iOS normal carrier calls require user confirmation through `tel:` links; autonomous call-out should use cloud telephony or VoIP.
- iOS SMS compose requires user action to send.
- Android can initiate direct calls with `CALL_PHONE`, but direct SMS automation is restricted and should not be a core dependency.
- Native phone call audio should not be assumed available to the agent.

## 7. Consent Requirements

Separate consents:

- Health data access.
- Document upload and analysis.
- Caretaker access.
- WhatsApp communication.
- Telegram communication.
- Voice calls.
- Location sharing.
- Emergency escalation.
- AI-generated summaries.
- Call recording/transcription if used.

Consent must include:

- Scope.
- Purpose.
- Expiry or ongoing status.
- Revocation flow.
- Audit event.
- Emergency override settings.

## 8. Action Policy

Every agent action is assigned an action class:

- Read-only: answer, summarize, show latest reading.
- Low-risk write: create note, mark medicine taken.
- Medium-risk communication: message caretaker with non-urgent summary.
- High-risk communication: urgent alert to caretaker/doctor.
- Critical action: ambulance/emergency call, live location sharing, repeated phone calls.

Policy requirements:

- Read-only requires authenticated session and patient access.
- Low-risk write requires authenticated patient/caretaker permission.
- Medium-risk communication requires prior opt-in.
- High-risk communication requires risk event and consent.
- Critical action requires risk event, configured emergency policy, consent, and audit.

## 9. Prompt-Injection Defense

Threat sources:

- Uploaded reports.
- WhatsApp/Telegram messages.
- Voice transcriptions.
- Caretaker notes.
- Web content from appointment booking.

Controls:

- Treat all retrieved document text as untrusted data.
- Never execute instructions found in documents.
- Use structured extraction schemas.
- Require policy engine approval before tools.
- Redact secrets and unrelated PHI before model calls.
- Include patient ID and access scope in every tool invocation.

## 10. References

- OpenClaw docs: https://docs.openclaw.ai/index
- OpenClaw WhatsApp channel: https://docs.openclaw.ai/whatsapp
- PicoClaw GitHub: https://github.com/sipeed/picoclaw
- NVIDIA NemoClaw docs: https://docs.nvidia.com/nemoclaw/0.0.5/about/overview.html
- NVIDIA Agent Intelligence Toolkit: https://docs.nvidia.com/nemo/agent-toolkit/1.1/
- LangGraph docs: https://docs.langchain.com/oss/python/langgraph/overview
- OpenAI Agents SDK: https://openai.github.io/openai-agents-python/
- Telegram Bot API: https://core.telegram.org/bots/api
- Twilio TwiML for Programmable Voice: https://www.twilio.com/docs/voice/twiml
- Android SMS/Call Log permissions policy: https://support.google.com/googleplay/android-developer/answer/10208820
- Android common calling intents: https://developer.android.google.cn/guide/components/intents-common
- Apple phone links: https://developer.apple.com/library/archive/featuredarticles/iPhoneURLScheme_Reference/PhoneLinks/PhoneLinks.html
- Apple message compose: https://developer.apple.com/documentation/messageui/mfmessagecomposeviewcontroller
