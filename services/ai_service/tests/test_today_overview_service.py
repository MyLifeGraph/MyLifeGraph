import asyncio
from datetime import UTC, date, datetime, timedelta
from uuid import UUID

from app.models.deadline_plans import DeadlinePlansResponse
from app.models.planner import (
    PlannerDay,
    PlannerDayItem,
    PlannerOverviewResponse,
    PlannerPreferencesResponse,
)
from app.repositories.today_overview_repository import (
    SupabaseTodayOverviewRepository,
    TodayCalendarRows,
    TodayHabitRows,
)
from app.services.today_overview_service import TodayOverviewService


NOW = datetime(2026, 7, 21, 20, tzinfo=UTC)
USER_ID = "today-owner"


class Repository:
    def __init__(self) -> None:
        self.daily_logs = []
        self.tasks = []
        self.habits = []
        self.habit_logs = []
        self.schedule_items = []
        self.focus_sessions = []
        self.calendar = TodayCalendarRows(source_label=None, events=[])
        self.fail_tasks = False
        self.capture_calls = []

    async def get_profile_timezone(self, *, user_id):
        assert user_id == USER_ID
        return "Europe/Berlin"

    async def list_daily_logs_page(self, *, user_id, offset, limit):
        assert user_id == USER_ID
        self.capture_calls.append((offset, limit))
        return self.daily_logs[offset : offset + limit]

    async def list_tasks(self, *, user_id):
        assert user_id == USER_ID
        if self.fail_tasks:
            raise RuntimeError("database detail must not leak")
        return self.tasks

    async def load_habits(self, *, user_id, week_starts_on, local_date):
        assert user_id == USER_ID
        assert week_starts_on == date(2026, 7, 20)
        assert local_date == date(2026, 7, 21)
        return TodayHabitRows(habits=self.habits, logs=self.habit_logs)

    async def list_schedule_items(self, *, user_id):
        assert user_id == USER_ID
        return self.schedule_items

    async def list_focus_sessions(
        self,
        *,
        user_id,
        range_starts_at,
        range_ends_at,
    ):
        assert user_id == USER_ID
        return self.focus_sessions

    async def load_current_calendar(self, *, user_id):
        assert user_id == USER_ID
        return self.calendar


class SelectClient:
    def __init__(self) -> None:
        self.calls = []

    async def select(self, table, *, params):
        self.calls.append((table, params))
        return []


class DeadlineService:
    async def list_plans(self, *, user_id):
        assert user_id == USER_ID
        return DeadlinePlansResponse(
            contract_version="deadline-plan-v1",
            origin="authenticated_backend",
            plans=[],
        )


def _service(repository: Repository) -> TodayOverviewService:
    return TodayOverviewService(
        repository=repository,
        deadline_plan_service=DeadlineService(),
        now=lambda: NOW,
    )


def test_today_schedule_read_includes_semester_metadata() -> None:
    client = SelectClient()
    repository = SupabaseTodayOverviewRepository(client)

    rows = asyncio.run(repository.list_schedule_items(user_id=USER_ID))

    assert rows == []
    params = next(
        params for table, params in client.calls if table == "schedule_items"
    )
    assert "metadata" in params["select"]


def _capture_row(entry_date: date, *, morning=True, evening=True, malformed=False):
    day = entry_date.isoformat()
    captures = {}
    if evening:
        captures["evening"] = {
            "capture_kind": "evening",
            "entry_date": day,
            "capture_id": f"evening-{day}",
            "captured_at": f"{day}T20:00:00+02:00",
            "mood": 7,
            "energy": 6,
            "stress_intensity": 4,
            "stress_intensity_label": "low",
            "main_friction": "unclear_priorities",
        }
    if morning:
        captures["morning"] = {
            "capture_kind": "morning",
            "entry_date": day,
            "capture_id": f"morning-{day}",
            "captured_at": f"{day}T20:05:00+02:00",
            "sleep_hours": 7.5,
            "current_energy": 8,
            "day_shape": "normal",
        }
    return {
        "id": str(UUID(int=entry_date.toordinal())),
        "entry_date": day,
        "sleep_hours": 7.5 if morning else None,
        "mood_score": 7 if evening else None,
        "energy_level": 8 if morning else (6 if evening else None),
        "stress_level": 4 if evening else None,
        "source": "quick_check_in",
        "metadata": {
            "capture_version": "wrong" if malformed else "daily-capture-v2",
            "captures": captures,
        },
        "updated_at": f"{day}T20:05:00+02:00",
    }


