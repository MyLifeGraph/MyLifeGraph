import asyncio

import pytest

from app.clients import supabase
from app.clients.supabase import SupabaseRestClient


class _Response:
    def __init__(
        self,
        content_range: str | None,
        preference_applied: str | None,
    ) -> None:
        self.headers = {}
        if content_range is not None:
            self.headers["Content-Range"] = content_range
        if preference_applied is not None:
            self.headers["Preference-Applied"] = preference_applied

    def raise_for_status(self) -> None:
        return None


class _AsyncClient:
    content_range: str | None = "0-0/123"
    preference_applied: str | None = "count=exact"
    instances = []

    def __init__(self, **kwargs) -> None:
        self.kwargs = kwargs
        self.head_call = None
        self.__class__.instances.append(self)

    async def __aenter__(self):
        return self

    async def __aexit__(self, exc_type, exc, traceback) -> None:
        return None

    async def head(self, url, *, params, headers):
        self.head_call = {
            "url": url,
            "params": params,
            "headers": headers,
        }
        return _Response(self.content_range, self.preference_applied)


class _SharedAsyncClient:
    def __init__(self) -> None:
        self.head_calls = []
        self.close_calls = 0

    async def head(self, url, *, params, headers):
        self.head_calls.append(
            {
                "url": url,
                "params": params,
                "headers": headers,
            },
        )
        return _Response("0-0/123", "count=exact")

    async def aclose(self) -> None:
        self.close_calls += 1


def _client() -> SupabaseRestClient:
    return SupabaseRestClient(
        url="http://supabase.test",
        service_role_key="service-role",
        timeout_seconds=7,
    )


def test_exact_count_uses_postgrest_head_without_transferring_rows(
    monkeypatch,
) -> None:
    _AsyncClient.instances = []
    _AsyncClient.content_range = "0-0/123"
    _AsyncClient.preference_applied = "count=exact"
    monkeypatch.setattr(supabase.httpx, "AsyncClient", _AsyncClient)

    params = [
        ("user_id", "eq.owner"),
        ("status", "in.(completed,abandoned)"),
    ]
    result = asyncio.run(
        _client().count_exact(
            "focus_sessions",
            params=params,
        ),
    )

    assert result == 123
    instance = _AsyncClient.instances[0]
    assert instance.kwargs == {"timeout": 7}
    assert instance.head_call["url"] == (
        "http://supabase.test/rest/v1/focus_sessions"
    )
    assert instance.head_call["params"] == params
    assert instance.head_call["headers"]["Prefer"] == "count=exact"
    assert instance.head_call["headers"]["Range-Unit"] == "items"
    assert instance.head_call["headers"]["Range"] == "0-0"


def test_injected_http_pool_is_reused_and_closed_exactly_once() -> None:
    transport = _SharedAsyncClient()
    client = SupabaseRestClient(
        url="http://supabase.test",
        service_role_key="service-role",
        timeout_seconds=7,
        http_client=transport,
    )

    async def exercise() -> None:
        assert await client.count_exact(
            "focus_sessions",
            params={"user_id": "eq.owner"},
        ) == 123
        assert await client.count_exact(
            "tasks",
            params={"user_id": "eq.owner"},
        ) == 123
        await client.aclose()
        await client.aclose()

    asyncio.run(exercise())

    assert [call["url"] for call in transport.head_calls] == [
        "http://supabase.test/rest/v1/focus_sessions",
        "http://supabase.test/rest/v1/tasks",
    ]
    assert transport.close_calls == 1


def test_exact_count_accepts_postgrest_empty_range(monkeypatch) -> None:
    _AsyncClient.instances = []
    _AsyncClient.content_range = "*/0"
    _AsyncClient.preference_applied = "count=exact"
    monkeypatch.setattr(supabase.httpx, "AsyncClient", _AsyncClient)

    result = asyncio.run(
        _client().count_exact(
            "focus_sessions",
            params={"user_id": "eq.owner"},
        ),
    )

    assert result == 0


@pytest.mark.parametrize("content_range", [None, "0-0/*", "invalid"])
def test_exact_count_rejects_missing_or_inexact_content_range(
    monkeypatch,
    content_range,
) -> None:
    _AsyncClient.instances = []
    _AsyncClient.content_range = content_range
    _AsyncClient.preference_applied = "count=exact"
    monkeypatch.setattr(supabase.httpx, "AsyncClient", _AsyncClient)

    with pytest.raises(ValueError):
        asyncio.run(
            _client().count_exact(
                "focus_sessions",
                params={"user_id": "eq.owner"},
            ),
        )


@pytest.mark.parametrize("preference_applied", [None, "", "return=minimal"])
def test_exact_count_rejects_unapplied_count_preference(
    monkeypatch,
    preference_applied,
) -> None:
    _AsyncClient.instances = []
    _AsyncClient.content_range = "0-0/123"
    _AsyncClient.preference_applied = preference_applied
    monkeypatch.setattr(supabase.httpx, "AsyncClient", _AsyncClient)

    with pytest.raises(ValueError):
        asyncio.run(
            _client().count_exact(
                "focus_sessions",
                params={"user_id": "eq.owner"},
            ),
        )
