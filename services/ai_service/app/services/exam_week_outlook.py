from collections.abc import Iterable
from dataclasses import dataclass
from datetime import UTC, date, datetime, time, timedelta
from typing import Any
from uuid import UUID
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from app.models.deadline_plans import (
    EXAM_WEEK_OUTLOOK_CONTRACT_VERSION,
    DeadlinePlanDetail,
    DeadlinePlanRevision,
    ExamWeekMinuteTotals,
    ExamWeekOutlookResponse,
    ExamWeekPlanOutlook,
    ExamWeekSleepNight,
    ExamWeekSleepPlan,
)
from app.repositories.deadline_plan_repository import DeadlinePlanningContext
from app.services.daily_capture_parser import (
    DailyCaptureV4SleepEpisode,
    DailyCaptureV4SleepPlan,
    parse_daily_capture_v4_sleep_episode,
    parse_daily_capture_v4_sleep_plan,
)
from app.services.local_time import LocalTimeResolutionError, resolve_local_datetime
from app.services.planning_availability import (
    BusySources,
    allocate_task_intervals,
)


class ExamWeekOutlookCapacityError(RuntimeError):
    pass


@dataclass
class _OutlookPlanInput:
    detail: DeadlinePlanDetail
    local_deadline_date: date
    days_remaining: int
    saved_buffer_days: int
    recommended_buffer_days: int
    last_preparation_date: date
    remaining_minutes: int
    future_scheduled_minutes: int
    future_minutes_after_buffer: int
    missed_preparation_minutes: int
    additional_minutes: int
    pending_preview_sleep_overlap: bool = False


@dataclass(frozen=True)
class _SimulationOutcome:
    planned_minutes: int
    unscheduled_minutes: int


_WARNING_ORDER = (
    "exam_overdue",
    "missing_recommended_buffer",
    "missed_preparation_blocks",
    "remaining_work_does_not_fit",
    "sleep_capacity_tradeoff",
    "repeated_sleep_shortfall",
    "sleep_plan_missing",
    "capacity_incomplete",
    "pending_preview_sleep_overlap",
)


