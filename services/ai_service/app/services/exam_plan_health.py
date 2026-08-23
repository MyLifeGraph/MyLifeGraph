from __future__ import annotations

import math
from collections.abc import Mapping, Sequence
from dataclasses import dataclass
from datetime import UTC, date, datetime, timedelta
from typing import Any
from uuid import UUID
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from app.models.exam_plan_health import (
    EXAM_PLAN_HEALTH_CONTRACT_VERSION,
    ExamPlanHealthItem,
    ExamPlanHealthPreviewRequest,
    ExamPlanHealthPreviewResponse,
    ExamPlanHealthResponse,
)
from app.repositories.deadline_plan_repository import ExamPlanHealthSnapshot
from app.services.deadline_plan_credit import deadline_block_credits
from app.services.planning_availability import (
    BusySources,
    PlannedInterval,
    allocate_task_intervals,
)


_MAX_CAPACITY_MINUTES = 200_000
_MAX_HEALTH_BLOCKS = 120
_NEW_PREVIEW_PLAN_ID = UUID("00000000-0000-4000-8000-000000000000")


@dataclass(frozen=True)
class _ExamCandidate:
    plan_id: UUID
    title: str
    deadline_at: datetime
    estimated_total_minutes: int
    credited_prior_minutes: int
    tracked_focus_minutes: int
    preferred_session_minutes: int
    max_daily_minutes: int
    planning_start_on: date
    buffer_days: int
    revision: int
    latest_revision: int
    tracked_focus_minutes_at_proposal: int
    active_block_count: int


@dataclass(frozen=True)
class _CapacityInputs:
    zone: ZoneInfo
    local_now: datetime
    local_today: date
    energy_window: str
    account_daily_budget_minutes: int | None
    recovery_minutes: int
    setup_focus_minutes: int | None
    use_calendar_availability: bool
    recurring: tuple[dict[str, Any], ...]
    base_timed: tuple[dict[str, Any], ...]
    all_day: tuple[dict[str, Any], ...]
    calendar_timed: tuple[dict[str, Any], ...]
    calendar_all_day: tuple[dict[str, Any], ...]
    deadline_daily_reserved: Mapping[date, int]
    deadline_plan_daily_reserved: Mapping[UUID, Mapping[date, int]]


