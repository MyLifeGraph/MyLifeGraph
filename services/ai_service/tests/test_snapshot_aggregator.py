import asyncio
from dataclasses import replace
from datetime import date, datetime, timezone

import httpx

from app.api.deps.auth import Principal
from app.main import create_app
from app.models.snapshots import SnapshotGenerateRequest, SnapshotGenerateResponse
from app.repositories.snapshot_repository import (
    SnapshotInputRows,
    SupabaseSnapshotRepository,
)
from app.services.snapshot_aggregator import SnapshotAggregator


TODAY = date(2026, 7, 2)
NOW = datetime(2026, 7, 2, 12, tzinfo=timezone.utc)


class FakeSnapshotRepository:
    def __init__(self, inputs: SnapshotInputRows | None = None) -> None:
        self.inputs = inputs or sample_inputs()
        self.load_calls: list[dict[str, object]] = []
        self.persist_calls: list[dict[str, object]] = []

    async def load_snapshot_inputs(
        self,
        *,
        user_id: str,
        target_date: date,
        window_days: int,
    ) -> SnapshotInputRows:
        self.load_calls.append(
            {
                "user_id": user_id,
                "target_date": target_date,
                "window_days": window_days,
            },
        )
        return self.inputs

    async def persist_user_state_snapshot(
        self,
        *,
        user_id: str,
        scope: str,
        period_key: str,
        row: dict,
    ) -> dict:
        self.persist_calls.append(
            {
                "user_id": user_id,
                "scope": scope,
                "period_key": period_key,
                "row": row,
            },
        )
        return {"id": "snapshot-123", **row}


class FakeSupabaseClient:
    def __init__(self, existing_snapshot: bool = False) -> None:
        self.existing_snapshot = existing_snapshot
        self.select_calls = []
        self.insert_calls: list[tuple[str, list[dict]]] = []
        self.update_calls: list[tuple[str, dict, dict[str, str]]] = []
        self.upsert_calls: list[tuple[str, list[dict], str | None]] = []

    async def select(self, table: str, *, params):
        self.select_calls.append((table, params))
        if table == "user_state_snapshots":
            return [{"id": "existing-snapshot"}] if self.existing_snapshot else []
        return []

    async def insert(self, table: str, *, rows: list[dict]):
        self.insert_calls.append((table, rows))
        return [{"id": "new-snapshot", **rows[0]}]

    async def update(self, table: str, *, values: dict, params: dict[str, str]):
        self.update_calls.append((table, values, params))
        return [{"id": "existing-snapshot", **values}]

    async def upsert(
        self,
        table: str,
        *,
        rows: list[dict],
        on_conflict: str | None = None,
    ):
        self.upsert_calls.append((table, rows, on_conflict))
        return [{"id": "upserted-snapshot", **rows[0]}]


class FakePagedSnapshotClient(FakeSupabaseClient):
    def __init__(self) -> None:
        super().__init__()
        self.rows_by_table = {
            "habit_logs": [{"id": f"habit-log-{index}"} for index in range(1005)],
            "focus_sessions": [
                {"id": f"focus-session-{index}"} for index in range(1002)
            ],
        }

    async def select(self, table: str, *, params):
        self.select_calls.append((table, params))
        rows = self.rows_by_table.get(table, [])
        offsets = _param_values(params, "offset")
        limits = _param_values(params, "limit")
        offset = int(offsets[-1]) if offsets else 0
        limit = int(limits[-1]) if limits else len(rows)
        return rows[offset : offset + limit]


class FakeTokenVerifier:
    async def verify(self, token: str) -> Principal | None:
        if token == "valid-test-token":
            return Principal(user_id="user-test-123")
        return None


