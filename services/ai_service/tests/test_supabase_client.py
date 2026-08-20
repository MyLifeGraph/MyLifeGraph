import asyncio

import httpx
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
    assert instance.head_call["url"] == ("http://supabase.test/rest/v1/focus_sessions")
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
        assert (
            await client.count_exact(
                "focus_sessions",
                params={"user_id": "eq.owner"},
            )
            == 123
        )
        assert (
            await client.count_exact(
                "tasks",
                params={"user_id": "eq.owner"},
            )
            == 123
        )
        await client.aclose()
        await client.aclose()

    asyncio.run(exercise())

    assert [call["url"] for call in transport.head_calls] == [
        "http://supabase.test/rest/v1/focus_sessions",
        "http://supabase.test/rest/v1/tasks",
    ]
    assert transport.close_calls == 1


def test_readiness_probe_uses_body_free_profiles_head() -> None:
    transport = _SharedAsyncClient()
    client = SupabaseRestClient(
        url="http://supabase.test",
        service_role_key="service-role",
        timeout_seconds=7,
        http_client=transport,
    )

    asyncio.run(client.readiness_probe())

    assert transport.head_calls == [
        {
            "url": "http://supabase.test/rest/v1/profiles",
            "params": {"select": "id", "limit": "1"},
            "headers": client._rest_headers(),
        },
    ]


def test_participation_gate_uses_service_role_rpc_and_requires_object() -> None:
    requests: list[httpx.Request] = []

    def handler(request: httpx.Request) -> httpx.Response:
        requests.append(request)
        return httpx.Response(
            200,
            json={
                "contract_version": "pilot-participation-gate-v1",
                "project_ref": "abcdefghijklmnopqrst",
                "participation_required": True,
                "notice_version": "pilot-participation-notice-v1",
            },
        )

    async def exercise() -> dict[str, object]:
        async with httpx.AsyncClient(
            transport=httpx.MockTransport(handler),
        ) as http_client:
            client = SupabaseRestClient(
                url="https://project.supabase.co",
                service_role_key="sb_secret_backend",
                http_client=http_client,
            )
            return await client.pilot_participation_gate()

    result = asyncio.run(exercise())

    assert result["participation_required"] is True
    assert requests[0].url.path == (
        "/rest/v1/rpc/get_pilot_participation_gate_v1"
    )
    assert requests[0].headers["apikey"] == "sb_secret_backend"
    assert "authorization" not in requests[0].headers


def test_hosted_database_contract_uses_the_exact_service_role_rpc() -> None:
    requests: list[httpx.Request] = []

    def handler(request: httpx.Request) -> httpx.Response:
        requests.append(request)
        return httpx.Response(
            200,
            json={
                "contract_version": "hosted-database-contract-v1",
                "migration_head": (
                    "20260820200000_account_deletion_replayer_role_guard_v2.sql"
                ),
                "migration_count": 69,
                "migration_identity_sha256": "5" * 64,
                "prefix_head": (
                    "20260820200000_account_deletion_replayer_role_guard_v2.sql"
                ),
                "prefix_count": 69,
                "prefix_identity_sha256": "5" * 64,
                "prepared_deletion_pending_guard": True,
            },
        )

    async def exercise() -> dict[str, object]:
        async with httpx.AsyncClient(
            transport=httpx.MockTransport(handler),
        ) as http_client:
            client = SupabaseRestClient(
                url="https://project.supabase.co",
                service_role_key="sb_secret_backend",
                http_client=http_client,
            )
            return await client.hosted_database_contract(
                through_head=(
                    "20260820200000_account_deletion_replayer_role_guard_v2.sql"
                ),
            )

    result = asyncio.run(exercise())

    assert result["prepared_deletion_pending_guard"] is True
    assert requests[0].url.path == (
        "/rest/v1/rpc/get_hosted_database_contract_v1"
    )
    assert requests[0].read() == (
        b'{"p_through_head":"20260820200000_account_deletion_replayer_role_guard_v2.sql"}'
    )
    assert requests[0].headers["apikey"] == "sb_secret_backend"
    assert "authorization" not in requests[0].headers


def test_opaque_secret_is_apikey_only_while_user_jwt_stays_bearer() -> None:
    requests: list[httpx.Request] = []

    def handler(request: httpx.Request) -> httpx.Response:
        requests.append(request)
        if request.url.path == "/rest/v1/profiles":
            return httpx.Response(200, json=[])
        if request.url.path == "/rest/v1/rpc/example":
            return httpx.Response(200, json={"ok": True})
        if request.url.path == "/auth/v1/user":
            return httpx.Response(200, json={"id": "owner-1"})
        raise AssertionError(request.url.path)

    async def exercise() -> None:
        async with httpx.AsyncClient(
            transport=httpx.MockTransport(handler)
        ) as http_client:
            client = SupabaseRestClient(
                url="https://project.supabase.co",
                service_role_key="sb_secret_backend",
                http_client=http_client,
            )
            assert await client.select("profiles", params={"limit": "1"}) == []
            assert await client.rpc("example", params={}) == {"ok": True}
            assert await client.get_user_for_token("verified-user-jwt") == {
                "id": "owner-1"
            }

    asyncio.run(exercise())

    for request in requests[:2]:
        assert request.headers["apikey"] == "sb_secret_backend"
        assert "authorization" not in request.headers
    assert requests[2].headers["apikey"] == "sb_secret_backend"
    assert requests[2].headers["authorization"] == "Bearer verified-user-jwt"


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