def build_exam_plan_health(
    *,
    snapshot: ExamPlanHealthSnapshot,
    preview: ExamPlanHealthPreviewRequest | None = None,
) -> ExamPlanHealthResponse | ExamPlanHealthPreviewResponse:
    if preview is not None:
        validate_exam_plan_health_preview_identity(
            snapshot=snapshot,
            preview=preview,
        )
    inputs = _capacity_inputs(snapshot)
    candidates = _exam_candidates(snapshot, preview=preview)
    preview_id = (
        preview.plan_id if preview and preview.plan_id else _NEW_PREVIEW_PLAN_ID
    )
    dynamic_timed = list(inputs.base_timed)
    dynamic_daily = dict(inputs.deadline_daily_reserved)
    results: list[ExamPlanHealthItem] = []
    shared_unknown = False

    for candidate in candidates:
        effective_preferred = (
            inputs.setup_focus_minutes or candidate.preferred_session_minutes
        )
        focus = min(
            candidate.estimated_total_minutes,
            candidate.credited_prior_minutes + candidate.tracked_focus_minutes,
        )
        remaining = max(0, candidate.estimated_total_minutes - focus)
        if remaining == 0:
            # A fully accounted Exam needs no availability decision. Missing
            # Calendar or recurring authority cannot make zero work Unknown.
            missing: list[str] = []
            authority_reasons: list[str] = []
        else:
            missing, authority_reasons = _missing_authority(
                snapshot=snapshot,
                candidate=candidate,
                inputs=inputs,
            )
            if shared_unknown and "higher_priority_exam_capacity" not in missing:
                missing.append("higher_priority_exam_capacity")
                authority_reasons.append("higher_priority_capacity_unknown")
        finish_on = _last_preferred_day(candidate, inputs.zone)
        candidate_blocks = [
            dict(block)
            for block in snapshot.deadline_blocks
            if str(block.get("plan_id")) == str(candidate.plan_id)
            and _int(block.get("revision"), "deadline block revision")
            == candidate.revision
        ]
        block_credits = deadline_block_credits(
            candidate_blocks,
            [
                dict(fact)
                for fact in snapshot.focus_facts
                if str(fact.get("plan_id")) == str(candidate.plan_id)
            ],
            tracked_focus_minutes_at_proposal=(
                candidate.tracked_focus_minutes_at_proposal
            ),
        )
        future_reserved = sum(
            max(
                0,
                _int(block.get("planned_minutes"), "deadline block minutes")
                - block_credits.get(str(block.get("id")), 0),
            )
            for block in candidate_blocks
            if _datetime(block.get("starts_at"), "deadline block start")
            >= snapshot.generated_at
            and _date(block.get("local_date"), "deadline block date") <= finish_on
        )
        future_reserved = min(remaining, future_reserved)
        minutes_to_schedule = max(0, remaining - future_reserved)
        plan_reserved = inputs.deadline_plan_daily_reserved.get(candidate.plan_id, {})
        start_on = max(inputs.local_today, candidate.planning_start_on)

        available: int | None = None
        reserve: int | None = None
        reserve_sessions: int | None = None
        latest_safe: date | None = None
        recommended: date | None = None
        recommendation_reason: str | None = None
        allocation: list[PlannedInterval] = []

        if not missing:
            try:
                available = _capacity_minutes(
                    candidate=candidate,
                    inputs=inputs,
                    starts_on=start_on,
                    ends_on=finish_on,
                    timed=dynamic_timed,
                    daily_reserved=dynamic_daily,
                    plan_reserved=plan_reserved,
                )
                reserve = available - minutes_to_schedule
                reserve_sessions = max(0, reserve) // effective_preferred
                latest_safe = _latest_safe_start(
                    candidate=candidate,
                    inputs=inputs,
                    minutes=minutes_to_schedule,
                    finish_on=finish_on,
                    timed=dynamic_timed,
                    daily_reserved=dynamic_daily,
                    plan_reserved=plan_reserved,
                )
                recommended = _recommended_start(
                    candidate=candidate,
                    inputs=inputs,
                    minutes=minutes_to_schedule,
                    finish_on=finish_on,
                    latest_safe=latest_safe,
                    timed=dynamic_timed,
                    daily_reserved=dynamic_daily,
                    plan_reserved=plan_reserved,
                )
                if recommended is None:
                    recommendation_reason = (
                        "No start date leaves both seven calendar days and "
                        "twenty percent placeable Focus reserve before the saved buffer."
                    )
                if minutes_to_schedule > 0:
                    allocation = _allocate(
                        candidate=candidate,
                        inputs=inputs,
                        starts_on=start_on,
                        ends_on=finish_on,
                        total_minutes=max(5, minutes_to_schedule),
                        timed=dynamic_timed,
                        daily_reserved=dynamic_daily,
                        plan_reserved=plan_reserved,
                    )
            except (ValueError, TypeError, OverflowError):
                missing.append("recurring_availability")
                authority_reasons.append("recurring_availability_invalid")
                shared_unknown = True
                available = reserve = reserve_sessions = None
                latest_safe = recommended = None
                recommendation_reason = (
                    "A recurring local-time occurrence is unavailable or ambiguous."
                )
                allocation = []

        if missing and recommendation_reason is None:
            recommendation_reason = (
                "A recommended start needs complete authoritative availability."
            )
        if not missing and minutes_to_schedule == 0:
            # No replan is required once the Exam is fully accounted.  Keep
            # the saved finish/buffer day when it is still ahead, but never
            # publish a latest-safe date in the past alongside today's
            # recommendation for an already completed overdue Exam.
            latest_safe = max(finish_on, inputs.local_today)
            recommended = inputs.local_today
            recommendation_reason = None

        status, reasons = _health_status(
            overdue=(candidate.deadline_at <= snapshot.generated_at and remaining > 0),
            missing_sources=missing,
            authority_reasons=authority_reasons,
            minutes_to_schedule=minutes_to_schedule,
            reserve_minutes=reserve,
            preferred_session_minutes=effective_preferred,
            latest_safe_start_on=latest_safe,
            local_today=inputs.local_today,
        )

        item = ExamPlanHealthItem(
            plan_id=candidate.plan_id,
            title=candidate.title,
            deadline_at=candidate.deadline_at,
            local_deadline_date=candidate.deadline_at.astimezone(inputs.zone).date(),
            status=status,
            remaining_minutes=remaining,
            preferred_session_minutes=effective_preferred,
            sessions_needed=(
                math.ceil(remaining / effective_preferred) if remaining else 0
            ),
            future_reserved_minutes=future_reserved,
            minutes_to_schedule=minutes_to_schedule,
            available_replan_capacity_minutes=available,
            reserve_minutes=reserve,
            reserve_full_sessions=reserve_sessions,
            latest_safe_start_on=latest_safe,
            recommended_start_on=recommended,
            recommended_start_reason=recommendation_reason,
            reasons=reasons,
            missing_sources=list(dict.fromkeys(missing)),
        )
        results.append(item)

        if missing and minutes_to_schedule > 0:
            shared_unknown = True

        # Priority is deterministic: earlier deadline, larger remaining work,
        # stable id. Only a complete higher-priority feasibility allocation may
        # consume capacity for the next Exam.
        if not missing:
            for block in allocation:
                reserved_end = block.reserved_ends_at or block.ends_at
                dynamic_timed.append(
                    {
                        "id": f"exam-health:{candidate.plan_id}:{block.starts_at.isoformat()}",
                        "starts_at": block.starts_at,
                        "ends_at": block.ends_at,
                        "reserved_ends_at": reserved_end,
                    },
                )
                local_day = block.starts_at.astimezone(inputs.zone).date()
                dynamic_daily[local_day] = dynamic_daily.get(local_day, 0) + (
                    block.minutes
                )

    if preview is None:
        return ExamPlanHealthResponse(
            contract_version=EXAM_PLAN_HEALTH_CONTRACT_VERSION,
            origin="authenticated_backend",
            generated_at=snapshot.generated_at,
            timezone=inputs.zone.key,
            local_date=inputs.local_today,
            exams=results,
        )
    preview_result = next(item for item in results if item.plan_id == preview_id)
    return ExamPlanHealthPreviewResponse(
        contract_version=EXAM_PLAN_HEALTH_CONTRACT_VERSION,
        origin="authenticated_backend_preview",
        generated_at=snapshot.generated_at,
        timezone=inputs.zone.key,
        local_date=inputs.local_today,
        exam=preview_result,
    )


