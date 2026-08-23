import asyncio
import json
import sqlite3
from pathlib import Path

import httpx
import pytest

from app.core.config import Settings
from app.providers.base import CoachProviderError
from app.providers.cloud_byok import CloudByokCoachProvider


def _settings() -> Settings:
    return Settings(
        APP_ENV="staging",
        COACH_BYOK_PROVIDERS="openai,gemini",
    )


def _snapshot(path: Path) -> Path:
    with sqlite3.connect(path) as connection:
        connection.execute("create table _coach_catalog (table_name text)")
        connection.execute(
            "create table _coach_relationships "
            "(from_table text, from_column text, to_table text, to_column text)"
        )
        connection.execute("create table tasks (title text)")
        connection.execute("insert into tasks values ('Review notes')")
    return path


def _output() -> str:
    return json.dumps(
        {
            "reply": "The available data supports one small next step.",
            "uncertainty": {
                "level": "medium",
                "reason": "Only the bounded snapshot was available.",
            },
            "safety": {"classification": "normal"},
        }
    )


def test_openai_capability_uses_bearer_key_without_persisting_it() -> None:
    seen: list[httpx.Request] = []

    def handler(request: httpx.Request) -> httpx.Response:
        seen.append(request)
        return httpx.Response(200, json={"id": "gpt-5.6-terra"})

    provider = CloudByokCoachProvider(
        provider="openai",
        api_key="secret-a",
        settings=_settings(),
        client=httpx.AsyncClient(transport=httpx.MockTransport(handler)),
    )
    capability = asyncio.run(provider.capability())

    assert capability.state == "ready"
    assert seen[0].headers["authorization"] == "Bearer secret-a"
    assert "secret-a" not in repr(provider)


@pytest.mark.parametrize(
    ("status", "reason"),
    [(401, "invalid_api_key"), (404, "unavailable_model"), (429, "account_limit")],
)
def test_capability_maps_provider_failures_without_echoing_body(
    status: int,
    reason: str,
) -> None:
    client = httpx.AsyncClient(
        transport=httpx.MockTransport(
            lambda _: httpx.Response(status, json={"error": "secret-a"})
        )
    )
    provider = CloudByokCoachProvider(
        provider="openai",
        api_key="secret-a",
        settings=_settings(),
        client=client,
    )
    capability = asyncio.run(provider.capability())
    assert capability.reason_code == reason


def test_openai_agent_is_stateless_and_replays_only_current_tool_steps(
    tmp_path: Path,
) -> None:
    bodies: list[dict[str, object]] = []

    def handler(request: httpx.Request) -> httpx.Response:
        if request.method == "GET":
            return httpx.Response(200, json={"id": "gpt-5.6-terra"})
        body = json.loads(request.content)
        bodies.append(body)
        if len(bodies) == 1:
            return httpx.Response(
                200,
                json={
                    "output": [
                        {
                            "type": "function_call",
                            "name": "query_data",
                            "call_id": "call-1",
                            "arguments": '{"sql":"select title from tasks"}',
                        }
                    ]
                },
            )
        return httpx.Response(200, json={"output": [], "output_text": _output()})

    provider = CloudByokCoachProvider(
        provider="openai",
        api_key="secret-a",
        settings=_settings(),
        client=httpx.AsyncClient(transport=httpx.MockTransport(handler)),
    )
    result = asyncio.run(
        provider.respond_agent(
            prompt="prompt",
            snapshot_path=_snapshot(tmp_path / "snapshot.sqlite3"),
            trace_path=tmp_path / "trace.jsonl",
        )
    )

    assert result.model_reported == "gpt-5.6-terra"
    assert all(body["store"] is False for body in bodies)
    assert all(body["max_output_tokens"] == 4096 for body in bodies)
    assert bodies[1]["input"][-1]["type"] == "function_call_output"
    assert "Review notes" in bodies[1]["input"][-1]["output"]
    assert {tool["name"] for tool in bodies[0]["tools"]} == {
        "inspect_data",
        "query_data",
    }


