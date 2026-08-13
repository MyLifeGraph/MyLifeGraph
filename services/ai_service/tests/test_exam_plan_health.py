import json
from datetime import UTC, date, datetime, timedelta
from uuid import UUID
from zoneinfo import ZoneInfo

import pytest
from pydantic import ValidationError

from app.models.exam_plan_health import (
    ExamPlanHealthItem,
    ExamPlanHealthPreviewRequest,
)
from app.repositories.deadline_plan_repository import ExamPlanHealthSnapshot
from app.services.exam_plan_health import (
    _capacity_inputs,
    _can_allocate_exact,
    _exam_candidates,
    _health_status,
    _recommended_start,
    _study_capacity_minutes,
    build_exam_plan_health,
)
from app.services.planning_availability import BusySources, allocate_task_intervals


NOW = datetime(2026, 8, 13, 8, tzinfo=UTC)
PLAN_ID = UUID("11111111-1111-4111-8111-111111111111")


def _snapshot(**overrides) -> ExamPlanHealthSnapshot:
    values = {
        "generated_at": NOW,
        "local_today": NOW.date(),
        "horizon_ends_before": NOW.date() + timedelta(days=367),
        "profile": {
            "timezone": "UTC",
            "timezone_revision": 3,
            "daily_preparation_budget_minutes": 120,
        },
        "best_energy_window": "morning",
        "study_setup": {
            "contract_version": "study-setup-v1",
            "focus_minutes": 50,
            "recovery_minutes": 10,
            "setup_revision": 4,
            "preparation_items": [],
            "current_semester": None,
            "next_semester": None,
        },
        "planner_preference": {"use_calendar_busy_time": False},
        "exams": [
            {
                "id": str(PLAN_ID),
                "title": "Analysis",
                "first_activated_at": "2026-08-01T08:00:00+00:00",
                "current_revision": 1,
                "latest_revision": 1,
                "revision": 1,
                "deadline_at": "2026-08-30T18:00:00+00:00",
                "estimated_total_minutes": 300,
                "credited_prior_minutes": 0,
                "preferred_session_minutes": 120,
                "max_daily_minutes": 120,
                "planning_start_on": "2026-08-13",
                "buffer_days": 2,
                "use_calendar_availability": False,
                "recovery_minutes": 10,
                "study_setup_revision": 4,
                "timezone": "UTC",
                "best_energy_window": "morning",
                "tracked_focus_minutes_at_proposal": 0,
                "active_block_count": 0,
            },
        ],
        "focus_totals": [
            {"plan_id": str(PLAN_ID), "actual_minutes": 0, "focus_count": 0},
        ],
        "focus_facts": [],
        "deadline_blocks": [],
        "schedule_items": [],
        "planner_task_blocks": [],
        "planner_habit_slots": [],
        "planner_commitments": [],
        "calendar_import": None,
        "calendar_timed_events": [],
        "calendar_all_day_events": [],
    }
    values.update(overrides)
    return ExamPlanHealthSnapshot(**values)


def _preview_payload() -> dict[str, object]:
    return {
        "contract_version": "exam-plan-health-v1",
        "kind": "exam",
        "title": "Physics",
        "deadline_at": "2026-09-20T18:00:00+00:00",
        "estimated_total_minutes": 420,
        "credited_prior_minutes": 20,
        "preferred_session_minutes": 120,
        "max_daily_minutes": 120,
        "planning_start_on": "2026-08-14",
        "buffer_days": 2,
        "source_kind": "manual",
        "use_calendar_availability": False,
    }


def _one_off_busy(
    *,
    starts_at: str,
    ends_at: str,
    suffix: int,
) -> dict[str, object]:
    return {
        "id": f"77777777-7777-4777-8777-{suffix:012d}",
        "recurrence": "one_off",
        "starts_at": starts_at,
        "ends_at": ends_at,
        "weekday": None,
        "local_starts_at": None,
        "local_ends_at": None,
        "created_at": "2026-08-01T08:00:00+00:00",
    }


def test_thresholds_are_exact_and_apply_only_to_uncovered_work() -> None:
    common = {
        "overdue": False,
        "missing_sources": [],
        "authority_reasons": [],
        "minutes_to_schedule": 500,
        "preferred_session_minutes": 50,
        "latest_safe_start_on": date(2026, 8, 21),
        "local_today": date(2026, 8, 13),
    }
    status, reasons = _health_status(reserve_minutes=100, **common)
    assert status == "green"
    assert reasons == []  # exactly 20%, exactly two sessions, eight days

    status, reasons = _health_status(
        reserve_minutes=99,
        **{**common, "latest_safe_start_on": date(2026, 8, 20)},
    )
    assert status == "yellow"
    assert reasons == [
        "low_percentage_reserve",
        "low_session_reserve",
        "latest_safe_start_near",
    ]

    status, reasons = _health_status(
        reserve_minutes=0,
        **{**common, "minutes_to_schedule": 0},
    )
    assert status == "green"
    assert reasons == []