def _capacity_inputs(snapshot: ExamPlanHealthSnapshot) -> _CapacityInputs:
    timezone = snapshot.profile.get("timezone")
    if not isinstance(timezone, str) or not timezone:
        raise ValueError("Exam health profile timezone is invalid.")
    try:
        zone = ZoneInfo(timezone)
    except ZoneInfoNotFoundError as exc:
        raise ValueError("Exam health profile timezone is invalid.") from exc
    local_now = snapshot.generated_at.astimezone(zone)
    if snapshot.local_today != local_now.date():
        raise ValueError("Exam health snapshot local date is inconsistent.")
    budget = snapshot.profile.get("daily_preparation_budget_minutes")
    if budget is not None and (
        type(budget) is not int or budget < 25 or budget > 480 or budget % 5
    ):
        raise ValueError("Exam health account budget is invalid.")
    planner_preference = snapshot.planner_preference
    if not isinstance(planner_preference, Mapping):
        raise ValueError("Exam health Planner preference is invalid.")
    use_calendar_availability = _bool(
        planner_preference.get("use_calendar_busy_time"),
        "Exam health Planner Calendar preference",
    )
    setup_focus: int | None = None
    recovery = 0
    if snapshot.study_setup is not None:
        focus_value = snapshot.study_setup.get("focus_minutes")
        recovery_value = snapshot.study_setup.get("recovery_minutes")
        if focus_value is not None or recovery_value is not None:
            setup_focus = _int(focus_value, "Study Focus duration")
            recovery = _int(recovery_value, "Study recovery duration")
            if (
                setup_focus < 25
                or setup_focus > 180
                or setup_focus % 5
                or recovery < 5
                or recovery > 60
                or recovery % 5
            ):
                raise ValueError("Exam health Study rhythm is invalid.")
    recurring: list[dict[str, Any]] = [dict(row) for row in snapshot.schedule_items]
    recurring.extend(
        {
            "id": row.get("id"),
            "weekday": row.get("weekday"),
            "starts_at": row.get("starts_at"),
            "ends_at": row.get("ends_at"),
        }
        for row in snapshot.planner_habit_slots
    )
    timed: list[dict[str, Any]] = [dict(row) for row in snapshot.deadline_blocks]
    timed.extend(dict(row) for row in snapshot.planner_task_blocks)
    for row in snapshot.planner_commitments:
        recurrence = row.get("recurrence")
        if recurrence == "weekly":
            recurring.append(
                {
                    "id": row.get("id"),
                    "weekday": row.get("weekday"),
                    "starts_at": row.get("local_starts_at"),
                    "ends_at": row.get("local_ends_at"),
                },
            )
        elif recurrence == "one_off":
            timed.append(
                {
                    "id": row.get("id"),
                    "starts_at": row.get("starts_at"),
                    "ends_at": row.get("ends_at"),
                },
            )
        else:
            raise ValueError("Exam health Planner commitment is invalid.")
    daily: dict[date, int] = {}
    per_plan: dict[UUID, dict[date, int]] = {}
    for row in snapshot.deadline_blocks:
        day = _date(row.get("local_date"), "deadline block date")
        minutes = _int(row.get("planned_minutes"), "deadline block minutes")
        plan_id = UUID(str(row.get("plan_id")))
        daily[day] = daily.get(day, 0) + minutes
        plan_days = per_plan.setdefault(plan_id, {})
        plan_days[day] = plan_days.get(day, 0) + minutes
    return _CapacityInputs(
        zone=zone,
        local_now=local_now,
        local_today=snapshot.local_today,
        energy_window=snapshot.best_energy_window,
        account_daily_budget_minutes=budget,
        recovery_minutes=recovery,
        setup_focus_minutes=setup_focus,
        use_calendar_availability=use_calendar_availability,
        recurring=tuple(recurring),
        base_timed=tuple(timed),
        all_day=(),
        calendar_timed=tuple(dict(row) for row in snapshot.calendar_timed_events),
        calendar_all_day=tuple(dict(row) for row in snapshot.calendar_all_day_events),
        deadline_daily_reserved=daily,
        deadline_plan_daily_reserved=per_plan,
    )