def test_gemini_interaction_uses_current_steps_schema_and_full_stateless_history(
    tmp_path: Path,
) -> None:
    bodies: list[dict[str, object]] = []
    requests: list[httpx.Request] = []
    provider_steps: list[dict[str, object]] = [
        {
            "type": "thought",
            "signature": "thought-sig-1",
            "summary": [{"type": "text", "text": "Inspect the bounded data."}],
        },
        {
            "type": "function_call",
            "id": "call-1",
            "name": "query_data",
            "arguments": {"sql": "select title from tasks"},
        },
    ]

    def handler(request: httpx.Request) -> httpx.Response:
        requests.append(request)
        if request.method == "GET":
            return httpx.Response(200, json={"name": "gemini-3.6-flash"})
        bodies.append(json.loads(request.content))
        if len(bodies) == 1:
            return httpx.Response(200, json={"steps": provider_steps})
        return httpx.Response(
            200,
            json={
                "steps": [
                    {
                        "type": "model_output",
                        "content": [{"type": "text", "text": _output()}],
                    }
                ]
            },
        )

    provider = CloudByokCoachProvider(
        provider="gemini",
        api_key="secret-b",
        settings=_settings(),
        client=httpx.AsyncClient(transport=httpx.MockTransport(handler)),
    )
    result = asyncio.run(
        provider.respond_agent(
            prompt="prompt",
            snapshot_path=_snapshot(tmp_path / "snapshot.sqlite3"),
            trace_path=tmp_path / "trace.jsonl",
        )
    )
    assert result.model_reported == "gemini-3.6-flash"
    assert len(bodies) == 2
    assert all(body["store"] is False for body in bodies)
    assert all(
        body["generation_config"] == {"max_output_tokens": 4096}
        for body in bodies
    )
    assert requests[1].headers["api-revision"] == "2026-05-20"
    assert requests[2].headers["api-revision"] == "2026-05-20"
    assert bodies[0]["input"] == [
        {
            "type": "user_input",
            "content": [{"type": "text", "text": "prompt"}],
        }
    ]
    assert bodies[0]["response_format"]["type"] == "text"
    assert bodies[0]["response_format"]["mime_type"] == "application/json"
    assert "schema" in bodies[0]["response_format"]
    assert bodies[1]["input"][:-1] == [
        {
            "type": "user_input",
            "content": [{"type": "text", "text": "prompt"}],
        },
        *provider_steps,
    ]
    assert bodies[1]["input"][-1]["type"] == "function_result"
    assert bodies[1]["input"][-1]["call_id"] == "call-1"
    assert "Review notes" in bodies[1]["input"][-1]["result"][0]["text"]
    assert {tool["name"] for tool in bodies[0]["tools"]} == {
        "inspect_data",
        "query_data",
    }


@pytest.mark.parametrize(
    "response",
    [
        {"outputs": [{"type": "model_output", "text": "legacy"}]},
        {"steps": []},
        {"steps": [{"type": "model_output", "content": "not-a-list"}]},
        {
            "steps": [
                {
                    "type": "function_call",
                    "id": "call-1",
                    "name": "query_data",
                    "arguments": "legacy-json-string",
                }
            ]
        },
        {"steps": [{"type": "google_search_call", "id": "forbidden"}]},
    ],
)
def test_gemini_rejects_legacy_or_unoffered_step_shapes(
    tmp_path: Path,
    response: dict[str, object],
) -> None:
    def handler(request: httpx.Request) -> httpx.Response:
        if request.method == "GET":
            return httpx.Response(200, json={})
        return httpx.Response(200, json=response)

    provider = CloudByokCoachProvider(
        provider="gemini",
        api_key="secret-b",
        settings=_settings(),
        client=httpx.AsyncClient(transport=httpx.MockTransport(handler)),
    )
    with pytest.raises(CoachProviderError, match="invalid output"):
        asyncio.run(
            provider.respond_agent(
                prompt="prompt",
                snapshot_path=_snapshot(tmp_path / "snapshot.sqlite3"),
                trace_path=tmp_path / "trace.jsonl",
            )
        )


def test_invalid_output_and_timeout_fail_without_provider_fallback(
    tmp_path: Path,
) -> None:
    calls = 0

    def invalid(request: httpx.Request) -> httpx.Response:
        nonlocal calls
        calls += 1
        if request.method == "GET":
            return httpx.Response(200, json={})
        return httpx.Response(200, json={"output": [], "output_text": "not-json"})

    provider = CloudByokCoachProvider(
        provider="openai",
        api_key="secret-a",
        settings=_settings(),
        client=httpx.AsyncClient(transport=httpx.MockTransport(invalid)),
    )
    with pytest.raises(CoachProviderError, match="invalid output"):
        asyncio.run(
            provider.respond_agent(
                prompt="prompt",
                snapshot_path=_snapshot(tmp_path / "snapshot.sqlite3"),
                trace_path=tmp_path / "trace.jsonl",
            )
        )
    assert calls == 2


