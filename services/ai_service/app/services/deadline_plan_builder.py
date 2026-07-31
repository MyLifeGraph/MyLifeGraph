import hashlib
import json
from collections.abc import Iterable
from datetime import UTC, date, datetime, time, timedelta
from typing import Any
from uuid import UUID
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from app.models.deadline_plans import (
    DEADLINE_PLAN_CONTRACT_VERSION,
    DeadlinePlanDetail,
    DeadlinePlanIdentity,
    DeadlinePlanProposalRequest,
    DeadlinePlanResponse,
)
from app.models.planning_timing import PlanningTimingProvenance
from app.services.local_time import (
    resolve_local_datetime,
    resolve_local_interval,
)
from app.repositories.deadline_plan_repository import (
    DeadlinePlanningContext,
)
from app.services.planning_availability import (
    BusySources,
    PlannedInterval,
    allocate_task_intervals,
    recurring_commitment_applies_on,
)


from app.services.planner_errors import (
    DeadlinePlanConflictError,
    DeadlinePlanValidationError,
)


def _timing_preference_from_row(
    row: dict[str, Any],
) -> PlanningTimingProvenance:
    return PlanningTimingProvenance(
        source=row.get("timing_preference_source", "setup"),
        window=row.get("timing_preference_window"),
        evidence_count=_int(row.get("timing_evidence_count", 0)),
        evidence_starts_on=(
            _date(row["timing_evidence_starts_on"])
            if row.get("timing_evidence_starts_on") is not None
            else None
        ),
        evidence_ends_on=(
            _date(row["timing_evidence_ends_on"])
            if row.get("timing_evidence_ends_on") is not None
            else None
        ),
        evidence_fingerprint=row.get("timing_evidence_fingerprint"),
        fell_back_to_setup=bool(row.get("timing_fell_back_to_setup", False)),
        warning=row.get("timing_warning"),
    )


def _valid_clock(value: object) -> bool:
    if not isinstance(value, str) or len(value) != 5:
        return False
    try:
        parsed = time.fromisoformat(value)
    except ValueError:
        return False
    return parsed.second == 0 and parsed.isoformat(timespec="minutes") == value


def _plan_blocks(
    *,
    request: DeadlinePlanProposalRequest,
    context: DeadlinePlanningContext,
    zone: ZoneInfo,
    local_now: datetime,
    local_deadline: datetime,
    effective_start: date,
    remaining_minutes: int,
    learned_focus_window: str | None = None,
) -> list[PlannedInterval]:
    deadline_day = local_deadline.date()
    last_preferred_day = (
        deadline_day
        if request.buffer_days == 0
        else deadline_day - timedelta(days=request.buffer_days + 1)
    )
    reserved_by_day = _confirmed_preparation_minutes_by_day(context)
    study_rhythm = _deadline_study_rhythm(context.study_setup)
    intervals = allocate_task_intervals(
        starts_on=effective_start,
        ends_on=last_preferred_day,
        total_minutes=remaining_minutes,
        preferred_session_minutes=request.preferred_session_minutes,
        max_daily_minutes=request.max_daily_minutes,
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
            ],
            all_day_intervals=context.all_day_calendar_events,
        ),
        deadline_at=local_deadline,
        daily_reserved_minutes=reserved_by_day,
        account_daily_budget_minutes=context.daily_preparation_budget_minutes,
        max_blocks=120,
        # Deadline Planner V1 permits an exact final minute remainder. Planner
        # Action V1 below opts into the stricter five-minute duration grid.
        duration_increment_minutes=1,
        recovery_minutes=study_rhythm[2] if study_rhythm is not None else 0,
        exact_session_blocks=study_rhythm is not None,
        learned_focus_window=learned_focus_window,
    )
    return intervals