def _health_status(
    *,
    overdue: bool,
    missing_sources: Sequence[str],
    authority_reasons: Sequence[str],
    minutes_to_schedule: int,
    reserve_minutes: int | None,
    preferred_session_minutes: int,
    latest_safe_start_on: date | None,
    local_today: date,
) -> tuple[str, list[str]]:
    reasons = list(dict.fromkeys(authority_reasons))
    if overdue:
        return "red", list(dict.fromkeys(["overdue_remaining", *reasons]))
    if missing_sources:
        return "unknown", reasons
    if reserve_minutes is None:
        raise ValueError("Complete Exam health requires a reserve total.")
    if reserve_minutes < 0:
        return "red", ["capacity_deficit", *reasons]
    if minutes_to_schedule > 0:
        if reserve_minutes * 5 < minutes_to_schedule:
            reasons.append("low_percentage_reserve")
        if reserve_minutes < 2 * preferred_session_minutes:
            reasons.append("low_session_reserve")
        if (
            latest_safe_start_on is not None
            and (latest_safe_start_on - local_today).days <= 7
        ):
            reasons.append("latest_safe_start_near")
    return ("yellow" if reasons else "green"), reasons


def _exam_candidates(
    snapshot: ExamPlanHealthSnapshot,
    *,
    preview: ExamPlanHealthPreviewRequest | None,
) -> list[_ExamCandidate]:
    focus = {
        UUID(str(row.get("plan_id"))): _int(
            row.get("actual_minutes"),
            "tracked Focus minutes",
        )
        for row in snapshot.focus_totals
    }
    candidates: list[_ExamCandidate] = []
    for row in snapshot.exams:
        plan_id = UUID(str(row.get("id")))
        if preview is not None and preview.plan_id == plan_id:
            continue
        candidates.append(_candidate_from_row(row, focus.get(plan_id, 0)))
    if preview is not None:
        plan_id = preview.plan_id or _NEW_PREVIEW_PLAN_ID
        preview_row = (
            _preview_exam_row(snapshot, preview)
            if preview.plan_id is not None
            else None
        )
        candidates.append(
            _ExamCandidate(
                plan_id=plan_id,
                title=preview.title,
                deadline_at=preview.deadline_at.astimezone(UTC),
                estimated_total_minutes=preview.estimated_total_minutes,
                credited_prior_minutes=preview.credited_prior_minutes,
                tracked_focus_minutes=focus.get(plan_id, 0),
                preferred_session_minutes=preview.preferred_session_minutes,
                max_daily_minutes=preview.max_daily_minutes,
                planning_start_on=preview.planning_start_on,
                buffer_days=preview.buffer_days,
                revision=(
                    _int(preview_row.get("revision"), "Exam revision")
                    if preview_row is not None
                    else 0
                ),
                latest_revision=(
                    _int(
                        preview_row.get("latest_revision"),
                        "Exam latest revision",
                    )
                    if preview_row is not None
                    else 0
                ),
                tracked_focus_minutes_at_proposal=(
                    _int(
                        preview_row.get(
                            "tracked_focus_minutes_at_proposal",
                        ),
                        "Exam proposal Focus credit",
                    )
                    if preview_row is not None
                    else 0
                ),
                active_block_count=(
                    _int(
                        preview_row.get("active_block_count"),
                        "Exam active block count",
                    )
                    if preview_row is not None
                    else 0
                ),
            ),
        )
    candidates.sort(
        key=lambda item: (
            item.deadline_at,
            -max(
                0,
                item.estimated_total_minutes
                - item.credited_prior_minutes
                - item.tracked_focus_minutes,
            ),
            str(item.plan_id),
        ),
    )
    return candidates


