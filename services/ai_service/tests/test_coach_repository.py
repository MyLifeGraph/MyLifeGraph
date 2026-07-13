import asyncio
from datetime import UTC, date, datetime, timedelta
from uuid import UUID

from app.repositories.coach_context_repository import SupabaseCoachContextRepository
from app.repositories.coach_repository import SupabaseCoachRepository


USER_ID = "11111111-1111-4111-8111-111111111111"
REQUEST_ID = UUID("22222222-2222-4222-8222-222222222222")
NOW = datetime(2026, 7, 13, 8, tzinfo=UTC)


class Client:
    def __init__(self) -> None:
        self.select_calls = []
        self.rpc_calls = []

    async def rpc(self, function, *, params):
        self.rpc_calls.append((function, params))
        return {
            "state": "pending",
            "remaining_requests": 19,
            "response": None,
            "error": None,
        }

    async def select(self, table, *, params):
        self.select_calls.append((table, params))
        values = dict(params)
        if table == "coach_memory_selections":
            return [
                {
                    "memory_id": "00000000-0000-4000-8000-000000000104",
                    "selected_at": "2026-07-13T08:00:00Z",
                },
            ]
        if table == "memory_entries" and "id" in values:
            ids = values["id"].removeprefix("in.(").removesuffix(")").split(",")
            return [_memory(int(memory_id.rsplit("-", 1)[1])) for memory_id in ids]
        if table == "memory_entries":
            offset = int(values.get("offset", 0))
            return [_memory(index) for index in range(offset, 105)]
        if table == "coach_usage_events":
            raise AssertionError("Capability counts retained requests, not usage rows")
        if table == "coach_requests" and values.get("select") == "request_id":
            return [{"request_id": str(index)} for index in range(7)]
        raise AssertionError((table, params))


def test_claim_uses_exact_rpc_boundary_without_persisting_message() -> None:
    client = Client()
    repository = SupabaseCoachRepository(client)
    result = asyncio.run(
        repository.claim_request(
            user_id=USER_ID,
            request_id=REQUEST_ID,
            message_fingerprint="a" * 64,
            context_scope="today",
            local_date=date(2026, 7, 13),
            provider="fake",
            provider_mode="deterministic_test_only",
            model_requested=None,
            model_source="not_applicable",
            prompt_version="controlled-coach-prompt-v1",
            context_version="coach-context-v1",
            claimed_at=NOW,
            lease_expires_at=NOW + timedelta(seconds=100),
            daily_limit=20,
        ),
    )
    assert result.state == "pending"
    function, params = client.rpc_calls[0]
    assert function == "claim_coach_request_v1"
    assert set(params) == {
        "p_user_id",
        "p_request_id",
        "p_message_fingerprint",
        "p_context_scope",
        "p_local_date",
        "p_provider",
        "p_provider_mode",
        "p_model_requested",
        "p_model_source",
        "p_prompt_version",
        "p_context_version",
        "p_claimed_at",
        "p_lease_expires_at",
        "p_daily_limit",
    }
    assert "p_message" not in params


def test_memory_preview_keeps_old_selected_memory_visible() -> None:
    client = Client()
    result = asyncio.run(SupabaseCoachRepository(client).list_memories(user_id=USER_ID))
    assert result.available_count == 105
    assert len(result.rows) == 101
    assert result.rows[0]["id"].endswith("104")
    assert result.rows[0]["selected_at"] == "2026-07-13T08:00:00Z"
    memory_queries = [
        params for table, params in client.select_calls if table == "memory_entries"
    ]
    assert all(
        dict(params).get("type") == "neq.preference" for params in memory_queries
    )


def test_memory_preview_explicitly_includes_deselected_target_outside_top_100() -> None:
    client = Client()
    target_id = UUID("00000000-0000-4000-8000-000000000103")

    result = asyncio.run(
        SupabaseCoachRepository(client).list_memories(
            user_id=USER_ID,
            include_memory_id=target_id,
        ),
    )

    matches = [row for row in result.rows if row["id"] == str(target_id)]
    assert len(matches) == 1
    assert matches[0]["selected_at"] is None
    assert result.available_count == 105


def test_capability_count_matches_retained_request_budget() -> None:
    client = Client()
    count = asyncio.run(
        SupabaseCoachRepository(client).count_usage(
            user_id=USER_ID,
            local_date=date(2026, 7, 13),
        ),
    )
    assert count == 7
    table, params = client.select_calls[0]
    assert table == "coach_requests"
    assert "state" not in params


class HistoryClient:
    async def select(self, table, *, params):
        values = dict(params)
        if table == "coach_requests":
            offset = int(values.get("offset", 0))
            if offset:
                return []
            return [
                {
                    "request_id": f"00000000-0000-4000-8000-{index:012d}",
                    "response": {"reply": f"reply {index}"},
                    "completed_at": f"2026-07-13T{index % 24:02d}:00:00Z",
                }
                for index in range(50)
            ]
        if table == "coach_messages":
            ids = values["request_id"].removeprefix("in.(").removesuffix(")").split(",")
            return [
                {"request_id": request_id, "content": f"message {index}"}
                for index, request_id in enumerate(ids)
            ]
        raise AssertionError(table)


def test_context_history_reports_all_available_rows_but_includes_six() -> None:
    result = asyncio.run(
        SupabaseCoachContextRepository(HistoryClient())._history(user_id=USER_ID),
    )
    assert result.available_count == 50
    assert len(result.rows) == 6


class ContextTablesClient:
    def __init__(self) -> None:
        self.tables = []
        self.calls = []

    async def select(self, table, *, params):
        self.tables.append(table)
        self.calls.append((table, params))
        if table == "profiles":
            return [
                {
                    "timezone": "Europe/Berlin",
                    "role": "user",
                    "auth_provider": "email",
                },
            ]
        return []


def test_context_repository_never_queries_excluded_sensitive_sources() -> None:
    client = ContextTablesClient()
    asyncio.run(
        SupabaseCoachContextRepository(client).load_today_context(
            user_id=USER_ID,
            local_date="2026-07-13",
        ),
    )
    assert {
        "calendar_events",
        "calendar_imports",
        "intake_responses",
        "daily_logs",
        "notifications",
    }.isdisjoint(client.tables)


def test_profile_context_carries_server_verified_account_eligibility() -> None:
    client = ContextTablesClient()
    profile = asyncio.run(
        SupabaseCoachContextRepository(client).get_profile(user_id=USER_ID),
    )

    assert profile.timezone == "Europe/Berlin"
    assert profile.role == "user"
    assert profile.auth_provider == "email"
    assert profile.is_eligible_authenticated_account is True
    _, params = next(call for call in client.calls if call[0] == "profiles")
    assert dict(params)["select"] == "timezone,role,auth_provider"


def _memory(index: int) -> dict:
    return {
        "id": f"00000000-0000-4000-8000-{index:012d}",
        "type": "goal",
        "title": f"Memory {index}",
        "content": f"Content {index}",
        "metadata": {},
        "updated_at": "2026-07-13T08:00:00Z",
    }