def _busy_intervals_by_day(
    *,
    days: list[date],
    context: DeadlinePlanningContext,
    zone: ZoneInfo,
    local_now: datetime,
) -> dict[date, list[tuple[datetime, datetime]]]:
    result: dict[date, list[tuple[datetime, datetime]]] = {day: [] for day in days}
    day_set = set(days)
    for day in days:
        if day == local_now.date():
            rounded_now = _round_up_quarter_hour(
                local_now + timedelta(minutes=15),
            )
            result[day].append(
                (
                    resolve_local_datetime(
                        local_date=day,
                        local_time=time.min,
                        zone=zone,
                        source_id=f"planning-day:{day.isoformat()}",
                    ),
                    rounded_now,
                ),
            )
    for item in context.schedule_items:
        weekday = _int(item.get("weekday"))
        starts = _time(item.get("starts_at"))
        ends = _time(item.get("ends_at"))
        if ends <= starts:
            continue
        for day in days:
            if day.isoweekday() == weekday and recurring_commitment_applies_on(
                item,
                day,
            ):
                result[day].append(
                    resolve_local_interval(
                        local_date=day,
                        starts_at=starts,
                        ends_at=ends,
                        zone=zone,
                        source_id=f"setup:{item.get('id', weekday)}",
                    ),
                )
    for item in [*context.confirmed_blocks, *context.timed_calendar_events]:
        starts_at = _datetime(item.get("starts_at")).astimezone(zone)
        ends_at = _datetime(item.get("ends_at")).astimezone(zone)
        cursor = starts_at.date()
        while cursor <= ends_at.date():
            if cursor in day_set:
                result[cursor].append((starts_at, ends_at))
            cursor += timedelta(days=1)
    for item in context.all_day_calendar_events:
        starts_on = _date(item.get("starts_on"))
        ends_on = _date(item.get("ends_on"))
        cursor = starts_on
        while cursor < ends_on:
            if cursor in day_set:
                result[cursor].append(
                    (
                        resolve_local_datetime(
                            local_date=cursor,
                            local_time=time.min,
                            zone=zone,
                            source_id=f"calendar-all-day:{item.get('id', cursor)}",
                        ),
                        resolve_local_datetime(
                            local_date=cursor + timedelta(days=1),
                            local_time=time.min,
                            zone=zone,
                            source_id=f"calendar-all-day:{item.get('id', cursor)}",
                        ),
                    ),
                )
            cursor += timedelta(days=1)
    return {day: _merge_intervals(intervals) for day, intervals in result.items()}


def _subtract_intervals(
    starts_at: datetime,
    ends_at: datetime,
    busy: list[tuple[datetime, datetime]],
) -> list[tuple[datetime, datetime]]:
    gaps: list[tuple[datetime, datetime]] = []
    cursor = starts_at
    for busy_start, busy_end in busy:
        clipped_start = max(starts_at, busy_start)
        clipped_end = min(ends_at, busy_end)
        if clipped_end <= cursor or clipped_start >= ends_at:
            continue
        if clipped_start > cursor:
            gaps.append((cursor, clipped_start))
        cursor = max(cursor, clipped_end)
    if cursor < ends_at:
        gaps.append((cursor, ends_at))
    return gaps


def _merge_intervals(
    intervals: Iterable[tuple[datetime, datetime]],
) -> list[tuple[datetime, datetime]]:
    merged: list[tuple[datetime, datetime]] = []
    for starts_at, ends_at in sorted(intervals, key=lambda value: value[0]):
        if ends_at <= starts_at:
            continue
        if not merged or starts_at > merged[-1][1]:
            merged.append((starts_at, ends_at))
        else:
            merged[-1] = (merged[-1][0], max(merged[-1][1], ends_at))
    return merged


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


def _fixed_commitment_minutes(
    schedule_items: list[dict[str, Any]],
    *,
    local_day: date,
) -> int:
    intervals: list[tuple[int, int]] = []
    for row in schedule_items:
        if _int(
            row.get("weekday")
        ) != local_day.isoweekday() or not recurring_commitment_applies_on(
            row, local_day
        ):
            continue
        starts = _time(row.get("starts_at"))
        ends = _time(row.get("ends_at"))
        start_minute = starts.hour * 60 + starts.minute
        end_minute = ends.hour * 60 + ends.minute
        if end_minute > start_minute:
            intervals.append((start_minute, end_minute))
    merged: list[tuple[int, int]] = []
    for starts, ends in sorted(intervals):
        if not merged or starts > merged[-1][1]:
            merged.append((starts, ends))
        else:
            merged[-1] = (merged[-1][0], max(merged[-1][1], ends))
    return sum(ends - starts for starts, ends in merged)


