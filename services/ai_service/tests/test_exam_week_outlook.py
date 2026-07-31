import asyncio
from datetime import UTC, date, datetime, time, timedelta
from types import MethodType
from uuid import UUID
from zoneinfo import ZoneInfo

import pytest

from app.models.deadline_plans import (
    DeadlinePlanBlock,
    DeadlinePlanDetail,
    DeadlinePlanIdentity,
    DeadlinePlanProgress,
    DeadlinePlanRevision,
)
from app.repositories.deadline_plan_repository import (
    DeadlinePlanProjection,
    DeadlinePlanningContext,
)
from app.services.deadline_plan_service import DeadlinePlanService
from app.services.exam_week_outlook import build_exam_week_outlook


NOW = datetime(2026, 7, 20, 8, tzinfo=UTC)
EXAM_ID = UUID("22222222-2222-4222-8222-222222222222")
ASSIGNMENT_ID = UUID("33333333-3333-4333-8333-333333333333")


class OutlookRepository:
    def __init__(
        self,
        *,
        context: DeadlinePlanningContext | None = None,
        sleep_rows: list[dict] | None = None,
    ) -> None:
        self.context = context or _context()
        self.sleep_rows = sleep_rows or []
        self.calls: list[tuple] = []

    async def load_projection(self, *, user_id, plan_id):
        self.calls.append(("projection", user_id, plan_id))
        return DeadlinePlanProjection(
            plans=[],
            revisions=[],
            blocks=[],
            focus_totals=[],
            calendar_events={},
        )

    async def load_planning_context(self, **kwargs):
        self.calls.append(("context", kwargs))
        assert kwargs["plan_id"] == UUID(int=0)
        return self.context

    async def list_sleep_capture_logs(self, *, user_id):
        self.calls.append(("sleep", user_id))
        return self.sleep_rows


def _context(
    *,
    timezone: str = "UTC",
    best_energy_window: str = "variable",
    schedule_items: list[dict] | None = None,
    confirmed_blocks: list[dict] | None = None,
    daily_budget: int | None = None,
    calendar_requested: bool = False,
    calendar_current: bool = False,
) -> DeadlinePlanningContext:
    return DeadlinePlanningContext(
        timezone=timezone,
        best_energy_window=best_energy_window,
        schedule_items=schedule_items or [],
        confirmed_blocks=confirmed_blocks or [],
        timed_calendar_events=[],
        all_day_calendar_events=[],
        source_calendar_event=None,
        calendar_availability_current=calendar_current,
        availability_connection_id=None,
        availability_import_id=None,
        daily_preparation_budget_minutes=daily_budget,
        planner_recurring_commitments=[],
        planner_timed_intervals=[],
        planner_use_calendar_busy_time=calendar_requested,
        study_setup=None,
    )


def _detail(
    *,
    plan_id: UUID,
    kind: str,
    days: int,
    remaining: int = 60,
    buffer_days: int = 1,
    max_daily_minutes: int = 480,
    now: datetime = NOW,
) -> DeadlinePlanDetail:
    deadline = datetime.combine(
        now.date() + timedelta(days=days),
        time(18),
        tzinfo=UTC,
    )
    title = "Algorithms exam" if kind == "exam" else "History assignment"
    identity = DeadlinePlanIdentity(
        id=plan_id,
        status="active",
        kind=kind,
        title=title,
        managed_task_id=plan_id,
        original_estimated_total_minutes=remaining,
        original_credited_prior_minutes=0,
        current_revision=1,
        latest_revision=1,
        created_at=now - timedelta(days=5),
        updated_at=now - timedelta(days=1),
    )
    revision = DeadlinePlanRevision(
        plan_id=plan_id,
        revision=1,
        base_revision=0,
        state="active",
        kind=kind,
        title=title,
        deadline_at=deadline,
        estimated_total_minutes=remaining,
        credited_prior_minutes=0,
        preferred_session_minutes=min(60, remaining),
        max_daily_minutes=max_daily_minutes,
        planning_start_on=now.date(),
        buffer_days=buffer_days,
        source_kind="manual",
        source_status="not_applicable",
        use_calendar_availability=False,
        timezone="UTC",
        best_energy_window="variable",
        planning_fingerprint="a" * 64,
        recovery_minutes=0,
        tracked_focus_minutes_at_proposal=0,
        remaining_minutes_at_proposal=remaining,
        planned_minutes=0,
        unscheduled_minutes=remaining,
        created_at=now - timedelta(days=2),
        activated_at=now - timedelta(days=1),
        blocks=[],
    )
    return DeadlinePlanDetail(
        plan=identity,
        active_revision=revision,
        progress=DeadlinePlanProgress(
            estimated_total_minutes=remaining,
            credited_prior_minutes=0,
            tracked_focus_minutes=0,
            accounted_minutes=0,
            remaining_minutes=remaining,
            completion_suggested=False,
        ),
    )