class FakeSnapshotAggregator:
    def __init__(self) -> None:
        self.calls: list[tuple[str, SnapshotGenerateRequest]] = []

    async def generate_snapshot(
        self,
        *,
        user_id: str,
        request: SnapshotGenerateRequest,
    ) -> SnapshotGenerateResponse:
        self.calls.append((user_id, request))
        return SnapshotGenerateResponse(
            snapshot_id="snapshot-123",
            scope=request.scope,
            period_key="2026-07-02",
            generated_at=NOW,
            summary={"recommended_next_focus": "recovery"},
            signals={"input_counts": {"daily_logs": 2}},
        )


def run(coro):
    return asyncio.run(coro)


def sample_inputs() -> SnapshotInputRows:
    return SnapshotInputRows(
        daily_logs=[
            {
                "id": "log-1",
                "entry_date": "2026-07-02",
                "sleep_hours": 5.75,
                "steps": 2000,
                "activity_level": 3,
                "focus_minutes": 20,
                "mood_score": 4,
                "energy_level": 3,
                "stress_level": 8,
            },
            {
                "id": "log-2",
                "entry_date": "2026-07-01",
                "sleep_hours": 6,
                "steps": 3000,
                "activity_level": 4,
                "focus_minutes": 25,
                "mood_score": 5,
                "energy_level": 4,
                "stress_level": 7,
            },
        ],
        behavioral_events=[
            {
                "id": "event-1",
                "event_type": "quick_mood_check_in",
                "occurred_at": "2026-07-02T09:00:00+00:00",
                "source": "app",
            },
        ],
        tasks=[
            {
                "id": "task-1",
                "status": "todo",
                "priority": "high",
                "deadline": "2026-07-01T12:00:00+00:00",
                "metadata": {},
            },
            {
                "id": "task-2",
                "status": "done",
                "priority": "medium",
                "deadline": "2026-07-02T12:00:00+00:00",
                "metadata": {},
            },
        ],
        goals=[
            {"id": "goal-1", "title": "Protect focus", "status": "active"},
        ],
        habits=[
            {"id": "habit-1", "title": "Walk", "frequency": "daily", "active": True},
        ],
        habit_logs=[
            {
                "id": "habit-log-1",
                "habit_id": "habit-1",
                "entry_date": "2026-07-02",
                "status": "completed",
                "value": 1,
            },
            {
                "id": "habit-log-2",
                "habit_id": "habit-1",
                "entry_date": "2026-07-01",
                "status": "skipped",
                "value": 0,
            },
        ],
        focus_sessions=[
            {
                "id": "focus-1",
                "status": "completed",
                "started_at": "2026-07-02T08:00:00+00:00",
                "ended_at": "2026-07-02T08:50:00+00:00",
                "planned_minutes": 50,
                "actual_minutes": 50,
            },
            {
                "id": "focus-2",
                "status": "active",
                "started_at": "2026-07-02T11:45:00+00:00",
                "ended_at": None,
                "planned_minutes": 25,
                "actual_minutes": None,
            },
            {
                "id": "focus-3",
                "status": "abandoned",
                "started_at": "2026-07-01T15:00:00+00:00",
                "ended_at": "2026-07-01T15:05:00+00:00",
                "planned_minutes": 25,
                "actual_minutes": 5,
            },
        ],
        schedule_items=[
            {"id": "schedule-1", "title": "Math", "weekday": 4},
        ],
        memory_entries=[
            {"id": "memory-1", "type": "goal", "title": "Goal"},
        ],
    )


def make_app(aggregator: FakeSnapshotAggregator | None = None):
    app = create_app()
    app.state.token_verifier = FakeTokenVerifier()
    app.state.snapshot_aggregator = aggregator or FakeSnapshotAggregator()
    return app


async def request(
    method: str,
    url: str,
    *,
    headers: dict[str, str] | None = None,
    json: dict[str, object] | None = None,
    aggregator: FakeSnapshotAggregator | None = None,
) -> httpx.Response:
    transport = httpx.ASGITransport(app=make_app(aggregator))
    async with httpx.AsyncClient(
        transport=transport,
        base_url="http://testserver",
    ) as client:
        return await client.request(method, url, headers=headers, json=json)


