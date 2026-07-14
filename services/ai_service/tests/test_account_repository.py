import asyncio

import httpx
import pytest

from app.clients.supabase import SupabaseResponseTooLargeError
from app.repositories.account_repository import (
    AccountDeletionOutcomeUnknownError,
    AccountExportSourceTooLargeError,
    AccountExportTable,
    AccountPersistenceError,
    AccountProfileUpdateOutcomeUnknownError,
    SupabaseAccountRepository,
)


class Client:
    def __init__(self) -> None:
        self.update_rows = [{"timezone": "America/New_York"}]
        self.select_rows: dict[str, list[dict[str, object]]] = {}
        self.rpc_result: object = {
            "deleted": True,
            "not_found": False,
            "user_id": "owner-1",
        }
        self.update_calls = []
        self.select_calls = []
        self.rpc_calls = []
        self.update_error: Exception | None = None
        self.select_error: Exception | None = None
        self.rpc_error: Exception | None = None
        self.rpc_outcomes: list[object | Exception] = []

    async def update(self, table: str, *, values, params):
        self.update_calls.append((table, values, params))
        if self.update_error is not None:
            raise self.update_error
        return self.update_rows

    async def select(self, table: str, *, params, max_response_bytes=None):
        self.select_calls.append((table, params, max_response_bytes))
        if self.select_error is not None:
            raise self.select_error
        return self.select_rows.get(table, [])

    async def rpc(self, function: str, *, params):
        self.rpc_calls.append((function, params))
        if self.rpc_outcomes:
            outcome = self.rpc_outcomes.pop(0)
            if isinstance(outcome, Exception):
                raise outcome
            return outcome
        if self.rpc_error is not None:
            raise self.rpc_error
        return self.rpc_result


def _http_error(status_code: int = 500) -> httpx.HTTPStatusError:
    request = httpx.Request("POST", "http://test/rest/v1/rpc/delete_account_v1")
    response = httpx.Response(
        status_code,
        request=request,
        json={"message": "secret"},
    )
    return httpx.HTTPStatusError(
        "secret upstream detail",
        request=request,
        response=response,
    )


def test_timezone_update_filters_by_owner_and_returns_exact_projection() -> None:
    client = Client()
    repository = SupabaseAccountRepository(client)  # type: ignore[arg-type]

    result = asyncio.run(
        repository.update_timezone(
            user_id="owner-1",
            timezone="America/New_York",
        ),
    )

    assert result == "America/New_York"
    assert client.update_calls == [
        (
            "profiles",
            {"timezone": "America/New_York"},
            {"id": "eq.owner-1", "select": "timezone"},
        ),
    ]


def test_timezone_update_returns_missing_and_rejects_mismatched_results() -> None:
    client = Client()
    repository = SupabaseAccountRepository(client)  # type: ignore[arg-type]
    client.update_rows = []
    assert (
        asyncio.run(
            repository.update_timezone(
                user_id="owner-1",
                timezone="Europe/Berlin",
            ),
        )
        is None
    )

    client.update_rows = [{"timezone": "UTC"}]
    client.select_rows["profiles"] = [{"timezone": "UTC"}]
    with pytest.raises(AccountProfileUpdateOutcomeUnknownError, match="determined"):
        asyncio.run(
            repository.update_timezone(
                user_id="owner-1",
                timezone="Europe/Berlin",
            ),
        )


def test_timezone_update_response_loss_converges_by_exact_readback() -> None:
    client = Client()
    client.update_error = httpx.ReadError("response lost")
    client.select_rows["profiles"] = [{"timezone": "Europe/Berlin"}]
    repository = SupabaseAccountRepository(client)  # type: ignore[arg-type]

    result = asyncio.run(
        repository.update_timezone(
            user_id="owner-1",
            timezone="Europe/Berlin",
        ),
    )

    assert result == "Europe/Berlin"
    assert client.select_calls == [
        (
            "profiles",
            {"select": "timezone", "id": "eq.owner-1", "limit": "1"},
            None,
        ),
    ]