def build_exam_week_outlook(
    *,
    generated_at: datetime,
    context: DeadlinePlanningContext,
    details: list[DeadlinePlanDetail],
    sleep_rows: list[dict[str, Any]],
) -> ExamWeekOutlookResponse:
    if generated_at.tzinfo is None or generated_at.utcoffset() is None:
        raise ValueError("Outlook clock must be timezone-aware.")
    zone = _zone(context.timezone)
    local_now = generated_at.astimezone(zone)
    local_date = local_now.date()
    sleep_plan, recent_nights = _sleep_outlook(
        sleep_rows,
        local_date=local_date,
    )
    active_details = [
        detail
        for detail in details
        if detail.plan.status == "active"
        and detail.active_revision is not None
        and detail.progress.remaining_minutes > 0
    ]
    active_exam_details = [
        detail
        for detail in active_details
        if detail.plan.kind == "exam"
        and (
            detail.active_revision.deadline_at.astimezone(zone).date() - local_date
        ).days
        <= 14
    ]
    overdue = any(
        detail.active_revision.deadline_at.astimezone(zone).date() < local_date
        for detail in active_exam_details
    )
    if overdue:
        mode = "overdue"
    elif any(
        0
        <= (
            detail.active_revision.deadline_at.astimezone(zone).date() - local_date
        ).days
        <= 7
        for detail in active_exam_details
    ):
        mode = "exam_week"
    elif any(
        8
        <= (
            detail.active_revision.deadline_at.astimezone(zone).date() - local_date
        ).days
        <= 14
        for detail in active_exam_details
    ):
        mode = "watch"
    else:
        mode = "inactive"

    if mode == "inactive":
        return ExamWeekOutlookResponse(
            contract_version=EXAM_WEEK_OUTLOOK_CONTRACT_VERSION,
            origin="authenticated_backend",
            generated_at=generated_at,
            timezone=context.timezone,
            local_date=local_date,
            mode="inactive",
            risk_level="on_track",
            capacity_status="unknown",
            current_sleep_plan=sleep_plan,
            recent_sleep_nights=recent_nights,
            exams=[],
            assignments=[],
            warning_codes=[],
            minutes=ExamWeekMinuteTotals(
                remaining_minutes=0,
                future_scheduled_minutes=0,
                missed_preparation_minutes=0,
                simulated_regular_minutes=0,
                unscheduled_regular_minutes=0,
                simulated_sleep_protected_minutes=None,
                unscheduled_sleep_protected_minutes=None,
            ),
        )

    relevant_details = [
        detail
        for detail in active_details
        if (detail.plan.kind == "exam" and detail in active_exam_details)
        or (
            detail.plan.kind == "assignment"
            and (
                detail.active_revision.deadline_at.astimezone(zone).date() - local_date
            ).days
            <= 14
        )
    ]
    relevant_details.sort(
        key=lambda detail: (
            detail.active_revision.deadline_at,
            0 if detail.plan.kind == "exam" else 1,
            str(detail.plan.id),
        ),
    )
    inputs = [
        _outlook_plan_input(
            detail,
            generated_at=generated_at,
            local_date=local_date,
            zone=zone,
        )
        for detail in relevant_details
    ]
    sleep_intervals: list[dict[str, Any]] | None = None
    sleep_intervals_complete = True
    if sleep_plan is not None:
        sleep_intervals, sleep_intervals_complete = _sleep_busy_intervals(
            sleep_plan,
            starts_on=local_date - timedelta(days=1),
            ends_on=local_date + timedelta(days=16),
            zone=zone,
        )
    for item in inputs:
        item.pending_preview_sleep_overlap = bool(
            sleep_intervals
            and item.detail.pending_revision is not None
            and _revision_overlaps_intervals(
                item.detail.pending_revision,
                sleep_intervals,
            )
        )

    regular = _simulate_outlook(
        inputs,
        context=context,
        zone=zone,
        local_now=local_now,
        extra_busy=(),
    )
    protected = (
        _simulate_outlook(
            inputs,
            context=context,
            zone=zone,
            local_now=local_now,
            extra_busy=sleep_intervals,
        )
        if sleep_intervals is not None and sleep_intervals_complete
        else None
    )
    regular_unscheduled = sum(
        outcome.unscheduled_minutes for outcome in regular.values()
    )
    protected_unscheduled = (
        None
        if protected is None
        else sum(outcome.unscheduled_minutes for outcome in protected.values())
    )
    availability_incomplete = (
        context.planner_use_calendar_busy_time is True
        and not context.calendar_availability_current
    ) or not sleep_intervals_complete
    if regular_unscheduled > 0:
        capacity_status = "does_not_fit_before_buffer"
    elif protected_unscheduled == 0 and not availability_incomplete:
        capacity_status = "fits_with_sleep_protected"
    elif (
        protected_unscheduled is not None
        and protected_unscheduled > 0
        and not availability_incomplete
    ):
        capacity_status = "fits_only_using_sleep_window"
    else:
        capacity_status = "unknown"

    warnings: set[str] = set()
    if overdue:
        warnings.add("exam_overdue")
    if any(
        item.detail.plan.kind == "exam"
        and (item.saved_buffer_days < 1 or item.future_minutes_after_buffer > 0)
        for item in inputs
    ):
        warnings.add("missing_recommended_buffer")
    if any(item.missed_preparation_minutes > 0 for item in inputs):
        warnings.add("missed_preparation_blocks")
    if regular_unscheduled > 0:
        warnings.add("remaining_work_does_not_fit")
    if capacity_status == "fits_only_using_sleep_window":
        warnings.add("sleep_capacity_tradeoff")
    if sleep_plan is None:
        warnings.add("sleep_plan_missing")
    if availability_incomplete:
        warnings.add("capacity_incomplete")
    if any(item.pending_preview_sleep_overlap for item in inputs):
        warnings.add("pending_preview_sleep_overlap")
    repeated_shortfall = (
        sum(1 for night in recent_nights if night.at_least_one_hour_short) >= 2
    )
    if repeated_shortfall:
        warnings.add("repeated_sleep_shortfall")

    if overdue or regular_unscheduled > 0:
        risk_level = "high"
    elif warnings.intersection(
        {
            "missing_recommended_buffer",
            "missed_preparation_blocks",
            "sleep_capacity_tradeoff",
            "sleep_plan_missing",
            "pending_preview_sleep_overlap",
        },
    ):
        risk_level = "attention"
    elif availability_incomplete:
        risk_level = "unknown"
    else:
        risk_level = "on_track"
    if repeated_shortfall:
        risk_level = {
            "on_track": "attention",
            "attention": "high",
            "high": "critical",
            "critical": "critical",
            "unknown": "attention",
        }[risk_level]

    rendered = [
        _render_outlook_plan(
            item,
            regular=regular[str(item.detail.plan.id)],
            protected=(
                None if protected is None else protected[str(item.detail.plan.id)]
            ),
        )
        for item in inputs
    ]
    exams = [item for item in rendered if item.kind == "exam"]
    assignments = [item for item in rendered if item.kind == "assignment"]
    return ExamWeekOutlookResponse(
        contract_version=EXAM_WEEK_OUTLOOK_CONTRACT_VERSION,
        origin="authenticated_backend",
        generated_at=generated_at,
        timezone=context.timezone,
        local_date=local_date,
        mode=mode,
        risk_level=risk_level,
        capacity_status=capacity_status,
        current_sleep_plan=sleep_plan,
        recent_sleep_nights=recent_nights,
        exams=exams,
        assignments=assignments,
        warning_codes=[code for code in _WARNING_ORDER if code in warnings],
        minutes=ExamWeekMinuteTotals(
            remaining_minutes=sum(item.remaining_minutes for item in inputs),
            future_scheduled_minutes=sum(
                item.future_scheduled_minutes for item in inputs
            ),
            missed_preparation_minutes=sum(
                item.missed_preparation_minutes for item in inputs
            ),
            simulated_regular_minutes=sum(
                outcome.planned_minutes for outcome in regular.values()
            ),
            unscheduled_regular_minutes=regular_unscheduled,
            simulated_sleep_protected_minutes=(
                None
                if protected is None
                else sum(outcome.planned_minutes for outcome in protected.values())
            ),
            unscheduled_sleep_protected_minutes=protected_unscheduled,
        ),
    )


