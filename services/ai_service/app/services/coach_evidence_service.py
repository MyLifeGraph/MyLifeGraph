from __future__ import annotations

import asyncio
import hashlib
import json
from collections import defaultdict
from collections.abc import Callable
from dataclasses import dataclass, field
from datetime import UTC, date, datetime, timedelta
from statistics import fmean
from typing import Any, Protocol
from uuid import UUID
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from app.models.coach import (
    COACH_CONTEXT_OPTIONS_CONTRACT_VERSION,
    CoachContextOptionsResponse,
    CoachFocusContextOption,
    CoachPatternsHorizon,
)
from app.models.coach_evidence import (
    COACH_EVIDENCE_CONTRACT_VERSION,
    CoachEvidenceBucket,
    CoachEvidenceDigest,
    CoachEvidenceSourceSummary,
    CoachEvidenceWindow,
    CoachFocusEvidenceSelection,
)
from app.models.learning import LearningPreferencesState
from app.models.weekly_reviews import WeeklyReviewFacts
from app.repositories.coach_evidence_repository import (
    CoachEvidenceRepository,
    CoachEvidenceRows,
    EvidenceRows,
)


class LearningPreferencesReader(Protocol):
    async def get_preferences(self, *, user_id: str) -> LearningPreferencesState: ...


class CoachEvidenceError(RuntimeError):
    pass


class CoachEvidenceAnalysisDisabled(CoachEvidenceError):
    pass


class CoachEvidenceFocusNotFound(CoachEvidenceError):
    pass


class CoachEvidenceTimeout(CoachEvidenceError):
    pass


@dataclass
class _BucketAccumulator:
    starts_on: date
    ends_on: date
    counts: dict[str, int] = field(default_factory=lambda: defaultdict(int))
    values: dict[str, list[float]] = field(
        default_factory=lambda: defaultdict(list),
    )

    def count(self, key: str, amount: int = 1) -> None:
        self.counts[key] += amount

    def value(self, key: str, value: Any) -> None:
        if isinstance(value, bool) or not isinstance(value, (int, float)):
            return
        self.values[key].append(float(value))

    def metrics(self) -> dict[str, int | float]:
        result: dict[str, int | float] = dict(sorted(self.counts.items()))
        for key, values in sorted(self.values.items()):
            if values:
                result[f"average_{key}"] = round(fmean(values), 2)
        return result


