import asyncio
from datetime import UTC, date, datetime, timedelta
from uuid import UUID

import pytest
from pydantic import ValidationError

from app.models.today_week_agenda import (
    TodayWeekAgendaAction,
    TodayWeekAgendaDay,
    TodayWeekAgendaItem,
    TodayWeekAgendaResponse,
    TodayWeekAgendaSourceState,
    TodayWeekAgendaSourceStates,
)
from app.repositories.today_week_agenda_repository import (
    WeekCalendarRows,
    WeekHabitRows,
    WeekPreparationRows,
    WeekTaskRows,
)
from app.services.today_week_agenda_service import TodayWeekAgendaService
from app.services.today_week_agenda_service import TodayWeekAgendaUnavailableError


class Repository:
    def __init__(self) -> None:
        self.calls: list[str] = []
        self.fail_calendar = False
        self.timezone = "Europe/Berlin"
        self.setup_rows = [
            {
                "id": "11111111-1111-4111-8111-111111111111",
                "title": "Lecture",
                "location": "Hall A",
                "weekday": 1,
                "starts_at": "09:00:00",
                "ends_at": "10:30:00",
                "source": "intake-v1",
                "metadata": {},
            },
        ]
        self.preparation = WeekPreparationRows(plans=[], blocks=[])
        self.calendar = WeekCalendarRows(source_label=None, events=[])
        self.focus_rows: list[dict[str, object]] = []
        self.tasks = WeekTaskRows(plans=[], blocks=[], tasks=[])
        self.habits = WeekHabitRows(plans=[], slots=[], habits=[], logs=[])
        self.fixed_rows: list[dict[str, object]] = []

    async def get_profile_timezone(self, *, user_id):
        self.calls.append(f"profile:{user_id}")
        return self.timezone

    async def list_setup(self, *, user_id):
        self.calls.append("setup")
        return self.setup_rows

    async def load_preparation(self, **kwargs):
        self.calls.append("preparation")
        return self.preparation

    async def load_calendar(self, **kwargs):
        self.calls.append("calendar")
        if self.fail_calendar:
            raise ValueError("stale")
        return self.calendar

    async def list_focus(self, **kwargs):
        self.calls.append("focus")
        return self.focus_rows

    async def load_tasks(self, **kwargs):
        self.calls.append("tasks")
        return self.tasks

    async def load_habits(self, **kwargs):
        self.calls.append("habits")
        return self.habits

    async def list_fixed_commitments(self, **kwargs):
        self.calls.append("fixed_commitments")
        return self.fixed_rows


NOW = datetime(2026, 8, 15, 10, tzinfo=UTC)


def test_week_agenda_reads_each_source_once_and_returns_exact_profile_week() -> None:
    repository = Repository()
    service = TodayWeekAgendaService(repository=repository, now=lambda: NOW)

    result = asyncio.run(service.get_week(user_id="week-user"))

    assert result.contract_version == "today-week-agenda-v1"
    assert result.local_today == date(2026, 8, 15)
    assert result.week_starts_on == date(2026, 8, 10)
    assert result.week_ends_on == date(2026, 8, 16)
    assert [day.local_date for day in result.days] == [
        date(2026, 8, day) for day in range(10, 17)
    ]
    assert [item.title for item in result.days[0].items] == ["Lecture"]
    assert result.days[0].items[0].local_starts_at == "2026-08-10T09:00:00"
    assert result.days[0].items[0].starts_at.isoformat() == "2026-08-10T09:00:00+02:00"
    assert repository.calls == [
        "profile:week-user",
        "setup",
        "preparation",
        "calendar",
        "focus",
        "tasks",
        "habits",
        "fixed_commitments",
    ]


def test_week_agenda_isolates_one_failed_source_without_inventing_items() -> None:
    repository = Repository()
    repository.fail_calendar = True
    service = TodayWeekAgendaService(repository=repository, now=lambda: NOW)

    result = asyncio.run(service.get_week(user_id="week-user"))

    assert result.source_states.calendar.status == "unavailable"
    assert result.source_states.setup.status == "current"
    assert [item.category for day in result.days for item in day.items] == ["setup"]


