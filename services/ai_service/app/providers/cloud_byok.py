"""Per-request BYOK Coach providers with bounded, stateless tool loops."""

import json
from pathlib import Path
from typing import Any, Literal

import httpx
from pydantic import ValidationError

from app.core.config import Settings
from app.mcp.coach_data_server import CoachDataMcpServer, ToolFailure
from app.models.coach import COACH_AGENT_MAX_TOOL_CALLS, CoachAgentModelOutput
from app.providers.base import (
    CoachActivityCallback,
    CoachAgentProviderResult,
    CoachProviderCapability,
    CoachProviderError,
    CoachProviderResult,
)


ProviderName = Literal["openai", "gemini"]
_MODELS = {"openai": "gpt-5.6-terra", "gemini": "gemini-3.6-flash"}
_OPENAI_BASE = "https://api.openai.com/v1"
_GEMINI_BASE = "https://generativelanguage.googleapis.com/v1beta"
_GEMINI_API_REVISION = "2026-05-20"
_MAX_PROVIDER_OUTPUT_TOKENS = 4_096
_MAX_PROVIDER_RESPONSE_BYTES = 256 * 1024
_MAX_PROVIDER_OUTPUT_ITEMS = 32
_MAX_PROVIDER_CONTENT_BLOCKS = 8
_MAX_TOOL_RESULT_HISTORY_BYTES = 512 * 1024
_TOOLS = [
    {
        "name": "inspect_data",
        "description": "Inspect the private snapshot catalog and date ranges.",
        "parameters": {
            "type": "object",
            "properties": {},
            "additionalProperties": False,
        },
    },
    {
        "name": "query_data",
        "description": "Run one bounded read-only SQLite SELECT or WITH query.",
        "parameters": {
            "type": "object",
            "properties": {"sql": {"type": "string", "minLength": 1}},
            "required": ["sql"],
            "additionalProperties": False,
        },
    },
]