def test_generate_daily_snapshot_builds_compact_summary_and_persists_by_principal():
    repository = FakeSnapshotRepository()
    response = run(
        SnapshotAggregator(
            repository=repository,
            today_provider=lambda: TODAY,
            now_provider=lambda: NOW,
        ).generate_snapshot(
            user_id="principal-user-123",
            request=SnapshotGenerateRequest(),
        ),
    )

    assert response.snapshot_id == "snapshot-123"
    assert response.scope == "daily"
    assert response.period_key == "2026-07-02"
    assert repository.load_calls == [
        {
            "user_id": "principal-user-123",
            "target_date": TODAY,
            "window_days": 7,
        },
    ]
    persisted = repository.persist_calls[0]
    assert persisted["user_id"] == "principal-user-123"
    assert persisted["scope"] == "daily"
    assert persisted["period_key"] == "2026-07-02"
    row = persisted["row"]
    assert row["user_id"] == "principal-user-123"
    assert row["summary"]["sleep"]["average_hours"] == 5.88
    assert row["summary"]["tasks"]["overdue"] == 1
    assert row["summary"]["habits"] == {
        "active": 1,
        "outcome_counts": {"completed": 1, "skipped": 1, "unknown": 0},
    }
    assert row["summary"]["focus_sessions"] == {
        "count": 3,
        "status_counts": {
            "active": 1,
            "completed": 1,
            "abandoned": 1,
            "unknown": 0,
        },
        "planned_minutes": 100,
        "actual_minutes": 55,
        "completed_minutes": 50,
        "abandoned_minutes": 5,
    }
    assert row["summary"]["recommended_next_focus"] == "recovery"
    assert row["summary"]["daily_state"]["mode"] == "recover"
    assert row["summary"]["daily_state"]["data_quality"] == "partial"
    assert row["summary"]["daily_state"]["provenance"] == {
        "kind": "deterministic",
        "basis": "legacy_numeric",
        "baseline": "none",
        "history_claim": "current_state_only",
    }
    assert row["metadata"]["daily_state_contract_version"] == (
        "explainable-daily-state-v1"
    )
    assert row["metadata"]["state_lookback_days"] == 7
    assert row["signals"]["input_counts"]["daily_logs"] == 2
    assert row["signals"]["input_counts"]["habit_logs"] == 2
    assert row["signals"]["input_counts"]["focus_sessions"] == 3
    assert row["signals"]["habit_outcome_counts"] == {
        "completed": 1,
        "skipped": 1,
        "unknown": 0,
    }
    assert row["signals"]["focus_session_status_counts"] == {
        "active": 1,
        "completed": 1,
        "abandoned": 1,
        "unknown": 0,
    }
    assert row["signals"]["daily_state"]["engine"] == "deterministic"
    assert {"table": "daily_logs", "id": "log-1"} in row["signals"]["evidence_refs"]
    assert {"table": "habit_logs", "id": "habit-log-1"} in row["signals"][
        "evidence_refs"
    ]
    assert {"table": "focus_sessions", "id": "focus-1"} in row["signals"][
        "evidence_refs"
    ]


def test_snapshot_keeps_unknown_action_rows_neutral() -> None:
    inputs = replace(
        sample_inputs(),
        habit_logs=[
            {
                "id": "legacy-zero",
                "habit_id": "habit-1",
                "entry_date": "2026-07-02",
                "value": 0,
            },
        ],
        focus_sessions=[
            {
                "id": "future-status",
                "status": "paused",
                "started_at": "2026-07-02T09:00:00+00:00",
                "planned_minutes": -25,
                "actual_minutes": -5,
            },
        ],
    )

    response = run(
        SnapshotAggregator(
            repository=FakeSnapshotRepository(inputs),
            today_provider=lambda: TODAY,
            now_provider=lambda: NOW,
        ).generate_snapshot(
            user_id="principal-user-123",
            request=SnapshotGenerateRequest(),
        ),
    )

    assert response.summary["habits"]["outcome_counts"] == {
        "completed": 0,
        "skipped": 0,
        "unknown": 1,
    }
    assert response.summary["focus_sessions"] == {
        "count": 1,
        "status_counts": {
            "active": 0,
            "completed": 0,
            "abandoned": 0,
            "unknown": 1,
        },
        "planned_minutes": 0,
        "actual_minutes": 0,
        "completed_minutes": 0,
        "abandoned_minutes": 0,
    }