def test_week_agenda_contract_requires_exact_ordered_seven_days() -> None:
    repository = Repository()
    result = asyncio.run(
        TodayWeekAgendaService(repository=repository, now=lambda: NOW).get_week(
            user_id="week-user",
        ),
    )
    payload = result.model_dump(mode="json")
    payload["days"] = payload["days"][:-1]

    with pytest.raises(ValidationError):
        TodayWeekAgendaResponse.model_validate(payload, strict=True)


def test_week_agenda_item_rejects_wrong_status_source_and_identity() -> None:
    block_id = UUID("33333333-3333-4333-8333-333333333333")
    plan_id = UUID("22222222-2222-4222-8222-222222222222")
    base = {
        "id": UUID("11111111-1111-4111-8111-111111111111"),
        "category": "preparation",
        "source_id": block_id,
        "plan_id": plan_id,
        "local_date": date(2026, 8, 13),
        "title": "Exam review",
        "detail": "60 min remaining · 0/60 min tracked",
        "status": "upcoming",
        "planned_minutes": 60,
        "credited_tracked_minutes": 0,
        "remaining_minutes": 60,
        "all_day": False,
        "local_starts_at": "2026-08-13T10:00:00",
        "local_ends_at": "2026-08-13T11:00:00",
        "starts_at": datetime(2026, 8, 13, 8, tzinfo=UTC),
        "ends_at": datetime(2026, 8, 13, 9, tzinfo=UTC),
        "action": TodayWeekAgendaAction(
            kind="start_preparation_focus",
            target_id=block_id,
            source_kind="deadline_plan_block",
        ),
    }
    TodayWeekAgendaItem.model_validate(base)

    with pytest.raises(ValidationError, match="status"):
        TodayWeekAgendaItem.model_validate({**base, "status": "scheduled"})
    with pytest.raises(ValidationError, match="target"):
        TodayWeekAgendaItem.model_validate(
            {
                **base,
                "action": TodayWeekAgendaAction(
                    kind="start_preparation_focus",
                    target_id=plan_id,
                    source_kind="deadline_plan_block",
                ),
            },
        )
    with pytest.raises(ValidationError, match="source"):
        TodayWeekAgendaAction.model_validate(
            {
                "kind": "start_preparation_focus",
                "target_id": block_id,
                "source_kind": "planner_task_block",
            },
        )


def test_week_agenda_response_rejects_cross_zone_wall_time_and_outside_today() -> None:
    start = date(2026, 8, 10)
    state = TodayWeekAgendaSourceState(status="current")
    sources = TodayWeekAgendaSourceStates(
        setup=state,
        preparation=state,
        calendar=state,
        focus=state,
        tasks=state,
        habits=state,
        fixed_commitments=state,
    )
    mismatched = TodayWeekAgendaItem(
        id=UUID("11111111-1111-4111-8111-111111111111"),
        category="setup",
        source_id=UUID("22222222-2222-4222-8222-222222222222"),
        local_date=start,
        title="Lecture",
        status="scheduled",
        all_day=False,
        local_starts_at="2026-08-10T08:00:00",
        local_ends_at="2026-08-10T09:00:00",
        starts_at=datetime(2026, 8, 10, 7, tzinfo=UTC),
        ends_at=datetime(2026, 8, 10, 8, tzinfo=UTC),
    )
    days = [
        TodayWeekAgendaDay(
            local_date=start + timedelta(days=offset),
            items=[mismatched] if offset == 0 else [],
        )
        for offset in range(7)
    ]
    with pytest.raises(ValidationError, match="timezone"):
        TodayWeekAgendaResponse(
            contract_version="today-week-agenda-v1",
            origin="authenticated_backend",
            generated_at=NOW,
            timezone="Europe/Berlin",
            local_today=date(2026, 8, 15),
            week_starts_on=start,
            week_ends_on=start + timedelta(days=6),
            days=days,
            source_states=sources,
        )

    with pytest.raises(ValidationError, match="bounds"):
        TodayWeekAgendaResponse(
            contract_version="today-week-agenda-v1",
            origin="authenticated_backend",
            generated_at=datetime(2026, 8, 17, 10, tzinfo=UTC),
            timezone="Europe/Berlin",
            local_today=date(2026, 8, 17),
            week_starts_on=start,
            week_ends_on=start + timedelta(days=6),
            days=[
                TodayWeekAgendaDay(local_date=start + timedelta(days=offset))
                for offset in range(7)
            ],
            source_states=sources,
        )