class CloudByokCoachProvider:
    """A secret-bearing provider instance whose lifetime is one HTTP request."""

    __slots__ = ("_provider", "_api_key", "_settings", "_client")

    def __init__(
        self,
        *,
        provider: ProviderName,
        api_key: str,
        settings: Settings,
        client: httpx.AsyncClient | None = None,
    ) -> None:
        key = api_key.strip()
        if not key:
            raise CoachProviderError(
                "provider_unavailable",
                "A provider API key is required.",
                retryable=False,
            )
        self._provider = provider
        self._api_key = key
        self._settings = settings
        self._client = client

    def __repr__(self) -> str:
        return (
            f"CloudByokCoachProvider(provider={self._provider!r}, api_key=<redacted>)"
        )

    async def capability(self) -> CoachProviderCapability:
        if self._provider not in self._settings.coach_byok_providers:
            return self._capability("unavailable", "provider_not_enabled")
        try:
            async with self._client_context() as client:
                if self._provider == "openai":
                    status_code = await _get_status(
                        client,
                        f"{_OPENAI_BASE}/models/{self.model}",
                        headers={"Authorization": f"Bearer {self._api_key}"},
                    )
                else:
                    status_code = await _get_status(
                        client,
                        f"{_GEMINI_BASE}/models/{self.model}",
                        headers={"x-goog-api-key": self._api_key},
                    )
            if status_code == 200:
                return self._capability("ready", "ready")
            return self._capability("unavailable", _reason_for_status(status_code))
        except httpx.TimeoutException:
            return self._capability("unavailable", "provider_timeout")
        except httpx.HTTPError:
            return self._capability("unavailable", "provider_failure")

    async def respond(self, *, prompt: str) -> CoachProviderResult:
        del prompt
        raise CoachProviderError(
            "provider_unavailable",
            "BYOK providers support the current Coach contract only.",
            retryable=False,
        )

    async def respond_agent(
        self,
        *,
        prompt: str,
        snapshot_path: Path,
        trace_path: Path,
        activity_callback: CoachActivityCallback | None = None,
    ) -> CoachAgentProviderResult:
        capability = await self.capability()
        if capability.state != "ready":
            raise CoachProviderError(
                capability.reason_code,
                "The selected Coach provider is unavailable.",
                retryable=capability.reason_code
                in {"provider_failure", "provider_timeout"},
            )
        executor = CoachDataMcpServer.for_snapshot(
            snapshot_path=snapshot_path,
            trace_path=trace_path,
            docker_bin=self._settings.coach_analysis_docker_bin,
            image=self._settings.coach_analysis_image,
        )
        if activity_callback is not None:
            await activity_callback("Checking available personal data …")
        if self._provider == "openai":
            output = await self._run_openai(prompt=prompt, executor=executor)
        else:
            output = await self._run_gemini(prompt=prompt, executor=executor)
        return CoachAgentProviderResult(output=output, model_reported=self.model)

    @property
    def model(self) -> str:
        return _MODELS[self._provider]

    def _capability(self, state: str, reason: str) -> CoachProviderCapability:
        return CoachProviderCapability(
            state=state,
            provider=self._provider,
            provider_mode="user_supplied_key",
            model_requested=self.model,
            model_source="explicit",
            reason_code=reason,
        )

    def _client_context(self) -> "_ClientContext":
        return _ClientContext(self._client)

    async def _run_openai(
        self,
        *,
        prompt: str,
        executor: CoachDataMcpServer,
    ) -> CoachAgentModelOutput:
        input_items: list[dict[str, Any]] = [
            {"role": "user", "content": [{"type": "input_text", "text": prompt}]},
        ]
        tools = [{"type": "function", "strict": True, **tool} for tool in _TOOLS]
        total_tool_calls = 0
        tool_result_bytes = 0
        for _ in range(COACH_AGENT_MAX_TOOL_CALLS + 1):
            body = {
                "model": self.model,
                "store": False,
                "max_output_tokens": _MAX_PROVIDER_OUTPUT_TOKENS,
                "input": input_items,
                "tools": tools,
                "text": {
                    "format": {
                        "type": "json_schema",
                        "name": "coach_agent_output",
                        "strict": True,
                        "schema": _output_schema(),
                    },
                },
            }
            response = await self._post(
                f"{_OPENAI_BASE}/responses",
                body,
                {"Authorization": f"Bearer {self._api_key}"},
            )
            output = _openai_output_items(response)
            calls = [item for item in output if item.get("type") == "function_call"]
            if calls:
                total_tool_calls = _next_tool_call_count(total_tool_calls, len(calls))
                input_items.extend(output)
                for call in calls:
                    tool_output = self._call_tool(executor, call)
                    tool_result_bytes = _next_tool_result_bytes(
                        tool_result_bytes,
                        tool_output,
                    )
                    input_items.append(
                        {
                            "type": "function_call_output",
                            "call_id": _required_string(call, "call_id"),
                            "output": tool_output,
                        },
                    )
                continue
            return _parse_output(_openai_text(response))
        raise CoachProviderError(
            "tool_limit", "Coach exceeded its tool limit.", retryable=False
        )

    async def _run_gemini(
        self,
        *,
        prompt: str,
        executor: CoachDataMcpServer,
    ) -> CoachAgentModelOutput:
        inputs: list[dict[str, Any]] = [
            {
                "type": "user_input",
                "content": [{"type": "text", "text": prompt}],
            }
        ]
        tools = [{"type": "function", **tool} for tool in _TOOLS]
        total_tool_calls = 0
        tool_result_bytes = 0
        for _ in range(COACH_AGENT_MAX_TOOL_CALLS + 1):
            response = await self._post(
                f"{_GEMINI_BASE}/interactions",
                {
                    "model": self.model,
                    "store": False,
                    "generation_config": {
                        "max_output_tokens": _MAX_PROVIDER_OUTPUT_TOKENS,
                    },
                    "input": inputs,
                    "tools": tools,
                    "response_format": {
                        "type": "text",
                        "mime_type": "application/json",
                        "schema": _output_schema(),
                    },
                },
                {
                    "x-goog-api-key": self._api_key,
                    "Api-Revision": _GEMINI_API_REVISION,
                },
            )
            steps = _gemini_steps(response)
            calls = [item for item in steps if item["type"] == "function_call"]
            if calls:
                total_tool_calls = _next_tool_call_count(total_tool_calls, len(calls))
                # With store=false the complete exact step timeline is required
                # for every continuation, including signed thought steps.
                inputs.extend(steps)
                for call in calls:
                    tool_output = self._call_tool(executor, call)
                    tool_result_bytes = _next_tool_result_bytes(
                        tool_result_bytes,
                        tool_output,
                    )
                    inputs.append(
                        {
                            "type": "function_result",
                            "name": _required_string(call, "name"),
                            "call_id": _required_string(call, "id"),
                            "result": [
                                {
                                    "type": "text",
                                    "text": tool_output,
                                }
                            ],
                        },
                    )
                continue
            return _parse_output(_gemini_text(steps))
        raise CoachProviderError(
            "tool_limit", "Coach exceeded its tool limit.", retryable=False
        )

    def _call_tool(self, executor: CoachDataMcpServer, call: dict[str, Any]) -> str:
        name = _required_string(call, "name")
        arguments = call.get("arguments", {})
        if isinstance(arguments, str):
            try:
                arguments = json.loads(arguments)
            except json.JSONDecodeError as exc:
                raise _invalid_output() from exc
        if not isinstance(arguments, dict):
            raise _invalid_output()
        try:
            return executor.call_readonly_tool(name=name, arguments=arguments)
        except ToolFailure as exc:
            return json.dumps({"error": str(exc)[:300]}, separators=(",", ":"))

    async def _post(
        self,
        url: str,
        body: dict[str, Any],
        headers: dict[str, str],
    ) -> dict[str, Any]:
        try:
            async with self._client_context() as client:
                async with client.stream(
                    "POST",
                    url,
                    json=body,
                    headers=headers,
                ) as response:
                    if response.status_code >= 400:
                        reason = _reason_for_status(response.status_code)
                        raise CoachProviderError(
                            reason,
                            "The Coach provider rejected the request.",
                            retryable=reason
                            in {"provider_failure", "provider_timeout"},
                        )
                    content_length = response.headers.get("Content-Length")
                    if content_length is not None:
                        if not content_length.isdigit():
                            raise _invalid_output()
                        if int(content_length) > _MAX_PROVIDER_RESPONSE_BYTES:
                            raise _invalid_output()
                    raw = bytearray()
                    async for chunk in response.aiter_bytes():
                        raw.extend(chunk)
                        if len(raw) > _MAX_PROVIDER_RESPONSE_BYTES:
                            raise _invalid_output()
        except httpx.TimeoutException:
            raise CoachProviderError(
                "provider_timeout", "The Coach provider timed out.", retryable=True
            ) from None
        except httpx.HTTPError:
            raise CoachProviderError(
                "provider_failure", "The Coach provider request failed.", retryable=True
            ) from None
        try:
            value = json.loads(raw.decode("utf-8"))
        except (UnicodeError, json.JSONDecodeError, RecursionError) as exc:
            raise _invalid_output() from exc
        if not isinstance(value, dict):
            raise _invalid_output()
        return value