class CoachEvidenceService:
    def __init__(
        self,
        *,
        repository: CoachEvidenceRepository,
        learning: LearningPreferencesReader,
        semaphore: asyncio.Semaphore,
        timeout_seconds: float = 15,
        now: Callable[[], datetime] | None = None,
    ) -> None:
        self._repository = repository
        self._learning = learning
        self._semaphore = semaphore
        self._timeout_seconds = timeout_seconds
        self._now = now or (lambda: datetime.now(UTC))

    async def get_context_options(
        self,
        *,
        user_id: str,
        timezone: str,
    ) -> CoachContextOptionsResponse:
        zone = _zone(timezone)

        async def load():
            async with self._semaphore:
                return await asyncio.gather(
                    self._learning.get_preferences(user_id=user_id),
                    self._repository.load_focus_options(user_id=user_id, limit=10),
                )

        try:
            preferences, result = await asyncio.wait_for(
                load(),
                timeout=self._timeout_seconds,
            )
        except TimeoutError as exc:
            raise CoachEvidenceTimeout("Coach context options timed out.") from exc
        options = [_focus_option(row, zone=zone) for row in result.sessions]
        default = next(
            (option.focus_session_id for option in options if option.has_reflection),
            options[0].focus_session_id if options else None,
        )
        return CoachContextOptionsResponse(
            contract_version=COACH_CONTEXT_OPTIONS_CONTRACT_VERSION,
            timezone=timezone,
            personal_pattern_analysis_enabled=(
                preferences.personal_pattern_analysis_enabled
            ),
            focus_options=options,
            default_focus_session_id=default,
            more_focus_options_available=result.more_available,
        )

    async def build_patterns(
        self,
        *,
        user_id: str,
        timezone: str,
        horizon: CoachPatternsHorizon,
    ) -> CoachEvidenceDigest:
        preferences = await self._learning.get_preferences(user_id=user_id)
        if not preferences.personal_pattern_analysis_enabled:
            raise CoachEvidenceAnalysisDisabled(
                "Personal pattern analysis is disabled.",
            )
        now = _aware_now(self._now())
        zone = _zone(timezone)
        local_today = now.astimezone(zone).date()
        starts_at = (
            now - timedelta(days=90)
            if horizon == "90_days"
            else (now - timedelta(days=365) if horizon == "1_year" else None)
        )
        local_start = starts_at.astimezone(zone).date() if starts_at else None
        rows = await self._load(
            user_id=user_id,
            starts_at=starts_at,
            ends_at=now,
            local_starts_on=local_start,
            local_ends_on=local_today,
        )
        digest = _digest(
            mode="patterns",
            horizon=horizon,
            generated_at=now,
            timezone=timezone,
            zone=zone,
            rows=rows,
            selected_focus=None,
        )
        return digest

    async def build_review(
        self,
        *,
        user_id: str,
        timezone: str,
    ) -> CoachEvidenceDigest:
        now = _aware_now(self._now())
        zone = _zone(timezone)
        local_today = now.astimezone(zone).date()
        current_monday = local_today - timedelta(days=local_today.isoweekday() - 1)
        starts_on = current_monday - timedelta(days=14)
        ends_on = current_monday - timedelta(days=1)
        starts_at = datetime.combine(
            starts_on,
            datetime.min.time(),
            tzinfo=zone,
        ).astimezone(UTC)
        ends_at = datetime.combine(
            current_monday,
            datetime.min.time(),
            tzinfo=zone,
        ).astimezone(UTC)
        rows = await self._load(
            user_id=user_id,
            starts_at=starts_at,
            ends_at=ends_at,
            local_starts_on=starts_on,
            local_ends_on=ends_on,
        )
        digest = _digest(
            mode="review",
            horizon="previous_two_full_iso_weeks",
            generated_at=now,
            timezone=timezone,
            zone=zone,
            rows=rows,
            selected_focus=None,
            fixed_window=(starts_on, ends_on),
        )
        return digest

    async def build_focus(
        self,
        *,
        user_id: str,
        timezone: str,
        focus_session_id: UUID,
    ) -> CoachEvidenceDigest:
        now = _aware_now(self._now())
        zone = _zone(timezone)
        starts_at = now - timedelta(days=90)

        async def load() -> tuple[
            dict[str, Any] | None,
            CoachEvidenceRows,
            set[str],
        ]:
            async with self._semaphore:
                selected, evidence, options = await asyncio.gather(
                    self._repository.load_selected_focus(
                        user_id=user_id,
                        focus_session_id=focus_session_id,
                    ),
                    self._repository.load_evidence(
                        user_id=user_id,
                        starts_at=starts_at,
                        ends_at=now,
                        local_starts_on=starts_at.astimezone(zone).date(),
                        local_ends_on=now.astimezone(zone).date(),
                    ),
                    self._repository.load_focus_options(
                        user_id=user_id,
                        limit=10,
                    ),
                )
                return (
                    selected,
                    evidence,
                    {str(row.get("id")) for row in options.sessions},
                )

        try:
            selected_row, rows, allowed_ids = await asyncio.wait_for(
                load(),
                timeout=self._timeout_seconds,
            )
        except TimeoutError as exc:
            raise CoachEvidenceTimeout("Coach evidence timed out.") from exc
        if selected_row is None or str(focus_session_id) not in allowed_ids:
            raise CoachEvidenceFocusNotFound(
                "The selected terminal Focus session is unavailable.",
            )
        selected = _focus_selection(selected_row, zone=zone)
        digest = _digest(
            mode="focus",
            horizon="selected_focus_with_90_day_baseline",
            generated_at=now,
            timezone=timezone,
            zone=zone,
            rows=rows,
            selected_focus=selected,
        )
        return digest

    async def _load(
        self,
        *,
        user_id: str,
        starts_at: datetime | None,
        ends_at: datetime,
        local_starts_on: date | None,
        local_ends_on: date,
    ) -> CoachEvidenceRows:
        async def load() -> CoachEvidenceRows:
            async with self._semaphore:
                return await self._repository.load_evidence(
                    user_id=user_id,
                    starts_at=starts_at,
                    ends_at=ends_at,
                    local_starts_on=local_starts_on,
                    local_ends_on=local_ends_on,
                )

        try:
            return await asyncio.wait_for(
                load(),
                timeout=self._timeout_seconds,
            )
        except TimeoutError as exc:
            raise CoachEvidenceTimeout("Coach evidence timed out.") from exc


