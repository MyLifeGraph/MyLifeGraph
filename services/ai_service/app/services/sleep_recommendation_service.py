from __future__ import annotations

import hashlib
import json
from collections import defaultdict
from collections.abc import Callable, Iterable
from dataclasses import dataclass
from datetime import UTC, date, datetime, timedelta
from math import ceil, floor
from statistics import median
from typing import Any
from zoneinfo import ZoneInfo

from pydantic import ValidationError

from app.contracts.daily_capture_v4 import (
    DailyCaptureV4SleepEpisode,
    parse_daily_capture_sleep_episode,
)
from app.models.sleep_recommendation import (
    SLEEP_RECOMMENDATION_CONTRACT_VERSION,
    SleepClockWindow,
    SleepDurationWindow,
    SleepRecommendationEvidence,
    SleepRecommendationReady,
    SleepRecommendationResponse,
    SleepRecommendationSample,
    SleepRecommendationWindow,
)
from app.repositories.personal_patterns_repository import (
    PersonalPatternsNotFound as PersonalPatternsPersistenceNotFound,
    PersonalPatternsPersistenceError,
    PersonalPatternsRepository,
)
from app.services.learning_service import (
    LearningContractError,
    LearningNotFoundError,
    LearningUnavailableError,
)
from app.services.personal_patterns_service import (
    LearningPreferencesReader,
    PersonalPatternsDataError,
    _reflections,
    _sessions,
    _zone,
)


class SleepRecommendationDataError(PersonalPatternsDataError):
    pass


class SleepRecommendationNotFoundError(RuntimeError):
    pass


class SleepRecommendationUnavailableError(RuntimeError):
    pass


@dataclass(frozen=True)
class _Day:
    local_date: date
    episode: DailyCaptureV4SleepEpisode
    bedtime_minute: int
    wake_minute: int
    wake_day_offset: int
    morning_readiness: float
    sleep_quality: float
    morning_energy: float
    useful_progress: float
    focus_quality: float
    completion_rate: float
    rated_sessions: int


@dataclass(frozen=True)
class _Metrics:
    morning_readiness: float
    sleep_quality: float
    morning_energy: float
    useful_progress: float
    focus_quality: float
    completion_rate: float


@dataclass(frozen=True)
class _Candidate:
    days: tuple[_Day, ...]
    comparison: tuple[_Day, ...]
    preferred: _Metrics
    baseline: _Metrics

    @property
    def morning_delta(self) -> float:
        return self.preferred.morning_readiness - self.baseline.morning_readiness

    @property
    def progress_delta(self) -> float:
        return self.preferred.useful_progress - self.baseline.useful_progress

    @property
    def quality_delta(self) -> float:
        return self.preferred.focus_quality - self.baseline.focus_quality

    @property
    def completion_delta(self) -> float:
        return self.preferred.completion_rate - self.baseline.completion_rate