def test_status_precedence_covers_one_minute_deficit_unknown_and_overdue() -> None:
    common = {
        "authority_reasons": [],
        "minutes_to_schedule": 1,
        "preferred_session_minutes": 50,
        "latest_safe_start_on": None,
        "local_today": date(2026, 8, 13),
    }
    assert _health_status(
        overdue=False,
        missing_sources=[],
        reserve_minutes=-1,
        **common,
    ) == ("red", ["capacity_deficit"])
    assert _health_status(
        overdue=False,
        missing_sources=["calendar_import"],
        authority_reasons=["calendar_import_unavailable"],
        reserve_minutes=None,
        **{key: value for key, value in common.items() if key != "authority_reasons"},
    ) == ("unknown", ["calendar_import_unavailable"])
    assert _health_status(
        overdue=True,
        missing_sources=["calendar_import"],
        authority_reasons=["calendar_import_unavailable"],
        reserve_minutes=None,
        **{key: value for key, value in common.items() if key != "authority_reasons"},
    ) == (
        "red",
        ["overdue_remaining", "calendar_import_unavailable"],
    )


def test_builder_uses_focus_credit_and_returns_all_capacity_numbers() -> None:
    snapshot = _snapshot(
        focus_totals=[
            {"plan_id": str(PLAN_ID), "actual_minutes": 75, "focus_count": 2},
        ],
    )
    response = build_exam_plan_health(snapshot=snapshot)
    item = response.exams[0]
    assert item.remaining_minutes == 225
    assert item.sessions_needed == 5
    assert item.preferred_session_minutes == 50
    assert item.available_replan_capacity_minutes is not None
    assert item.reserve_minutes == (
        item.available_replan_capacity_minutes - item.minutes_to_schedule
    )
    assert item.future_reserved_minutes == 0


def test_study_short_only_capacity_covers_remaining_work_with_recovery() -> None:
    exam = {
        **_snapshot().exams[0],
        "deadline_at": "2026-08-13T21:00:00+00:00",
        "estimated_total_minutes": 30,
        "max_daily_minutes": 50,
        "buffer_days": 0,
    }
    item = build_exam_plan_health(
        snapshot=_snapshot(
            exams=[exam],
            planner_commitments=[
                _one_off_busy(
                    starts_at="2026-08-13T08:55:00+00:00",
                    ends_at="2026-08-13T21:00:00+00:00",
                    suffix=1,
                ),
            ],
        ),
    ).exams[0]

    assert item.available_replan_capacity_minutes == 30
    assert item.reserve_minutes == 0
    assert item.status != "red"


def test_non_study_capacity_keeps_partial_gap_behavior() -> None:
    exam = {
        **_snapshot().exams[0],
        "deadline_at": "2026-08-13T21:00:00+00:00",
        "estimated_total_minutes": 40,
        "preferred_session_minutes": 50,
        "max_daily_minutes": 50,
        "buffer_days": 0,
    }
    item = build_exam_plan_health(
        snapshot=_snapshot(
            study_setup=None,
            exams=[exam],
            planner_commitments=[
                _one_off_busy(
                    starts_at="2026-08-13T08:55:00+00:00",
                    ends_at="2026-08-13T21:00:00+00:00",
                    suffix=31,
                ),
            ],
        ),
    ).exams[0]

    assert item.available_replan_capacity_minutes == 40
    assert item.reserve_minutes == 0


def test_study_capacity_adds_one_final_short_remainder_after_full_blocks() -> None:
    exam = {
        **_snapshot().exams[0],
        "deadline_at": "2026-08-13T21:00:00+00:00",
        "estimated_total_minutes": 100,
        "buffer_days": 0,
    }
    item = build_exam_plan_health(
        snapshot=_snapshot(
            exams=[exam],
            planner_commitments=[
                _one_off_busy(
                    starts_at="2026-08-13T10:55:00+00:00",
                    ends_at="2026-08-13T21:00:00+00:00",
                    suffix=2,
                ),
            ],
        ),
    ).exams[0]

    assert item.available_replan_capacity_minutes == 120
    assert item.reserve_minutes == 20
    assert item.status != "red"


def test_study_capacity_does_not_invent_a_remainder_without_a_post_full_gap() -> None:
    exam = {
        **_snapshot().exams[0],
        "deadline_at": "2026-08-13T21:00:00+00:00",
        "estimated_total_minutes": 100,
        "buffer_days": 0,
    }
    item = build_exam_plan_health(
        snapshot=_snapshot(
            exams=[exam],
            planner_commitments=[
                _one_off_busy(
                    starts_at="2026-08-13T08:40:00+00:00",
                    ends_at="2026-08-13T09:00:00+00:00",
                    suffix=3,
                ),
                _one_off_busy(
                    starts_at="2026-08-13T10:00:00+00:00",
                    ends_at="2026-08-13T21:00:00+00:00",
                    suffix=4,
                ),
            ],
        ),
    ).exams[0]

    assert item.available_replan_capacity_minutes == 50


