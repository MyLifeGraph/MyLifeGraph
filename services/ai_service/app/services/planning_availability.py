from __future__ import annotations

from collections.abc import Iterable, Mapping, Sequence
from dataclasses import dataclass
from datetime import UTC, date, datetime, time, timedelta
from typing import Any
from zoneinfo import ZoneInfo


ENERGY_WINDOWS: dict[str, tuple[tuple[time, time], ...]] = {
    "early_morning": (
        (time(6), time(11)),
        (time(13), time(17)),
        (time(18), time(21)),
    ),
    "morning": (
        (time(8), time(13)),
        (time(14), time(18)),
        (time(18), time(21)),
    ),
    "afternoon": (
        (time(13), time(18)),
        (time(9), time(12)),
        (time(18), time(21)),
    ),
    "evening": (
        (time(18), time(23)),
        (time(14), time(17)),
        (time(9), time(12)),
    ),
    "variable": (
        (time(9), time(12)),
        (time(14), time(18)),
        (time(18), time(21)),
    ),
}


@dataclass(frozen=True)
class BusySources:
    """Bounded persisted inputs shared by every deterministic planner."""

    recurring_commitments: Sequence[Mapping[str, Any]] = ()
    timed_intervals: Sequence[Mapping[str, Any]] = ()
    all_day_intervals: Sequence[Mapping[str, Any]] = ()


@dataclass(frozen=True)
class PlannedInterval:
    starts_at: datetime
    ends_at: datetime
    minutes: int


@dataclass(frozen=True)
class RecurringSlot:
    weekday: int
    starts_at: time
    ends_at: time
    minutes: int