def _digest(
    *,
    mode: str,
    horizon: str,
    generated_at: datetime,
    timezone: str,
    zone: ZoneInfo,
    rows: CoachEvidenceRows,
    selected_focus: CoachFocusEvidenceSelection | None,
    fixed_window: tuple[date, date] | None = None,
) -> CoachEvidenceDigest:
    dates = _evidence_dates(rows, zone=zone)
    if fixed_window is not None:
        starts_on, ends_on = fixed_window
    elif horizon == "90_days" or horizon == "selected_focus_with_90_day_baseline":
        ends_on = generated_at.astimezone(zone).date()
        starts_on = (generated_at - timedelta(days=90)).astimezone(zone).date()
    elif horizon == "1_year":
        ends_on = generated_at.astimezone(zone).date()
        starts_on = (generated_at - timedelta(days=365)).astimezone(zone).date()
    else:
        ends_on = generated_at.astimezone(zone).date()
        starts_on = min(dates) if dates else ends_on
    granularity = _granularity(
        mode=mode,
        starts_on=starts_on,
        ends_on=ends_on,
    )
    buckets = _buckets(
        rows,
        zone=zone,
        starts_on=starts_on,
        ends_on=ends_on,
        granularity=granularity,
    )
    selected_focus_in_baseline = (
        selected_focus is not None
        and generated_at - timedelta(days=90)
        <= selected_focus.local_started_at.astimezone(UTC)
        < generated_at
    )
    sources = _source_summaries(
        rows,
        selected_focus=selected_focus,
        selected_focus_in_baseline=selected_focus_in_baseline,
    )
    partial = any(source.partial for source in sources)
    nonempty = selected_focus is not None or any(
        source.included_count for source in sources
    )
    limitations = [
        "These are observational records and do not establish cause.",
        "Missing or deleted records are not reconstructed.",
    ]
    if mode == "focus":
        limitations.append(
            "The selected session is compared only with the retained 90-day baseline.",
        )
    if mode == "review":
        limitations.append(
            "The comparison covers exactly the previous two complete ISO weeks.",
        )
    if partial:
        limitations.append(
            "At least one source exceeded its processing cap; results are partial.",
        )
    limitations.append(
        "Task rows describe retained terminal state, not a complete edit history.",
    )
    summary = _summary_metrics(rows, zone=zone)
    fingerprint = _fingerprint(
        timezone=timezone,
        horizon=horizon,
        starts_on=starts_on,
        ends_on=ends_on,
        rows=rows,
        selected_focus=selected_focus,
    )
    return CoachEvidenceDigest(
        contract_version=COACH_EVIDENCE_CONTRACT_VERSION,
        mode=mode,
        status="partial" if partial else ("available" if nonempty else "empty"),
        generated_at=generated_at,
        timezone=timezone,
        window=CoachEvidenceWindow(
            starts_on=starts_on,
            ends_on=ends_on,
            horizon=horizon,
            granularity=granularity,
        ),
        sources=sources,
        buckets=buckets,
        summary_metrics=summary,
        selected_focus=selected_focus,
        limitations=limitations,
        evidence_fingerprint=fingerprint,
    )