class SleepRecommendationService:
    def __init__(
        self,
        *,
        learning: LearningPreferencesReader,
        repository: PersonalPatternsRepository,
        now: Callable[[], datetime] | None = None,
    ) -> None:
        self._learning = learning
        self._repository = repository
        self._now = now or (lambda: datetime.now(UTC))

    async def get_recommendation(
        self,
        *,
        user_id: str,
    ) -> SleepRecommendationResponse:
        generated_at = self._now()
        if generated_at.utcoffset() is None:
            raise SleepRecommendationDataError(
                "Sleep recommendation generation instant must be aware.",
            )
        generated_at = generated_at.astimezone(UTC)
        starts_at = generated_at - timedelta(days=90)
        try:
            preferences = await self._learning.get_preferences(user_id=user_id)
        except LearningNotFoundError as exc:
            raise SleepRecommendationNotFoundError(str(exc)) from exc
        except (LearningUnavailableError, LearningContractError) as exc:
            raise SleepRecommendationUnavailableError(
                "Sleep recommendation preferences could not be loaded.",
            ) from exc
        try:
            timezone = await self._repository.get_profile_timezone(user_id=user_id)
            zone = _zone(timezone)
        except PersonalPatternsPersistenceNotFound as exc:
            raise SleepRecommendationNotFoundError(str(exc)) from exc
        except PersonalPatternsPersistenceError as exc:
            raise SleepRecommendationUnavailableError(
                "Sleep recommendation profile could not be loaded.",
            ) from exc
        except PersonalPatternsDataError as exc:
            raise SleepRecommendationDataError(
                "Sleep recommendation profile timezone is invalid.",
            ) from exc
        window = SleepRecommendationWindow(
            rolling_days=90,
            starts_at=starts_at,
            ends_at=generated_at,
            local_starts_on=starts_at.astimezone(zone).date(),
            local_ends_on=generated_at.astimezone(zone).date(),
        )
        if not preferences.personal_pattern_analysis_enabled:
            return _response(
                status="disabled",
                reason="analysis_disabled",
                generated_at=generated_at,
                timezone=timezone,
                window=window,
                valid_nights=0,
                days=(),
                summary="Sleep recommendation analysis is turned off.",
                limitations=["No sleep or Focus history was read."],
            )

        try:
            (
                session_rows,
                reflection_rows,
                daily_log_rows,
            ) = await self._repository.load_evidence(
                user_id=user_id,
                starts_at=starts_at,
                ends_at=generated_at,
                local_starts_on=window.local_starts_on,
                local_ends_on=window.local_ends_on,
            )
        except PersonalPatternsPersistenceError as exc:
            raise SleepRecommendationUnavailableError(
                "Sleep recommendation evidence could not be loaded.",
            ) from exc

        try:
            sessions = _sessions(
                session_rows,
                starts_at=starts_at,
                ends_at=generated_at,
                zone=zone,
            )
            reflections = _reflections(
                reflection_rows,
                generated_at=generated_at,
            )
            episodes = _episodes(
                daily_log_rows,
                generated_at=generated_at,
                window=window,
            )
            days = _eligible_days(
                sessions=sessions,
                reflections=reflections,
                episodes=episodes,
                zone=zone,
            )
        except PersonalPatternsDataError as exc:
            raise SleepRecommendationDataError(str(exc)) from exc

        if len(days) < 30:
            return _response(
                status="collecting",
                reason="insufficient_eligible_days",
                generated_at=generated_at,
                timezone=timezone,
                window=window,
                valid_nights=len(episodes),
                days=days,
                summary=(
                    "No stable window yet. Keep completing Morning check-ins and "
                    "rated Focus sessions."
                ),
                limitations=["At least 30 eligible days are required."],
            )

        recurring, comparable = _candidates(days)
        if not recurring:
            return _unstable(
                reason="no_recurring_pattern",
                generated_at=generated_at,
                timezone=timezone,
                window=window,
                valid_nights=len(episodes),
                days=days,
                limitation="No sleep pattern repeated within the 45-minute bounds.",
            )
        if not comparable:
            return _unstable(
                reason="insufficient_comparison_days",
                generated_at=generated_at,
                timezone=timezone,
                window=window,
                valid_nights=len(episodes),
                days=days,
                limitation="A recurring window needs at least ten comparison days.",
            )
        morning_safe = [value for value in comparable if _morning_passes(value)]
        if not morning_safe:
            return _unstable(
                reason="mixed_morning_outcomes",
                generated_at=generated_at,
                timezone=timezone,
                window=window,
                valid_nights=len(episodes),
                days=days,
                limitation="Morning outcomes are mixed across the recurring windows.",
            )
        focus_safe = [value for value in morning_safe if _focus_passes(value)]
        if not focus_safe:
            return _unstable(
                reason="mixed_focus_outcomes",
                generated_at=generated_at,
                timezone=timezone,
                window=window,
                valid_nights=len(episodes),
                days=days,
                limitation="Focus outcomes do not support the same recurring window.",
            )
        stable = [value for value in focus_safe if _stable_in_halves(value, days)]
        if not stable:
            return _unstable(
                reason="temporally_unstable_pattern",
                generated_at=generated_at,
                timezone=timezone,
                window=window,
                valid_nights=len(episodes),
                days=days,
                limitation="The observed direction does not repeat in both time halves.",
            )

        selected = sorted(stable, key=_candidate_sort_key)[0]
        recommendation = _ready_recommendation(
            candidate=selected,
            timezone=timezone,
            window=window,
            all_days=days,
        )
        return _response(
            status="ready",
            reason="ready",
            generated_at=generated_at,
            timezone=timezone,
            window=window,
            valid_nights=len(episodes),
            days=days,
            recommendation=recommendation,
            summary=(
                "This is the best-supported sleep window in your recent history "
                "and is associated with stronger mornings and useful Focus progress."
            ),
            limitations=[
                "This is an observed association, not a medical optimum or a causal claim."
            ],
        )