def _candidate_from_row(row: Mapping[str, Any], tracked: int) -> _ExamCandidate:
    return _ExamCandidate(
        plan_id=UUID(str(row.get("id"))),
        title=_text(row.get("title"), "Exam title"),
        deadline_at=_datetime(row.get("deadline_at"), "Exam deadline").astimezone(
            UTC,
        ),
        estimated_total_minutes=_int(
            row.get("estimated_total_minutes"),
            "Exam estimate",
        ),
        credited_prior_minutes=_int(
            row.get("credited_prior_minutes"),
            "Exam prior credit",
        ),
        tracked_focus_minutes=tracked,
        preferred_session_minutes=_int(
            row.get("preferred_session_minutes"),
            "Exam preferred session",
        ),
        max_daily_minutes=_int(row.get("max_daily_minutes"), "Exam daily limit"),
        planning_start_on=_date(row.get("planning_start_on"), "Exam start"),
        buffer_days=_int(row.get("buffer_days"), "Exam buffer"),
        revision=_int(row.get("revision"), "Exam revision"),
        latest_revision=_int(row.get("latest_revision"), "Exam latest revision"),
        tracked_focus_minutes_at_proposal=_int(
            row.get("tracked_focus_minutes_at_proposal"),
            "Exam proposal Focus credit",
        ),
        active_block_count=_int(
            row.get("active_block_count"),
            "Exam active block count",
        ),
    )


def validate_exam_plan_health_preview_identity(
    *,
    snapshot: ExamPlanHealthSnapshot,
    preview: ExamPlanHealthPreviewRequest,
) -> None:
    _validate_exam_plan_health_preview_window(snapshot=snapshot, preview=preview)
    if preview.plan_id is None:
        if preview.base_revision is not None:
            raise ValueError(
                "A new Exam health preview cannot include a base revision."
            )
        return
    row = _preview_exam_row(snapshot, preview)
    active_revision = _int(row.get("revision"), "Exam revision")
    current_revision = _int(row.get("current_revision"), "Exam current revision")
    latest_revision = _int(row.get("latest_revision"), "Exam latest revision")
    if active_revision != current_revision or preview.base_revision != latest_revision:
        raise ValueError("Exam health preview revision is not current.")