class _ClientContext:
    def __init__(self, client: httpx.AsyncClient | None) -> None:
        self._client = client
        self._owned: httpx.AsyncClient | None = None

    async def __aenter__(self) -> httpx.AsyncClient:
        if self._client is not None:
            return self._client
        self._owned = httpx.AsyncClient(timeout=45, follow_redirects=False)
        return self._owned

    async def __aexit__(self, *_: object) -> None:
        if self._owned is not None:
            await self._owned.aclose()


def _reason_for_status(status: int) -> str:
    if status in {401, 403}:
        return "invalid_api_key"
    if status == 404:
        return "unavailable_model"
    if status == 429:
        return "account_limit"
    return "provider_failure"


def _output_schema() -> dict[str, Any]:
    return CoachAgentModelOutput.model_json_schema()


async def _get_status(
    client: httpx.AsyncClient,
    url: str,
    *,
    headers: dict[str, str],
) -> int:
    async with client.stream("GET", url, headers=headers) as response:
        return response.status_code


def _next_tool_call_count(current: int, batch_size: int) -> int:
    next_count = current + batch_size
    if batch_size < 1 or next_count > COACH_AGENT_MAX_TOOL_CALLS:
        raise CoachProviderError(
            "tool_limit",
            "Coach exceeded its tool limit.",
            retryable=False,
        )
    return next_count