def _outlook_plan_input(
    detail: DeadlinePlanDetail,
    *,
    generated_at: datetime,
    local_date: date,
    zone: ZoneInfo,
) -> _OutlookPlanInput:
    revision = detail.active_revision
    if detail.plan.status != "active" or revision is None:
        raise ValueError("Outlook received a non-active deadline plan.")
    local_deadline = revision.deadline_at.astimezone(zone).date()
    recommended_buffer = (
        max(revision.buffer_days, 1)
        if detail.plan.kind == "exam"
        else revision.buffer_days
    )
    last_preparation_date = (
        local_deadline
        if recommended_buffer == 0
        else local_deadline - timedelta(days=recommended_buffer + 1)
    )
    future_scheduled = 0
    future_after_buffer = 0
    missed = 0
    for block in revision.blocks:
        uncredited = block.planned_minutes - block.credited_tracked_minutes
        if uncredited <= 0:
            continue
        if block.ends_at <= generated_at:
            missed += uncredited
        elif block.local_date <= last_preparation_date:
            future_scheduled += uncredited
        else:
            future_after_buffer += uncredited
    remaining = detail.progress.remaining_minutes
    return _OutlookPlanInput(
        detail=detail,
        local_deadline_date=local_deadline,
        days_remaining=(local_deadline - local_date).days,
        saved_buffer_days=revision.buffer_days,
        recommended_buffer_days=recommended_buffer,
        last_preparation_date=last_preparation_date,
        remaining_minutes=remaining,
        future_scheduled_minutes=min(remaining, future_scheduled),
        future_minutes_after_buffer=future_after_buffer,
        missed_preparation_minutes=missed,
        additional_minutes=max(0, remaining - future_scheduled),
    )