def test_week_agenda_response_rejects_habit_action_outside_local_today() -> None:
    repository = Repository()
    repository.setup_rows = []
    repository.habits = WeekHabitRows(
        plans=[
            {
                "id": "99999999-9999-4999-8999-999999999999",
                "target_kind": "habit",
                "target_id": "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee",
                "status": "active",
                "current_revision": 1,
            },
        ],
        slots=[
            {
                "id": "bbbbbbbb-cccc-4ddd-8eee-ffffffffffff",
                "plan_id": "99999999-9999-4999-8999-999999999999",
                "revision": 1,
                "weekday": 5,
                "starts_at": "16:00:00",
                "ends_at": "16:30:00",
                "duration_minutes": 30,
                "state": "active",
            },
        ],
        habits=[
            {
                "id": "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee",
                "title": "Walk",
                "description": None,
                "frequency": "daily",
                "target": 1,
                "active": True,
                "metadata": {},
            },
        ],
        logs=[],
    )
    result = asyncio.run(
        TodayWeekAgendaService(repository=repository, now=lambda: NOW).get_week(
            user_id="week-user",
        ),
    )
    payload = result.model_dump()
    friday = payload["days"][4]
    habit = friday["items"][0]
    habit["action"] = {
        "kind": "open_habit",
        "target_id": habit["habit_id"],
        "source_kind": None,
        "local_date": friday["local_date"],
    }

    with pytest.raises(ValidationError, match="local today"):
        TodayWeekAgendaResponse.model_validate(payload, strict=True)


def test_week_agenda_projects_all_categories_with_date_safe_actions() -> None:
    repository = Repository()
    repository.preparation = WeekPreparationRows(
        plans=[
            {
                "id": "22222222-2222-4222-8222-222222222222",
                "title": "Exam review",
                "status": "active",
                "current_revision": 1,
                "managed_task_id": "22222222-2222-4222-8222-222222222222",
                "first_activated_at": "2026-08-01T08:00:00+00:00",
            },
        ],
        revisions=[
            {
                "plan_id": "22222222-2222-4222-8222-222222222222",
                "revision": 1,
                "state": "active",
                "tracked_focus_minutes_at_proposal": 0,
            },
        ],
        credit_blocks=[
            {
                "id": "33333333-3333-4333-8333-333333333333",
                "plan_id": "22222222-2222-4222-8222-222222222222",
                "revision": 1,
                "sequence": 1,
                "local_date": "2026-08-13",
                "starts_at": "2026-08-13T08:00:00+00:00",
                "ends_at": "2026-08-13T09:00:00+00:00",
                "planned_minutes": 60,
                "reservation_state": "active",
            },
        ],
        blocks=[
            {
                "id": "33333333-3333-4333-8333-333333333333",
                "plan_id": "22222222-2222-4222-8222-222222222222",
                "revision": 1,
                "local_date": "2026-08-13",
                "starts_at": "2026-08-13T08:00:00+00:00",
                "ends_at": "2026-08-13T09:00:00+00:00",
                "planned_minutes": 60,
                "reservation_state": "active",
            },
        ],
    )
    repository.calendar = WeekCalendarRows(
        source_label="University",
        events=[
            {
                "id": "44444444-4444-4444-8444-444444444444",
                "title": "Campus day",
                "location": None,
                "event_kind": "all_day",
                "busy_status": "busy",
                "event_status": "confirmed",
                "starts_at": None,
                "ends_at": None,
                "starts_on": "2026-08-11",
                "ends_on": "2026-08-12",
            },
        ],
    )
    repository.focus_rows = [
        {
            "id": "55555555-5555-4555-8555-555555555555",
            "status": "active",
            "started_at": "2026-08-15T09:00:00+00:00",
            "ended_at": None,
            "planned_minutes": 60,
            "actual_minutes": None,
            "label": "Essay focus",
            "task_id": None,
            "habit_id": None,
            "metadata": {"entry_date": "2026-08-15"},
        },
    ]
    repository.tasks = WeekTaskRows(
        plans=[
            {
                "id": "66666666-6666-4666-8666-666666666666",
                "target_kind": "task",
                "target_id": "77777777-7777-4777-8777-777777777777",
                "status": "active",
                "current_revision": 1,
            },
        ],
        blocks=[
            {
                "id": "88888888-8888-4888-8888-888888888888",
                "plan_id": "66666666-6666-4666-8666-666666666666",
                "revision": 1,
                "local_date": "2026-08-14",
                "starts_at": "2026-08-14T12:00:00+00:00",
                "ends_at": "2026-08-14T13:00:00+00:00",
                "planned_minutes": 60,
                "state": "active",
            },
        ],
        tasks=[
            {
                "id": "77777777-7777-4777-8777-777777777777",
                "title": "Draft essay",
                "description": None,
                "status": "todo",
                "source": "manual",
            },
        ],
    )
    repository.habits = WeekHabitRows(
        plans=[
            {
                "id": "99999999-9999-4999-8999-999999999999",
                "target_kind": "habit",
                "target_id": "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee",
                "status": "active",
                "current_revision": 1,
            },
        ],
        slots=[
            {
                "id": "bbbbbbbb-cccc-4ddd-8eee-ffffffffffff",
                "plan_id": "99999999-9999-4999-8999-999999999999",
                "revision": 1,
                "weekday": 6,
                "starts_at": "16:00:00",
                "ends_at": "16:30:00",
                "duration_minutes": 30,
                "state": "active",
            },
        ],
        habits=[
            {
                "id": "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee",
                "title": "Walk",
                "description": None,
                "frequency": "daily",
                "target": 1,
                "active": True,
                "metadata": {},
            },
        ],
        logs=[],
    )
    repository.fixed_rows = [
        {
            "id": "cccccccc-dddd-4eee-8fff-000000000000",
            "title": "Volunteer shift",
            "location": "Library",
            "recurrence": "weekly",
            "status": "active",
            "starts_at": None,
            "ends_at": None,
            "weekday": 7,
            "local_starts_at": "10:00:00",
            "local_ends_at": "12:00:00",
        },
    ]

    result = asyncio.run(
        TodayWeekAgendaService(repository=repository, now=lambda: NOW).get_week(
            user_id="week-user",
        ),
    )

    items = [item for day in result.days for item in day.items]
    assert {item.category for item in items} == {
        "setup",
        "preparation",
        "calendar",
        "focus",
        "task",
        "habit",
        "fixed_commitment",
    }
    actions = {
        item.category: item.action.kind if item.action is not None else None
        for item in items
    }
    assert actions == {
        "setup": None,
        "preparation": "start_preparation_focus",
        "calendar": None,
        "focus": "resume_focus",
        "task": "start_task_focus",
        "habit": "open_habit",
        "fixed_commitment": None,
    }
    habit = next(item for item in items if item.category == "habit")
    assert habit.action is not None
    assert habit.action.local_date == result.local_today
    assert (
        next(item for item in items if item.category == "preparation").status
        == "missed"
    )