def _validate_exam_plan_health_preview_window(
    *,
    snapshot: ExamPlanHealthSnapshot,
    preview: ExamPlanHealthPreviewRequest,
) -> None:
    generated_at = snapshot.generated_at.astimezone(UTC)
    deadline_at = preview.deadline_at.astimezone(UTC)
    if deadline_at <= generated_at:
        raise ValueError("deadline_at must be in the future")
    if deadline_at > generated_at + timedelta(days=366):
        raise ValueError("deadline_at must be within 366 days")

    timezone = snapshot.profile.get("timezone")
    if not isinstance(timezone, str) or not timezone:
        raise ValueError("Exam health profile timezone is invalid.")
    try:
        zone = ZoneInfo(timezone)
    except ZoneInfoNotFoundError as exc:
        raise ValueError("Exam health profile timezone is invalid.") from exc
    local_now = snapshot.generated_at.astimezone(zone)
    if snapshot.local_today != local_now.date():
        raise ValueError("Exam health snapshot local date is inconsistent.")
    local_deadline = preview.deadline_at.astimezone(zone).date()
    if (local_deadline - snapshot.local_today).days > 366:
        raise ValueError("deadline_at must be within 366 profile-local days")
    if preview.planning_start_on > local_deadline:
        raise ValueError(
            "planning_start_on cannot be after the profile-local deadline day",
        )
    if (local_deadline - preview.planning_start_on).days > 366:
        raise ValueError("deadline planning horizon cannot exceed 366 days")


def _preview_exam_row(
    snapshot: ExamPlanHealthSnapshot,
    preview: ExamPlanHealthPreviewRequest,
) -> Mapping[str, Any]:
    matches = [
        row for row in snapshot.exams if str(row.get("id")) == str(preview.plan_id)
    ]
    if len(matches) != 1:
        raise ValueError("Exam health preview plan is unavailable.")
    return matches[0]


def _missing_authority(
    *,
    snapshot: ExamPlanHealthSnapshot,
    candidate: _ExamCandidate,
    inputs: _CapacityInputs,
) -> tuple[list[str], list[str]]:
    if not inputs.use_calendar_availability:
        return [], []
    imported = snapshot.calendar_import
    if (
        imported is None
        or imported.get("planning_status") != "current"
        or imported.get("timezone") != inputs.zone.key
        or imported.get("profile_timezone_revision")
        != snapshot.profile.get("timezone_revision")
    ):
        return ["calendar_import"], ["calendar_import_unavailable"]
    starts = max(inputs.local_today, candidate.planning_start_on)
    finish = _last_preferred_day(candidate, inputs.zone)
    window_start = _date(imported.get("window_starts_on"), "Calendar window start")
    window_end = _date(imported.get("window_ends_before"), "Calendar window end")
    if window_start > starts or window_end <= finish:
        return ["calendar_horizon"], ["calendar_window_incomplete"]
    return [], []


def _last_preferred_day(candidate: _ExamCandidate, zone: ZoneInfo) -> date:
    deadline_day = candidate.deadline_at.astimezone(zone).date()
    if candidate.buffer_days == 0:
        return deadline_day
    return deadline_day - timedelta(days=candidate.buffer_days + 1)


def _capacity_minutes(
    *,
    candidate: _ExamCandidate,
    inputs: _CapacityInputs,
    starts_on: date,
    ends_on: date,
    timed: Sequence[Mapping[str, Any]],
    daily_reserved: Mapping[date, int],
    plan_reserved: Mapping[date, int],
) -> int:
    if starts_on > ends_on:
        return 0
    if inputs.setup_focus_minutes is not None:
        return _study_capacity_minutes(
            candidate=candidate,
            inputs=inputs,
            starts_on=starts_on,
            ends_on=ends_on,
            timed=timed,
            daily_reserved=daily_reserved,
            plan_reserved=plan_reserved,
        )
    return sum(
        block.minutes
        for block in _allocate(
            candidate=candidate,
            inputs=inputs,
            starts_on=starts_on,
            ends_on=ends_on,
            total_minutes=_MAX_CAPACITY_MINUTES,
            timed=timed,
            daily_reserved=daily_reserved,
            plan_reserved=plan_reserved,
        )
    )