def _days(starts_on: date, ends_on: date) -> Iterable[date]:
    cursor = starts_on
    while cursor <= ends_on:
        yield cursor
        cursor += timedelta(days=1)


def _context_fingerprint_input(
    *,
    context: DeadlinePlanningContext,
    plan_id: UUID,
    effective_start: date,
    local_deadline: datetime,
    generated_at: datetime,
) -> dict[str, Any]:
    return {
        "timezone": context.timezone,
        "best_energy_window": context.best_energy_window,
        "daily_preparation_budget_minutes": (context.daily_preparation_budget_minutes),
        "availability_connection_id": context.availability_connection_id,
        "availability_import_id": context.availability_import_id,
        "effective_start": effective_start.isoformat(),
        "local_deadline_day": local_deadline.date().isoformat(),
        "captured_at": generated_at.isoformat(),
        "schedule_items": context.schedule_items,
        "confirmed_blocks": [
            item
            for item in context.confirmed_blocks
            if str(item.get("plan_id")) != str(plan_id)
        ],
        "timed_calendar_events": context.timed_calendar_events,
        "all_day_calendar_events": context.all_day_calendar_events,
        "source_calendar_event": context.source_calendar_event,
        "planner_recurring_commitments": (context.planner_recurring_commitments or []),
        "planner_timed_intervals": context.planner_timed_intervals or [],
        "planner_use_calendar_busy_time": (context.planner_use_calendar_busy_time),
        "study_setup": context.study_setup,
    }


def _deadline_study_rhythm(
    row: dict[str, Any] | None,
) -> tuple[int, int, int] | None:
    if row is None:
        return None
    revision = _int(row.get("setup_revision"))
    focus = row.get("focus_minutes")
    recovery = row.get("recovery_minutes")
    if focus is None and recovery is None:
        return None
    focus_minutes = _int(focus)
    recovery_minutes = _int(recovery)
    if (
        revision < 1
        or focus_minutes < 25
        or focus_minutes > 180
        or focus_minutes % 5 != 0
        or recovery_minutes < 5
        or recovery_minutes > 60
        or recovery_minutes % 5 != 0
    ):
        raise ValueError("Deadline Study Setup projection is invalid.")
    return revision, focus_minutes, recovery_minutes


def _require_current_source(
    *,
    request: DeadlinePlanProposalRequest,
    context: DeadlinePlanningContext,
) -> None:
    if request.source_kind == "manual":
        return
    event = context.source_calendar_event
    if event is None:
        raise DeadlinePlanConflictError(
            "Selected calendar source is unavailable. Reload before planning.",
        )
    if (
        not _calendar_event_is_current(event)
        or event.get(
            "source_fingerprint",
        )
        != request.source_calendar_event_fingerprint
    ):
        raise DeadlinePlanConflictError(
            "Selected calendar source changed. Reload before planning.",
        )


def _calendar_event_is_current(event: dict[str, Any]) -> bool:
    return (
        event.get("_connection_status") == "connected"
        and event.get("_connection_imported_data_deleted_at") is None
        and event.get("_import_planning_status") == "current"
        and event.get("import_id") is not None
        and str(event.get("import_id")) == str(event.get("_connection_last_import_id"))
    )


def _calendar_event_has_status_projection(event: dict[str, Any]) -> bool:
    return {
        "_connection_status",
        "_connection_last_import_id",
        "_connection_imported_data_deleted_at",
        "_import_planning_status",
    }.issubset(event)


def _round_up_quarter_hour(value: datetime) -> datetime:
    rounded = value.replace(second=0, microsecond=0)
    remainder = rounded.minute % 15
    if value.second or value.microsecond or remainder:
        rounded += timedelta(minutes=(15 - remainder) if remainder else 15)
    return rounded


def _ceil_local_five_minutes(value: datetime) -> datetime:
    rounded = value.replace(second=0, microsecond=0)
    remainder = rounded.minute % 5
    if value.second or value.microsecond or remainder:
        rounded += timedelta(minutes=(5 - remainder) if remainder else 5)
    return rounded


def _floor_local_five_minutes(value: datetime) -> datetime:
    return value.replace(
        minute=value.minute - (value.minute % 5),
        second=0,
        microsecond=0,
    )