def allocate_task_intervals(
    *,
    starts_on: date,
    ends_on: date,
    total_minutes: int,
    preferred_session_minutes: int,
    max_daily_minutes: int,
    zone: ZoneInfo,
    local_now: datetime,
    energy_window: str,
    busy_sources: BusySources,
    deadline_at: datetime | None = None,
    daily_reserved_minutes: Mapping[date, int] | None = None,
    account_daily_budget_minutes: int | None = None,
    max_blocks: int = 120,
    duration_increment_minutes: int = 1,
) -> list[PlannedInterval]:
    """Allocate five-minute task blocks without mutating any source record.

    The first pass is spread across the available runway. Later passes reuse
    all viable days. This preserves Deadline Planner's established behavior
    while making the same calculation available to Task planning.
    """

    if total_minutes < 5 or starts_on > ends_on:
        return []
    if energy_window not in ENERGY_WINDOWS:
        raise ValueError("Energy window is invalid.")
    if preferred_session_minutes < 5 or preferred_session_minutes > 240:
        raise ValueError("Preferred session duration is invalid.")
    if max_daily_minutes < 5 or max_daily_minutes > 480:
        raise ValueError("Daily planning duration is invalid.")
    if max_blocks < 1 or max_blocks > 1_500:
        raise ValueError("Planning block bound is invalid.")
    if duration_increment_minutes < 1 or 60 % duration_increment_minutes != 0:
        raise ValueError("Planning duration increment is invalid.")

    days = list(calendar_days(starts_on, ends_on))
    busy_by_day = busy_intervals_by_day(
        days=days,
        sources=busy_sources,
        zone=zone,
        local_now=local_now,
    )
    free_by_day = free_energy_gaps_by_day(
        days=days,
        zone=zone,
        energy_window=energy_window,
        busy_by_day=busy_by_day,
        deadline_at=deadline_at,
    )
    reserved = daily_reserved_minutes or {}
    daily_left = {
        day: (
            max_daily_minutes
            if account_daily_budget_minutes is None
            else min(
                max_daily_minutes,
                max(0, account_daily_budget_minutes - reserved.get(day, 0)),
            )
        )
        for day in days
    }
    viable_days = [
        day
        for day in days
        if any(interval_minutes(gap[0], gap[1]) >= 5 for gap in free_by_day[day])
    ]
    target = min(240, preferred_session_minutes)
    first_count = min(len(viable_days), (total_minutes + target - 1) // target)
    if first_count <= 1:
        first_round_days = viable_days[:first_count]
    else:
        first_round_days = [
            viable_days[
                round(index * (len(viable_days) - 1) / (first_count - 1))
            ]
            for index in range(first_count)
        ]

    blocks: list[PlannedInterval] = []
    remaining = total_minutes
    first_round = True
    while remaining >= 5 and len(blocks) < max_blocks:
        placed = False
        for day in first_round_days if first_round else viable_days:
            if remaining < 5 or len(blocks) >= max_blocks:
                break
            if daily_left[day] < 5:
                continue
            for gap in free_by_day[day]:
                available = interval_minutes(gap[0], gap[1])
                duration = min(target, remaining, daily_left[day], available)
                duration -= duration % duration_increment_minutes
                if duration < 5:
                    continue
                block_start = gap[0]
                block_end = (
                    block_start.astimezone(UTC) + timedelta(minutes=duration)
                ).astimezone(zone)
                if not is_unambiguous_local(block_end, zone):
                    continue
                blocks.append(
                    PlannedInterval(
                        starts_at=block_start,
                        ends_at=block_end,
                        minutes=duration,
                    ),
                )
                gap[0] = (
                    block_end.astimezone(UTC) + timedelta(minutes=5)
                ).astimezone(zone)
                remaining -= duration
                daily_left[day] -= duration
                placed = True
                break
        first_round = False
        if not placed:
            break

    blocks.sort(key=lambda value: (value.starts_at, value.ends_at))
    return blocks


def choose_recurring_habit_slots(
    *,
    weekdays: Sequence[int],
    duration_minutes: int,
    horizon_starts_on: date,
    horizon_days: int,
    zone: ZoneInfo,
    local_now: datetime,
    energy_window: str,
    busy_sources: BusySources,
) -> tuple[list[RecurringSlot], list[int]]:
    """Choose stable weekly wall-clock slots that fit every occurrence.

    A candidate is accepted only when it stays free for the complete bounded
    horizon. This is the Planner's explicit four-week one-off conflict check;
    later conflicts are surfaced on read and never move a slot automatically.
    """

    if horizon_days < 7 or horizon_days > 31:
        raise ValueError("Habit planning horizon is invalid.")
    if duration_minutes < 5 or duration_minutes > 240 or duration_minutes % 5:
        raise ValueError("Habit duration must use five-minute increments.")
    normalized_weekdays = list(dict.fromkeys(weekdays))
    if (
        not normalized_weekdays
        or len(normalized_weekdays) > 7
        or any(day < 1 or day > 7 for day in normalized_weekdays)
    ):
        raise ValueError("Habit weekdays are invalid.")
    if energy_window not in ENERGY_WINDOWS:
        raise ValueError("Energy window is invalid.")

    days = list(
        calendar_days(
            horizon_starts_on,
            horizon_starts_on + timedelta(days=horizon_days - 1),
        ),
    )
    busy = busy_intervals_by_day(
        days=days,
        sources=busy_sources,
        zone=zone,
        local_now=local_now,
    )
    selected: list[RecurringSlot] = []
    unplaced: list[int] = []
    for weekday in normalized_weekdays:
        occurrences = [day for day in days if day.isoweekday() == weekday]
        candidate = _recurring_candidate(
            occurrences=occurrences,
            duration_minutes=duration_minutes,
            zone=zone,
            energy_window=energy_window,
            busy_by_day=busy,
        )
        if candidate is None:
            unplaced.append(weekday)
            continue
        selected.append(
            RecurringSlot(
                weekday=weekday,
                starts_at=candidate[0],
                ends_at=candidate[1],
                minutes=duration_minutes,
            ),
        )
    selected.sort(key=lambda slot: (slot.weekday, slot.starts_at))
    return selected, unplaced


def busy_intervals_by_day(
    *,
    days: Sequence[date],
    sources: BusySources,
    zone: ZoneInfo,
    local_now: datetime,
) -> dict[date, list[tuple[datetime, datetime]]]:
    result: dict[date, list[tuple[datetime, datetime]]] = {day: [] for day in days}
    day_set = set(days)
    for day in days:
        if day == local_now.date():
            rounded_now = round_up_quarter_hour(local_now + timedelta(minutes=15))
            day_start = datetime.combine(day, time.min, tzinfo=zone)
            if rounded_now > day_start:
                result[day].append((day_start, rounded_now))

    for item in sources.recurring_commitments:
        weekday = exact_int(item.get("weekday"))
        starts = exact_time(item.get("starts_at"))
        ends = exact_time(item.get("ends_at"))
        for day in days:
            if (
                day.isoweekday() != weekday
                or not recurring_commitment_applies_on(item, day)
            ):
                continue
            interval_start = datetime.combine(day, starts, tzinfo=zone)
            interval_end = datetime.combine(day, ends, tzinfo=zone)
            if interval_end <= interval_start:
                interval_end += timedelta(days=1)
            result[day].append((interval_start, interval_end))
            if interval_end.date() != day and day + timedelta(days=1) in day_set:
                result[day + timedelta(days=1)].append(
                    (interval_start, interval_end),
                )

    for item in sources.timed_intervals:
        starts_at = exact_datetime(item.get("starts_at")).astimezone(zone)
        ends_at = exact_datetime(item.get("ends_at")).astimezone(zone)
        cursor = starts_at.date()
        while cursor <= ends_at.date():
            if cursor in day_set:
                result[cursor].append((starts_at, ends_at))
            cursor += timedelta(days=1)

    for item in sources.all_day_intervals:
        starts_on = exact_date(item.get("starts_on"))
        ends_on = exact_date(item.get("ends_on"))
        cursor = starts_on
        while cursor < ends_on:
            if cursor in day_set:
                result[cursor].append(
                    (
                        datetime.combine(cursor, time.min, tzinfo=zone),
                        datetime.combine(
                            cursor + timedelta(days=1),
                            time.min,
                            tzinfo=zone,
                        ),
                    ),
                )
            cursor += timedelta(days=1)
    return {day: merge_intervals(intervals) for day, intervals in result.items()}


def free_energy_gaps_by_day(
    *,
    days: Sequence[date],
    zone: ZoneInfo,
    energy_window: str,
    busy_by_day: Mapping[date, Sequence[tuple[datetime, datetime]]],
    deadline_at: datetime | None,
) -> dict[date, list[list[datetime]]]:
    result: dict[date, list[list[datetime]]] = {}
    for day in days:
        gaps: list[list[datetime]] = []
        for window_start, window_end in ENERGY_WINDOWS[energy_window]:
            starts_at = datetime.combine(day, window_start, tzinfo=zone)
            ends_at = datetime.combine(day, window_end, tzinfo=zone)
            if deadline_at is not None:
                ends_at = min(ends_at, deadline_at.astimezone(zone))
            if ends_at <= starts_at or not safe_fixed_offset_interval(
                starts_at,
                ends_at,
                zone,
            ):
                continue
            for gap_start, gap_end in subtract_intervals(
                starts_at,
                ends_at,
                busy_by_day.get(day, ()),
            ):
                normalized_start = ceil_local_five_minutes(gap_start)
                normalized_end = floor_local_five_minutes(gap_end)
                if safe_fixed_offset_interval(normalized_start, normalized_end, zone):
                    gaps.append([normalized_start, normalized_end])
        result[day] = gaps
    return result


def subtract_intervals(
    starts_at: datetime,
    ends_at: datetime,
    busy: Sequence[tuple[datetime, datetime]],
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


def merge_intervals(
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


def calendar_days(starts_on: date, ends_on: date) -> Iterable[date]:
    cursor = starts_on
    while cursor <= ends_on:
        yield cursor
        cursor += timedelta(days=1)


def round_up_quarter_hour(value: datetime) -> datetime:
    rounded = value.replace(second=0, microsecond=0)
    remainder = rounded.minute % 15
    if remainder:
        rounded += timedelta(minutes=15 - remainder)
    return rounded


def ceil_local_five_minutes(value: datetime) -> datetime:
    rounded = value.replace(second=0, microsecond=0)
    remainder = rounded.minute % 5
    if remainder:
        rounded += timedelta(minutes=5 - remainder)
    return rounded


def floor_local_five_minutes(value: datetime) -> datetime:
    rounded = value.replace(second=0, microsecond=0)
    return rounded - timedelta(minutes=rounded.minute % 5)


def safe_fixed_offset_interval(
    starts_at: datetime,
    ends_at: datetime,
    zone: ZoneInfo,
) -> bool:
    return (
        ends_at > starts_at
        and is_unambiguous_local(starts_at, zone)
        and is_unambiguous_local(ends_at, zone)
        and starts_at.utcoffset() == ends_at.utcoffset()
    )


def is_unambiguous_local(value: datetime, zone: ZoneInfo) -> bool:
    naive = value.replace(tzinfo=None)
    candidates = {
        candidate.astimezone(UTC)
        for fold in (0, 1)
        if (
            candidate := naive.replace(tzinfo=zone, fold=fold)
        ).astimezone(UTC).astimezone(zone).replace(tzinfo=None)
        == naive
    }
    return len(candidates) == 1


def interval_minutes(starts_at: datetime, ends_at: datetime) -> int:
    return int(
        (ends_at.astimezone(UTC) - starts_at.astimezone(UTC)).total_seconds()
        // 60
    )


def exact_datetime(value: object) -> datetime:
    if isinstance(value, datetime):
        parsed = value
    elif isinstance(value, str):
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    else:
        raise ValueError("Planning timestamp is invalid.")
    if parsed.tzinfo is None or parsed.utcoffset() is None:
        raise ValueError("Planning timestamp must be timezone-aware.")
    return parsed


def exact_date(value: object) -> date:
    if isinstance(value, datetime):
        raise ValueError("Planning date is invalid.")
    if isinstance(value, date):
        return value
    if not isinstance(value, str):
        raise ValueError("Planning date is invalid.")
    try:
        return date.fromisoformat(value)
    except ValueError as exc:
        raise ValueError("Planning date is invalid.") from exc


def exact_time(value: object) -> time:
    if isinstance(value, time):
        parsed = value
    elif isinstance(value, str):
        try:
            parsed = time.fromisoformat(value)
        except ValueError as exc:
            raise ValueError("Planning time is invalid.") from exc
    else:
        raise ValueError("Planning time is invalid.")
    if parsed.tzinfo is not None:
        raise ValueError("Planning wall time must be timezone-naive.")
    return parsed


def exact_int(value: object) -> int:
    if isinstance(value, bool) or not isinstance(value, int):
        raise ValueError("Planning integer is invalid.")
    return value


def recurring_commitment_applies_on(
    item: Mapping[str, Any],
    local_day: date,
) -> bool:
    """Return whether a recurring busy row applies on one local date.

    New Setup rows keep optional semester bounds in their owned metadata. Rows
    from before this additive contract and non-Setup schedule rows remain
    intentionally unbounded.
    """

    valid_from, valid_until = recurring_commitment_validity(item)
    return (valid_from is None or local_day >= valid_from) and (
        valid_until is None or local_day <= valid_until
    )


def recurring_commitment_validity(
    item: Mapping[str, Any],
) -> tuple[date | None, date | None]:
    metadata = item.get("metadata")
    if not isinstance(metadata, Mapping) or metadata.get("managed_by") != "setup":
        return None, None

    valid_from = _optional_exact_date(metadata.get("valid_from"))
    valid_until = _optional_exact_date(metadata.get("valid_until"))
    if (
        valid_from is not None
        and valid_until is not None
        and valid_until < valid_from
    ):
        raise ValueError("Planning recurring validity range is invalid.")
    return valid_from, valid_until


def _optional_exact_date(value: object) -> date | None:
    return None if value is None else exact_date(value)


def _recurring_candidate(
    *,
    occurrences: Sequence[date],
    duration_minutes: int,
    zone: ZoneInfo,
    energy_window: str,
    busy_by_day: Mapping[date, Sequence[tuple[datetime, datetime]]],
) -> tuple[time, time] | None:
    if not occurrences:
        return None
    for window_start, window_end in ENERGY_WINDOWS[energy_window]:
        cursor = datetime.combine(occurrences[0], window_start, tzinfo=zone)
        window_limit = datetime.combine(occurrences[0], window_end, tzinfo=zone)
        while cursor < window_limit:
            wall_start = cursor.time().replace(tzinfo=None)
            if all(
                _occurrence_is_free(
                    local_day=local_day,
                    wall_start=wall_start,
                    duration_minutes=duration_minutes,
                    zone=zone,
                    busy=busy_by_day.get(local_day, ()),
                    window_end=window_end,
                )
                for local_day in occurrences
            ):
                sample_start = datetime.combine(
                    occurrences[0],
                    wall_start,
                    tzinfo=zone,
                )
                sample_end = (
                    sample_start.astimezone(UTC)
                    + timedelta(minutes=duration_minutes)
                ).astimezone(zone)
                return wall_start, sample_end.time().replace(tzinfo=None)
            cursor += timedelta(minutes=5)
    return None


def _occurrence_is_free(
    *,
    local_day: date,
    wall_start: time,
    duration_minutes: int,
    zone: ZoneInfo,
    busy: Sequence[tuple[datetime, datetime]],
    window_end: time,
) -> bool:
    starts_at = datetime.combine(local_day, wall_start, tzinfo=zone)
    ends_at = (
        starts_at.astimezone(UTC) + timedelta(minutes=duration_minutes)
    ).astimezone(zone)
    if ends_at.date() != local_day or ends_at.time() > window_end:
        return False
    if not safe_fixed_offset_interval(starts_at, ends_at, zone):
        return False
    return all(ends_at <= busy_start or starts_at >= busy_end for busy_start, busy_end in busy)