def _simulate_outlook(
    inputs: list[_OutlookPlanInput],
    *,
    context: DeadlinePlanningContext,
    zone: ZoneInfo,
    local_now: datetime,
    extra_busy: Iterable[dict[str, Any]],
) -> dict[str, _SimulationOutcome]:
    if len(context.schedule_items) > 1_000:
        raise ExamWeekOutlookCapacityError(
            "Schedule context exceeds the outlook bound.",
        )
    if len(context.confirmed_blocks) > 6_000:
        raise ExamWeekOutlookCapacityError(
            "Preparation reservations exceed the outlook bound.",
        )
    base_reserved = _confirmed_preparation_minutes_by_day(context)
    own_reserved: dict[str, dict[date, int]] = {}
    for row in context.confirmed_blocks:
        plan_id = str(UUID(str(row.get("plan_id"))))
        day = _date(row.get("local_date"))
        minutes = _int(row.get("planned_minutes"))
        if minutes < 5 or minutes > 240:
            raise ValueError("Confirmed preparation duration is invalid.")
        totals = own_reserved.setdefault(plan_id, {})
        totals[day] = totals.get(day, 0) + minutes

    simulated_intervals: list[dict[str, Any]] = []
    simulated_reserved: dict[date, int] = {}
    extra = list(extra_busy)
    outcomes: dict[str, _SimulationOutcome] = {}
    for item in inputs:
        revision = item.detail.active_revision
        assert revision is not None
        daily_reserved = {
            day: minutes + simulated_reserved.get(day, 0)
            for day, minutes in base_reserved.items()
        }
        for day, minutes in simulated_reserved.items():
            daily_reserved.setdefault(day, minutes)
        intervals = allocate_task_intervals(
            starts_on=max(local_now.date(), revision.planning_start_on),
            ends_on=item.last_preparation_date,
            total_minutes=item.additional_minutes,
            preferred_session_minutes=revision.preferred_session_minutes,
            max_daily_minutes=revision.max_daily_minutes,
            zone=zone,
            local_now=local_now,
            energy_window=context.best_energy_window,
            busy_sources=BusySources(
                recurring_commitments=[
                    *context.schedule_items,
                    *(context.planner_recurring_commitments or []),
                ],
                timed_intervals=[
                    *context.confirmed_blocks,
                    *(context.planner_timed_intervals or []),
                    *context.timed_calendar_events,
                    *extra,
                    *simulated_intervals,
                ],
                all_day_intervals=context.all_day_calendar_events,
            ),
            deadline_at=revision.deadline_at,
            daily_reserved_minutes=daily_reserved,
            plan_daily_reserved_minutes=own_reserved.get(
                str(item.detail.plan.id),
                {},
            ),
            account_daily_budget_minutes=context.daily_preparation_budget_minutes,
            max_blocks=120,
            duration_increment_minutes=1,
            recovery_minutes=revision.recovery_minutes,
            exact_session_blocks=revision.recovery_minutes > 0,
        )
        planned = sum(interval.minutes for interval in intervals)
        outcomes[str(item.detail.plan.id)] = _SimulationOutcome(
            planned_minutes=planned,
            unscheduled_minutes=item.additional_minutes - planned,
        )
        for interval in intervals:
            simulated_intervals.append(
                {
                    "starts_at": interval.starts_at.astimezone(UTC).isoformat(),
                    "ends_at": interval.ends_at.astimezone(UTC).isoformat(),
                    "reserved_ends_at": (interval.reserved_ends_at or interval.ends_at)
                    .astimezone(UTC)
                    .isoformat(),
                },
            )
            day = interval.starts_at.astimezone(zone).date()
            simulated_reserved[day] = simulated_reserved.get(day, 0) + interval.minutes
    return outcomes


