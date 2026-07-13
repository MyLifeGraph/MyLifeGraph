import asyncio
from datetime import UTC, date, datetime
from typing import Any

import pytest

from app.repositories.weekly_review_repository import (
    SupabaseWeeklyReviewRepository,
    _weekly_review,
)


class FakeClient:
    def __init__(self) -> None:
        self.select_calls = []
        self.upsert_calls = []
        self.review_rows: list[dict[str, Any]] = []

    async def select(self, table: str, *, params):
        self.select_calls.append((table, params))
        if table == "profiles":
            return [
                {
                    "timezone": "Europe/Berlin",
                    "onboarding_completed_at": "2026-07-01T10:00:00+00:00",
                },
            ]
        if table == "weekly_reviews":
            return self.review_rows
        if table == "habit_logs":
            offset = int(dict(params)["offset"])
            if offset == 0:
                return [
                    {
                        "id": f"log-{index}",
                        "habit_id": "habit-1",
                        "entry_date": "2026-07-06",
                        "status": "completed",
                        "value": 1,
                        "created_at": "2026-07-06T10:00:00+00:00",
                        "updated_at": "2026-07-06T10:00:00+00:00",
                    }
                    for index in range(1000)
                ]
            if offset == 1000:
                return [
                    {
                        "id": "log-final",
                        "habit_id": "habit-1",
                        "entry_date": "2026-07-07",
                        "status": "skipped",
                        "value": 0,
                        "created_at": "2026-07-07T10:00:00+00:00",
                        "updated_at": "2026-07-07T10:00:00+00:00",
                    },
                ]
        return []

    async def upsert(self, table: str, *, rows, on_conflict: str):
        self.upsert_calls.append((table, rows, on_conflict))
        return [{"id": "review-1", **rows[0]}]


def test_profile_and_context_reads_are_owner_scoped_bounded_and_paginated() -> None:
    client = FakeClient()
    repository = SupabaseWeeklyReviewRepository(client)

    async def run():
        profile = await repository.get_profile(user_id="user-1")
        context = await repository.load_context(
            user_id="user-1",
            starts_on=date(2026, 7, 6),
            ends_on=date(2026, 7, 12),
            starts_at=datetime(2026, 7, 5, 22, tzinfo=UTC),
            ends_at=datetime(2026, 7, 12, 22, tzinfo=UTC),
        )
        return profile, context

    profile, context = asyncio.run(run())

    assert profile.timezone == "Europe/Berlin"
    assert profile.onboarded is True
    assert len(context.habit_logs) == 1001
    habit_log_calls = [
        dict(params)
        for table, params in client.select_calls
        if table == "habit_logs"
    ]
    assert [call["offset"] for call in habit_log_calls] == ["0", "1000"]
    assert all(call["user_id"] == "eq.user-1" for call in habit_log_calls)
    assert all(call["entry_date"] == "lte.2026-07-12" for call in habit_log_calls)

    task_calls = [
        params
        for table, params in client.select_calls
        if table == "tasks"
    ]
    assert len(task_calls) == 3
    task_filters = [dict(call) for call in task_calls]
    assert {call["status"] for call in task_filters} == {
        "in.(todo,in_progress)",
        "eq.done",
        "eq.cancelled",
    }
    assert task_filters[0]["created_at"] == "lt.2026-07-12T22:00:00+00:00"
    assert task_filters[1]["completed_at"] == "lt.2026-07-12T22:00:00+00:00"
    assert task_filters[2]["cancelled_at"] == "lt.2026-07-12T22:00:00+00:00"


def test_persisted_review_parser_normalizes_json_dates_and_timestamps() -> None:
    client = FakeClient()
    client.review_rows = [valid_review_row()]
    repository = SupabaseWeeklyReviewRepository(client)

    review = asyncio.run(
        repository.get_weekly_review(user_id="user-1", period_key="2026-W28"),
    )

    assert review is not None
    assert review.generated_at == datetime(2026, 7, 13, 8, tzinfo=UTC)
    assert review.provenance.evidence_window.starts_on == date(2026, 7, 6)
    assert review.provenance.source_snapshot_generated_at == datetime(
        2026,
        7,
        13,
        7,
        tzinfo=UTC,
    )
    assert review.proposals[0].expected_updated_at == datetime(
        2026,
        7,
        1,
        8,
        tzinfo=UTC,
    )
    assert review.proposals[0].change.before.cadence.scheduled_weekdays == []