def test_study_capacity_returns_only_an_exact_canonical_allocation() -> None:
    generated = datetime(2026, 8, 12, 8, tzinfo=UTC)
    exam = {
        **_snapshot().exams[0],
        "deadline_at": "2026-08-15T21:00:00+00:00",
        "estimated_total_minutes": 25,
        "max_daily_minutes": 70,
        "active_block_count": 115,
        "buffer_days": 0,
    }
    commitments = [
        _one_off_busy(
            starts_at=f"2026-08-{day:02d}T{busy_start}:00+00:00",
            ends_at=f"2026-08-{day:02d}T21:00:00+00:00",
            suffix=40 + day,
        )
        for day, busy_start in ((13, "08:35"), (14, "10:00"), (15, "08:55"))
    ]
    snapshot = _snapshot(
        generated_at=generated,
        local_today=generated.date(),
        horizon_ends_before=generated.date() + timedelta(days=367),
        exams=[exam],
        planner_commitments=commitments,
    )

    item = build_exam_plan_health(snapshot=snapshot).exams[0]
    direct_args = dict(
        starts_on=date(2026, 8, 13),
        ends_on=date(2026, 8, 15),
        preferred_session_minutes=50,
        max_daily_minutes=70,
        zone=ZoneInfo("UTC"),
        local_now=generated,
        energy_window="morning",
        busy_sources=BusySources(
            timed_intervals=[
                {
                    "starts_at": commitment["starts_at"],
                    "ends_at": commitment["ends_at"],
                }
                for commitment in commitments
            ],
        ),
        deadline_at=datetime(2026, 8, 15, 21, tzinfo=UTC),
        account_daily_budget_minutes=120,
        max_blocks=5,
        duration_increment_minutes=5,
        recovery_minutes=10,
        exact_session_blocks=True,
        allocation_policy="spread_first",
    )
    direct_50 = allocate_task_intervals(total_minutes=50, **direct_args)
    direct_25 = allocate_task_intervals(total_minutes=25, **direct_args)

    assert sum(block.minutes for block in direct_50) != 50
    assert sum(block.minutes for block in direct_25) == 25
    assert item.available_replan_capacity_minutes == 25


def test_study_capacity_search_is_bounded_by_slots_and_focus_size(monkeypatch) -> None:
    snapshot = _snapshot()
    inputs = _capacity_inputs(snapshot)
    candidate = _exam_candidates(snapshot, preview=None)[0]
    calls = 0

    def count_failed_allocations(**_kwargs):
        nonlocal calls
        calls += 1
        return []

    monkeypatch.setattr(
        "app.services.exam_plan_health._allocate",
        count_failed_allocations,
    )

    result = _study_capacity_minutes(
        candidate=candidate,
        inputs=inputs,
        starts_on=date(2026, 8, 13),
        ends_on=date(2026, 8, 27),
        timed=(),
        daily_reserved={},
        plan_reserved={},
    )

    remaining_slots = 120 - candidate.active_block_count
    assert result == 0
    assert calls <= 1 + remaining_slots * inputs.setup_focus_minutes // 5


def test_study_target_feasibility_uses_one_exact_allocator_call(monkeypatch) -> None:
    snapshot = _snapshot()
    inputs = _capacity_inputs(snapshot)
    candidate = _exam_candidates(snapshot, preview=None)[0]
    calls = 0

    def count_exact_allocation(**kwargs):
        nonlocal calls
        calls += 1
        return [
            type("Interval", (), {"minutes": kwargs["total_minutes"]})(),
        ]

    monkeypatch.setattr(
        "app.services.exam_plan_health._allocate",
        count_exact_allocation,
    )

    assert _can_allocate_exact(
        candidate=candidate,
        inputs=inputs,
        starts_on=date(2026, 8, 13),
        ends_on=date(2026, 8, 27),
        target_minutes=300,
        timed=(),
        daily_reserved={},
        plan_reserved={},
    )
    assert calls == 1


@pytest.mark.parametrize(
    ("account_cap", "plan_cap"),
    [(70, 120), (120, 70)],
)
def test_study_remainder_capacity_obeys_account_and_plan_daily_caps(
    account_cap: int,
    plan_cap: int,
) -> None:
    exam = {
        **_snapshot().exams[0],
        "deadline_at": "2026-08-13T21:00:00+00:00",
        "estimated_total_minutes": 70,
        "max_daily_minutes": plan_cap,
        "buffer_days": 0,
    }
    item = build_exam_plan_health(
        snapshot=_snapshot(
            profile={
                "timezone": "UTC",
                "timezone_revision": 3,
                "daily_preparation_budget_minutes": account_cap,
            },
            exams=[exam],
        ),
    ).exams[0]

    assert item.available_replan_capacity_minutes == 70