def test_timezone_update_response_loss_has_explicit_unknown_failed_readback() -> None:
    client = Client()
    client.update_error = ValueError("invalid response")
    client.select_error = _http_error()
    repository = SupabaseAccountRepository(client)  # type: ignore[arg-type]

    with pytest.raises(AccountProfileUpdateOutcomeUnknownError, match="determined"):
        asyncio.run(
            repository.update_timezone(
                user_id="owner-1",
                timezone="Europe/Berlin",
            ),
        )


def test_export_query_always_has_exact_owner_filter_and_stable_page() -> None:
    client = Client()
    client.select_rows["daily_logs"] = [{"id": "log-1", "user_id": "owner-1"}]
    repository = SupabaseAccountRepository(client)  # type: ignore[arg-type]
    table = AccountExportTable(
        name="daily_logs",
        owner_column="user_id",
        select="id,user_id,entry_date",
        cursor_column="id",
        watermark_column="created_at",
    )

    rows = asyncio.run(
        repository.list_export_rows(
            user_id="owner-1",
            table=table,
            after_cursor="log-500",
            not_after="2026-07-13T12:00:00+00:00",
            limit=500,
            max_response_bytes=8192,
        ),
    )

    assert rows == [{"id": "log-1", "user_id": "owner-1"}]
    assert client.select_calls == [
        (
            "daily_logs",
            {
                "select": "id,user_id,entry_date",
                "user_id": "eq.owner-1",
                "order": "id.asc",
                "created_at": "lte.2026-07-13T12:00:00+00:00",
                "limit": "500",
                "id": "gt.log-500",
            },
            8192,
        ),
    ]


def test_export_maps_a_stream_response_bound_without_retaining_the_page() -> None:
    client = Client()
    client.select_error = SupabaseResponseTooLargeError("bounded")
    repository = SupabaseAccountRepository(client)  # type: ignore[arg-type]
    table = AccountExportTable(
        name="daily_logs",
        owner_column="user_id",
        select="*",
        cursor_column="id",
        watermark_column="created_at",
    )

    with pytest.raises(AccountExportSourceTooLargeError, match="byte bound"):
        asyncio.run(
            repository.list_export_rows(
                user_id="owner-1",
                table=table,
                after_cursor=None,
                not_after="2026-07-13T12:00:00+00:00",
                limit=25,
                max_response_bytes=8192,
            ),
        )


def test_export_watermark_is_owner_scoped_and_stream_bounded() -> None:
    client = Client()
    client.select_rows["daily_logs"] = [
        {"user_id": "owner-1", "created_at": "2026-07-13T12:00:00+00:00"},
    ]
    repository = SupabaseAccountRepository(client)  # type: ignore[arg-type]
    table = AccountExportTable(
        name="daily_logs",
        owner_column="user_id",
        select="*",
        cursor_column="id",
        watermark_column="created_at",
    )

    watermark = asyncio.run(
        repository.get_export_watermark(
            user_id="owner-1",
            table=table,
            max_response_bytes=4096,
        ),
    )

    assert watermark == "2026-07-13T12:00:00+00:00"
    assert client.select_calls == [
        (
            "daily_logs",
            {
                "select": "user_id,created_at",
                "user_id": "eq.owner-1",
                "order": "created_at.desc",
                "limit": "1",
            },
            4096,
        ),
    ]


def test_delete_uses_one_atomic_rpc_without_a_fallible_success_readback() -> None:
    client = Client()
    repository = SupabaseAccountRepository(client)  # type: ignore[arg-type]

    asyncio.run(
        repository.delete_account(user_id="owner-1", confirmation="DELETE"),
    )

    assert client.rpc_calls == [
        (
            "delete_account_v1",
            {"p_user_id": "owner-1", "p_confirmation": "DELETE"},
        ),
    ]
    assert client.select_calls == []


def test_delete_treats_not_found_as_idempotent_convergence() -> None:
    client = Client()
    repository = SupabaseAccountRepository(client)  # type: ignore[arg-type]

    client.rpc_result = {
        "deleted": False,
        "not_found": True,
        "user_id": "owner-1",
    }
    asyncio.run(
        repository.delete_account(user_id="owner-1", confirmation="DELETE"),
    )
    assert client.select_calls == []