def test_generate_weekly_snapshot_uses_iso_week_period_key():
    repository = FakeSnapshotRepository()
    response = run(
        SnapshotAggregator(
            repository=repository,
            today_provider=lambda: TODAY,
            now_provider=lambda: NOW,
        ).generate_snapshot(
            user_id="principal-user-123",
            request=SnapshotGenerateRequest(scope="weekly", window_days=14),
        ),
    )

    assert response.scope == "weekly"
    assert response.period_key == "2026-W27"
    assert repository.persist_calls[0]["period_key"] == "2026-W27"
    assert repository.persist_calls[0]["row"]["summary"]["window"]["days"] == 14


def test_daily_and_weekly_snapshots_share_target_date_daily_state() -> None:
    repository = FakeSnapshotRepository()
    aggregator = SnapshotAggregator(
        repository=repository,
        today_provider=lambda: TODAY,
        now_provider=lambda: NOW,
    )

    daily = run(
        aggregator.generate_snapshot(
            user_id="principal-user-123",
            request=SnapshotGenerateRequest(scope="daily", target_date=TODAY),
        ),
    )
    weekly = run(
        aggregator.generate_snapshot(
            user_id="principal-user-123",
            request=SnapshotGenerateRequest(scope="weekly", target_date=TODAY),
        ),
    )

    assert weekly.summary["daily_state"] == daily.summary["daily_state"]
    assert weekly.signals["daily_state"] == daily.signals["daily_state"]
    assert weekly.summary["daily_state"]["target_date"] == TODAY.isoformat()


def test_action_outcomes_do_not_change_phase_two_daily_state() -> None:
    inputs = sample_inputs()
    with_actions = run(
        SnapshotAggregator(
            repository=FakeSnapshotRepository(inputs),
            today_provider=lambda: TODAY,
            now_provider=lambda: NOW,
        ).generate_snapshot(
            user_id="principal-user-123",
            request=SnapshotGenerateRequest(),
        ),
    )
    without_actions = run(
        SnapshotAggregator(
            repository=FakeSnapshotRepository(
                replace(inputs, habit_logs=[], focus_sessions=[]),
            ),
            today_provider=lambda: TODAY,
            now_provider=lambda: NOW,
        ).generate_snapshot(
            user_id="principal-user-123",
            request=SnapshotGenerateRequest(),
        ),
    )

    assert with_actions.summary["daily_state"] == without_actions.summary[
        "daily_state"
    ]
    assert with_actions.signals["daily_state"] == without_actions.signals[
        "daily_state"
    ]