def test_persisted_review_parser_rejects_cross_boundary_metadata() -> None:
    row = valid_review_row()
    row["source_fingerprint"] = "b" * 64
    with pytest.raises(ValueError, match="fingerprint"):
        _weekly_review(row)

    row = valid_review_row()
    row["provenance"]["evidence_window"]["ends_on"] = "2026-07-19"
    with pytest.raises(ValueError, match="evidence window"):
        _weekly_review(row)


def test_persist_uses_stable_user_period_identity() -> None:
    client = FakeClient()
    repository = SupabaseWeeklyReviewRepository(client)
    row = valid_review_row()
    row.pop("id")

    review = asyncio.run(
        repository.persist_weekly_review(
            user_id="user-1",
            period_key="2026-W28",
            row=row,
        ),
    )

    assert review.id == "review-1"
    table, rows, conflict = client.upsert_calls[0]
    assert table == "weekly_reviews"
    assert rows == [row]
    assert conflict == "user_id,period_key"


def valid_review_row() -> dict[str, Any]:
    return {
        "id": "review-1",
        "user_id": "user-1",
        "period_key": "2026-W28",
        "week_start": "2026-07-06",
        "week_end": "2026-07-12",
        "timezone": "Europe/Berlin",
        "data_quality": "sufficient",
        "narrative": "A bounded weekly review.",
        "facts": {
            "tasks": {
                "completed": 1,
                "carried": 1,
                "overdue_carried": 0,
                "cancelled": 0,
                "goal_linked_completed": 0,
            },
            "habits": {
                "active": 1,
                "paused": 0,
                "archived": 0,
                "stable_definitions": 1,
                "changed_definitions": 0,
                "scheduled_opportunities": 4,
                "completed": 2,
                "skipped": 0,
                "missed": 2,
                "recovery_open": 0,
                "unknown": 0,
            },
            "focus": {
                "completed_sessions": 0,
                "abandoned_sessions": 0,
                "active_sessions": 0,
                "actual_minutes": 0,
            },
            "recovery": {"observed_days": 7, "recovery_days": 0},
            "feedback": {
                "total": 1,
                "done": 0,
                "later": 0,
                "not_helpful": 0,
                "too_much": 1,
                "does_not_fit": 0,
            },
        },
        "proposals": [
            {
                "id": "weekly-review:2026-W28:habit:habit-1:shrink",
                "operation": "shrink",
                "target_kind": "habit",
                "target_id": "habit-1",
                "target_title": "Walk",
                "ownership": "manual",
                "application_mode": "direct_habit",
                "expected_updated_at": "2026-07-01T08:00:00+00:00",
                "reason_code": "habit_weekly_target_too_large",
                "reason": "The explicit feedback supports a smaller target.",
                "evidence_refs": [
                    {"table": "habits", "id": "habit-1", "field": "updated_at"},
                ],
                "change": {
                    "before": {
                        "lifecycle": "active",
                        "cadence": {
                            "kind": "weekly_target",
                            "weekly_target": 4,
                            "scheduled_weekdays": [],
                        },
                    },
                    "after": {
                        "lifecycle": "active",
                        "cadence": {
                            "kind": "weekly_target",
                            "weekly_target": 3,
                            "scheduled_weekdays": [],
                        },
                    },
                },
            },
        ],
        "evidence_refs": [
            {"table": "habits", "id": "habit-1", "field": "updated_at"},
        ],
        "provenance": {
            "engine": "deterministic",
            "contract_version": "weekly-review-v1",
            "source_snapshot_id": "snapshot-1",
            "source_snapshot_generated_at": "2026-07-13T07:00:00+00:00",
            "evidence_window": {
                "starts_on": "2026-07-06",
                "ends_on": "2026-07-12",
                "days": 7,
            },
            "source_fingerprint": "a" * 64,
            "baseline": "none",
            "limitations": [],
            "llm_used": False,
        },
        "source_fingerprint": "a" * 64,
        "generated_at": "2026-07-13T08:00:00+00:00",
        "created_at": "2026-07-13T08:00:00+00:00",
        "updated_at": "2026-07-13T08:00:00+00:00",
    }
