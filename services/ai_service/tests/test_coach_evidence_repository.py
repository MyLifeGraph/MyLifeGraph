import asyncio
from datetime import UTC, date, datetime
from decimal import Decimal

import pytest

from app.clients.supabase import SupabaseResponseTooLargeError
from app.repositories.coach_evidence_repository import (
    CoachEvidencePersistenceError,
    EvidenceRows,
    SupabaseCoachEvidenceRepository,
    _safe_daily_log,
)


class PagingClient:
    def __init__(self) -> None:
        self.calls = []
        self.count_calls = []

    async def select(self, table, *, params, max_response_bytes=None):
        self.calls.append((table, params, max_response_bytes))
        values = dict(params)
        return [
            {"id": f"row-{index}"}
            for index in range(int(values["limit"]))
        ]

    async def count_exact(self, table, *, params):
        self.count_calls.append((table, params))
        return 17


def test_bounded_reader_limits_examined_raw_rows_before_sanitizing() -> None:
    client = PagingClient()
    repository = SupabaseCoachEvidenceRepository(client)

    result = asyncio.run(
        repository._select_bounded(
            "daily_logs",
            params=[
                ("select", "id,entry_date"),
                ("user_id", "eq.owner"),
                ("order", "entry_date.asc,id.asc"),
            ],
            cap=2,
            sanitizer=lambda _: None,
        ),
    )

    assert result.rows == []
    assert result.partial is True
    assert result.available_count == 17
    assert sum(int(dict(params)["limit"]) for _, params, _ in client.calls) == 3
    assert {
        max_response_bytes
        for _, _, max_response_bytes in client.calls
    } == {4 * 1024 * 1024}
    assert client.count_calls == [
        (
            "daily_logs",
            [
                ("select", "id"),
                ("user_id", "eq.owner"),
            ],
        ),
    ]


def test_daily_sanitizer_drops_free_text_capture_ids_and_raw_clocks() -> None:
    result = _safe_daily_log(
        {
            "id": "daily",
            "entry_date": "2026-07-28",
            "sleep_hours": Decimal("7.5"),
            "steps": 9000,
            "activity_level": 6,
            "mood_score": 7,
            "energy_level": 6,
            "stress_level": 4,
            "metadata": {
                "captures": {
                    "morning": {
                        "branch_version": "daily-capture-v4",
                        "capture_kind": "morning",
                        "entry_date": "2026-07-28",
                        "capture_id": "secret-id",
                        "captured_at": "2026-07-28T07:00:00Z",
                        "estimated_sleep_started_at": "2026-07-27T23:00:00Z",
                        "woke_at": "2026-07-28T07:00:00Z",
                        "sleep_quality": 8,
                        "current_energy": 6,
                        "reflection": "SECRET",
                    },
                    "evening": {
                        "planned_sleep_time": "23:00",
                        "mood": 7,
                        "tomorrow_priority": "SECRET",
                    },
                },
            },
        },
    )

    serialized = str(result)
    assert "SECRET" not in serialized
    assert "secret-id" not in serialized
    assert "23:00" not in serialized
    assert "captured_at" not in serialized
    assert result["sleep_hours"] == 7.5
    assert result["sleep_quality"] == 8
    assert "id" not in result
    assert "morning" not in result
    assert "evening" not in result


class EmptyClient:
    def __init__(self) -> None:
        self.calls = []

    async def select(self, table, *, params, max_response_bytes=None):
        self.calls.append((table, params, max_response_bytes))
        return []


class TaskCountRepository(SupabaseCoachEvidenceRepository):
    async def _terminal_tasks(self, *, status, **kwargs):
        timestamp = (
            {"completed_at": "2026-07-20T08:00:00Z"}
            if status == "done"
            else {"cancelled_at": "2026-07-21T08:00:00Z"}
        )
        return EvidenceRows(
            rows=[{"id": status, "status": status, **timestamp}],
            available_count=101 if status == "done" else 75,
            partial=True,
        )


def test_terminal_task_manifest_sums_exact_counts_from_both_statuses() -> None:
    result = asyncio.run(
        TaskCountRepository(EmptyClient()).load_evidence(
            user_id="owner",
            starts_at=None,
            ends_at=datetime(2026, 7, 28, tzinfo=UTC),
            local_starts_on=None,
            local_ends_on=date(2026, 7, 28),
        ),
    )

    assert len(result.task_lifecycle.rows) == 2
    assert result.task_lifecycle.available_count == 176
    assert result.task_lifecycle.partial is True


def test_evidence_queries_are_owner_scoped_and_exclude_forbidden_tables() -> None:
    client = EmptyClient()
    repository = SupabaseCoachEvidenceRepository(client)

    asyncio.run(
        repository.load_evidence(
            user_id="owner",
            starts_at=None,
            ends_at=datetime(2026, 7, 28, tzinfo=UTC),
            local_starts_on=None,
            local_ends_on=date(2026, 7, 28),
        ),
    )

    tables = {table for table, _, _ in client.calls}
    assert {
        "calendar_events",
        "planner_task_blocks",
        "deadline_plan_blocks",
        "coach_messages",
    }.isdisjoint(tables)
    assert all(
        ("user_id", "eq.owner") in list(params)
        for _, params, _ in client.calls
    )


class LateReflectionClient:
    async def select(self, table, *, params, max_response_bytes=None):
        if table == "focus_sessions":
            return [
                {
                    "id": "11111111-1111-4111-8111-111111111111",
                    "status": "completed",
                    "started_at": "2026-07-26T18:00:00Z",
                    "ended_at": "2026-07-26T18:25:00Z",
                    "planned_minutes": 25,
                    "actual_minutes": 25,
                },
            ]
        if table == "focus_session_reflections":
            values = dict(params)
            assert "created_at" not in values
            assert values["focus_session_id"].startswith("in.(")
            return [
                {
                    "focus_session_id": (
                        "11111111-1111-4111-8111-111111111111"
                    ),
                    "contract_version": "focus-reflection-v1",
                    "focus_quality": 4,
                    "useful_progress": 5,
                    "obstacles": [],
                    "created_at": "2026-07-27T07:00:00Z",
                    "updated_at": "2026-07-27T07:00:00Z",
                },
            ]
        return []


def test_reflection_is_selected_by_in_window_session_not_reflection_time() -> None:
    result = asyncio.run(
        SupabaseCoachEvidenceRepository(LateReflectionClient()).load_evidence(
            user_id="owner",
            starts_at=datetime(2026, 7, 13, tzinfo=UTC),
            ends_at=datetime(2026, 7, 27, tzinfo=UTC),
            local_starts_on=date(2026, 7, 13),
            local_ends_on=date(2026, 7, 26),
        ),
    )

    assert len(result.focus_sessions.rows) == 1
    assert len(result.reflections.rows) == 1


class OversizedDailyMetadataClient:
    async def select(self, table, *, params, max_response_bytes=None):
        if table == "daily_logs":
            assert max_response_bytes == 4 * 1024 * 1024
            raise SupabaseResponseTooLargeError("oversized page")
        return []


def test_oversized_raw_evidence_page_fails_closed_before_sanitizing() -> None:
    repository = SupabaseCoachEvidenceRepository(
        OversizedDailyMetadataClient(),
    )

    with pytest.raises(CoachEvidencePersistenceError):
        asyncio.run(
            repository.load_evidence(
                user_id="owner",
                starts_at=None,
                ends_at=datetime(2026, 7, 28, tzinfo=UTC),
                local_starts_on=None,
                local_ends_on=date(2026, 7, 28),
            ),
        )
