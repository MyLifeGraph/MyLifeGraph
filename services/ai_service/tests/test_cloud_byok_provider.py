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
    assert bodies[1]["input"][-1]["type"] == "function_call_output"
    assert "Review notes" in bodies[1]["input"][-1]["output"]
    assert {tool["name"] for tool in bodies[0]["tools"]} == {
        "inspect_data",
        "query_data",
    }


def test_gemini_interaction_is_stateless_and_never_offers_python(
    tmp_path: Path,
) -> None:
    bodies: list[dict[str, object]] = []

    def handler(request: httpx.Request) -> httpx.Response:
        if request.method == "GET":
            return httpx.Response(200, json={"name": "gemini-3.6-flash"})
        bodies.append(json.loads(request.content))
        return httpx.Response(
            200,
            json={"outputs": [{"type": "model_output", "text": _output()}]},
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
    assert bodies[0]["store"] is False
    assert {tool["name"] for tool in bodies[0]["tools"]} == {
        "inspect_data",
        "query_data",
    }


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