def test_streak_paginates_and_today_incomplete_is_a_grace_day() -> None:
    repository = Repository()
    today = date(2026, 7, 21)
    repository.daily_logs = [
        _capture_row(today, morning=True, evening=False),
        *[
            _capture_row(today - timedelta(days=offset))
            for offset in range(1, 126)
        ],
        _capture_row(today - timedelta(days=126), malformed=True),
    ]

    response = asyncio.run(_service(repository).get_overview(user_id=USER_ID))

    assert response.check_ins is not None
    assert response.check_ins.morning_saved is True
    assert response.check_ins.evening_saved is False
    assert response.check_ins.completed_days_streak == 125
    assert repository.capture_calls == [(0, 100), (100, 100)]
    assert response.progress == response.progress.model_copy(
        update={"completed": 1, "total": 2},
    )


def test_incomplete_previous_day_breaks_streak_and_legacy_does_not_count() -> None:
    repository = Repository()
    today = date(2026, 7, 21)
    legacy = _capture_row(today - timedelta(days=1))
    legacy["metadata"] = {}
    repository.daily_logs = [
        _capture_row(today),
        legacy,
        _capture_row(today - timedelta(days=2)),
    ]

    response = asyncio.run(_service(repository).get_overview(user_id=USER_ID))

    assert response.check_ins is not None
    assert response.check_ins.completed_days_streak == 1


def test_today_filters_tasks_and_habits_and_counts_only_completed_outcomes() -> None:
    repository = Repository()
    repository.daily_logs = [_capture_row(date(2026, 7, 21))]
    repository.tasks = [
        _task(
            "00000000-0000-4000-8000-000000000001",
            "Overdue",
            "todo",
            "2026-07-20T12:00:00Z",
        ),
        _task(
            "00000000-0000-4000-8000-000000000002",
            "Future active",
            "in_progress",
            "2026-08-01T12:00:00Z",
        ),
        _task(
            "00000000-0000-4000-8000-000000000003",
            "Future todo",
            "todo",
            "2026-08-01T12:00:00Z",
        ),
        _task(
            "00000000-0000-4000-8000-000000000004",
            "Done today",
            "done",
            None,
            completed_at="2026-07-21T08:00:00Z",
        ),
        _task(
            "00000000-0000-4000-8000-000000000005",
            "Managed plan",
            "in_progress",
            "2026-07-21T12:00:00Z",
            source="deadline-plan-v1",
        ),
    ]
    repository.habits = [
        _habit("10000000-0000-4000-8000-000000000001", "Daily", {"cadence": "daily"}),
        _habit(
            "10000000-0000-4000-8000-000000000002",
            "Tuesday",
            {"cadence": "weekdays", "scheduled_weekdays": [2]},
        ),
        _habit(
            "10000000-0000-4000-8000-000000000003",
            "Weekly",
            {"cadence": "weekly_target"},
            frequency="weekly",
            target=2,
        ),
    ]
    repository.habit_logs = [
        _habit_log("10000000-0000-4000-8000-000000000001", "completed"),
        _habit_log("10000000-0000-4000-8000-000000000002", "skipped"),
        _habit_log(
            "10000000-0000-4000-8000-000000000003",
            "completed",
            entry_date="2026-07-20",
        ),
    ]

    response = asyncio.run(_service(repository).get_overview(user_id=USER_ID))

    assert [task.title for task in response.tasks.today] == [
        "Overdue",
        "Future active",
        "Done today",
    ]
    assert len(response.tasks.all) == 5
    assert [habit.title for habit in response.habits] == ["Weekly", "Daily", "Tuesday"]
    assert response.progress is not None
    assert response.progress.total == 8  # two check-ins, three tasks, three habits
    # Both check-ins, one done task, and one completed daily habit.
    assert response.progress.completed == 4