def _service(
    details: list[DeadlinePlanDetail],
    *,
    context: DeadlinePlanningContext | None = None,
    sleep_rows: list[dict] | None = None,
    now: datetime = NOW,
) -> tuple[DeadlinePlanService, OutlookRepository]:
    repository = OutlookRepository(context=context, sleep_rows=sleep_rows)
    service = DeadlinePlanService(repository=repository, now=lambda: now)

    async def render_details(self, *, user_id, projection):
        assert user_id == "owner"
        return details

    service._details_from_projection = MethodType(render_details, service)
    return service, repository


@pytest.mark.parametrize(
    ("days", "expected_mode"),
    ((7, "exam_week"), (8, "watch"), (14, "watch"), (15, "inactive")),
)
def test_exam_mode_uses_exact_profile_local_boundaries(
    days: int,
    expected_mode: str,
) -> None:
    service, _ = _service(
        [_detail(plan_id=EXAM_ID, kind="exam", days=days)],
        sleep_rows=[_sleep_row(NOW.date(), estimated_minutes=480)],
    )

    result = asyncio.run(service.get_exam_week_outlook(user_id="owner"))

    assert result.mode == expected_mode
    assert bool(result.exams) is (expected_mode != "inactive")


def test_outlook_builder_is_pure_and_independent_of_repository_or_service() -> None:
    details = [_detail(plan_id=EXAM_ID, kind="exam", days=5)]
    context = _context()
    sleep_rows = [_sleep_row(NOW.date(), estimated_minutes=480)]

    first = build_exam_week_outlook(
        generated_at=NOW,
        context=context,
        details=details,
        sleep_rows=sleep_rows,
    )
    second = build_exam_week_outlook(
        generated_at=NOW,
        context=context,
        details=details,
        sleep_rows=sleep_rows,
    )

    assert first == second
    assert first.mode == "exam_week"
    assert first.exams[0].plan_id == EXAM_ID


def test_overdue_exam_with_remaining_work_is_high_and_never_mutates() -> None:
    service, repository = _service(
        [_detail(plan_id=EXAM_ID, kind="exam", days=-1)],
        sleep_rows=[_sleep_row(NOW.date(), estimated_minutes=480)],
    )

    result = asyncio.run(service.get_exam_week_outlook(user_id="owner"))

    assert result.mode == "overdue"
    assert result.risk_level == "high"
    assert "exam_overdue" in result.warning_codes
    assert [call[0] for call in repository.calls] == [
        "projection",
        "context",
        "sleep",
    ]


def test_exam_precedes_same_deadline_assignment_and_assignment_uses_capacity() -> None:
    details = [
        _detail(
            plan_id=ASSIGNMENT_ID,
            kind="assignment",
            days=3,
            remaining=400,
            buffer_days=0,
        ),
        _detail(
            plan_id=EXAM_ID,
            kind="exam",
            days=3,
            remaining=300,
        ),
    ]
    service, _ = _service(
        details,
        context=_context(daily_budget=100),
        sleep_rows=[_sleep_row(NOW.date(), estimated_minutes=480)],
    )

    result = asyncio.run(service.get_exam_week_outlook(user_id="owner"))

    assert result.exams[0].simulated_regular_minutes == 200
    assert result.assignments[0].simulated_regular_minutes == 200
    assert result.assignments[0].unscheduled_regular_minutes == 200
    assert result.capacity_status == "does_not_fit_before_buffer"
    assert "remaining_work_does_not_fit" in result.warning_codes