def test_generate_snapshot_ignores_logs_outside_target_window():
    inputs = sample_inputs()
    inputs.daily_logs.append(
        {
            "id": "future-log",
            "entry_date": "2026-07-03",
            "sleep_hours": 10,
            "focus_minutes": 999,
            "energy_level": 10,
            "stress_level": 0,
        },
    )
    inputs.behavioral_events.append(
        {
            "id": "future-event",
            "event_type": "future",
            "occurred_at": "2026-07-03T09:00:00+00:00",
            "source": "app",
        },
    )
    inputs.habit_logs.append(
        {
            "id": "future-habit-log",
            "habit_id": "habit-1",
            "entry_date": "2026-07-03",
            "status": "completed",
            "value": 1,
        },
    )
    inputs.focus_sessions.append(
        {
            "id": "future-focus",
            "status": "completed",
            "started_at": "2026-07-03T09:00:00+00:00",
            "planned_minutes": 90,
            "actual_minutes": 90,
        },
    )
    repository = FakeSnapshotRepository(inputs)

    response = run(
        SnapshotAggregator(
            repository=repository,
            today_provider=lambda: TODAY,
            now_provider=lambda: NOW,
        ).generate_snapshot(
            user_id="principal-user-123",
            request=SnapshotGenerateRequest(target_date=TODAY, window_days=7),
        ),
    )

    assert response.summary["focus"]["total_minutes"] == 45
    assert response.signals["input_counts"]["daily_logs"] == 2
    assert response.signals["event_type_counts"] == {"quick_mood_check_in": 1}
    assert response.signals["input_counts"]["habit_logs"] == 2
    assert response.signals["input_counts"]["focus_sessions"] == 3


def test_snapshot_event_window_prefers_local_entry_date_with_utc_fallback():
    inputs = replace(
        sample_inputs(),
        behavioral_events=[
            {
                "id": "local-morning",
                "event_type": "local_morning",
                "occurred_at": "2026-07-01T22:30:00+00:00",
                "source": "quick_check_in",
                "metadata": {"entry_date": "2026-07-02"},
            },
            {
                "id": "next-local-day",
                "event_type": "next_local_day",
                "occurred_at": "2026-07-02T22:30:00+00:00",
                "source": "quick_check_in",
                "metadata": {"entry_date": "2026-07-03"},
            },
            {
                "id": "utc-fallback",
                "event_type": "utc_fallback",
                "occurred_at": "2026-07-02T09:00:00+00:00",
                "source": "legacy",
            },
            {
                "id": "invalid-metadata-fallback",
                "event_type": "invalid_metadata_fallback",
                "occurred_at": "2026-07-02T10:00:00+00:00",
                "source": "legacy",
                "metadata": {"entry_date": "not-a-date"},
            },
        ],
    )
    repository = FakeSnapshotRepository(inputs)

    response = run(
        SnapshotAggregator(
            repository=repository,
            today_provider=lambda: TODAY,
            now_provider=lambda: NOW,
        ).generate_snapshot(
            user_id="principal-user-123",
            request=SnapshotGenerateRequest(target_date=TODAY, window_days=1),
        ),
    )

    assert response.signals["event_type_counts"] == {
        "local_morning": 1,
        "utc_fallback": 1,
        "invalid_metadata_fallback": 1,
    }


def test_snapshot_focus_window_prefers_local_entry_date_with_utc_fallback():
    inputs = replace(
        sample_inputs(),
        focus_sessions=[
            {
                "id": "local-morning-focus",
                "status": "completed",
                "started_at": "2026-07-01T22:30:00+00:00",
                "planned_minutes": 25,
                "actual_minutes": 20,
                "metadata": {"entry_date": "2026-07-02"},
            },
            {
                "id": "next-local-day-focus",
                "status": "completed",
                "started_at": "2026-07-02T22:30:00+00:00",
                "planned_minutes": 25,
                "actual_minutes": 20,
                "metadata": {"entry_date": "2026-07-03"},
            },
            {
                "id": "utc-focus-fallback",
                "status": "active",
                "started_at": "2026-07-02T09:00:00+00:00",
                "planned_minutes": 25,
                "actual_minutes": None,
            },
            {
                "id": "invalid-focus-metadata-fallback",
                "status": "abandoned",
                "started_at": "2026-07-02T10:00:00+00:00",
                "planned_minutes": 25,
                "actual_minutes": 5,
                "metadata": {"entry_date": "not-a-date"},
            },
            {
                "id": "offset-crosses-utc-day",
                "status": "completed",
                "started_at": "2026-07-02T00:30:00+02:00",
                "planned_minutes": 25,
                "actual_minutes": 20,
            },
            {
                "id": "timestamp-shaped-entry-date-must-fallback",
                "status": "completed",
                "started_at": "2026-07-01T10:00:00+00:00",
                "planned_minutes": 25,
                "actual_minutes": 20,
                "metadata": {"entry_date": "2026-07-02T00:00:00Z"},
            },
        ],
    )

    response = run(
        SnapshotAggregator(
            repository=FakeSnapshotRepository(inputs),
            today_provider=lambda: TODAY,
            now_provider=lambda: NOW,
        ).generate_snapshot(
            user_id="principal-user-123",
            request=SnapshotGenerateRequest(target_date=TODAY, window_days=1),
        ),
    )

    assert response.signals["input_counts"]["focus_sessions"] == 3
    assert response.signals["focus_session_status_counts"] == {
        "active": 1,
        "completed": 1,
        "abandoned": 1,
        "unknown": 0,
    }