def test_timeline_keeps_overlaps_and_all_day_first_with_distinct_sources() -> None:
    repository = Repository()
    repository.daily_logs = [_capture_row(date(2026, 7, 21))]
    repository.schedule_items = [
        {
            "id": "20000000-0000-4000-8000-000000000001",
            "title": "Late class",
            "location": "Campus",
            "weekday": 1,
            "starts_at": "23:30:00",
            "ends_at": "00:30:00",
            "source": "setup",
        },
        {
            "id": "20000000-0000-4000-8000-000000000002",
            "title": "Expired class",
            "location": "Campus",
            "weekday": 2,
            "starts_at": "08:00:00",
            "ends_at": "09:00:00",
            "source": "setup",
            "metadata": {
                "managed_by": "setup",
                "valid_until": "2026-07-20",
            },
        },
    ]
    repository.calendar = TodayCalendarRows(
        source_label="Studies",
        events=[
            {
                "id": "30000000-0000-4000-8000-000000000001",
                "title": "All-day event",
                "location": None,
                "event_kind": "all_day",
                "busy_status": "busy",
                "event_status": "confirmed",
                "starts_at": None,
                "ends_at": None,
                "starts_on": "2026-07-21",
                "ends_on": "2026-07-22",
            },
            {
                "id": "30000000-0000-4000-8000-000000000002",
                "title": "Calendar seminar",
                "location": "Room 2",
                "event_kind": "timed",
                "busy_status": "busy",
                "event_status": "tentative",
                "starts_at": "2026-07-21T08:00:00Z",
                "ends_at": "2026-07-21T09:00:00Z",
                "starts_on": None,
                "ends_on": None,
            },
        ],
    )
    repository.focus_sessions = [
        {
            "id": "40000000-0000-4000-8000-000000000001",
            "status": "completed",
            "started_at": "2026-07-21T08:00:00Z",
            "ended_at": "2026-07-21T08:30:00Z",
            "planned_minutes": 30,
            "actual_minutes": 30,
            "label": "Essay focus",
            "task_id": None,
            "habit_id": None,
            "metadata": {},
        },
    ]

    response = asyncio.run(_service(repository).get_overview(user_id=USER_ID))

    assert [item.kind for item in response.timeline] == [
        "calendar_event",
        "setup_commitment",
        "calendar_event",
        "focus_session",
    ]
    assert response.timeline[2].starts_at == response.timeline[3].starts_at
    assert all(item.title != "Expired class" for item in response.timeline)
    assert response.progress is not None
    assert response.progress.total == 2  # timeline sources above do not count


def test_one_counted_source_failure_nulls_progress_but_keeps_other_sources() -> None:
    repository = Repository()
    repository.fail_tasks = True
    repository.daily_logs = [_capture_row(date(2026, 7, 21))]

    response = asyncio.run(_service(repository).get_overview(user_id=USER_ID))

    assert response.progress is None
    assert response.progress_unavailable_sources == ["tasks"]
    assert response.source_states.tasks.message == "Tasks could not be loaded."
    assert response.source_states.check_ins.status == "current"
    assert response.tasks.today == []


class PlannerReader:
    def __init__(self, response: PlannerOverviewResponse | None) -> None:
        self.response = response

    async def get_overview(self, *, user_id):
        assert user_id == USER_ID
        if self.response is None:
            raise RuntimeError("private Planner failure")
        return self.response