def _episodes(
    rows: list[dict[str, Any]],
    *,
    generated_at: datetime,
    window: SleepRecommendationWindow,
) -> dict[date, DailyCaptureV4SleepEpisode]:
    result: dict[date, DailyCaptureV4SleepEpisode] = {}
    for row in rows:
        try:
            row_date = date.fromisoformat(str(row.get("entry_date")))
        except ValueError:
            continue
        updated = _aware_datetime(row.get("updated_at"))
        metadata = row.get("metadata")
        if (
            row_date < window.local_starts_on
            or row_date > window.local_ends_on
            or updated is None
            or updated > generated_at
            or not isinstance(metadata, dict)
            or metadata.get("capture_version")
            not in {"daily-capture-v4", "daily-capture-v5"}
            or not isinstance(metadata.get("captures"), dict)
        ):
            continue
        parsed = parse_daily_capture_sleep_episode(
            metadata["captures"].get("morning"),
            row_date=row_date,
            container_version=metadata["capture_version"],
        )
        episode = parsed.value
        if not isinstance(episode, DailyCaptureV4SleepEpisode):
            continue
        if not (
            window.starts_at <= episode.captured_at < generated_at
            and episode.woke_at < generated_at
        ):
            continue
        existing = result.get(row_date)
        if existing is not None and existing.capture_id != episode.capture_id:
            raise SleepRecommendationDataError(
                "Sleep recommendation has ambiguous Morning evidence.",
            )
        result[row_date] = episode
    return result


def _eligible_days(
    *,
    sessions: list[Any],
    reflections: dict[str, Any],
    episodes: dict[date, DailyCaptureV4SleepEpisode],
    zone: ZoneInfo,
) -> tuple[_Day, ...]:
    grouped: dict[date, list[tuple[Any, Any]]] = defaultdict(list)
    for session in sessions:
        episode = episodes.get(session.local_date)
        reflection = reflections.get(session.id)
        if (
            episode is None
            or reflection is None
            or session.started_at < episode.woke_at
            or session.started_at < episode.captured_at
            or reflection.created_at < session.ended_at
        ):
            continue
        grouped[session.local_date].append((session, reflection))

    result: list[_Day] = []
    for local_day in sorted(grouped):
        episode = episodes[local_day]
        values = grouped[local_day]
        bedtime = episode.estimated_sleep_started_at.astimezone(zone)
        wake = episode.woke_at.astimezone(zone)
        wake_day_offset = (wake.date() - bedtime.date()).days
        if wake_day_offset not in {0, 1}:
            raise SleepRecommendationDataError(
                "Sleep recommendation has an invalid local sleep interval.",
            )
        result.append(
            _Day(
                local_date=local_day,
                episode=episode,
                bedtime_minute=bedtime.hour * 60 + bedtime.minute,
                wake_minute=wake.hour * 60 + wake.minute,
                wake_day_offset=wake_day_offset,
                morning_readiness=(
                    float(episode.sleep_quality + episode.current_energy) / 2
                ),
                sleep_quality=float(episode.sleep_quality),
                morning_energy=float(episode.current_energy),
                useful_progress=float(
                    median(reflection.useful_progress for _, reflection in values)
                ),
                focus_quality=float(
                    median(reflection.focus_quality for _, reflection in values)
                ),
                completion_rate=(
                    sum(session.status == "completed" for session, _ in values)
                    / len(values)
                ),
                rated_sessions=len(values),
            ),
        )
    return tuple(result)