def test_daily_state_uses_fixed_seven_day_lookback_without_widening_aggregates():
    inputs = sample_inputs()
    repository = FakeSnapshotRepository(inputs)

    response = run(
        SnapshotAggregator(
            repository=repository,
            today_provider=lambda: TODAY,
            now_provider=lambda: NOW,
        ).generate_snapshot(
            user_id="principal-user-123",
            request=SnapshotGenerateRequest(target_date=TODAY, window_days=1),
        ),
    )

    assert repository.load_calls[0]["window_days"] == 7
    assert response.summary["window"]["days"] == 1
    assert response.summary["check_ins"]["count"] == 1
    assert response.signals["input_counts"]["daily_logs"] == 1
    assert response.summary["daily_state"]["target_date"] == "2026-07-02"


def test_unmeasured_focus_does_not_create_a_low_focus_risk() -> None:
    inputs = sample_inputs()
    for row in inputs.daily_logs:
        row["focus_minutes"] = None
    repository = FakeSnapshotRepository(inputs)

    response = run(
        SnapshotAggregator(
            repository=repository,
            today_provider=lambda: TODAY,
            now_provider=lambda: NOW,
        ).generate_snapshot(
            user_id="principal-user-123",
            request=SnapshotGenerateRequest(),
        ),
    )

    assert response.summary["focus"] == {
        "total_minutes": 0,
        "measured_days": 0,
    }
    assert "low_focus_time" not in response.summary["window_risk_flags"]


def test_snapshot_repository_scopes_every_read_to_explicit_user_id():
    client = FakeSupabaseClient()
    repository = SupabaseSnapshotRepository(client)

    run(
        repository.load_snapshot_inputs(
            user_id="user-test-123",
            target_date=TODAY,
            window_days=7,
        ),
    )

    assert {table for table, _ in client.select_calls} == {
        "daily_logs",
        "behavioral_events",
        "tasks",
        "goals",
        "habits",
        "habit_logs",
        "focus_sessions",
        "schedule_items",
        "memory_entries",
    }
    assert all(
        _param_values(params, "user_id") == ["eq.user-test-123"]
        for _, params in client.select_calls
    )


def test_snapshot_repository_reads_metadata_and_widens_event_utc_bounds():
    client = FakeSupabaseClient()
    repository = SupabaseSnapshotRepository(client)

    run(
        repository.load_snapshot_inputs(
            user_id="user-test-123",
            target_date=TODAY,
            window_days=7,
        ),
    )

    daily_params = _params_for_table(client, "daily_logs")
    event_params = _params_for_table(client, "behavioral_events")
    habit_log_params = _params_for_table(client, "habit_logs")
    focus_params = _params_for_table(client, "focus_sessions")
    assert _param_values(daily_params, "entry_date") == [
        "gte.2026-06-26",
        "lte.2026-07-02",
    ]
    assert _param_values(event_params, "occurred_at") == [
        "gte.2026-06-25T00:00:00+00:00",
        "lt.2026-07-04T00:00:00+00:00",
    ]
    assert _param_values(habit_log_params, "entry_date") == [
        "gte.2026-06-26",
        "lte.2026-07-02",
    ]
    assert _param_values(focus_params, "started_at") == [
        "gte.2026-06-25T00:00:00+00:00",
        "lt.2026-07-04T00:00:00+00:00",
    ]
    assert "status" in _param_values(habit_log_params, "select")[0].split(",")
    assert "status" in _param_values(focus_params, "select")[0].split(",")
    assert "metadata" in _param_values(focus_params, "select")[0].split(",")
    assert "metadata" in _param_values(daily_params, "select")[0].split(",")
    assert "metadata" in _param_values(event_params, "select")[0].split(",")
    assert _param_values(daily_params, "limit") == ["7"]
    assert _param_values(event_params, "limit") == ["200"]