@pytest.mark.parametrize(
    ("active_block_count", "expected_capacity"),
    [(119, 30), (120, 0)],
)
def test_study_capacity_obeys_remaining_revision_block_slots(
    active_block_count: int,
    expected_capacity: int,
) -> None:
    exam = {
        **_snapshot().exams[0],
        "deadline_at": "2026-08-13T21:00:00+00:00",
        "active_block_count": active_block_count,
        "buffer_days": 0,
    }

    item = build_exam_plan_health(
        snapshot=_snapshot(
            exams=[exam],
            planner_commitments=[
                _one_off_busy(
                    starts_at="2026-08-13T08:55:00+00:00",
                    ends_at="2026-08-13T21:00:00+00:00",
                    suffix=5,
                ),
            ],
        ),
    ).exams[0]

    assert item.available_replan_capacity_minutes == expected_capacity


def test_recommended_start_requires_twenty_percent_placeable_study_capacity() -> None:
    deadline = date(2026, 8, 22)
    exam = {
        **_snapshot().exams[0],
        "deadline_at": "2026-08-22T21:00:00+00:00",
        "estimated_total_minutes": 25,
        "max_daily_minutes": 50,
        "buffer_days": 0,
    }
    commitments = [
        _one_off_busy(
            starts_at=f"{day.isoformat()}T{end}:00+00:00",
            ends_at=f"{day.isoformat()}T21:00:00+00:00",
            suffix=index,
        )
        for index, day in enumerate(
            (
                date(2026, 8, 13) + timedelta(days=offset)
                for offset in range((deadline - date(2026, 8, 13)).days + 1)
            ),
            start=10,
        )
        for end in [
            "08:55"
            if day == date(2026, 8, 13)
            else "09:00"
            if day == date(2026, 8, 15)
            else "08:40"
        ]
    ]

    without_reserve = build_exam_plan_health(
        snapshot=_snapshot(
            exams=[exam],
            planner_commitments=[
                {
                    **commitment,
                    "starts_at": f"{commitment['starts_at'][:10]}T08:35:00+00:00",
                }
                for commitment in commitments
            ],
        ),
    ).exams[0]
    item = build_exam_plan_health(
        snapshot=_snapshot(exams=[exam], planner_commitments=commitments),
    ).exams[0]

    assert item.latest_safe_start_on == deadline
    assert without_reserve.recommended_start_on is None
    assert item.recommended_start_on == date(2026, 8, 15)


def test_study_recommended_start_rounds_raw_twenty_percent_target_to_grid() -> None:
    deadline = date(2026, 8, 22)
    exam = {
        **_snapshot().exams[0],
        "deadline_at": "2026-08-22T21:00:00+00:00",
        "estimated_total_minutes": 30,
        "max_daily_minutes": 50,
        "buffer_days": 0,
    }
    days = [
        date(2026, 8, 13) + timedelta(days=offset)
        for offset in range((deadline - date(2026, 8, 13)).days + 1)
    ]
    ample = [
        _one_off_busy(
            starts_at=(
                f"{day.isoformat()}T"
                f"{'09:00' if day == date(2026, 8, 15) else '08:40'}:00+00:00"
            ),
            ends_at=f"{day.isoformat()}T21:00:00+00:00",
            suffix=100 + index,
        )
        for index, day in enumerate(days)
    ]
    only_thirty = [
        {
            **commitment,
            "starts_at": f"{commitment['starts_at'][:10]}T08:40:00+00:00",
        }
        for commitment in ample
    ]
    insufficient_thirty_five = [
        {
            **commitment,
            "starts_at": f"{commitment['starts_at'][:10]}T08:45:00+00:00",
        }
        for commitment in ample
    ]

    ample_snapshot = _snapshot(exams=[exam], planner_commitments=ample)
    thirty_snapshot = _snapshot(exams=[exam], planner_commitments=only_thirty)
    thirty_five_snapshot = _snapshot(
        exams=[exam],
        planner_commitments=insufficient_thirty_five,
    )
    recommended = build_exam_plan_health(snapshot=ample_snapshot).exams[0]
    insufficient = build_exam_plan_health(snapshot=thirty_snapshot).exams[0]
    insufficient_35 = build_exam_plan_health(snapshot=thirty_five_snapshot).exams[0]

    def exact_from_recommended_start(
        snapshot: ExamPlanHealthSnapshot,
        target: int,
    ) -> bool:
        inputs = _capacity_inputs(snapshot)
        candidate = _exam_candidates(snapshot, preview=None)[0]
        return _can_allocate_exact(
            candidate=candidate,
            inputs=inputs,
            starts_on=date(2026, 8, 15),
            ends_on=deadline,
            target_minutes=target,
            timed=inputs.base_timed,
            daily_reserved=inputs.deadline_daily_reserved,
            plan_reserved={},
        )

    assert exact_from_recommended_start(ample_snapshot, 40)
    assert recommended.recommended_start_on == date(2026, 8, 15)
    assert exact_from_recommended_start(thirty_snapshot, 30)
    assert not exact_from_recommended_start(thirty_snapshot, 40)
    assert insufficient.recommended_start_on is None
    assert exact_from_recommended_start(thirty_five_snapshot, 35)
    assert not exact_from_recommended_start(thirty_five_snapshot, 40)
    assert insufficient_35.recommended_start_on is None


