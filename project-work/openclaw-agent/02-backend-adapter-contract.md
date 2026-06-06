# OpenClaw Backend Adapter Contract

Last updated: 2026-06-06

## Existing Backend Contract

The current backend has a small synchronous adapter interface:

```python
class AgentRuntimeAdapter(Protocol):
    @property
    def config(self) -> AgentRuntimeConfig:
        ...

    def generate(self, request: AgentRuntimeRequest) -> AgentRuntimeResponse:
        ...
```

The first OpenClaw implementation should fit this contract before introducing async sessions or long-running orchestration. Keep the first slice narrow and testable.

## Required Request Fields

`AgentRuntimeRequest` already carries:

- `request_id`
- `messages`
- `patient_id`
- `conversation_id`
- `tools`
- `metadata`

OpenClaw adapter requirements:

- Reject empty `request_id`.
- Reject empty `messages`.
- Preserve `request_id` in the response.
- Pass only approved tool definitions.
- Redact sensitive metadata before logs, exceptions, traces, and response metadata.
- Include `patient_id` only as an opaque ID when needed for backend tool calls. Do not include broad patient profile context by default.
- Include `conversation_id` only as a routing selector, not an authorization token.

## Tool Boundary

The adapter can expose only these tool names, already defined in `app/services/agent_tools.py`:

- `get_patient_profile`
- `get_recent_vitals`
- `get_device_status`
- `get_medicine_schedule`
- `log_medicine_taken`
- `search_medical_documents`
- `create_alert`
- `request_patient_confirmation`
- `send_channel_message`
- `place_voice_call`
- `start_escalation_protocol`
- `book_appointment_request`

Every tool request must be converted into `AgentToolRequest` and evaluated through backend policy. Direct OpenClaw tool execution is not allowed for PHI or side-effect actions.

## Minimal Adapter Shape

Target file:

- `C:\Users\ASUS\Desktop\careagent-backend\app\agent\runtime.py`

Implementation outline:

```python
class OpenClawAgentRuntimeAdapter:
    def __init__(self, config: AgentRuntimeConfig, transport: OpenClawTransport | None = None) -> None:
        self._config = config
        self._transport = transport or HttpOpenClawTransport(config)

    @property
    def config(self) -> AgentRuntimeConfig:
        return self._config

    def generate(self, request: AgentRuntimeRequest) -> AgentRuntimeResponse:
        _validate_request(request)
        payload = build_openclaw_payload(request, self.config)
        raw_response = self._transport.generate(payload, timeout_seconds=self.config.timeout_seconds)
        return parse_openclaw_response(request, raw_response, self.config)
```

Keep transport injectable so tests never require a live OpenClaw gateway.

## Factory Change

Target file:

- `C:\Users\ASUS\Desktop\careagent-backend\app\services\agent_runtime.py`

Factory rule:

- `AGENT_RUNTIME_ADAPTER=mock`: return `MockAgentRuntimeAdapter`.
- `AGENT_RUNTIME_ADAPTER=openclaw`: return `OpenClawAgentRuntimeAdapter`.
- Any other adapter name: fail closed with `AgentRuntimeConfigurationError`.

Do not make `openclaw` the default until tests and staging checks pass.

## Response Mapping

The adapter must return:

- `request_id`: original request ID.
- `provider`: `openclaw`.
- `model`: configured model label.
- `output_text`: assistant text, sanitized for user display.
- `tool_calls`: normalized requested tool calls only, with secrets redacted.
- `metadata`: redacted gateway trace ID, latency, endpoint host, adapter name, and policy notes.

Do not return:

- Raw OpenClaw auth headers.
- Channel credentials.
- Provider API keys.
- Full prompt text containing PHI.
- Raw uploaded document text.
- Unredacted tool inputs.

## Failure Behavior

Fail closed for:

- Gateway unavailable.
- Timeout.
- Non-2xx response.
- Malformed response.
- Tool call with unknown name.
- Tool call missing `patient_id`, `request_id`, `authorization_scope`, `reason`, or `input`.
- Attempted critical action without backend policy approval.

Safe user-facing fallback:

> CareAgent cannot complete that agent action right now. No emergency message or call was sent.

The exact UI copy can change, but it must not imply that a side effect happened.

## Required Tests

Add or extend:

- `tests/test_agent_runtime_adapter.py`
- `tests/test_agent_tools_contract.py`
- New `tests/test_openclaw_adapter.py`

Test cases:

- Builds OpenClaw config from environment without leaking secret values.
- Factory returns OpenClaw adapter only when explicitly selected.
- Adapter maps valid request to transport payload.
- Adapter preserves request ID.
- Adapter redacts secret-like metadata.
- Adapter rejects unknown tool call.
- Adapter fails closed on timeout/network failure.
- Adapter never executes `send_channel_message`, `place_voice_call`, or `start_escalation_protocol` without backend policy.