def _study_capacity_minutes(
    *,
    candidate: _ExamCandidate,
    inputs: _CapacityInputs,
    starts_on: date,
    ends_on: date,
    timed: Sequence[Mapping[str, Any]],
    daily_reserved: Mapping[date, int],
    plan_reserved: Mapping[date, int],
) -> int:
    """Project maximum Study Focus while preserving final-remainder rules."""

    preferred = inputs.setup_focus_minutes
    if preferred is None:
        raise ValueError("Study capacity requires a Focus duration.")
    remaining_block_slots = _MAX_HEALTH_BLOCKS - candidate.active_block_count
    if remaining_block_slots <= 0:
        return 0

    full_blocks = _allocate(
        candidate=candidate,
        inputs=inputs,
        starts_on=starts_on,
        ends_on=ends_on,
        total_minutes=preferred * remaining_block_slots,
        timed=timed,
        daily_reserved=daily_reserved,
        plan_reserved=plan_reserved,
    )
    full_minutes = sum(block.minutes for block in full_blocks)
    upper_bound = min(
        preferred * remaining_block_slots,
        full_minutes + preferred - 5,
    )

    # Study capacity is truthful only when the canonical allocator can place
    # that exact total.  A partial sum returned for a larger failed request is
    # not proof: different targets can choose different first-round days and
    # make a later final remainder succeed or fail.  Search the finite contract
    # space (at most remaining slots * preferred / 5 candidates) downward.
    for target in range(upper_bound, 0, -5):
        if _can_allocate_exact(
            candidate=candidate,
            inputs=inputs,
            starts_on=starts_on,
            ends_on=ends_on,
            target_minutes=target,
            timed=timed,
            daily_reserved=daily_reserved,
            plan_reserved=plan_reserved,
        ):
            return target
    return 0


def _can_allocate_exact(
    *,
    candidate: _ExamCandidate,
    inputs: _CapacityInputs,
    starts_on: date,
    ends_on: date,
    target_minutes: int,
    timed: Sequence[Mapping[str, Any]],
    daily_reserved: Mapping[date, int],
    plan_reserved: Mapping[date, int],
) -> bool:
    allocated = _allocate(
        candidate=candidate,
        inputs=inputs,
        starts_on=starts_on,
        ends_on=ends_on,
        total_minutes=target_minutes,
        timed=timed,
        daily_reserved=daily_reserved,
        plan_reserved=plan_reserved,
    )
    return sum(block.minutes for block in allocated) == target_minutes


def _allocate(
    *,
    candidate: _ExamCandidate,
    inputs: _CapacityInputs,
    starts_on: date,
    ends_on: date,
    total_minutes: int,
    timed: Sequence[Mapping[str, Any]],
    daily_reserved: Mapping[date, int],
    plan_reserved: Mapping[date, int],
) -> list[PlannedInterval]:
    remaining_block_slots = _MAX_HEALTH_BLOCKS - candidate.active_block_count
    if remaining_block_slots <= 0:
        return []
    preferred = inputs.setup_focus_minutes or candidate.preferred_session_minutes
    return allocate_task_intervals(
        starts_on=starts_on,
        ends_on=ends_on,
        total_minutes=total_minutes,
        preferred_session_minutes=preferred,
        max_daily_minutes=candidate.max_daily_minutes,
        zone=inputs.zone,
        local_now=inputs.local_now,
        energy_window=inputs.energy_window,
        busy_sources=BusySources(
            recurring_commitments=inputs.recurring,
            timed_intervals=[
                *timed,
                *(inputs.calendar_timed if inputs.use_calendar_availability else ()),
            ],
            all_day_intervals=[
                *inputs.all_day,
                *(inputs.calendar_all_day if inputs.use_calendar_availability else ()),
            ],
        ),
        deadline_at=candidate.deadline_at,
        daily_reserved_minutes=daily_reserved,
        plan_daily_reserved_minutes=plan_reserved,
        account_daily_budget_minutes=inputs.account_daily_budget_minutes,
        max_blocks=remaining_block_slots,
        duration_increment_minutes=5 if inputs.setup_focus_minutes else 1,
        recovery_minutes=inputs.recovery_minutes,
        exact_session_blocks=inputs.setup_focus_minutes is not None,
        allocation_policy="spread_first",
    )


def _latest_safe_start(
    *,
    candidate: _ExamCandidate,
    inputs: _CapacityInputs,
    minutes: int,
    finish_on: date,
    timed: Sequence[Mapping[str, Any]],
    daily_reserved: Mapping[date, int],
    plan_reserved: Mapping[date, int],
) -> date | None:
    if minutes <= 0:
        return finish_on
    return _latest_date_with_capacity(
        candidate=candidate,
        inputs=inputs,
        target_minutes=minutes,
        first=inputs.local_today,
        last=finish_on,
        finish_on=finish_on,
        timed=timed,
        daily_reserved=daily_reserved,
        plan_reserved=plan_reserved,
    )