def test_sleep_window_is_compared_without_becoming_a_hard_lock() -> None:
    commitments = [
        {
            "id": f"busy-{weekday}",
            "weekday": weekday,
            "starts_at": "07:00:00",
            "ends_at": "21:00:00",
        }
        for weekday in range(1, 8)
    ]
    service, _ = _service(
        [
            _detail(
                plan_id=EXAM_ID,
                kind="exam",
                days=4,
                remaining=120,
                max_daily_minutes=60,
            ),
        ],
        context=_context(
            best_energy_window="early_morning",
            schedule_items=commitments,
        ),
        sleep_rows=[_sleep_row(NOW.date(), estimated_minutes=480)],
    )

    result = asyncio.run(service.get_exam_week_outlook(user_id="owner"))

    assert result.capacity_status == "fits_only_using_sleep_window"
    assert result.exams[0].simulated_regular_minutes == 120
    assert result.exams[0].simulated_sleep_protected_minutes == 0
    assert "sleep_capacity_tradeoff" in result.warning_codes


def test_missing_sleep_plan_keeps_a_fitting_capacity_unknown() -> None:
    service, _ = _service(
        [_detail(plan_id=EXAM_ID, kind="exam", days=7, remaining=60)],
    )

    result = asyncio.run(service.get_exam_week_outlook(user_id="owner"))

    assert result.capacity_status == "unknown"
    assert result.risk_level == "attention"
    assert result.current_sleep_plan is None
    assert "sleep_plan_missing" in result.warning_codes


def test_two_of_three_short_nights_raise_risk_exactly_one_level() -> None:
    rows = [
        _sleep_row(NOW.date(), estimated_minutes=360),
        _sleep_row(NOW.date() - timedelta(days=1), estimated_minutes=420),
        _sleep_row(NOW.date() - timedelta(days=2), estimated_minutes=360),
    ]
    service, _ = _service(
        [
            _detail(
                plan_id=EXAM_ID,
                kind="exam",
                days=7,
                remaining=60,
                buffer_days=1,
            ),
        ],
        sleep_rows=rows,
    )

    result = asyncio.run(service.get_exam_week_outlook(user_id="owner"))

    assert result.capacity_status == "fits_with_sleep_protected"
    assert result.risk_level == "attention"
    assert "repeated_sleep_shortfall" in result.warning_codes
    assert [night.entry_date for night in result.recent_sleep_nights] == [
        NOW.date(),
        NOW.date() - timedelta(days=1),
        NOW.date() - timedelta(days=2),
    ]


def test_future_capture_rows_do_not_supply_sleep_plan_or_nights() -> None:
    service, _ = _service(
        [_detail(plan_id=EXAM_ID, kind="exam", days=7, remaining=60)],
        sleep_rows=[
            _sleep_row(NOW.date() + timedelta(days=1), estimated_minutes=360),
        ],
    )

    result = asyncio.run(service.get_exam_week_outlook(user_id="owner"))

    assert result.current_sleep_plan is None
    assert result.recent_sleep_nights == []
    assert "sleep_plan_missing" in result.warning_codes


def test_missing_current_calendar_never_reports_on_track() -> None:
    service, _ = _service(
        [_detail(plan_id=EXAM_ID, kind="exam", days=7, remaining=60)],
        context=_context(calendar_requested=True, calendar_current=False),
        sleep_rows=[_sleep_row(NOW.date(), estimated_minutes=480)],
    )

    result = asyncio.run(service.get_exam_week_outlook(user_id="owner"))

    assert result.capacity_status == "unknown"
    assert result.risk_level == "unknown"
    assert "capacity_incomplete" in result.warning_codes