def _source_summaries(
    rows: CoachEvidenceRows,
    *,
    selected_focus: CoachFocusEvidenceSelection | None,
    selected_focus_in_baseline: bool,
) -> list[CoachEvidenceSourceSummary]:
    focus_available = rows.focus_sessions.available_count
    focus_included = len(rows.focus_sessions.rows)
    if selected_focus is not None:
        session_ids = {str(row.get("id")) for row in rows.focus_sessions.rows}
        selected_id = str(selected_focus.focus_session_id)
        if selected_id not in session_ids:
            focus_included += 1
            if not selected_focus_in_baseline:
                focus_available += 1
    focus_available = max(focus_available, focus_included)
    values = [
        ("daily_capture", rows.daily_logs),
        (
            "focus_reflections",
            EvidenceRows(
                rows=rows.focus_sessions.rows,
                available_count=focus_available,
                partial=rows.focus_sessions.partial,
            ),
        ),
        ("habit_outcomes", rows.habit_outcomes),
        ("weekly_reviews", rows.weekly_reviews),
        ("task_lifecycle", rows.task_lifecycle),
    ]
    summaries = []
    for source, source_rows in values:
        included = (
            focus_included if source == "focus_reflections" else len(source_rows.rows)
        )
        summaries.append(
            CoachEvidenceSourceSummary(
                source=source,
                available_count=source_rows.available_count,
                included_count=included,
                partial=source_rows.partial,
            ),
        )
    return summaries


def _summary_metrics(
    rows: CoachEvidenceRows,
    *,
    zone: ZoneInfo,
) -> dict[str, int | float | str | None]:
    reflections = {
        str(row.get("focus_session_id")): row
        for row in rows.reflections.rows
        if row.get("contract_version") == "focus-reflection-v1"
    }
    terminal = rows.focus_sessions.rows
    rated = [
        reflections[str(row.get("id"))]
        for row in terminal
        if str(row.get("id")) in reflections
    ]
    obstacles: dict[str, int] = defaultdict(int)
    for reflection in rated:
        raw = reflection.get("obstacles")
        if isinstance(raw, list):
            for value in raw:
                if value in _OBSTACLES:
                    obstacles[value] += 1
    top_obstacle = (
        min(obstacles, key=lambda value: (-obstacles[value], value))
        if obstacles
        else None
    )
    completed = sum(row.get("status") == "completed" for row in terminal)
    focus_minutes = sum(
        value
        for row in terminal
        if (value := _integer(row.get("actual_minutes"), minimum=0)) is not None
    )
    daily = rows.daily_logs.rows
    return {
        "observed_local_days": len(set(_evidence_dates(rows, zone=zone))),
        "daily_capture_days": len(daily),
        "terminal_focus_sessions": len(terminal),
        "completed_focus_sessions": completed,
        "abandoned_focus_sessions": len(terminal) - completed,
        "actual_focus_minutes": focus_minutes,
        "rated_focus_sessions": len(rated),
        "rated_focus_coverage": (
            0.0 if not terminal else round(len(rated) / len(terminal), 4)
        ),
        "average_focus_quality": _average(row.get("focus_quality") for row in rated),
        "average_useful_progress": _average(
            row.get("useful_progress") for row in rated
        ),
        "top_obstacle": top_obstacle,
        "habit_completions": sum(
            row.get("status") == "completed" for row in rows.habit_outcomes.rows
        ),
        "habit_skips": sum(
            row.get("status") == "skipped" for row in rows.habit_outcomes.rows
        ),
        "persisted_weekly_reviews": len(rows.weekly_reviews.rows),
        "retained_completed_tasks": sum(
            row.get("status") == "done" for row in rows.task_lifecycle.rows
        ),
        "retained_cancelled_tasks": sum(
            row.get("status") == "cancelled" for row in rows.task_lifecycle.rows
        ),
    }