def _render_outlook_plan(
    item: _OutlookPlanInput,
    *,
    regular: _SimulationOutcome,
    protected: _SimulationOutcome | None,
) -> ExamWeekPlanOutlook:
    revision = item.detail.active_revision
    assert revision is not None
    return ExamWeekPlanOutlook(
        plan_id=item.detail.plan.id,
        kind=item.detail.plan.kind,
        title=item.detail.plan.title,
        deadline_at=revision.deadline_at,
        local_deadline_date=item.local_deadline_date,
        days_remaining=item.days_remaining,
        active_revision=revision.revision,
        pending_revision=(
            item.detail.pending_revision.revision
            if item.detail.pending_revision is not None
            else None
        ),
        saved_buffer_days=item.saved_buffer_days,
        recommended_buffer_days=item.recommended_buffer_days,
        last_preparation_date=item.last_preparation_date,
        remaining_minutes=item.remaining_minutes,
        future_scheduled_minutes=item.future_scheduled_minutes,
        future_minutes_after_buffer=item.future_minutes_after_buffer,
        missed_preparation_minutes=item.missed_preparation_minutes,
        simulated_regular_minutes=regular.planned_minutes,
        unscheduled_regular_minutes=regular.unscheduled_minutes,
        simulated_sleep_protected_minutes=(
            protected.planned_minutes if protected is not None else None
        ),
        unscheduled_sleep_protected_minutes=(
            protected.unscheduled_minutes if protected is not None else None
        ),
        pending_preview_sleep_overlap=item.pending_preview_sleep_overlap,
    )


def _sleep_outlook(
    rows: list[dict[str, Any]],
    *,
    local_date: date,
) -> tuple[ExamWeekSleepPlan | None, list[ExamWeekSleepNight]]:
    plans: list[ExamWeekSleepPlan] = []
    nights: list[ExamWeekSleepNight] = []
    for row in rows:
        row_date = _strict_date(row.get("entry_date"))
        metadata = row.get("metadata")
        if (
            row_date is None
            or row_date > local_date
            or not isinstance(metadata, dict)
            or metadata.get("capture_version") != "daily-capture-v4"
            or not isinstance(metadata.get("captures"), dict)
        ):
            continue
        evening = metadata["captures"].get("evening")
        parsed_plan = _parse_v4_sleep_plan(evening, row_date=row_date)
        if parsed_plan is not None:
            plans.append(parsed_plan)
        if local_date - timedelta(days=6) <= row_date <= local_date:
            morning = metadata["captures"].get("morning")
            parsed_night = _parse_v4_sleep_night(morning, row_date=row_date)
            if parsed_night is not None:
                nights.append(parsed_night)
    plans.sort(
        key=lambda item: (item.entry_date, item.captured_at, item.capture_id),
        reverse=True,
    )
    nights.sort(key=lambda item: item.entry_date, reverse=True)
    return (plans[0] if plans else None, nights[:3])


def _parse_v4_sleep_plan(
    raw: object,
    *,
    row_date: date,
) -> ExamWeekSleepPlan | None:
    parsed = parse_daily_capture_v4_sleep_plan(raw, row_date=row_date).value
    if not isinstance(parsed, DailyCaptureV4SleepPlan):
        return None
    return ExamWeekSleepPlan(
        capture_id=parsed.capture_id,
        entry_date=row_date,
        captured_at=parsed.captured_at,
        planned_sleep_time=parsed.planned_sleep_time,
        sleep_target_minutes=parsed.sleep_target_minutes,
    )