def test_non_study_recommended_start_keeps_raw_twenty_percent_target(
    monkeypatch,
) -> None:
    snapshot = _snapshot(study_setup=None)
    inputs = _capacity_inputs(snapshot)
    candidate = _exam_candidates(snapshot, preview=None)[0]
    observed_target: int | None = None

    def capture_target(**kwargs):
        nonlocal observed_target
        observed_target = kwargs["target_minutes"]
        return kwargs["first"]

    monkeypatch.setattr(
        "app.services.exam_plan_health._latest_date_with_capacity",
        capture_target,
    )

    result = _recommended_start(
        candidate=candidate,
        inputs=inputs,
        minutes=30,
        finish_on=date(2026, 8, 27),
        latest_safe=date(2026, 8, 27),
        timed=(),
        daily_reserved={},
        plan_reserved={},
    )

    assert observed_target == 36
    assert result == inputs.local_today


def test_study_short_capacity_reserves_recovery_across_dst_change() -> None:
    generated = datetime(2026, 3, 28, 7, tzinfo=UTC)
    exam = {
        **_snapshot().exams[0],
        "deadline_at": "2026-03-29T19:00:00+00:00",
        "estimated_total_minutes": 30,
        "max_daily_minutes": 50,
        "planning_start_on": "2026-03-29",
        "buffer_days": 0,
        "timezone": "Europe/Berlin",
    }
    item = build_exam_plan_health(
        snapshot=_snapshot(
            generated_at=generated,
            local_today=date(2026, 3, 28),
            horizon_ends_before=date(2027, 3, 30),
            profile={
                "timezone": "Europe/Berlin",
                "timezone_revision": 4,
                "daily_preparation_budget_minutes": 120,
            },
            exams=[exam],
            planner_commitments=[
                _one_off_busy(
                    starts_at="2026-03-29T06:40:00+00:00",
                    ends_at="2026-03-29T19:00:00+00:00",
                    suffix=30,
                ),
            ],
        ),
    ).exams[0]

    assert item.available_replan_capacity_minutes == 30
    assert item.status != "red"


def test_completed_overdue_exam_is_green_with_noncontradictory_dates() -> None:
    exam = {
        **_snapshot().exams[0],
        "deadline_at": "2026-08-10T18:00:00+00:00",
        "planning_start_on": "2026-08-01",
    }
    item = build_exam_plan_health(
        snapshot=_snapshot(
            exams=[exam],
            planner_preference={"use_calendar_busy_time": True},
            schedule_items=[
                {
                    "id": "88888888-8888-4888-8888-888888888888",
                    "weekday": 7,
                    "starts_at": "02:15:00",
                    "ends_at": "03:15:00",
                    "metadata": {},
                },
            ],
            focus_totals=[
                {
                    "plan_id": str(PLAN_ID),
                    "actual_minutes": 300,
                    "focus_count": 6,
                },
            ],
        ),
    ).exams[0]

    assert item.remaining_minutes == 0
    assert item.minutes_to_schedule == 0
    assert item.status == "green"
    assert item.reasons == []
    assert item.recommended_start_on == NOW.date()
    assert item.latest_safe_start_on == NOW.date()


def test_future_reservations_and_shared_exam_priority_are_exact() -> None:
    second_id = UUID("22222222-2222-4222-8222-222222222222")
    first = dict(_snapshot().exams[0])
    first["estimated_total_minutes"] = 400
    second = {
        **first,
        "id": str(second_id),
        "title": "Smaller exam",
        "estimated_total_minutes": 100,
    }
    response = build_exam_plan_health(
        snapshot=_snapshot(
            exams=[second, first],
            focus_totals=[
                {"plan_id": str(PLAN_ID), "actual_minutes": 75, "focus_count": 2},
                {"plan_id": str(second_id), "actual_minutes": 0, "focus_count": 0},
            ],
            deadline_blocks=[
                {
                    "id": "44444444-4444-4444-8444-444444444444",
                    "plan_id": str(PLAN_ID),
                    "revision": 1,
                    "sequence": 1,
                    "starts_at": "2026-08-20T09:00:00+00:00",
                    "ends_at": "2026-08-20T09:50:00+00:00",
                    "reserved_ends_at": "2026-08-20T10:00:00+00:00",
                    "local_date": "2026-08-20",
                    "planned_minutes": 50,
                    "recovery_minutes": 10,
                },
            ],
        ),
    )

    larger, smaller = response.exams
    assert larger.plan_id == PLAN_ID
    assert smaller.plan_id == second_id
    assert larger.remaining_minutes == 325
    assert larger.future_reserved_minutes == 50
    assert larger.minutes_to_schedule == 275
    assert smaller.available_replan_capacity_minutes <= (
        larger.available_replan_capacity_minutes - larger.minutes_to_schedule
    )