def _buckets(
    rows: CoachEvidenceRows,
    *,
    zone: ZoneInfo,
    starts_on: date,
    ends_on: date,
    granularity: str,
) -> list[CoachEvidenceBucket]:
    accumulators: dict[str, _BucketAccumulator] = {}
    covered_years = ends_on.year - starts_on.year + 1
    year_span = max(1, (covered_years + 23) // 24)

    def bucket(local_date: date) -> _BucketAccumulator | None:
        if local_date < starts_on or local_date > ends_on:
            return None
        key, bucket_start, bucket_end = _bucket_identity(
            local_date,
            granularity=granularity,
            year_span=year_span,
            anchor_year=starts_on.year,
        )
        bucket_start = max(starts_on, bucket_start)
        bucket_end = min(ends_on, bucket_end)
        return accumulators.setdefault(
            key,
            _BucketAccumulator(bucket_start, bucket_end),
        )

    for row in rows.daily_logs.rows:
        local_date = _date(row.get("entry_date"))
        target = bucket(local_date) if local_date is not None else None
        if target is None:
            continue
        target.count("daily_capture_days")
        for key in (
            "sleep_hours",
            "steps",
            "activity_level",
            "mood_score",
            "energy_level",
            "stress_level",
        ):
            target.value(key, row.get(key))
        target.value("sleep_quality", row.get("sleep_quality"))

    reflections = {
        str(row.get("focus_session_id")): row
        for row in rows.reflections.rows
        if row.get("contract_version") == "focus-reflection-v1"
    }
    for row in rows.focus_sessions.rows:
        local_date = _local_datetime_date(row.get("started_at"), zone=zone)
        target = bucket(local_date) if local_date is not None else None
        if target is None:
            continue
        target.count("terminal_focus_sessions")
        target.count(
            "completed_focus_sessions"
            if row.get("status") == "completed"
            else "abandoned_focus_sessions",
        )
        minutes = _integer(row.get("actual_minutes"), minimum=0)
        if minutes is not None:
            target.count("actual_focus_minutes", minutes)
        reflection = reflections.get(str(row.get("id")))
        if reflection is not None:
            target.count("rated_focus_sessions")
            target.value("focus_quality", reflection.get("focus_quality"))
            target.value("useful_progress", reflection.get("useful_progress"))

    for row in rows.habit_outcomes.rows:
        local_date = _date(row.get("entry_date"))
        target = bucket(local_date) if local_date is not None else None
        if target is not None and row.get("status") in {"completed", "skipped"}:
            target.count(f"habit_{row['status']}")

    for row in rows.weekly_reviews.rows:
        local_date = _date(row.get("week_start"))
        target = bucket(local_date) if local_date is not None else None
        if target is None:
            continue
        target.count("persisted_weekly_reviews")
        facts = row.get("facts")
        if isinstance(facts, dict):
            _add_review_facts(target, facts)

    for row in rows.task_lifecycle.rows:
        raw_at = row.get("completed_at") or row.get("cancelled_at")
        local_date = _local_datetime_date(raw_at, zone=zone)
        target = bucket(local_date) if local_date is not None else None
        if target is not None and row.get("status") in {"done", "cancelled"}:
            target.count(f"retained_task_{row['status']}")

    result = [
        CoachEvidenceBucket(
            key=key,
            starts_on=value.starts_on,
            ends_on=value.ends_on,
            metrics=value.metrics(),
        )
        for key, value in sorted(accumulators.items())
        if value.metrics()
    ]
    if len(result) > 24:
        raise CoachEvidenceError("Coach evidence bucket bound was exceeded.")
    return result


def _add_review_facts(target: _BucketAccumulator, facts: dict[str, Any]) -> None:
    try:
        facts = WeeklyReviewFacts.model_validate(facts, strict=True).model_dump(
            mode="python",
        )
    except ValueError:
        return
    mappings = (
        ("tasks", "completed", "review_task_completed"),
        ("habits", "completed", "review_habit_completed"),
        ("habits", "skipped", "review_habit_skipped"),
        ("focus", "actual_minutes", "review_focus_minutes"),
    )
    for group, field_name, metric in mappings:
        group_value = facts.get(group)
        value = group_value.get(field_name) if isinstance(group_value, dict) else None
        integer = _integer(value, minimum=0)
        if integer is not None:
            target.count(metric, integer)


def _evidence_dates(rows: CoachEvidenceRows, *, zone: ZoneInfo) -> list[date]:
    values: list[date] = []
    for row in rows.daily_logs.rows:
        if (value := _date(row.get("entry_date"))) is not None:
            values.append(value)
    for row in rows.focus_sessions.rows:
        if (
            value := _local_datetime_date(row.get("started_at"), zone=zone)
        ) is not None:
            values.append(value)
    for row in rows.habit_outcomes.rows:
        if (value := _date(row.get("entry_date"))) is not None:
            values.append(value)
    for row in rows.weekly_reviews.rows:
        if (value := _date(row.get("week_start"))) is not None:
            values.append(value)
    for row in rows.task_lifecycle.rows:
        raw_at = row.get("completed_at") or row.get("cancelled_at")
        if (value := _local_datetime_date(raw_at, zone=zone)) is not None:
            values.append(value)
    return values


def _granularity(*, mode: str, starts_on: date, ends_on: date) -> str:
    if mode == "review" or (ends_on - starts_on).days <= 120:
        return "week"
    days = (ends_on - starts_on).days + 1
    if days <= 550:
        return "month"
    if days <= 365 * 5:
        return "quarter"
    return "year"


def _bucket_identity(
    value: date,
    *,
    granularity: str,
    year_span: int,
    anchor_year: int,
) -> tuple[str, date, date]:
    if granularity == "week":
        start = value - timedelta(days=value.isoweekday() - 1)
        iso_year, iso_week, _ = start.isocalendar()
        return f"{iso_year}-W{iso_week:02d}", start, start + timedelta(days=6)
    if granularity == "month":
        start = value.replace(day=1)
        next_month = (
            date(start.year + 1, 1, 1)
            if start.month == 12
            else date(start.year, start.month + 1, 1)
        )
        return (
            f"{start.year:04d}-{start.month:02d}",
            start,
            next_month - timedelta(days=1),
        )
    if granularity == "quarter":
        quarter = (value.month - 1) // 3 + 1
        start = date(value.year, (quarter - 1) * 3 + 1, 1)
        next_start = (
            date(value.year + 1, 1, 1)
            if quarter == 4
            else date(value.year, quarter * 3 + 1, 1)
        )
        return f"{value.year:04d}-Q{quarter}", start, next_start - timedelta(days=1)
    group_index = (value.year - anchor_year) // year_span
    first_year = anchor_year + group_index * year_span
    last_year = first_year + year_span - 1
    start = date(first_year, 1, 1)
    key = str(first_year) if first_year == last_year else f"{first_year}-{last_year}"
    return key, start, date(last_year, 12, 31)


def _focus_option(row: dict[str, Any], *, zone: ZoneInfo) -> CoachFocusContextOption:
    return CoachFocusContextOption(
        focus_session_id=UUID(str(row.get("id"))),
        status=row.get("status"),
        local_started_at=_datetime(row.get("started_at")).astimezone(zone),
        planned_minutes=_required_integer(
            row.get("planned_minutes"),
            minimum=5,
            maximum=240,
        ),
        actual_minutes=_required_integer(
            row.get("actual_minutes"),
            minimum=0,
            maximum=90 * 24 * 60,
        ),
        has_reflection=row.get("has_reflection") is True,
    )


def _focus_selection(
    row: dict[str, Any],
    *,
    zone: ZoneInfo,
) -> CoachFocusEvidenceSelection:
    reflection = row.get("reflection")
    if not isinstance(reflection, dict) or reflection.get("contract_version") != (
        "focus-reflection-v1"
    ):
        reflection = {}
    obstacles = reflection.get("obstacles")
    safe_obstacles = (
        [value for value in obstacles if value in _OBSTACLES][:2]
        if isinstance(obstacles, list)
        else []
    )
    return CoachFocusEvidenceSelection(
        focus_session_id=UUID(str(row.get("id"))),
        status=row.get("status"),
        local_started_at=_datetime(row.get("started_at")).astimezone(zone),
        planned_minutes=_required_integer(
            row.get("planned_minutes"),
            minimum=5,
            maximum=240,
        ),
        actual_minutes=_required_integer(
            row.get("actual_minutes"),
            minimum=0,
            maximum=90 * 24 * 60,
        ),
        focus_quality=_integer(
            reflection.get("focus_quality"),
            minimum=1,
            maximum=5,
        ),
        useful_progress=_integer(
            reflection.get("useful_progress"),
            minimum=1,
            maximum=5,
        ),
        obstacles=safe_obstacles,
    )


def _fingerprint(
    *,
    timezone: str,
    horizon: str,
    starts_on: date,
    ends_on: date,
    rows: CoachEvidenceRows,
    selected_focus: CoachFocusEvidenceSelection | None,
) -> str:
    payload = {
        "timezone": timezone,
        "horizon": horizon,
        "starts_on": starts_on.isoformat(),
        "ends_on": ends_on.isoformat(),
        "sources": {
            "daily_logs": rows.daily_logs.rows,
            "focus_sessions": rows.focus_sessions.rows,
            "reflections": rows.reflections.rows,
            "habit_outcomes": rows.habit_outcomes.rows,
            "weekly_reviews": rows.weekly_reviews.rows,
            "task_lifecycle": rows.task_lifecycle.rows,
        },
        "selected_focus": (
            selected_focus.model_dump(mode="json")
            if selected_focus is not None
            else None
        ),
    }
    encoded = json.dumps(
        payload,
        ensure_ascii=False,
        separators=(",", ":"),
        sort_keys=True,
        default=str,
    ).encode("utf-8")
    return hashlib.sha256(encoded).hexdigest()


def _average(values) -> float | None:
    valid = [
        float(value)
        for value in values
        if isinstance(value, (int, float)) and not isinstance(value, bool)
    ]
    return round(fmean(valid), 2) if valid else None


def _integer(
    value: Any,
    *,
    minimum: int,
    maximum: int | None = None,
) -> int | None:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        return None
    numeric = float(value)
    if not numeric.is_integer():
        return None
    integer = int(numeric)
    if integer < minimum or (maximum is not None and integer > maximum):
        return None
    return integer


def _required_integer(
    value: Any,
    *,
    minimum: int,
    maximum: int,
) -> int:
    parsed = _integer(value, minimum=minimum, maximum=maximum)
    if parsed is None:
        raise CoachEvidenceError("Focus evidence contains an invalid duration.")
    return parsed


def _datetime(value: Any) -> datetime:
    if isinstance(value, datetime):
        parsed = value
    elif isinstance(value, str):
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    else:
        raise CoachEvidenceError("Coach evidence timestamp is invalid.")
    if parsed.utcoffset() is None:
        raise CoachEvidenceError("Coach evidence timestamp is invalid.")
    return parsed


def _date(value: Any) -> date | None:
    if isinstance(value, date) and not isinstance(value, datetime):
        return value
    if not isinstance(value, str):
        return None
    try:
        return date.fromisoformat(value)
    except ValueError:
        return None


def _local_datetime_date(value: Any, *, zone: ZoneInfo) -> date | None:
    try:
        return _datetime(value).astimezone(zone).date()
    except (ValueError, CoachEvidenceError):
        return None


def _zone(value: str) -> ZoneInfo:
    try:
        return ZoneInfo(value)
    except ZoneInfoNotFoundError as exc:
        raise CoachEvidenceError("Profile timezone is invalid.") from exc


def _aware_now(value: datetime) -> datetime:
    if value.utcoffset() is None:
        raise CoachEvidenceError("Coach evidence time must be aware.")
    return value.astimezone(UTC)


_OBSTACLES = frozenset(
    {
        "tired",
        "distracted",
        "interrupted",
        "unclear_goal",
        "material_too_difficult",
        "session_too_long",
        "environment",
        "other",
    },
)