def test_pending_preview_sleep_overlap_is_warning_only() -> None:
    detail = _detail(plan_id=EXAM_ID, kind="exam", days=7)
    starts_at = datetime.combine(NOW.date(), time(23, 30), tzinfo=UTC)
    block = DeadlinePlanBlock(
        id=UUID("44444444-4444-4444-8444-444444444444"),
        sequence=1,
        starts_at=starts_at,
        ends_at=starts_at + timedelta(minutes=25),
        local_date=starts_at.date(),
        local_start_time=starts_at.time().replace(tzinfo=None),
        local_end_time=(starts_at + timedelta(minutes=25)).time().replace(tzinfo=None),
        planned_minutes=25,
        recovery_minutes=0,
        reserved_ends_at=starts_at + timedelta(minutes=25),
        credited_tracked_minutes=0,
        state="proposed",
    )
    active = detail.active_revision
    assert active is not None
    pending = DeadlinePlanRevision(
        **{
            **active.model_dump(),
            "revision": 2,
            "base_revision": 1,
            "state": "proposed",
            "planned_minutes": 25,
            "unscheduled_minutes": 35,
            "created_at": NOW,
            "activated_at": None,
            "blocks": [block],
        },
    )
    detail = DeadlinePlanDetail(
        plan=detail.plan.model_copy(update={"latest_revision": 2}),
        active_revision=active,
        pending_revision=pending,
        progress=detail.progress,
    )
    service, _ = _service(
        [detail],
        sleep_rows=[_sleep_row(NOW.date(), estimated_minutes=480)],
    )

    result = asyncio.run(service.get_exam_week_outlook(user_id="owner"))

    assert result.exams[0].active_revision == 1
    assert result.exams[0].pending_revision == 2
    assert result.exams[0].pending_preview_sleep_overlap is True
    assert "pending_preview_sleep_overlap" in result.warning_codes


@pytest.mark.parametrize(
    "now",
    (
        datetime(2026, 3, 29, 0, 30, tzinfo=UTC),
        datetime(2026, 10, 25, 0, 30, tzinfo=UTC),
    ),
)
def test_dst_gap_or_fold_keeps_sleep_protected_capacity_unknown(
    now: datetime,
) -> None:
    local_date = now.astimezone(ZoneInfo("Europe/Berlin")).date()
    service, _ = _service(
        [_detail(plan_id=EXAM_ID, kind="exam", days=7, now=now)],
        context=_context(timezone="Europe/Berlin"),
        sleep_rows=[
            _sleep_row(
                local_date,
                estimated_minutes=480,
                planned_sleep_time="02:30",
            ),
        ],
        now=now,
    )

    result = asyncio.run(service.get_exam_week_outlook(user_id="owner"))

    assert result.capacity_status == "unknown"
    assert result.risk_level == "unknown"
    assert "capacity_incomplete" in result.warning_codes


def _sleep_row(
    local_date: date,
    *,
    estimated_minutes: int,
    planned_sleep_time: str = "23:00",
) -> dict:
    started_at = datetime.combine(
        local_date - timedelta(days=1),
        time(23),
        tzinfo=UTC,
    )
    woke_at = started_at + timedelta(minutes=estimated_minutes)
    return {
        "id": f"sleep-{local_date.isoformat()}",
        "entry_date": local_date.isoformat(),
        "metadata": {
            "capture_version": "daily-capture-v4",
            "captures": {
                "evening": {
                    "branch_version": "daily-capture-v4",
                    "capture_kind": "evening",
                    "entry_date": local_date.isoformat(),
                    "capture_id": f"evening-{local_date.isoformat()}",
                    "captured_at": datetime.combine(
                        local_date - timedelta(days=1),
                        time(20),
                        tzinfo=UTC,
                    ).isoformat(),
                    "mood": 7,
                    "energy": 6,
                    "stress_intensity": 3,
                    "stress_intensity_label": "low",
                    "planned_sleep_time": planned_sleep_time,
                    "sleep_target_minutes": 480,
                },
                "morning": {
                    "branch_version": "daily-capture-v4",
                    "capture_kind": "morning",
                    "entry_date": local_date.isoformat(),
                    "capture_id": f"morning-{local_date.isoformat()}",
                    "captured_at": woke_at.isoformat(),
                    "estimated_sleep_started_at": started_at.isoformat(),
                    "woke_at": woke_at.isoformat(),
                    "estimated_sleep_minutes": estimated_minutes,
                    "sleep_target_minutes": 480,
                    "source_evening_capture_id": (f"evening-{local_date.isoformat()}"),
                    "sleep_hours": estimated_minutes / 60,
                    "sleep_quality": 7,
                    "current_energy": 7,
                    "day_shape": "normal",
                },
            },
        },
    }