def test_future_reservation_subtracts_exact_source_linked_focus_credit() -> None:
    block_id = "44444444-4444-4444-8444-444444444444"
    exam = {**_snapshot().exams[0], "active_block_count": 1}
    item = build_exam_plan_health(
        snapshot=_snapshot(
            exams=[exam],
            focus_totals=[
                {"plan_id": str(PLAN_ID), "actual_minutes": 50, "focus_count": 1},
            ],
            focus_facts=[
                {
                    "id": "99999999-9999-4999-8999-999999999999",
                    "plan_id": str(PLAN_ID),
                    "started_at": "2026-08-13T08:00:00+00:00",
                    "actual_minutes": 50,
                    "deadline_plan_block_id": block_id,
                },
            ],
            deadline_blocks=[
                {
                    "id": block_id,
                    "plan_id": str(PLAN_ID),
                    "revision": 1,
                    "sequence": 1,
                    "starts_at": "2026-08-20T09:00:00+00:00",
                    "ends_at": "2026-08-20T09:50:00+00:00",
                    "reserved_ends_at": "2026-08-20T10:00:00+00:00",
                    "local_date": "2026-08-20",
                    "planned_minutes": 50,
                    "recovery_minutes": 10,
                },
            ],
        ),
    ).exams[0]

    assert item.remaining_minutes == 250
    assert item.future_reserved_minutes == 0
    assert item.minutes_to_schedule == 250


def test_proposal_time_focus_is_not_reused_as_future_block_credit() -> None:
    block_id = "44444444-4444-4444-8444-444444444444"
    exam = {
        **_snapshot().exams[0],
        "tracked_focus_minutes_at_proposal": 50,
        "active_block_count": 1,
    }
    item = build_exam_plan_health(
        snapshot=_snapshot(
            exams=[exam],
            focus_totals=[
                {"plan_id": str(PLAN_ID), "actual_minutes": 50, "focus_count": 1},
            ],
            focus_facts=[
                {
                    "id": "99999999-9999-4999-8999-999999999999",
                    "plan_id": str(PLAN_ID),
                    "started_at": "2026-08-02T08:00:00+00:00",
                    "actual_minutes": 50,
                    "deadline_plan_block_id": block_id,
                },
            ],
            deadline_blocks=[
                {
                    "id": block_id,
                    "plan_id": str(PLAN_ID),
                    "revision": 1,
                    "sequence": 1,
                    "starts_at": "2026-08-20T09:00:00+00:00",
                    "ends_at": "2026-08-20T09:50:00+00:00",
                    "reserved_ends_at": "2026-08-20T10:00:00+00:00",
                    "local_date": "2026-08-20",
                    "planned_minutes": 50,
                    "recovery_minutes": 10,
                },
            ],
        ),
    ).exams[0]

    assert item.remaining_minutes == 250
    assert item.future_reserved_minutes == 50
    assert item.minutes_to_schedule == 200


def test_retained_blocks_consume_the_revision_block_limit() -> None:
    exam = {**_snapshot().exams[0], "active_block_count": 120}
    item = build_exam_plan_health(snapshot=_snapshot(exams=[exam])).exams[0]

    assert item.available_replan_capacity_minutes == 0
    assert item.reserve_minutes == -300
    assert item.status == "red"


def test_consumers_recovery_and_account_cap_reduce_real_capacity() -> None:
    baseline = build_exam_plan_health(snapshot=_snapshot()).exams[0]
    constrained = build_exam_plan_health(
        snapshot=_snapshot(
            profile={
                "timezone": "UTC",
                "timezone_revision": 3,
                "daily_preparation_budget_minutes": 50,
            },
            study_setup={
                **_snapshot().study_setup,
                "recovery_minutes": 60,
            },
            planner_task_blocks=[
                {
                    "id": "55555555-5555-4555-8555-555555555555",
                    "plan_id": "66666666-6666-4666-8666-666666666666",
                    "starts_at": "2026-08-14T09:00:00+00:00",
                    "ends_at": "2026-08-14T11:00:00+00:00",
                    "reserved_ends_at": "2026-08-14T11:10:00+00:00",
                    "local_date": "2026-08-14",
                    "planned_minutes": 120,
                    "recovery_minutes": 10,
                },
            ],
            planner_commitments=[
                {
                    "id": "77777777-7777-4777-8777-777777777777",
                    "recurrence": "weekly",
                    "starts_at": None,
                    "ends_at": None,
                    "weekday": 1,
                    "local_starts_at": "09:00:00",
                    "local_ends_at": "12:00:00",
                    "created_at": "2026-08-01T08:00:00+00:00",
                },
            ],
        ),
    ).exams[0]

    assert constrained.available_replan_capacity_minutes < (
        baseline.available_replan_capacity_minutes
    )