def _candidates(days: tuple[_Day, ...]) -> tuple[list[_Candidate], list[_Candidate]]:
    memberships: set[tuple[date, ...]] = set()
    recurring: list[_Candidate] = []
    comparable: list[_Candidate] = []
    for seed in days:
        members = tuple(
            value
            for value in days
            if _circular_distance(value.bedtime_minute, seed.bedtime_minute) <= 45
            and _circular_distance(value.wake_minute, seed.wake_minute) <= 45
            and value.wake_day_offset == seed.wake_day_offset
            and abs(
                value.episode.estimated_sleep_minutes
                - seed.episode.estimated_sleep_minutes
            )
            <= 45
        )
        if (
            len(members) < 10
            or _circular_span(value.bedtime_minute for value in members) > 45
            or _circular_span(value.wake_minute for value in members) > 45
            or max(value.episode.estimated_sleep_minutes for value in members)
            - min(value.episode.estimated_sleep_minutes for value in members)
            > 45
        ):
            continue
        identity = tuple(value.local_date for value in members)
        if identity in memberships:
            continue
        memberships.add(identity)
        member_dates = set(identity)
        comparison = tuple(
            value for value in days if value.local_date not in member_dates
        )
        candidate = _Candidate(
            days=members,
            comparison=comparison,
            preferred=_metrics(members),
            baseline=_metrics(comparison) if comparison else _metrics(members),
        )
        recurring.append(candidate)
        if len(comparison) >= 10:
            comparable.append(candidate)
    return recurring, comparable


def _morning_passes(value: _Candidate) -> bool:
    return (
        value.morning_delta >= 0.5
        and value.preferred.sleep_quality - value.baseline.sleep_quality >= -0.5
        and value.preferred.morning_energy - value.baseline.morning_energy >= -0.5
    )


def _focus_passes(value: _Candidate) -> bool:
    return (
        value.progress_delta >= 0.5
        and value.quality_delta >= -0.5
        and value.completion_delta >= -0.10
    )


def _stable_in_halves(value: _Candidate, all_days: tuple[_Day, ...]) -> bool:
    midpoint = len(all_days) // 2
    halves = (
        set(day.local_date for day in all_days[:midpoint]),
        set(day.local_date for day in all_days[midpoint:]),
    )
    preferred_dates = {day.local_date for day in value.days}
    comparison_dates = {day.local_date for day in value.comparison}
    for half in halves:
        preferred = tuple(day for day in value.days if day.local_date in half)
        comparison = tuple(day for day in value.comparison if day.local_date in half)
        if (
            len(preferred) < 5
            or len(comparison) < 5
            or not (preferred_dates & half)
            or not (comparison_dates & half)
        ):
            return False
        left = _metrics(preferred)
        right = _metrics(comparison)
        if (
            left.morning_readiness <= right.morning_readiness
            or left.useful_progress <= right.useful_progress
            or left.sleep_quality - right.sleep_quality < -0.5
            or left.morning_energy - right.morning_energy < -0.5
            or left.focus_quality - right.focus_quality < -0.5
            or left.completion_rate - right.completion_rate < -0.10
        ):
            return False
    return True


def _candidate_sort_key(value: _Candidate) -> tuple[float, ...]:
    return (
        -value.morning_delta,
        -value.progress_delta,
        -value.quality_delta,
        -value.completion_delta,
        -len(value.days),
        _clock_anchor(day.bedtime_minute for day in value.days),
        _clock_anchor(day.wake_minute for day in value.days),
        float(median(day.episode.estimated_sleep_minutes for day in value.days)),
    )