@pytest.mark.parametrize(
    (
        "plan_status",
        "reservation_state",
        "starts_at",
        "ends_at",
        "credit",
        "expected_status",
        "expected_action",
    ),
    [
        (
            "active",
            "active",
            "2026-08-16T08:00:00+00:00",
            "2026-08-16T09:00:00+00:00",
            0,
            "upcoming",
            "start_preparation_focus",
        ),
        (
            "active",
            "active",
            "2026-08-13T08:00:00+00:00",
            "2026-08-13T09:00:00+00:00",
            25,
            "partial",
            "start_preparation_focus",
        ),
        (
            "active",
            "active",
            "2026-08-13T08:00:00+00:00",
            "2026-08-13T09:00:00+00:00",
            60,
            "completed",
            None,
        ),
        (
            "active",
            "active",
            "2026-08-13T08:00:00+00:00",
            "2026-08-13T09:00:00+00:00",
            0,
            "missed",
            "start_preparation_focus",
        ),
        (
            "completed",
            "superseded",
            "2026-08-13T08:00:00+00:00",
            "2026-08-13T09:00:00+00:00",
            25,
            "partial",
            "open_preparation_plan",
        ),
    ],
)
def test_preparation_uses_canonical_credit_and_lifecycle(
    plan_status: str,
    reservation_state: str,
    starts_at: str,
    ends_at: str,
    credit: int,
    expected_status: str,
    expected_action: str | None,
) -> None:
    repository = Repository()
    repository.setup_rows = []
    plan_id = "22222222-2222-4222-8222-222222222222"
    block_id = "33333333-3333-4333-8333-333333333333"
    block = {
        "id": block_id,
        "plan_id": plan_id,
        "revision": 2,
        "sequence": 1,
        "local_date": "2026-08-16" if "16T" in starts_at else "2026-08-13",
        "starts_at": starts_at,
        "ends_at": ends_at,
        "planned_minutes": 60,
        "reservation_state": reservation_state,
    }
    facts = []
    if credit:
        facts.append(
            {
                "id": "44444444-4444-4444-8444-444444444444",
                "plan_id": plan_id,
                "started_at": "2026-08-12T08:00:00+00:00",
                "actual_minutes": credit,
                "deadline_plan_block_id": block_id,
            },
        )
    repository.preparation = WeekPreparationRows(
        plans=[
            {
                "id": plan_id,
                "title": "Exam review",
                "status": plan_status,
                "current_revision": 2,
                "managed_task_id": plan_id,
                "first_activated_at": "2026-08-01T08:00:00+00:00",
            },
        ],
        revisions=[
            {
                "plan_id": plan_id,
                "revision": 2,
                "state": "active",
                "tracked_focus_minutes_at_proposal": 0,
            },
        ],
        blocks=[block],
        credit_blocks=[block],
        focus_facts=facts,
    )

    result = asyncio.run(
        TodayWeekAgendaService(repository=repository, now=lambda: NOW).get_week(
            user_id="week-user",
        ),
    )

    item = next(item for day in result.days for item in day.items)
    assert item.status == expected_status
    assert item.plan_id is not None and str(item.plan_id) == plan_id
    assert item.planned_minutes == 60
    assert item.credited_tracked_minutes == credit
    assert item.remaining_minutes == 60 - credit
    assert (item.action.kind if item.action is not None else None) == expected_action
    if expected_action == "start_preparation_focus":
        assert item.action is not None and str(item.action.target_id) == block_id
    if expected_action == "open_preparation_plan":
        assert item.action is not None and str(item.action.target_id) == plan_id