def test_dst_ambiguous_recurring_occurrence_returns_unknown() -> None:
    generated = datetime(2026, 10, 20, 8, tzinfo=UTC)
    exam = {
        **_snapshot().exams[0],
        "deadline_at": "2026-10-30T18:00:00+00:00",
        "planning_start_on": "2026-10-20",
        "timezone": "Europe/Berlin",
    }
    item = build_exam_plan_health(
        snapshot=_snapshot(
            generated_at=generated,
            local_today=date(2026, 10, 20),
            horizon_ends_before=date(2027, 10, 22),
            profile={
                "timezone": "Europe/Berlin",
                "timezone_revision": 4,
                "daily_preparation_budget_minutes": 120,
            },
            exams=[exam],
            schedule_items=[
                {
                    "id": "88888888-8888-4888-8888-888888888888",
                    "weekday": 7,
                    "starts_at": "02:15:00",
                    "ends_at": "03:15:00",
                    "metadata": {},
                },
            ],
        ),
    ).exams[0]

    assert item.status == "unknown"
    assert item.missing_sources == ["recurring_availability"]
    assert item.reasons == ["recurring_availability_invalid"]


def test_previous_day_overnight_recurrence_blocks_first_health_day() -> None:
    exam = {
        **_snapshot().exams[0],
        "deadline_at": "2026-08-13T21:00:00+00:00",
        "buffer_days": 0,
    }
    item = build_exam_plan_health(
        snapshot=_snapshot(
            exams=[exam],
            schedule_items=[
                {
                    "id": "88888888-8888-4888-8888-888888888888",
                    "weekday": 3,
                    "starts_at": "23:00:00",
                    "ends_at": "09:30:00",
                    "metadata": {},
                },
            ],
            planner_commitments=[
                {
                    "id": "77777777-7777-4777-8777-777777777777",
                    "recurrence": "one_off",
                    "starts_at": "2026-08-13T10:00:00+00:00",
                    "ends_at": "2026-08-13T21:00:00+00:00",
                    "weekday": None,
                    "local_starts_at": None,
                    "local_ends_at": None,
                    "created_at": "2026-08-01T08:00:00+00:00",
                },
            ],
        ),
    ).exams[0]

    assert item.available_replan_capacity_minutes == 20
    assert item.status == "red"


def test_invalid_nonoverlapping_previous_day_dst_occurrence_is_ignored() -> None:
    generated = datetime(2026, 10, 26, 7, tzinfo=UTC)
    exam = {
        **_snapshot().exams[0],
        "deadline_at": "2026-10-26T20:00:00+00:00",
        "planning_start_on": "2026-10-26",
        "buffer_days": 0,
        "timezone": "Europe/Berlin",
    }
    item = build_exam_plan_health(
        snapshot=_snapshot(
            generated_at=generated,
            local_today=date(2026, 10, 26),
            horizon_ends_before=date(2027, 10, 28),
            profile={
                "timezone": "Europe/Berlin",
                "timezone_revision": 4,
                "daily_preparation_budget_minutes": 120,
            },
            exams=[exam],
            schedule_items=[
                {
                    "id": "88888888-8888-4888-8888-888888888888",
                    "weekday": 7,
                    "starts_at": "02:15:00",
                    "ends_at": "03:15:00",
                    "metadata": {},
                },
            ],
        ),
    ).exams[0]

    assert item.status != "unknown"
    assert item.missing_sources == []


def test_invalid_previous_day_dst_occurrence_is_unknown_when_it_can_spill() -> None:
    generated = datetime(2026, 10, 26, 7, tzinfo=UTC)
    exam = {
        **_snapshot().exams[0],
        "deadline_at": "2026-10-26T20:00:00+00:00",
        "planning_start_on": "2026-10-26",
        "buffer_days": 0,
        "timezone": "Europe/Berlin",
    }
    item = build_exam_plan_health(
        snapshot=_snapshot(
            generated_at=generated,
            local_today=date(2026, 10, 26),
            horizon_ends_before=date(2027, 10, 28),
            profile={
                "timezone": "Europe/Berlin",
                "timezone_revision": 4,
                "daily_preparation_budget_minutes": 120,
            },
            exams=[exam],
            schedule_items=[
                {
                    "id": "88888888-8888-4888-8888-888888888888",
                    "weekday": 7,
                    "starts_at": "02:15:00",
                    "ends_at": "01:00:00",
                    "metadata": {},
                },
            ],
        ),
    ).exams[0]

    assert item.status == "unknown"
    assert item.missing_sources == ["recurring_availability"]