def test_v2_adds_planner_blocks_without_counting_a_target_twice() -> None:
    repository = Repository()
    repository.daily_logs = [_capture_row(date(2026, 7, 21))]
    task_id = "50000000-0000-4000-8000-000000000001"
    habit_id = "60000000-0000-4000-8000-000000000001"
    repository.tasks = [
        _task(task_id, "Future scheduled Task", "todo", "2026-07-30T12:00:00Z"),
    ]
    repository.habits = [
        _habit(
            habit_id,
            "Tuesday Habit",
            {"cadence": "weekdays", "scheduled_weekdays": [2]},
        ),
    ]
    local_date = date(2026, 7, 21)
    planner_items = [
        PlannerDayItem(
            id=UUID("70000000-0000-4000-8000-000000000001"),
            kind="task_block",
            title="Future scheduled Task",
            source_id=UUID(task_id),
            starts_at=datetime(2026, 7, 21, 8, tzinfo=UTC),
            ends_at=datetime(2026, 7, 21, 8, 30, tzinfo=UTC),
            all_day=False,
            state="active",
        ),
        PlannerDayItem(
            id=UUID("70000000-0000-4000-8000-000000000002"),
            kind="task_block",
            title="Future scheduled Task",
            source_id=UUID(task_id),
            starts_at=datetime(2026, 7, 21, 9, tzinfo=UTC),
            ends_at=datetime(2026, 7, 21, 9, 30, tzinfo=UTC),
            all_day=False,
            state="active",
        ),
        PlannerDayItem(
            id=UUID("80000000-0000-4000-8000-000000000001"),
            kind="habit_slot",
            title="Tuesday Habit",
            source_id=UUID(habit_id),
            starts_at=datetime(2026, 7, 21, 10, tzinfo=UTC),
            ends_at=datetime(2026, 7, 21, 10, 20, tzinfo=UTC),
            all_day=False,
            state="active",
        ),
        PlannerDayItem(
            id=UUID("90000000-0000-4000-8000-000000000001"),
            kind="manual_commitment",
            title="Tutoring",
            source_id=UUID("90000000-0000-4000-8000-000000000001"),
            starts_at=datetime(2026, 7, 21, 11, tzinfo=UTC),
            ends_at=datetime(2026, 7, 21, 12, tzinfo=UTC),
            all_day=False,
            state="active",
        ),
    ]
    planner = PlannerOverviewResponse(
        contract_version="planner-v1",
        origin="authenticated_backend",
        generated_at=NOW,
        timezone="Europe/Berlin",
        local_date=local_date,
        preferences=PlannerPreferencesResponse(
            contract_version="planner-preferences-v1",
            origin="authenticated_backend",
            use_calendar_busy_time=False,
            updated_at=None,
            current_calendar_import_id=None,
            calendar_available=False,
        ),
        action_plans=[],
        commitments=[],
        needs_attention=[],
        days=[
            PlannerDay(
                local_date=local_date + timedelta(days=offset),
                items=planner_items if offset == 0 else [],
            )
            for offset in range(7)
        ],
        ongoing_preparation=[],
        unscheduled=[],
        history=[],
    )
    service = TodayOverviewService(
        repository=repository,
        deadline_plan_service=DeadlineService(),
        planner_service=PlannerReader(planner),
        now=lambda: NOW,
    )

    response = asyncio.run(service.get_overview_v2(user_id=USER_ID))

    assert response.contract_version == "today-overview-v2"
    assert [task.id for task in response.tasks.today] == [UUID(task_id)]
    assert response.tasks.today[0].today_reason == "scheduled_today"
    assert response.tasks.today[0].scheduled_today is True
    assert [habit.id for habit in response.habits] == [UUID(habit_id)]
    assert response.habits[0].scheduled_today is True
    assert [item.kind for item in response.timeline] == [
        "task_block",
        "task_block",
        "habit_slot",
        "manual_commitment",
    ]
    assert response.progress is not None
    assert response.progress.total == 4
    assert response.progress.completed == 2


def test_v2_planner_failure_is_isolated_and_never_fabricates_blocks() -> None:
    repository = Repository()
    repository.daily_logs = [_capture_row(date(2026, 7, 21))]
    service = TodayOverviewService(
        repository=repository,
        deadline_plan_service=DeadlineService(),
        planner_service=PlannerReader(None),
        now=lambda: NOW,
    )

    response = asyncio.run(service.get_overview_v2(user_id=USER_ID))

    assert response.timeline == []
    assert response.progress is None
    assert response.progress_unavailable_sources == ["planner"]
    assert response.source_states.planner.status == "unavailable"
    assert "private" not in (response.source_states.planner.message or "")


def _task(task_id, title, status, deadline, *, completed_at=None, source="manual"):
    return {
        "id": task_id,
        "title": title,
        "description": None,
        "status": status,
        "priority": "medium",
        "deadline": deadline,
        "estimated_minutes": 30,
        "completed_at": completed_at,
        "source": source,
        "metadata": {},
        "updated_at": "2026-07-21T08:00:00Z",
    }


def _habit(habit_id, title, cadence, *, frequency="daily", target=1):
    return {
        "id": habit_id,
        "title": title,
        "description": None,
        "frequency": frequency,
        "target": target,
        "active": True,
        "metadata": {
            "contract_version": "habit-v1",
            "lifecycle": "active",
            **cadence,
        },
        "created_at": "2026-07-01T08:00:00Z",
        "updated_at": "2026-07-21T08:00:00Z",
    }


def _habit_log(habit_id, status, *, entry_date="2026-07-21"):
    return {
        "id": str(UUID(int=hash((habit_id, status, entry_date)) % (2**128))),
        "habit_id": habit_id,
        "entry_date": entry_date,
        "status": status,
        "value": 1 if status == "completed" else 0,
        "created_at": "2026-07-21T08:00:00Z",
        "updated_at": "2026-07-21T08:00:00Z",
    }