def _safe_fixed_offset_interval(
    starts_at: datetime,
    ends_at: datetime,
    zone: ZoneInfo,
) -> bool:
    if ends_at <= starts_at or starts_at.utcoffset() != ends_at.utcoffset():
        return False
    return _is_unambiguous_local(starts_at, zone) and _is_unambiguous_local(
        ends_at,
        zone,
    )


def _is_unambiguous_local(value: datetime, zone: ZoneInfo) -> bool:
    naive = value.replace(tzinfo=None)
    instants = {
        candidate.astimezone(UTC)
        for fold in (0, 1)
        if (candidate := naive.replace(tzinfo=zone, fold=fold))
        .astimezone(UTC)
        .astimezone(zone)
        .replace(tzinfo=None)
        == naive
    }
    return len(instants) == 1


def _plan_identity(row: dict[str, Any]) -> DeadlinePlanIdentity:
    return DeadlinePlanIdentity(
        id=UUID(str(row["id"])),
        status=row["status"],
        kind=row["kind"],
        title=row["title"],
        managed_task_id=(
            UUID(str(row["managed_task_id"])) if row.get("managed_task_id") else None
        ),
        original_estimated_total_minutes=_int(
            row["original_estimated_total_minutes"],
        ),
        original_credited_prior_minutes=_int(row["original_credited_prior_minutes"]),
        current_revision=_int(row["current_revision"]),
        latest_revision=_int(row["latest_revision"]),
        attention_reasons=list(
            dict.fromkeys(
                value
                for value in row.get("attention_reasons", [])
                if isinstance(value, str) and value
            ),
        ),
        created_at=_datetime(row["created_at"]),
        updated_at=_datetime(row["updated_at"]),
        completed_at=_optional_datetime(row.get("completed_at")),
        cancelled_at=_optional_datetime(row.get("cancelled_at")),
    )


def _response(detail: DeadlinePlanDetail) -> DeadlinePlanResponse:
    return DeadlinePlanResponse(
        contract_version=DEADLINE_PLAN_CONTRACT_VERSION,
        origin="authenticated_backend",
        plan=detail.plan,
        active_revision=detail.active_revision,
        pending_revision=detail.pending_revision,
        progress=detail.progress,
    )


def _fingerprint(value: Any) -> str:
    encoded = json.dumps(
        value,
        sort_keys=True,
        separators=(",", ":"),
        ensure_ascii=False,
        default=_json_default,
    ).encode("utf-8")
    return hashlib.sha256(encoded).hexdigest()


def _json_default(value: Any) -> str:
    if isinstance(value, (date, datetime, time, UUID)):
        return value.isoformat() if not isinstance(value, UUID) else str(value)
    raise TypeError(f"Unsupported canonical JSON value: {type(value)!r}")


def _zone(value: str) -> ZoneInfo:
    try:
        return ZoneInfo(value)
    except ZoneInfoNotFoundError as exc:
        raise DeadlinePlanValidationError("Profile timezone is invalid.") from exc


def _aware_utc(value: datetime) -> datetime:
    if value.tzinfo is None or value.utcoffset() is None:
        raise ValueError("Deadline service clock must be timezone-aware.")
    return value.astimezone(UTC)


def _datetime(value: object) -> datetime:
    if isinstance(value, datetime):
        parsed = value
    elif isinstance(value, str):
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    else:
        raise ValueError("Deadline timestamp is invalid.")
    if parsed.tzinfo is None or parsed.utcoffset() is None:
        raise ValueError("Deadline timestamp must be timezone-aware.")
    return parsed


def _optional_datetime(value: object) -> datetime | None:
    return None if value is None else _datetime(value)


def _date(value: object) -> date:
    if isinstance(value, date) and not isinstance(value, datetime):
        return value
    if isinstance(value, str):
        return date.fromisoformat(value)
    raise ValueError("Deadline local date is invalid.")


def _time(value: object) -> time:
    if isinstance(value, time):
        return value.replace(tzinfo=None)
    if isinstance(value, str):
        return time.fromisoformat(value).replace(tzinfo=None)
    raise ValueError("Deadline local time is invalid.")


def _int(value: object) -> int:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise ValueError("Deadline integer is invalid.")
    if int(value) != value:
        raise ValueError("Deadline integer is invalid.")
    return int(value)