def test_preparation_replays_proposal_credit_before_source_credit() -> None:
    repository = Repository()
    repository.setup_rows = []
    plan_id = "22222222-2222-4222-8222-222222222222"
    first_id = "33333333-3333-4333-8333-333333333333"
    second_id = "44444444-4444-4444-8444-444444444444"
    blocks = [
        {
            "id": first_id,
            "plan_id": plan_id,
            "revision": 1,
            "sequence": 1,
            "local_date": "2026-08-13",
            "starts_at": "2026-08-13T08:00:00+00:00",
            "ends_at": "2026-08-13T09:00:00+00:00",
            "planned_minutes": 60,
            "reservation_state": "active",
        },
        {
            "id": second_id,
            "plan_id": plan_id,
            "revision": 1,
            "sequence": 2,
            "local_date": "2026-08-16",
            "starts_at": "2026-08-16T08:00:00+00:00",
            "ends_at": "2026-08-16T09:00:00+00:00",
            "planned_minutes": 60,
            "reservation_state": "active",
        },
    ]
    repository.preparation = WeekPreparationRows(
        plans=[
            {
                "id": plan_id,
                "title": "Exam review",
                "status": "active",
                "current_revision": 1,
                "managed_task_id": plan_id,
                "first_activated_at": "2026-08-01T08:00:00+00:00",
            },
        ],
        revisions=[
            {
                "plan_id": plan_id,
                "revision": 1,
                "state": "active",
                "tracked_focus_minutes_at_proposal": 20,
            },
        ],
        blocks=blocks,
        credit_blocks=blocks,
        focus_facts=[
            {
                "id": "55555555-5555-4555-8555-555555555555",
                "plan_id": plan_id,
                "started_at": "2026-08-02T08:00:00+00:00",
                "actual_minutes": 20,
                "deadline_plan_block_id": first_id,
            },
            {
                "id": "66666666-6666-4666-8666-666666666666",
                "plan_id": plan_id,
                "started_at": "2026-08-12T08:00:00+00:00",
                "actual_minutes": 30,
                "deadline_plan_block_id": second_id,
            },
        ],
    )

    result = asyncio.run(
        TodayWeekAgendaService(repository=repository, now=lambda: NOW).get_week(
            user_id="week-user",
        ),
    )
    preparation = {
        str(item.source_id): item
        for day in result.days
        for item in day.items
        if item.category == "preparation"
    }
    assert preparation[first_id].credited_tracked_minutes == 0
    assert preparation[second_id].credited_tracked_minutes == 30