def test_delete_invalid_rpc_owner_uses_ambiguous_readback() -> None:
    client = Client()
    repository = SupabaseAccountRepository(client)  # type: ignore[arg-type]

    client.rpc_outcomes = [
        {"deleted": True, "not_found": False, "user_id": "other-owner"},
        {"deleted": False, "not_found": True, "user_id": "owner-1"},
    ]
    asyncio.run(
        repository.delete_account(user_id="owner-1", confirmation="DELETE"),
    )


def test_delete_response_loss_converges_when_profile_is_absent() -> None:
    client = Client()
    client.rpc_outcomes = [
        httpx.ReadError("response lost"),
        {"deleted": False, "not_found": True, "user_id": "owner-1"},
    ]
    repository = SupabaseAccountRepository(client)  # type: ignore[arg-type]

    asyncio.run(
        repository.delete_account(user_id="owner-1", confirmation="DELETE"),
    )

    assert client.rpc_calls == [
        (
            "delete_account_v1",
            {"p_user_id": "owner-1", "p_confirmation": "DELETE"},
        ),
    ] * 2
    assert client.select_calls == []


def test_delete_invalid_response_and_5xx_converge_when_profile_is_absent() -> None:
    for error in [ValueError("invalid JSON"), _http_error(503)]:
        client = Client()
        client.rpc_outcomes = [
            error,
            {"deleted": False, "not_found": True, "user_id": "owner-1"},
        ]
        repository = SupabaseAccountRepository(client)  # type: ignore[arg-type]

        asyncio.run(
            repository.delete_account(user_id="owner-1", confirmation="DELETE"),
        )

        assert len(client.rpc_calls) == 2
        assert client.select_calls == []


def test_delete_response_loss_never_treats_an_mvcc_profile_read_as_non_commit() -> None:
    client = Client()
    client.rpc_outcomes = [
        httpx.ReadError("response lost"),
        httpx.ReadError("replay response lost"),
    ]
    repository = SupabaseAccountRepository(client)  # type: ignore[arg-type]

    with pytest.raises(AccountDeletionOutcomeUnknownError, match="determined"):
        asyncio.run(
            repository.delete_account(user_id="owner-1", confirmation="DELETE"),
        )

    assert client.select_calls == []


def test_delete_response_loss_has_explicit_unknown_outcome_on_failed_readback() -> None:
    client = Client()
    client.rpc_outcomes = [
        httpx.ReadError("response lost"),
        _http_error(),
    ]
    repository = SupabaseAccountRepository(client)  # type: ignore[arg-type]

    with pytest.raises(AccountDeletionOutcomeUnknownError, match="determined"):
        asyncio.run(
            repository.delete_account(user_id="owner-1", confirmation="DELETE"),
        )


def test_delete_response_loss_rejects_an_invalid_replay_owner() -> None:
    client = Client()
    client.rpc_outcomes = [
        httpx.ReadError("response lost"),
        {"deleted": True, "not_found": False, "user_id": "other-owner"},
    ]
    repository = SupabaseAccountRepository(client)  # type: ignore[arg-type]

    with pytest.raises(AccountDeletionOutcomeUnknownError, match="determined"):
        asyncio.run(
            repository.delete_account(user_id="owner-1", confirmation="DELETE"),
        )


def test_delete_known_rpc_error_does_not_attempt_ambiguous_readback() -> None:
    client = Client()
    client.rpc_error = _http_error(409)
    repository = SupabaseAccountRepository(client)  # type: ignore[arg-type]

    with pytest.raises(AccountPersistenceError, match="could not be completed"):
        asyncio.run(
            repository.delete_account(user_id="owner-1", confirmation="DELETE"),
        )

    assert client.select_calls == []


def test_repository_maps_upstream_details_to_sanitized_error() -> None:
    client = Client()
    client.rpc_error = _http_error(400)
    repository = SupabaseAccountRepository(client)  # type: ignore[arg-type]

    with pytest.raises(AccountPersistenceError) as captured:
        asyncio.run(
            repository.delete_account(user_id="owner-1", confirmation="DELETE"),
        )

    assert "secret" not in str(captured.value)