def _recommended_start(
    *,
    candidate: _ExamCandidate,
    inputs: _CapacityInputs,
    minutes: int,
    finish_on: date,
    latest_safe: date | None,
    timed: Sequence[Mapping[str, Any]],
    daily_reserved: Mapping[date, int],
    plan_reserved: Mapping[date, int],
) -> date | None:
    if minutes <= 0:
        return inputs.local_today
    if latest_safe is None:
        return None
    latest_with_calendar_reserve = latest_safe - timedelta(days=7)
    if latest_with_calendar_reserve < inputs.local_today:
        return None
    target = minutes + math.ceil(minutes * 0.20)
    if inputs.setup_focus_minutes is not None:
        target = math.ceil(target / 5) * 5
    return _latest_date_with_capacity(
        candidate=candidate,
        inputs=inputs,
        target_minutes=target,
        first=inputs.local_today,
        last=latest_with_calendar_reserve,
        finish_on=finish_on,
        timed=timed,
        daily_reserved=daily_reserved,
        plan_reserved=plan_reserved,
    )


def _latest_date_with_capacity(
    *,
    candidate: _ExamCandidate,
    inputs: _CapacityInputs,
    target_minutes: int,
    first: date,
    last: date,
    finish_on: date,
    timed: Sequence[Mapping[str, Any]],
    daily_reserved: Mapping[date, int],
    plan_reserved: Mapping[date, int],
) -> date | None:
    if first > last:
        return None
    if inputs.setup_focus_minutes is not None:
        # Exact Study placement is deliberately non-monotonic: changing the
        # first candidate day can change spread-first day selection and whether
        # the single short final block is chronological.  The Health horizon is
        # already bounded to 366 days, so inspect those dates newest-first.
        candidate_day = last
        while candidate_day >= first:
            if _can_allocate_exact(
                candidate=candidate,
                inputs=inputs,
                starts_on=candidate_day,
                ends_on=finish_on,
                target_minutes=target_minutes,
                timed=timed,
                daily_reserved=daily_reserved,
                plan_reserved=plan_reserved,
            ):
                return candidate_day
            candidate_day -= timedelta(days=1)
        return None
    low = 0
    high = (last - first).days
    answer: date | None = None
    while low <= high:
        middle = (low + high) // 2
        candidate_day = first + timedelta(days=middle)
        capacity = _capacity_minutes(
            candidate=candidate,
            inputs=inputs,
            starts_on=candidate_day,
            ends_on=finish_on,
            timed=timed,
            daily_reserved=daily_reserved,
            plan_reserved=plan_reserved,
        )
        if capacity >= target_minutes:
            answer = candidate_day
            low = middle + 1
        else:
            high = middle - 1
    return answer


def _datetime(value: object, field: str) -> datetime:
    if isinstance(value, datetime):
        result = value
    elif isinstance(value, str):
        try:
            result = datetime.fromisoformat(value.replace("Z", "+00:00"))
        except ValueError as exc:
            raise ValueError(f"{field} is invalid.") from exc
    else:
        raise ValueError(f"{field} is invalid.")
    if result.tzinfo is None or result.utcoffset() is None:
        raise ValueError(f"{field} must be timezone-aware.")
    return result


def _date(value: object, field: str) -> date:
    if isinstance(value, datetime):
        raise ValueError(f"{field} is invalid.")
    if isinstance(value, date):
        return value
    if isinstance(value, str):
        try:
            return date.fromisoformat(value)
        except ValueError as exc:
            raise ValueError(f"{field} is invalid.") from exc
    raise ValueError(f"{field} is invalid.")


def _int(value: object, field: str) -> int:
    if type(value) is not int:
        raise ValueError(f"{field} is invalid.")
    return value


def _bool(value: object, field: str) -> bool:
    if type(value) is not bool:
        raise ValueError(f"{field} is invalid.")
    return value


def _text(value: object, field: str) -> str:
    if not isinstance(value, str) or not value or value != value.strip():
        raise ValueError(f"{field} is invalid.")
    return value