def test_long_terminal_focus_remains_visible_and_credits_preparation() -> None:
    repository = Repository()
    repository.setup_rows = []
    plan_id = "22222222-2222-4222-8222-222222222222"
    block_id = "33333333-3333-4333-8333-333333333333"
    focus_id = "44444444-4444-4444-8444-444444444444"
    block = {
        "id": block_id,
        "plan_id": plan_id,
        "revision": 1,
        "sequence": 1,
        "local_date": "2026-08-16",
        "starts_at": "2026-08-16T08:00:00+00:00",
        "ends_at": "2026-08-16T09:00:00+00:00",
        "planned_minutes": 60,
        "reservation_state": "active",
    }
    repository.preparation = WeekPreparationRows(
        plans=[
            {
                "id": plan_id,
                "title": "Exam review",
                "status": "active",
                "current_revision": 1,
                "managed_task_id": plan_id,
                "first_activated_at": "2026-08-01T08:00:00+00:00",
            },
        ],
        revisions=[
            {
                "plan_id": plan_id,
                "revision": 1,
                "state": "active",
                "tracked_focus_minutes_at_proposal": 0,
            },
        ],
        blocks=[block],
        credit_blocks=[block],
        focus_facts=[
            {
                "id": focus_id,
                "plan_id": plan_id,
                "started_at": "2026-08-12T08:00:00+00:00",
                "actual_minutes": 1_500,
                "deadline_plan_block_id": block_id,
            },
        ],
    )
    repository.focus_rows = [
        {
            "id": focus_id,
            "status": "completed",
            "started_at": "2026-08-12T08:00:00+00:00",
            "ended_at": "2026-08-13T09:00:00+00:00",
            "planned_minutes": 60,
            "actual_minutes": 1_500,
            "label": "Long exam review",
            "task_id": plan_id,
            "habit_id": None,
            "metadata": {"entry_date": "2026-08-12"},
        },
    ]

    result = asyncio.run(
        TodayWeekAgendaService(repository=repository, now=lambda: NOW).get_week(
            user_id="week-user",
        ),
    )

    preparation = next(
        item
        for day in result.days
        for item in day.items
        if item.category == "preparation"
    )
    focus = next(
        item for day in result.days for item in day.items if item.category == "focus"
    )
    assert result.source_states.preparation.status == "current"
    assert preparation.status == "completed"
    assert preparation.credited_tracked_minutes == 60
    assert preparation.remaining_minutes == 0
    assert result.source_states.focus.status == "current"
    assert focus.detail == "1500 min"


def test_focus_entry_date_wins_and_legacy_fallback_uses_utc_week_boundary() -> None:
    repository = Repository()
    repository.setup_rows = []
    repository.focus_rows = [
        {
            "id": f"50000000-0000-4000-8000-{index:012d}",
            "status": "completed",
            "started_at": "2026-08-09T22:30:00+00:00",
            "ended_at": "2026-08-09T23:00:00+00:00",
            "planned_minutes": 30,
            "actual_minutes": 30,
            "label": label,
            "task_id": None,
            "habit_id": None,
            "metadata": metadata,
        }
        for index, (label, metadata) in enumerate(
            (
                ("Explicit Monday", {"entry_date": "2026-08-10"}),
                ("Missing legacy date", {}),
                ("Invalid legacy date", {"entry_date": "not-a-date"}),
            ),
            start=1,
        )
    ]
    now = datetime(2026, 8, 10, 10, tzinfo=UTC)

    result = asyncio.run(
        TodayWeekAgendaService(repository=repository, now=lambda: now).get_week(
            user_id="week-user",
        ),
    )

    focus_items = [
        item for day in result.days for item in day.items if item.category == "focus"
    ]
    assert result.week_starts_on == date(2026, 8, 10)
    assert result.source_states.focus.status == "current"
    assert [item.title for item in focus_items] == ["Explicit Monday"]
    assert focus_items[0].local_date == date(2026, 8, 10)