def test_calendar_missing_and_exclusive_window_end_are_unknown() -> None:
    exam = dict(_snapshot().exams[0])
    exam["use_calendar_availability"] = True
    missing = build_exam_plan_health(
        snapshot=_snapshot(
            exams=[exam],
            planner_preference={"use_calendar_busy_time": True},
        ),
    ).exams[0]
    assert missing.status == "unknown"
    assert missing.missing_sources == ["calendar_import"]
    assert missing.available_replan_capacity_minutes is None

    finish = date(2026, 8, 27)  # deadline 30th with two saved buffer days
    incomplete = build_exam_plan_health(
        snapshot=_snapshot(
            exams=[exam],
            planner_preference={"use_calendar_busy_time": True},
            calendar_import={
                "connection_id": "22222222-2222-4222-8222-222222222222",
                "import_id": "33333333-3333-4333-8333-333333333333",
                "planning_status": "current",
                "timezone": "UTC",
                "profile_timezone_revision": 3,
                "window_starts_on": "2026-08-13",
                "window_ends_before": finish.isoformat(),
            },
        ),
    ).exams[0]
    assert incomplete.status == "unknown"
    assert incomplete.missing_sources == ["calendar_horizon"]

    # Health models a replan with the current account preference. The saved
    # revision value remains historical input for its existing blocks.
    calendar_off = build_exam_plan_health(snapshot=_snapshot(exams=[exam])).exams[0]
    assert calendar_off.status != "unknown"
    assert calendar_off.missing_sources == []

    preview = ExamPlanHealthPreviewRequest.model_validate(_preview_payload())
    preview_unknown = build_exam_plan_health(
        snapshot=_snapshot(
            exams=[],
            planner_preference={"use_calendar_busy_time": True},
        ),
        preview=preview,
    ).exam
    assert preview.use_calendar_availability is False
    assert preview_unknown.status == "unknown"
    assert preview_unknown.missing_sources == ["calendar_import"]


def test_preview_contract_is_strict_and_does_not_need_mutation_identity() -> None:
    parsed = ExamPlanHealthPreviewRequest.model_validate_json(
        json.dumps(_preview_payload()),
    )
    assert parsed.kind == "exam"
    assert not hasattr(parsed, "request_id")
    response = build_exam_plan_health(snapshot=_snapshot(), preview=parsed)
    assert response.origin == "authenticated_backend_preview"
    assert response.exam.title == "Physics"
    assert response.exam.plan_id == UUID(
        "00000000-0000-4000-8000-000000000000",
    )

    invalid = _preview_payload()
    invalid["kind"] = "assignment"
    with pytest.raises(ValidationError):
        ExamPlanHealthPreviewRequest.model_validate_json(json.dumps(invalid))


@pytest.mark.parametrize(
    ("overrides", "message"),
    [
        (
            {"deadline_at": NOW.isoformat()},
            "deadline_at must be in the future",
        ),
        (
            {"deadline_at": (NOW + timedelta(days=366, seconds=1)).isoformat()},
            "deadline_at must be within 366 days",
        ),
        (
            {
                "deadline_at": (NOW + timedelta(days=10)).isoformat(),
                "planning_start_on": (NOW.date() + timedelta(days=11)).isoformat(),
            },
            "planning_start_on cannot be after the profile-local deadline day",
        ),
        (
            {
                "deadline_at": (NOW + timedelta(days=10)).isoformat(),
                "planning_start_on": (NOW.date() - timedelta(days=357)).isoformat(),
            },
            "deadline planning horizon cannot exceed 366 days",
        ),
    ],
)
def test_preview_rejects_editor_window_violations_with_stable_detail(
    overrides: dict[str, object],
    message: str,
) -> None:
    preview = ExamPlanHealthPreviewRequest.model_validate(
        {**_preview_payload(), **overrides},
    )

    with pytest.raises(ValueError, match=f"^{message}$"):
        build_exam_plan_health(snapshot=_snapshot(), preview=preview)


def test_existing_preview_requires_exact_owner_active_exam_base_revision() -> None:
    payload = _preview_payload()
    payload["plan_id"] = str(PLAN_ID)
    payload["base_revision"] = 1
    preview = ExamPlanHealthPreviewRequest.model_validate(payload)
    assert (
        build_exam_plan_health(snapshot=_snapshot(), preview=preview).exam.plan_id
        == PLAN_ID
    )

    stale = ExamPlanHealthPreviewRequest.model_validate(
        {**payload, "base_revision": 2},
    )
    with pytest.raises(ValueError, match="revision is not current"):
        build_exam_plan_health(snapshot=_snapshot(), preview=stale)

    arbitrary = ExamPlanHealthPreviewRequest.model_validate(
        {
            **payload,
            "plan_id": "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
        },
    )
    with pytest.raises(ValueError, match="plan is unavailable"):
        build_exam_plan_health(snapshot=_snapshot(), preview=arbitrary)

    with pytest.raises(ValidationError):
        ExamPlanHealthPreviewRequest.model_validate(
            {**_preview_payload(), "base_revision": 1},
        )


def test_item_rejects_false_green_when_authority_is_missing() -> None:
    with pytest.raises(ValidationError):
        ExamPlanHealthItem(
            plan_id=PLAN_ID,
            title="Analysis",
            deadline_at=NOW + timedelta(days=20),
            local_deadline_date=(NOW + timedelta(days=20)).date(),
            status="green",
            remaining_minutes=50,
            preferred_session_minutes=50,
            sessions_needed=1,
            future_reserved_minutes=0,
            minutes_to_schedule=50,
            available_replan_capacity_minutes=None,
            reserve_minutes=None,
            reserve_full_sessions=None,
            latest_safe_start_on=None,
            recommended_start_on=None,
            recommended_start_reason="Calendar authority is incomplete.",
            reasons=["calendar_import_unavailable"],
            missing_sources=["calendar_import"],
        )