@pytest.mark.parametrize("provider_name", ["openai", "gemini"])
def test_parallel_tool_batch_over_limit_executes_zero_tools(
    tmp_path: Path,
    provider_name: str,
) -> None:
    def handler(request: httpx.Request) -> httpx.Response:
        if request.method == "GET":
            return httpx.Response(200, json={})
        if provider_name == "openai":
            calls = [
                {
                    "type": "function_call",
                    "name": "query_data",
                    "call_id": f"call-{index}",
                    "arguments": '{"sql":"select title from tasks"}',
                }
                for index in range(13)
            ]
            return httpx.Response(200, json={"output": calls})
        calls = [
            {
                "type": "function_call",
                "name": "query_data",
                "id": f"call-{index}",
                "arguments": {"sql": "select title from tasks"},
            }
            for index in range(13)
        ]
        return httpx.Response(200, json={"steps": calls})

    trace = tmp_path / "trace.jsonl"
    provider = CloudByokCoachProvider(
        provider=provider_name,
        api_key="secret",
        settings=_settings(),
        client=httpx.AsyncClient(transport=httpx.MockTransport(handler)),
    )
    with pytest.raises(CoachProviderError, match="tool limit"):
        asyncio.run(
            provider.respond_agent(
                prompt="prompt",
                snapshot_path=_snapshot(tmp_path / "snapshot.sqlite3"),
                trace_path=trace,
            )
        )
    assert not trace.exists()


def test_cumulative_tool_limit_rejects_next_batch_before_execution(
    tmp_path: Path,
) -> None:
    responses = 0

    def calls(start: int, count: int) -> list[dict[str, str]]:
        return [
            {
                "type": "function_call",
                "name": "query_data",
                "call_id": f"call-{index}",
                "arguments": '{"sql":"select title from tasks"}',
            }
            for index in range(start, start + count)
        ]

    def handler(request: httpx.Request) -> httpx.Response:
        nonlocal responses
        if request.method == "GET":
            return httpx.Response(200, json={})
        responses += 1
        if responses == 1:
            return httpx.Response(200, json={"output": calls(0, 7)})
        return httpx.Response(200, json={"output": calls(7, 6)})

    trace = tmp_path / "trace.jsonl"
    provider = CloudByokCoachProvider(
        provider="openai",
        api_key="secret",
        settings=_settings(),
        client=httpx.AsyncClient(transport=httpx.MockTransport(handler)),
    )
    with pytest.raises(CoachProviderError, match="tool limit"):
        asyncio.run(
            provider.respond_agent(
                prompt="prompt",
                snapshot_path=_snapshot(tmp_path / "snapshot.sqlite3"),
                trace_path=trace,
            )
        )
    assert len(trace.read_text().splitlines()) == 7


class _OversizedStream(httpx.AsyncByteStream):
    async def __aiter__(self):
        yield b"x" * (128 * 1024)
        yield b"x" * (128 * 1024 + 1)


@pytest.mark.parametrize("mode", ["declared", "chunked"])
def test_provider_response_body_is_bounded_before_json_decode(
    tmp_path: Path,
    mode: str,
) -> None:
    def handler(request: httpx.Request) -> httpx.Response:
        if request.method == "GET":
            return httpx.Response(200, json={})
        if mode == "declared":
            return httpx.Response(
                200,
                headers={"Content-Length": str(256 * 1024 + 1)},
                content=b"{}",
            )
        return httpx.Response(200, stream=_OversizedStream())

    provider = CloudByokCoachProvider(
        provider="openai",
        api_key="secret",
        settings=_settings(),
        client=httpx.AsyncClient(transport=httpx.MockTransport(handler)),
    )
    with pytest.raises(CoachProviderError, match="invalid output"):
        asyncio.run(
            provider.respond_agent(
                prompt="prompt",
                snapshot_path=_snapshot(tmp_path / "snapshot.sqlite3"),
                trace_path=tmp_path / "trace.jsonl",
            )
        )


def test_parallel_provider_instances_keep_keys_separate() -> None:
    seen: list[str] = []

    def handler(request: httpx.Request) -> httpx.Response:
        seen.append(request.headers["authorization"])
        return httpx.Response(200, json={})

    client = httpx.AsyncClient(transport=httpx.MockTransport(handler))
    providers = [
        CloudByokCoachProvider(
            provider="openai",
            api_key=key,
            settings=_settings(),
            client=client,
        )
        for key in ("secret-a", "secret-b")
    ]

    async def probe_all() -> None:
        await asyncio.gather(*(provider.capability() for provider in providers))

    asyncio.run(probe_all())
    assert sorted(seen) == ["Bearer secret-a", "Bearer secret-b"]