def test_snapshot_repository_paginates_complete_action_fact_windows():
    client = FakePagedSnapshotClient()
    repository = SupabaseSnapshotRepository(client)

    inputs = run(
        repository.load_snapshot_inputs(
            user_id="user-test-123",
            target_date=TODAY,
            window_days=7,
        ),
    )

    assert len(inputs.habit_logs) == 1005
    assert len(inputs.focus_sessions) == 1002
    assert [
        _param_values(params, "offset")[-1]
        for table, params in client.select_calls
        if table == "habit_logs"
    ] == ["0", "1000"]
    assert [
        _param_values(params, "offset")[-1]
        for table, params in client.select_calls
        if table == "focus_sessions"
    ] == ["0", "1000"]


def test_snapshot_repository_upserts_existing_period_snapshot_atomically():
    client = FakeSupabaseClient(existing_snapshot=True)
    repository = SupabaseSnapshotRepository(client)

    row = run(
        repository.persist_user_state_snapshot(
            user_id="user-test-123",
            scope="daily",
            period_key="2026-07-02",
            row={
                "user_id": "user-test-123",
                "scope": "daily",
                "period_key": "2026-07-02",
                "summary": {},
                "signals": {},
            },
        ),
    )

    assert row["id"] == "upserted-snapshot"
    assert client.select_calls == []
    assert client.insert_calls == []
    assert client.update_calls == []
    assert client.upsert_calls == [
        (
            "user_state_snapshots",
            [
                {
                    "user_id": "user-test-123",
                    "scope": "daily",
                    "period_key": "2026-07-02",
                    "summary": {},
                    "signals": {},
                },
            ],
            "user_id,scope,period_key",
        ),
    ]


def _params_for_table(client: FakeSupabaseClient, table: str):
    return next(
        params for called_table, params in client.select_calls if called_table == table
    )


def _param_values(params, key: str) -> list[str]:
    if isinstance(params, dict):
        value = params.get(key)
        return [] if value is None else [value]
    return [value for name, value in params if name == key]


def test_generate_snapshot_without_authorization_returns_401() -> None:
    response = run(request("POST", "/v1/snapshots/generate", json={}))

    assert response.status_code == 401
    assert response.headers["www-authenticate"] == "Bearer"


def test_generate_snapshot_with_fake_principal_matches_contract() -> None:
    aggregator = FakeSnapshotAggregator()
    response = run(
        request(
            "POST",
            "/v1/snapshots/generate",
            headers={"Authorization": "Bearer valid-test-token"},
            json={"scope": "daily", "target_date": "2026-07-02"},
            aggregator=aggregator,
        ),
    )

    assert response.status_code == 200
    assert response.json()["snapshot_id"] == "snapshot-123"
    assert aggregator.calls[0][0] == "user-test-123"
    assert aggregator.calls[0][1].target_date == TODAY


def test_generate_snapshot_rejects_request_user_id() -> None:
    response = run(
        request(
            "POST",
            "/v1/snapshots/generate",
            headers={"Authorization": "Bearer valid-test-token"},
            json={
                "scope": "daily",
                "target_date": "2026-07-02",
                "user_id": "attacker-controlled",
            },
        ),
    )

    assert response.status_code == 422
