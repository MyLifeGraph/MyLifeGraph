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
                    response = await client.get(
                        f"{_OPENAI_BASE}/models/{self.model}",
                        headers={"Authorization": f"Bearer {self._api_key}"},
                    )
                else:
                    response = await client.get(
                        f"{_GEMINI_BASE}/models/{self.model}",
                        headers={"x-goog-api-key": self._api_key},
                    )
            if response.status_code == 200:
                return self._capability("ready", "ready")
            return self._capability(
                "unavailable", _reason_for_status(response.status_code)
            )
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
        for _ in range(COACH_AGENT_MAX_TOOL_CALLS + 1):
            body = {
                "model": self.model,
                "store": False,
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
            output = response.get("output")
            if not isinstance(output, list):
                raise _invalid_output()
            calls = [item for item in output if item.get("type") == "function_call"]
            if calls:
                input_items.extend(output)
                for call in calls:
                    input_items.append(
                        {
                            "type": "function_call_output",
                            "call_id": _required_string(call, "call_id"),
                            "output": self._call_tool(executor, call),
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
        inputs: list[dict[str, Any]] = [{"type": "text", "text": prompt}]
        tools = [{"type": "function", **tool} for tool in _TOOLS]
        for _ in range(COACH_AGENT_MAX_TOOL_CALLS + 1):
            response = await self._post(
                f"{_GEMINI_BASE}/interactions",
                {
                    "model": self.model,
                    "store": False,
                    "input": inputs,
                    "tools": tools,
                    "response_format": {
                        "type": "json_schema",
                        "json_schema": {
                            "name": "coach_agent_output",
                            "schema": _output_schema(),
                        },
                    },
                },
                {"x-goog-api-key": self._api_key},
            )
            outputs = response.get("outputs") or response.get("output")
            if not isinstance(outputs, list):
                raise _invalid_output()
            calls = [item for item in outputs if item.get("type") == "function_call"]
            if calls:
                inputs.extend(outputs)
                for call in calls:
                    inputs.append(
                        {
                            "type": "function_result",
                            "name": _required_string(call, "name"),
                            "call_id": _required_string(call, "id", fallback="call_id"),
                            "result": [
                                {
                                    "type": "text",
                                    "text": self._call_tool(executor, call),
                                }
                            ],
                        },
                    )
                continue
            return _parse_output(_gemini_text(outputs))
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
                response = await client.post(url, json=body, headers=headers)
        except httpx.TimeoutException:
            raise CoachProviderError(
                "provider_timeout", "The Coach provider timed out.", retryable=True
            ) from None
        except httpx.HTTPError:
            raise CoachProviderError(
                "provider_failure", "The Coach provider request failed.", retryable=True
            ) from None
        if response.status_code >= 400:
            reason = _reason_for_status(response.status_code)
            raise CoachProviderError(
                reason,
                "The Coach provider rejected the request.",
                retryable=reason in {"provider_failure", "provider_timeout"},
            )
        try:
            value = response.json()
        except ValueError as exc:
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


def _gemini_text(outputs: list[dict[str, Any]]) -> str:
    for item in outputs:
        if isinstance(item, dict) and item.get("type") in {"text", "model_output"}:
            text = item.get("text") or item.get("content")
            if isinstance(text, str):
                return text
    raise _invalid_output()


def _parse_output(value: str) -> CoachAgentModelOutput:
    try:
        return CoachAgentModelOutput.model_validate_json(value)
    except (ValidationError, ValueError) as exc:
        raise _invalid_output() from exc


def _invalid_output() -> CoachProviderError:
    return CoachProviderError(
        "invalid_output", "The Coach provider returned invalid output.", retryable=True
    )