def _ready_recommendation(
    *,
    candidate: _Candidate,
    timezone: str,
    window: SleepRecommendationWindow,
    all_days: tuple[_Day, ...],
) -> SleepRecommendationReady:
    raw_duration = int(
        median(day.episode.estimated_sleep_minutes for day in candidate.days)
    )
    confirmed_target = int(
        median(day.episode.sleep_target_minutes for day in candidate.days)
    )
    evidence = SleepRecommendationEvidence(
        candidate_days=len(candidate.days),
        comparison_days=len(candidate.comparison),
        morning_readiness_median_delta=candidate.morning_delta,
        sleep_quality_median_delta=(
            candidate.preferred.sleep_quality - candidate.baseline.sleep_quality
        ),
        morning_energy_median_delta=(
            candidate.preferred.morning_energy - candidate.baseline.morning_energy
        ),
        useful_progress_median_delta=candidate.progress_delta,
        focus_quality_median_delta=candidate.quality_delta,
        completion_rate_delta=candidate.completion_delta,
        consistent_in_both_halves=True,
    )
    return SleepRecommendationReady(
        bedtime=_clock_window(day.bedtime_minute for day in candidate.days),
        wake_time=_clock_window(day.wake_minute for day in candidate.days),
        duration=_duration_window(
            day.episode.estimated_sleep_minutes for day in candidate.days
        ),
        wake_day_offset=candidate.days[0].wake_day_offset,
        raw_median_duration_minutes=raw_duration,
        median_confirmed_sleep_target_minutes=confirmed_target,
        warning=(
            "below_confirmed_sleep_target" if raw_duration < confirmed_target else None
        ),
        evidence=evidence,
        evidence_fingerprint=_fingerprint(
            timezone=timezone,
            window=window,
            all_days=all_days,
            candidate=candidate,
        ),
    )


def _metrics(values: Iterable[_Day]) -> _Metrics:
    items = tuple(values)
    if not items:
        raise SleepRecommendationDataError("Sleep recommendation group is empty.")
    return _Metrics(
        morning_readiness=float(median(value.morning_readiness for value in items)),
        sleep_quality=float(median(value.sleep_quality for value in items)),
        morning_energy=float(median(value.morning_energy for value in items)),
        useful_progress=float(median(value.useful_progress for value in items)),
        focus_quality=float(median(value.focus_quality for value in items)),
        completion_rate=float(median(value.completion_rate for value in items)),
    )


def _clock_window(values: Iterable[int]) -> SleepClockWindow:
    unwrapped = _unwrap_clock(values)
    start = floor(_percentile(unwrapped, 0.25) / 15) * 15
    end = ceil(_percentile(unwrapped, 0.75) / 15) * 15
    if end - start > 60:
        raise SleepRecommendationDataError("Sleep clock window is too wide.")
    return SleepClockWindow(
        start_local_time=_clock(start),
        end_local_time=_clock(end),
        end_day_offset=1 if end // 1440 > start // 1440 else 0,
        width_minutes=end - start,
    )


def _duration_window(values: Iterable[int]) -> SleepDurationWindow:
    items = sorted(values)
    minimum = floor(_percentile(items, 0.25) / 15) * 15
    maximum = ceil(_percentile(items, 0.75) / 15) * 15
    if maximum - minimum > 60:
        raise SleepRecommendationDataError("Sleep duration window is too wide.")
    try:
        return SleepDurationWindow(
            minimum_minutes=minimum,
            maximum_minutes=maximum,
        )
    except ValidationError as exc:
        raise SleepRecommendationDataError(
            "Sleep duration window is invalid.",
        ) from exc


def _percentile(values: Iterable[int], quantile: float) -> float:
    items = sorted(values)
    if len(items) == 1:
        return float(items[0])
    position = (len(items) - 1) * quantile
    lower = floor(position)
    upper = ceil(position)
    if lower == upper:
        return float(items[lower])
    return items[lower] + (items[upper] - items[lower]) * (position - lower)


def _unwrap_clock(values: Iterable[int]) -> list[int]:
    items = list(values)
    if not items:
        raise SleepRecommendationDataError("Sleep clock group is empty.")
    anchor = items[0]
    return sorted(anchor + _signed_clock_delta(value, anchor) for value in items)