def _next_tool_result_bytes(current: int, output: str) -> int:
    next_count = current + len(output.encode("utf-8"))
    if next_count > _MAX_TOOL_RESULT_HISTORY_BYTES:
        raise CoachProviderError(
            "tool_limit",
            "Coach exceeded its bounded tool-result history.",
            retryable=False,
        )
    return next_count


def _openai_output_items(response: dict[str, Any]) -> list[dict[str, Any]]:
    raw = response.get("output")
    if (
        not isinstance(raw, list)
        or len(raw) > _MAX_PROVIDER_OUTPUT_ITEMS
        or any(not isinstance(item, dict) for item in raw)
    ):
        raise _invalid_output()
    return raw


def _required_string(
    value: dict[str, Any], key: str, *, fallback: str | None = None
) -> str:
    raw = value.get(key)
    if raw is None and fallback is not None:
        raw = value.get(fallback)
    if not isinstance(raw, str) or not raw:
        raise _invalid_output()
    return raw


def _openai_text(response: dict[str, Any]) -> str:
    direct = response.get("output_text")
    if isinstance(direct, str):
        return direct
    for item in response.get("output", []):
        for content in item.get("content", []) if isinstance(item, dict) else []:
            if isinstance(content, dict) and content.get("type") == "output_text":
                return _required_string(content, "text")
    raise _invalid_output()


def _gemini_steps(response: dict[str, Any]) -> list[dict[str, Any]]:
    raw = response.get("steps")
    if (
        not isinstance(raw, list)
        or not raw
        or len(raw) > _MAX_PROVIDER_OUTPUT_ITEMS
    ):
        raise _invalid_output()
    steps: list[dict[str, Any]] = []
    for step in raw:
        if not isinstance(step, dict):
            raise _invalid_output()
        step_type = step.get("type")
        if step_type == "function_call":
            _required_string(step, "id")
            _required_string(step, "name")
            if not isinstance(step.get("arguments"), dict):
                raise _invalid_output()
        elif step_type == "model_output":
            content = step.get("content")
            if (
                not isinstance(content, list)
                or not content
                or len(content) > _MAX_PROVIDER_CONTENT_BLOCKS
            ):
                raise _invalid_output()
            for block in content:
                if (
                    not isinstance(block, dict)
                    or block.get("type") != "text"
                    or not isinstance(block.get("text"), str)
                ):
                    raise _invalid_output()
        elif step_type == "thought":
            # Preserve opaque thought signatures/summaries byte-for-byte in the
            # next request. They are provider state, never exposed as evidence.
            signature = step.get("signature")
            if signature is not None and (
                not isinstance(signature, str) or not signature
            ):
                raise _invalid_output()
            summary = step.get("summary")
            if summary is not None and (
                not isinstance(summary, list)
                or len(summary) > _MAX_PROVIDER_CONTENT_BLOCKS
                or any(
                    not isinstance(block, dict)
                    or block.get("type") != "text"
                    or not isinstance(block.get("text"), str)
                    for block in summary
                )
            ):
                raise _invalid_output()
        else:
            raise _invalid_output()
        steps.append(step)
    return steps


def _gemini_text(steps: list[dict[str, Any]]) -> str:
    text_blocks: list[str] = []
    for step in steps:
        if step["type"] != "model_output":
            continue
        for block in step["content"]:
            text_blocks.append(block["text"])
    if not text_blocks:
        raise _invalid_output()
    return "".join(text_blocks)


def _parse_output(value: str) -> CoachAgentModelOutput:
    try:
        return CoachAgentModelOutput.model_validate_json(value)
    except (ValidationError, ValueError) as exc:
        raise _invalid_output() from exc


def _invalid_output() -> CoachProviderError:
    return CoachProviderError(
        "invalid_output", "The Coach provider returned invalid output.", retryable=True
    )