def _parse_v4_sleep_night(
    raw: object,
    *,
    row_date: date,
) -> ExamWeekSleepNight | None:
    parsed = parse_daily_capture_v4_sleep_episode(raw, row_date=row_date).value
    if not isinstance(parsed, DailyCaptureV4SleepEpisode):
        return None
    shortfall = max(
        0,
        parsed.sleep_target_minutes - parsed.estimated_sleep_minutes,
    )
    return ExamWeekSleepNight(
        entry_date=row_date,
        estimated_sleep_minutes=parsed.estimated_sleep_minutes,
        sleep_target_minutes=parsed.sleep_target_minutes,
        shortfall_minutes=shortfall,
        at_least_one_hour_short=shortfall >= 60,
    )


def _sleep_busy_intervals(
    sleep_plan: ExamWeekSleepPlan,
    *,
    starts_on: date,
    ends_on: date,
    zone: ZoneInfo,
) -> tuple[list[dict[str, Any]], bool]:
    planned_time = time.fromisoformat(sleep_plan.planned_sleep_time)
    intervals: list[dict[str, Any]] = []
    complete = True
    for day in _days(starts_on, ends_on):
        try:
            starts_at = resolve_local_datetime(
                local_date=day,
                local_time=planned_time,
                zone=zone,
                source_id=f"sleep-plan:{sleep_plan.capture_id}",
            )
        except LocalTimeResolutionError:
            complete = False
            continue
        ends_at = (
            starts_at.astimezone(UTC)
            + timedelta(minutes=sleep_plan.sleep_target_minutes)
        ).astimezone(zone)
        intervals.append(
            {
                "starts_at": starts_at.astimezone(UTC).isoformat(),
                "ends_at": ends_at.astimezone(UTC).isoformat(),
                "reserved_ends_at": ends_at.astimezone(UTC).isoformat(),
            },
        )
    return intervals, complete


def _revision_overlaps_intervals(
    revision: DeadlinePlanRevision,
    intervals: list[dict[str, Any]],
) -> bool:
    sleep_intervals = [
        (_datetime(item["starts_at"]), _datetime(item["ends_at"])) for item in intervals
    ]
    return any(
        block.starts_at < sleep_end and block.reserved_ends_at > sleep_start
        for block in revision.blocks
        for sleep_start, sleep_end in sleep_intervals
    )


def _confirmed_preparation_minutes_by_day(
    context: DeadlinePlanningContext,
) -> dict[date, int]:
    totals: dict[date, int] = {}
    for row in context.confirmed_blocks:
        local_day = _date(row.get("local_date"))
        minutes = _int(row.get("planned_minutes"))
        if minutes < 5 or minutes > 240:
            raise ValueError("Confirmed preparation duration is invalid.")
        totals[local_day] = totals.get(local_day, 0) + minutes
    return totals


def _strict_date(value: object) -> date | None:
    if not isinstance(value, str) or len(value) != 10:
        return None
    try:
        parsed = date.fromisoformat(value)
    except ValueError:
        return None
    return parsed if parsed.isoformat() == value else None


def _zone(value: str) -> ZoneInfo:
    try:
        return ZoneInfo(value)
    except ZoneInfoNotFoundError as exc:
        raise ValueError("Outlook profile timezone is invalid.") from exc


def _datetime(value: object) -> datetime:
    if isinstance(value, datetime):
        parsed = value
    elif isinstance(value, str):
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    else:
        raise ValueError("Outlook timestamp is invalid.")
    if parsed.tzinfo is None or parsed.utcoffset() is None:
        raise ValueError("Outlook timestamp must be timezone-aware.")
    return parsed


def _date(value: object) -> date:
    if isinstance(value, datetime):
        return value.date()
    if isinstance(value, date):
        return value
    if isinstance(value, str):
        return date.fromisoformat(value)
    raise ValueError("Outlook date is invalid.")


def _int(value: object) -> int:
    if isinstance(value, bool) or not isinstance(value, int):
        raise ValueError("Outlook integer is invalid.")
    return value


def _days(starts_on: date, ends_on: date) -> Iterable[date]:
    cursor = starts_on
    while cursor <= ends_on:
        yield cursor
        cursor += timedelta(days=1)