def _clock_anchor(values: Iterable[int]) -> float:
    return float(median(_unwrap_clock(values))) % 1440


def _circular_span(values: Iterable[int]) -> int:
    items = sorted(value % 1440 for value in values)
    if len(items) < 2:
        return 0
    gaps = [items[index + 1] - items[index] for index in range(len(items) - 1)] + [
        items[0] + 1440 - items[-1]
    ]
    return 1440 - max(gaps)


def _circular_distance(left: int, right: int) -> int:
    return abs(_signed_clock_delta(left, right))


def _signed_clock_delta(value: int, anchor: int) -> int:
    return (value - anchor + 720) % 1440 - 720


def _clock(minutes: int) -> str:
    value = minutes % 1440
    return f"{value // 60:02d}:{value % 60:02d}"


def _fingerprint(
    *,
    timezone: str,
    window: SleepRecommendationWindow,
    all_days: tuple[_Day, ...],
    candidate: _Candidate,
) -> str:
    candidate_dates = {value.local_date for value in candidate.days}
    payload = {
        "contract_version": SLEEP_RECOMMENDATION_CONTRACT_VERSION,
        "timezone": timezone,
        "local_starts_on": window.local_starts_on.isoformat(),
        "local_ends_on": window.local_ends_on.isoformat(),
        "days": [
            {
                "local_date": value.local_date.isoformat(),
                "capture_id": value.episode.capture_id,
                "bedtime_minute": value.bedtime_minute,
                "wake_minute": value.wake_minute,
                "wake_day_offset": value.wake_day_offset,
                "duration_minutes": value.episode.estimated_sleep_minutes,
                "sleep_target_minutes": value.episode.sleep_target_minutes,
                "sleep_quality": value.sleep_quality,
                "morning_energy": value.morning_energy,
                "focus_quality": value.focus_quality,
                "useful_progress": value.useful_progress,
                "completion_rate": value.completion_rate,
                "candidate": value.local_date in candidate_dates,
            }
            for value in all_days
        ],
    }
    canonical = json.dumps(payload, sort_keys=True, separators=(",", ":")).encode()
    return hashlib.sha256(canonical).hexdigest()


def _unstable(
    *,
    reason: str,
    generated_at: datetime,
    timezone: str,
    window: SleepRecommendationWindow,
    valid_nights: int,
    days: tuple[_Day, ...],
    limitation: str,
) -> SleepRecommendationResponse:
    return _response(
        status="unstable",
        reason=reason,
        generated_at=generated_at,
        timezone=timezone,
        window=window,
        valid_nights=valid_nights,
        days=days,
        summary="No stable window yet. Recent outcomes do not support one window.",
        limitations=[limitation],
    )


def _response(
    *,
    status: str,
    reason: str,
    generated_at: datetime,
    timezone: str,
    window: SleepRecommendationWindow,
    valid_nights: int,
    days: tuple[_Day, ...],
    summary: str,
    limitations: list[str],
    recommendation: SleepRecommendationReady | None = None,
) -> SleepRecommendationResponse:
    eligible = len(days)
    return SleepRecommendationResponse(
        contract_version=SLEEP_RECOMMENDATION_CONTRACT_VERSION,
        status=status,
        reason=reason,
        generated_at=generated_at,
        timezone=timezone,
        window=window,
        sample=SleepRecommendationSample(
            valid_nights=valid_nights,
            eligible_focus_days=eligible,
            rated_sessions=sum(value.rated_sessions for value in days),
            required_eligible_days=30,
            progress=f"{min(eligible, 30)}/30",
        ),
        recommendation=recommendation,
        summary=summary,
        limitations=limitations,
    )


def _aware_datetime(value: object) -> datetime | None:
    if isinstance(value, datetime):
        result = value
    elif isinstance(value, str):
        try:
            result = datetime.fromisoformat(value.replace("Z", "+00:00"))
        except ValueError:
            return None
    else:
        return None
    if result.utcoffset() is None:
        return None
    return result.astimezone(UTC)