def test_preparation_fails_closed_for_noncurrent_active_block() -> None:
    repository = Repository()
    repository.setup_rows = []
    plan_id = "22222222-2222-4222-8222-222222222222"
    repository.preparation = WeekPreparationRows(
        plans=[
            {
                "id": plan_id,
                "title": "Exam review",
                "status": "active",
                "current_revision": 2,
                "managed_task_id": plan_id,
                "first_activated_at": "2026-08-01T08:00:00+00:00",
            },
        ],
        revisions=[
            {
                "plan_id": plan_id,
                "revision": 2,
                "state": "active",
                "tracked_focus_minutes_at_proposal": 0,
            },
        ],
        blocks=[
            {
                "id": "33333333-3333-4333-8333-333333333333",
                "plan_id": plan_id,
                "revision": 1,
                "local_date": "2026-08-13",
                "starts_at": "2026-08-13T08:00:00+00:00",
                "ends_at": "2026-08-13T09:00:00+00:00",
                "planned_minutes": 60,
                "reservation_state": "active",
            },
        ],
    )

    result = asyncio.run(
        TodayWeekAgendaService(repository=repository, now=lambda: NOW).get_week(
            user_id="week-user",
        ),
    )

    assert result.source_states.preparation.status == "unavailable"
    assert all(
        item.category != "preparation" for day in result.days for item in day.items
    )


def test_cancelled_preparation_superseded_block_is_absent_not_unavailable() -> None:
    repository = Repository()
    repository.setup_rows = []
    repository.preparation = WeekPreparationRows(
        plans=[],
        blocks=[
            {
                "id": "33333333-3333-4333-8333-333333333333",
                "plan_id": "22222222-2222-4222-8222-222222222222",
                "revision": 1,
                "local_date": "2026-08-13",
                "starts_at": "2026-08-13T08:00:00+00:00",
                "ends_at": "2026-08-13T09:00:00+00:00",
                "planned_minutes": 60,
                "reservation_state": "superseded",
            },
        ],
    )

    result = asyncio.run(
        TodayWeekAgendaService(repository=repository, now=lambda: NOW).get_week(
            user_id="week-user",
        ),
    )

    assert result.source_states.preparation.status == "current"
    assert all(
        item.category != "preparation" for day in result.days for item in day.items
    )


def test_week_agenda_accepts_a_real_fall_back_fold_interval() -> None:
    repository = Repository()
    repository.timezone = "Europe/Berlin"
    repository.setup_rows = []
    repository.calendar = WeekCalendarRows(
        source_label="University",
        events=[
            {
                "id": "dddddddd-eeee-4fff-8000-111111111111",
                "title": "Clock change",
                "location": None,
                "event_kind": "timed",
                "busy_status": "busy",
                "event_status": "confirmed",
                "starts_at": "2026-10-25T00:30:00+00:00",
                "ends_at": "2026-10-25T01:30:00+00:00",
                "starts_on": None,
                "ends_on": None,
            },
        ],
    )
    now = datetime(2026, 10, 25, 12, tzinfo=UTC)

    result = asyncio.run(
        TodayWeekAgendaService(repository=repository, now=lambda: now).get_week(
            user_id="week-user",
        ),
    )

    item = next(item for day in result.days for item in day.items)
    assert item.local_starts_at == "2026-10-25T02:30:00"
    assert item.local_ends_at == "2026-10-25T02:30:00"
    assert item.ends_at is not None and item.starts_at is not None
    assert item.ends_at > item.starts_at


def test_nonexistent_spring_time_isolated_to_its_source() -> None:
    repository = Repository()
    repository.setup_rows[0].update(
        weekday=7,
        starts_at="02:30:00",
        ends_at="03:30:00",
    )
    now = datetime(2026, 3, 29, 10, tzinfo=UTC)

    result = asyncio.run(
        TodayWeekAgendaService(repository=repository, now=lambda: now).get_week(
            user_id="week-user",
        ),
    )

    assert result.source_states.setup.status == "unavailable"
    assert result.source_states.calendar.status == "current"
    assert all(item.category != "setup" for day in result.days for item in day.items)


def test_profile_timezone_failure_is_route_wide_unavailable() -> None:
    repository = Repository()
    repository.timezone = "Not/A-Timezone"

    with pytest.raises(TodayWeekAgendaUnavailableError, match="profile timezone"):
        asyncio.run(
            TodayWeekAgendaService(repository=repository, now=lambda: NOW).get_week(
                user_id="week-user",
            ),
        )

    assert repository.calls == ["profile:week-user"]
