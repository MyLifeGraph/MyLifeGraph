from __future__ import annotations

import hashlib
import json
import logging
from collections import defaultdict
from collections.abc import Callable, Iterable
from dataclasses import dataclass
from datetime import UTC, date, datetime, timedelta
from statistics import median
from typing import Any, Protocol
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from app.models.learning import LearningPreferencesState
from app.models.personal_patterns import (
    PERSONAL_PATTERNS_CONTRACT_VERSION,
    LearnedFocusPlannerPreference,
    PersonalPattern,
    PersonalPatternCorrelationPoint,
    PersonalPatternEvidence,
    PersonalPatternsBaseline,
    PersonalPatternsResponse,
    PersonalPatternsSample,
    PersonalPatternsWindow,
)
from app.repositories.personal_patterns_repository import (
    PersonalPatternsPersistenceError,
    PersonalPatternsRepository,
)
from app.services.daily_capture_parser import (
    DailyCaptureV4SleepEpisode,
    parse_daily_capture_v4_sleep_episode,
)


class LearningPreferencesReader(Protocol):
    async def get_preferences(self, *, user_id: str) -> LearningPreferencesState: ...


class PersonalPatternsDataError(ValueError):
    pass


_TIME_WINDOWS = (
    ("05-09", "05:00–09:00"),
    ("09-13", "09:00–13:00"),
    ("13-18", "13:00–18:00"),
    ("18-23", "18:00–23:00"),
)
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
logger = logging.getLogger(__name__)


@dataclass(frozen=True)
class _Session:
    id: str
    status: str
    started_at: datetime
    ended_at: datetime
    planned_minutes: int
    actual_minutes: int
    local_started_at: datetime
    local_date: date
    time_window: str
    previous_gap_minutes: int | None = None


@dataclass(frozen=True)
class _Reflection:
    session_id: str
    focus_quality: int
    useful_progress: int
    obstacles: tuple[str, ...]
    created_at: datetime
    updated_at: datetime


@dataclass(frozen=True)
class _Observation:
    session: _Session
    reflection: _Reflection
    sleep: DailyCaptureV4SleepEpisode | None

    @property
    def focus_quality(self) -> float:
        return float(self.reflection.focus_quality)

    @property
    def useful_progress(self) -> float:
        return float(self.reflection.useful_progress)

    @property
    def completion(self) -> float:
        return 1.0 if self.session.status == "completed" else 0.0

    @property
    def local_date(self) -> date:
        return self.session.local_date


@dataclass(frozen=True)
class _RatedValue:
    focus_quality: float
    useful_progress: float
    completion: float
    local_date: date


@dataclass(frozen=True)
class _Metrics:
    count: int
    median_focus_quality: float
    median_useful_progress: float
    completion_rate: float


@dataclass(frozen=True)
class _Comparison:
    preferred_key: str
    preferred_label: str
    comparison_label: str
    preferred: _Metrics
    comparison: _Metrics
    preferred_dates: frozenset[date]
    comparison_dates: frozenset[date]
    preferred_values: tuple[_RatedValue, ...]
    comparison_values: tuple[_RatedValue, ...]

    @property
    def useful_delta(self) -> float:
        return (
            self.preferred.median_useful_progress
            - self.comparison.median_useful_progress
        )

    @property
    def focus_delta(self) -> float:
        return (
            self.preferred.median_focus_quality
            - self.comparison.median_focus_quality
        )

    @property
    def completion_delta(self) -> float:
        return (
            self.preferred.completion_rate
            - self.comparison.completion_rate
        )


class PersonalPatternsService:
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

    async def get_patterns(self, *, user_id: str) -> PersonalPatternsResponse:
        try:
            generated_at = self._now()
            if generated_at.utcoffset() is None:
                raise PersonalPatternsDataError(
                    "Personal pattern generation instant must be aware.",
                )
            generated_at = generated_at.astimezone(UTC)
            starts_at = generated_at - timedelta(days=90)
        except Exception:
            _log_failure(stage="request_time")
            raise
        try:
            preferences = await self._learning.get_preferences(user_id=user_id)
        except Exception:
            _log_failure(stage="preferences")
            raise
        try:
            timezone = await self._repository.get_profile_timezone(user_id=user_id)
            zone = _zone(timezone)
            window = PersonalPatternsWindow(
                rolling_days=90,
                starts_at=starts_at,
                ends_at=generated_at,
                local_starts_on=starts_at.astimezone(zone).date(),
                local_ends_on=generated_at.astimezone(zone).date(),
            )
        except Exception:
            _log_failure(stage="profile_timezone")
            raise
        if not preferences.personal_pattern_analysis_enabled:
            try:
                response = _disabled_response(
                    generated_at=generated_at,
                    timezone=timezone,
                    window=window,
                )
            except Exception:
                _log_failure(stage="response_validation")
                raise
            _log_success(response)
            return response

        try:
            session_rows, reflection_rows, daily_log_rows = (
                await self._repository.load_evidence(
                    user_id=user_id,
                    starts_at=starts_at,
                    ends_at=generated_at,
                    local_starts_on=window.local_starts_on,
                    local_ends_on=window.local_ends_on,
                )
            )
        except Exception:
            _log_failure(stage="evidence_read")
            raise
        try:
            sessions = _sessions(
                session_rows,
                starts_at=starts_at,
                ends_at=generated_at,
                zone=zone,
            )
            session_ids = {session.id for session in sessions}
            reflections = {
                session_id: reflection
                for session_id, reflection in _reflections(
                    reflection_rows,
                    generated_at=generated_at,
                ).items()
                if session_id in session_ids
            }
            episodes = _sleep_episodes(
                daily_log_rows,
                generated_at=generated_at,
            )
            observations = _observations(
                sessions=sessions,
                reflections=reflections,
                episodes=episodes,
            )
            used_episode_ids = {
                observation.sleep.capture_id
                for observation in observations
                if observation.sleep is not None
            }
            fingerprint = _evidence_fingerprint(
                timezone=timezone,
                window=window,
                sessions=sessions,
                reflections=reflections,
                episodes=[
                    episode
                    for episode in episodes
                    if episode.capture_id in used_episode_ids
                ],
            )
            response = _response(
                generated_at=generated_at,
                timezone=timezone,
                window=window,
                sessions=sessions,
                observations=observations,
                evidence_fingerprint=fingerprint,
            )
        except Exception:
            _log_failure(
                stage="evidence_analysis",
                terminal_sessions=len(session_rows),
                rated_sessions=len(reflection_rows),
            )
            raise
        _log_success(response)
        return response


def _log_success(response: PersonalPatternsResponse) -> None:
    logger.info(
        "Personal patterns completed: contract_version=%s status=%s "
        "terminal_sessions=%s rated_sessions=%s rated_local_days=%s",
        response.contract_version,
        response.status,
        response.sample.terminal_sessions,
        response.sample.rated_sessions,
        response.sample.rated_local_days,
    )


def _log_failure(
    *,
    stage: str,
    terminal_sessions: int = 0,
    rated_sessions: int = 0,
) -> None:
    logger.warning(
        "Personal patterns failed: contract_version=%s status=error "
        "terminal_sessions=%s rated_sessions=%s error_stage=%s",
        PERSONAL_PATTERNS_CONTRACT_VERSION,
        terminal_sessions,
        rated_sessions,
        stage,
    )


def _disabled_response(
    *,
    generated_at: datetime,
    timezone: str,
    window: PersonalPatternsWindow,
) -> PersonalPatternsResponse:
    return PersonalPatternsResponse(
        contract_version=PERSONAL_PATTERNS_CONTRACT_VERSION,
        status="disabled",
        generated_at=generated_at,
        timezone=timezone,
        window=window,
        summary=(
            "Personal pattern analysis is turned off in Personal learning."
        ),
        sample=PersonalPatternsSample(
            terminal_sessions=0,
            rated_sessions=0,
            rated_local_days=0,
            rating_coverage=0.0,
            first_rated_local_date=None,
            last_rated_local_date=None,
        ),
        baseline=None,
        patterns=[],
        planner_preference=LearnedFocusPlannerPreference(
            eligible=False,
            reason="analysis_disabled",
            window=None,
            window_label=None,
            evidence_count=0,
            evidence_starts_on=None,
            evidence_ends_on=None,
            evidence_fingerprint=None,
        ),
        limitations=[
            "No Focus or Daily Capture history was read for this response.",
            "Turn analysis on in Personal learning to begin again.",
        ],
        correlation_points=[],
        evidence_fingerprint=None,
    )


def _response(
    *,
    generated_at: datetime,
    timezone: str,
    window: PersonalPatternsWindow,
    sessions: list[_Session],
    observations: list[_Observation],
    evidence_fingerprint: str,
) -> PersonalPatternsResponse:
    rated_count = len(observations)
    terminal_count = len(sessions)
    rated_dates = sorted({value.session.local_date for value in observations})
    coverage = 0.0 if terminal_count == 0 else rated_count / terminal_count
    sample = PersonalPatternsSample(
        terminal_sessions=terminal_count,
        rated_sessions=rated_count,
        rated_local_days=len(rated_dates),
        rating_coverage=coverage,
        first_rated_local_date=rated_dates[0] if rated_dates else None,
        last_rated_local_date=rated_dates[-1] if rated_dates else None,
    )
    baseline = (
        PersonalPatternsBaseline(
            median_focus_quality=_median(
                value.reflection.focus_quality for value in observations
            ),
            median_useful_progress=_median(
                value.reflection.useful_progress for value in observations
            ),
            completion_rate=_rate(value.completion for value in observations),
        )
        if rated_count >= 3
        else None
    )
    stable = (
        rated_count >= 20
        and bool(rated_dates)
        and (rated_dates[-1] - rated_dates[0]).days + 1 >= 28
    )
    time_comparisons = _time_comparisons(observations)
    has_emerging_comparison = _has_emerging_comparison(
        observations,
        time_comparisons=time_comparisons,
    )
    status = (
        "stable"
        if stable
        else (
            "emerging"
            if rated_count >= 14 and has_emerging_comparison
            else "collecting"
        )
    )
    best_time = _best_comparison(time_comparisons)
    planner_time = _best_planner_comparison(time_comparisons)
    displayed_time = planner_time if stable and planner_time is not None else best_time
    patterns: list[PersonalPattern] = []
    if status in {"emerging", "stable"}:
        maturity = "stable" if status == "stable" else "emerging"
        if (
            displayed_time is not None
            and displayed_time.preferred.count >= 5
            and displayed_time.comparison.count >= 5
        ):
            patterns.append(_timing_pattern(displayed_time, maturity=maturity))
        sleep = _sleep_pattern(observations, maturity=maturity)
        if sleep is not None:
            patterns.append(sleep)
        length_or_gap = _length_or_gap_pattern(
            observations,
            maturity=maturity,
        )
        if length_or_gap is not None:
            patterns.append(length_or_gap)

    planner = _planner_preference(
        observations=observations,
        comparison=planner_time or best_time,
        stable=stable,
        coverage=coverage,
        fingerprint=evidence_fingerprint,
    )
    limitations = [
        "These are observational associations and do not show cause.",
        (
            "Missing reflections are excluded rather than scored as zero; "
            f"rated coverage is {coverage:.0%}."
        ),
        "Night sessions are visible evidence but can never become a Planner preference.",
        "Sleep evidence never changes your sleep target, capacity, or plans.",
        (
            "Evidence includes only facts observed by "
            f"{generated_at.isoformat()}."
        ),
        _obstacle_summary(observations),
    ]
    summary = _summary(status=status, rated_count=rated_count, patterns=patterns)
    return PersonalPatternsResponse(
        contract_version=PERSONAL_PATTERNS_CONTRACT_VERSION,
        status=status,
        generated_at=generated_at,
        timezone=timezone,
        window=window,
        summary=summary,
        sample=sample,
        baseline=baseline,
        patterns=patterns[:3],
        planner_preference=planner,
        limitations=limitations,
        correlation_points=_correlation_points(observations),
        evidence_fingerprint=evidence_fingerprint,
    )


def _sessions(
    rows: list[dict[str, Any]],
    *,
    starts_at: datetime,
    ends_at: datetime,
    zone: ZoneInfo,
) -> list[_Session]:
    parsed: list[_Session] = []
    seen: set[str] = set()
    for row in rows:
        session_id = _text(row.get("id"), maximum=200)
        status = row.get("status")
        started_at = _datetime(row.get("started_at"))
        ended_at = _datetime(row.get("ended_at"))
        planned = _integer(row.get("planned_minutes"), minimum=5, maximum=240)
        actual = _integer(
            row.get("actual_minutes"),
            minimum=0,
            maximum=90 * 24 * 60,
        )
        if ended_at is not None and ended_at >= ends_at:
            # A session that had not ended before the captured observation
            # instant is not a fact in this response.
            continue
        if (
            session_id is None
            or session_id in seen
            or status not in {"completed", "abandoned"}
            or started_at is None
            or ended_at is None
            or planned is None
            or actual is None
            or started_at < starts_at
            or started_at >= ends_at
            or ended_at < started_at
            or int((ended_at - started_at).total_seconds() // 60) != actual
        ):
            raise PersonalPatternsDataError(
                "Personal pattern Focus evidence is invalid.",
            )
        seen.add(session_id)
        local_started_at = started_at.astimezone(zone)
        parsed.append(
            _Session(
                id=session_id,
                status=status,
                started_at=started_at,
                ended_at=ended_at,
                planned_minutes=planned,
                actual_minutes=actual,
                local_started_at=local_started_at,
                local_date=local_started_at.date(),
                time_window=_time_window(local_started_at.hour),
            ),
        )
    parsed.sort(key=lambda value: (value.started_at, value.id))
    result: list[_Session] = []
    previous: _Session | None = None
    for session in parsed:
        gap = (
            None
            if previous is None
            else max(
                0,
                int((session.started_at - previous.ended_at).total_seconds() // 60),
            )
        )
        result.append(
            _Session(
                **{
                    **session.__dict__,
                    "previous_gap_minutes": gap,
                },
            ),
        )
        previous = session
    return result


def _reflections(
    rows: list[dict[str, Any]],
    *,
    generated_at: datetime,
) -> dict[str, _Reflection]:
    parsed: dict[str, _Reflection] = {}
    for row in rows:
        session_id = _text(row.get("focus_session_id"), maximum=200)
        focus_quality = _integer(row.get("focus_quality"), minimum=1, maximum=5)
        useful_progress = _integer(
            row.get("useful_progress"),
            minimum=1,
            maximum=5,
        )
        created_at = _datetime(row.get("created_at"))
        updated_at = _datetime(row.get("updated_at"))
        if (
            created_at is None
            or updated_at is None
            or created_at >= generated_at
            or updated_at > generated_at
        ):
            continue
        raw_obstacles = row.get("obstacles")
        if (
            row.get("contract_version") != "focus-reflection-v1"
            or session_id is None
            or session_id in parsed
            or focus_quality is None
            or useful_progress is None
            or created_at is None
            or updated_at is None
            or updated_at < created_at
            or not isinstance(raw_obstacles, list)
            or len(raw_obstacles) > 2
            or any(
                not isinstance(value, str) or value not in _OBSTACLES
                for value in raw_obstacles
            )
            or len(set(raw_obstacles)) != len(raw_obstacles)
        ):
            raise PersonalPatternsDataError(
                "Personal pattern reflection evidence is invalid.",
            )
        parsed[session_id] = _Reflection(
            session_id=session_id,
            focus_quality=focus_quality,
            useful_progress=useful_progress,
            obstacles=tuple(raw_obstacles),
            created_at=created_at,
            updated_at=updated_at,
        )
    return parsed


def _sleep_episodes(
    rows: list[dict[str, Any]],
    *,
    generated_at: datetime,
) -> list[DailyCaptureV4SleepEpisode]:
    episodes: dict[str, DailyCaptureV4SleepEpisode] = {}
    for row in rows:
        row_date = _date(row.get("entry_date"))
        updated_at = _datetime(row.get("updated_at"))
        metadata = row.get("metadata")
        if (
            row_date is None
            or (updated_at is not None and updated_at > generated_at)
            or not isinstance(metadata, dict)
            or metadata.get("capture_version") != "daily-capture-v4"
            or not isinstance(metadata.get("captures"), dict)
        ):
            continue
        morning = metadata["captures"].get("morning")
        result = parse_daily_capture_v4_sleep_episode(
            morning,
            row_date=row_date,
        )
        if not isinstance(result.value, DailyCaptureV4SleepEpisode):
            continue
        episode = result.value
        existing = episodes.get(episode.capture_id)
        if existing is not None and existing != episode:
            raise PersonalPatternsDataError(
                "Personal pattern sleep identity is ambiguous.",
            )
        episodes[episode.capture_id] = episode
    return sorted(
        episodes.values(),
        key=lambda value: (value.woke_at, value.capture_id),
    )


def _observations(
    *,
    sessions: list[_Session],
    reflections: dict[str, _Reflection],
    episodes: list[DailyCaptureV4SleepEpisode],
) -> list[_Observation]:
    result: list[_Observation] = []
    for session in sessions:
        reflection = reflections.get(session.id)
        if reflection is None:
            continue
        eligible_sleep = [
            episode
            for episode in episodes
            if episode.entry_date == session.local_date
            and episode.woke_at <= session.started_at
        ]
        sleep = eligible_sleep[-1] if eligible_sleep else None
        result.append(
            _Observation(
                session=session,
                reflection=reflection,
                sleep=sleep,
            ),
        )
    return result


def _time_comparisons(
    observations: list[_Observation],
) -> list[_Comparison]:
    daytime = [
        value for value in observations if value.session.time_window != "night"
    ]
    comparisons: list[_Comparison] = []
    for key, label in _TIME_WINDOWS:
        preferred = [
            _rated(value)
            for value in daytime
            if value.session.time_window == key
        ]
        other = [
            _rated(value)
            for value in daytime
            if value.session.time_window != key
        ]
        if not preferred or not other:
            continue
        comparisons.append(
            _comparison(
                preferred_key=key,
                preferred_label=label,
                comparison_label="other daytime windows",
                preferred=preferred,
                comparison=other,
            ),
        )
    return comparisons


def _best_comparison(values: list[_Comparison]) -> _Comparison | None:
    if not values:
        return None
    order = {key: index for index, (key, _) in enumerate(_TIME_WINDOWS)}
    return sorted(
        values,
        key=lambda value: (
            -value.useful_delta,
            order[value.preferred_key],
        ),
    )[0]


def _best_planner_comparison(
    values: list[_Comparison],
) -> _Comparison | None:
    if not values:
        return None
    order = {key: index for index, (key, _) in enumerate(_TIME_WINDOWS)}

    def readiness(value: _Comparison) -> tuple[int, int, int]:
        thresholds = (
            value.useful_delta >= 0.5
            and value.focus_delta >= -0.5
            and value.completion_delta >= -0.1
        )
        distinct_days = (
            len(value.preferred_dates) >= 10
            and len(value.comparison_dates) >= 10
        )
        consistent = distinct_days and _same_direction_in_halves(value)
        return int(thresholds), int(thresholds and distinct_days), int(consistent)

    return sorted(
        values,
        key=lambda value: (
            *(-flag for flag in reversed(readiness(value))),
            -value.useful_delta,
            order[value.preferred_key],
        ),
    )[0]


def _has_emerging_comparison(
    observations: list[_Observation],
    *,
    time_comparisons: list[_Comparison],
) -> bool:
    if any(
        value.preferred.count >= 5 and value.comparison.count >= 5
        for value in time_comparisons
    ):
        return True

    by_episode: dict[str, _Observation] = {}
    for observation in observations:
        if observation.sleep is not None:
            by_episode.setdefault(observation.sleep.capture_id, observation)
    sleep_counts: dict[str, int] = defaultdict(int)
    for observation in by_episode.values():
        assert observation.sleep is not None
        sleep_counts[_sleep_bucket(observation.sleep.estimated_sleep_minutes)] += 1
    if any(
        count >= 5 and sum(sleep_counts.values()) - count >= 5
        for count in sleep_counts.values()
    ):
        return True

    length_counts: dict[str, int] = defaultdict(int)
    for observation in observations:
        length_counts[_length_bucket(observation.session.actual_minutes)] += 1
    if any(
        count >= 5 and len(observations) - count >= 5
        for count in length_counts.values()
    ):
        return True

    short_gap_count = sum(
        observation.session.previous_gap_minutes is not None
        and observation.session.previous_gap_minutes < 120
        for observation in observations
    )
    longer_gap_count = sum(
        observation.session.previous_gap_minutes is not None
        and observation.session.previous_gap_minutes >= 120
        for observation in observations
    )
    return short_gap_count >= 5 and longer_gap_count >= 5


def _timing_pattern(
    comparison: _Comparison,
    *,
    maturity: str,
) -> PersonalPattern:
    if (
        comparison.useful_delta >= 0.5
        and comparison.focus_delta >= -0.5
        and comparison.completion_delta >= -0.1
    ):
        summary = (
            f"Sessions starting {comparison.preferred_label} were associated "
            "with higher median useful progress in these ratings."
        )
    else:
        summary = (
            f"Ratings for {comparison.preferred_label} and other daytime "
            "windows were similar or mixed."
        )
    return PersonalPattern(
        kind="focus_timing",
        maturity=maturity,
        title="Focus timing",
        summary=summary,
        evidence=_pattern_evidence(
            comparison,
            extra_details=[
                (
                    f"{len(comparison.preferred_dates)} preferred-window days "
                    f"and {len(comparison.comparison_dates)} comparison days."
                ),
            ],
        ),
    )


def _sleep_pattern(
    observations: list[_Observation],
    *,
    maturity: str,
) -> PersonalPattern | None:
    by_episode: dict[str, list[_Observation]] = defaultdict(list)
    for observation in observations:
        if observation.sleep is not None:
            by_episode[observation.sleep.capture_id].append(observation)
    values_by_bucket: dict[str, list[_RatedValue]] = defaultdict(list)
    details_by_bucket: dict[str, list[DailyCaptureV4SleepEpisode]] = defaultdict(
        list,
    )
    labels = {
        "under_7": "under 7 hours",
        "7_8": "7–8 hours",
        "8_9": "8–9 hours",
        "9_plus": "9 hours or more",
    }
    for episode_id, linked in by_episode.items():
        episode = linked[0].sleep
        assert episode is not None
        bucket = _sleep_bucket(episode.estimated_sleep_minutes)
        values_by_bucket[bucket].append(
            _RatedValue(
                focus_quality=_median(value.focus_quality for value in linked),
                useful_progress=_median(
                    value.useful_progress for value in linked
                ),
                completion=_rate(value.completion for value in linked),
                local_date=episode.entry_date,
            ),
        )
        details_by_bucket[bucket].append(episode)
        assert episode.capture_id == episode_id
    candidates: list[_Comparison] = []
    for key in labels:
        preferred = values_by_bucket[key]
        comparison = [
            item
            for other_key, values in values_by_bucket.items()
            if other_key != key
            for item in values
        ]
        if len(preferred) < 5 or len(comparison) < 5:
            continue
        candidates.append(
            _comparison(
                preferred_key=key,
                preferred_label=labels[key],
                comparison_label="other observed sleep ranges",
                preferred=preferred,
                comparison=comparison,
            ),
        )
    best = _best_generic_comparison(candidates, labels)
    if best is None:
        return None
    if best.useful_delta >= 0.5:
        summary = (
            f"{best.preferred_label} were associated with higher-rated "
            "sessions in this observed sample."
        )
    else:
        summary = (
            "Rated sessions did not show a clear difference between the "
            "observed sleep-duration ranges."
        )
    episodes = details_by_bucket[best.preferred_key]
    target_shortfall = _median(
        max(0, -value.target_deviation_minutes) for value in episodes
    )
    sleep_quality = _median(value.sleep_quality for value in episodes)
    return PersonalPattern(
        kind="sleep",
        maturity=maturity,
        title="Sleep and rated sessions",
        summary=summary,
        evidence=_pattern_evidence(
            best,
            extra_details=[
                (
                    "Each sleep episode counts once, even when several "
                    "sessions followed it."
                ),
                (
                    f"Preferred-range median sleep shortfall was "
                    f"{target_shortfall:.0f} min; median sleep quality was "
                    f"{sleep_quality:.1f}/10."
                ),
            ],
        ),
    )


def _length_or_gap_pattern(
    observations: list[_Observation],
    *,
    maturity: str,
) -> PersonalPattern | None:
    length_labels = {
        "under_25": "under 25 actual minutes",
        "25_49": "25–49 actual minutes",
        "50_89": "50–89 actual minutes",
        "90_plus": "90 actual minutes or more",
    }
    by_length: dict[str, list[_RatedValue]] = defaultdict(list)
    for observation in observations:
        by_length[_length_bucket(observation.session.actual_minutes)].append(
            _rated(observation),
        )
    length_candidates: list[_Comparison] = []
    for key, label in length_labels.items():
        preferred = by_length[key]
        comparison = [
            item
            for other_key, values in by_length.items()
            if other_key != key
            for item in values
        ]
        if len(preferred) >= 5 and len(comparison) >= 5:
            length_candidates.append(
                _comparison(
                    preferred_key=key,
                    preferred_label=label,
                    comparison_label="other actual session lengths",
                    preferred=preferred,
                    comparison=comparison,
                ),
            )
    length = _best_generic_comparison(length_candidates, length_labels)
    if length is not None and abs(length.useful_delta) >= 0.5:
        return PersonalPattern(
            kind="session_length_or_spacing",
            maturity=maturity,
            title="Session length",
            summary=(
                f"{length.preferred_label.capitalize()} were associated "
                "with a different median useful-progress rating."
            ),
            evidence=_pattern_evidence(
                length,
                extra_details=[
                    "Planned and actual duration remain explicit session facts; no new duration is inferred.",
                ],
            ),
        )

    short_gap = [
        _rated(value)
        for value in observations
        if value.session.previous_gap_minutes is not None
        and value.session.previous_gap_minutes < 120
    ]
    longer_gap = [
        _rated(value)
        for value in observations
        if value.session.previous_gap_minutes is not None
        and value.session.previous_gap_minutes >= 120
    ]
    if len(short_gap) < 5 or len(longer_gap) < 5:
        return None
    gap = _comparison(
        preferred_key="under_2h",
        preferred_label="less than two hours after a prior session",
        comparison_label="two hours or more after a prior session",
        preferred=short_gap,
        comparison=longer_gap,
    )
    return PersonalPattern(
        kind="session_length_or_spacing",
        maturity=maturity,
        title="Spacing between Focus sessions",
        summary=(
            "Sessions less than two hours apart had "
            f"{'higher' if gap.useful_delta > 0 else 'lower or similar'} "
            "median useful-progress ratings in this sample."
        ),
        evidence=_pattern_evidence(
            gap,
            extra_details=[
                "The gap is measured from the preceding terminal session.",
            ],
        ),
    )


def _planner_preference(
    *,
    observations: list[_Observation],
    comparison: _Comparison | None,
    stable: bool,
    coverage: float,
    fingerprint: str,
) -> LearnedFocusPlannerPreference:
    rated_dates = sorted({value.local_date for value in observations})
    common = {
        "eligible": False,
        "window": (
            comparison.preferred_key if comparison is not None else None
        ),
        "window_label": (
            comparison.preferred_label if comparison is not None else None
        ),
        "evidence_count": len(observations),
        "evidence_starts_on": rated_dates[0] if rated_dates else None,
        "evidence_ends_on": rated_dates[-1] if rated_dates else None,
        "evidence_fingerprint": fingerprint if rated_dates else None,
    }
    if len(observations) < 3:
        return LearnedFocusPlannerPreference(
            reason="insufficient_ratings",
            **common,
        )
    if not stable:
        return LearnedFocusPlannerPreference(
            reason="baseline_not_stable",
            **common,
        )
    if comparison is None:
        return LearnedFocusPlannerPreference(
            reason="no_daytime_comparison",
            **common,
        )
    if coverage < 0.7:
        return LearnedFocusPlannerPreference(
            reason="coverage_too_low",
            **common,
        )
    if (
        len(comparison.preferred_dates) < 10
        or len(comparison.comparison_dates) < 10
    ):
        return LearnedFocusPlannerPreference(
            reason="insufficient_distinct_days",
            **common,
        )
    if (
        comparison.useful_delta < 0.5
        or comparison.focus_delta < -0.5
        or comparison.completion_delta < -0.1
    ):
        return LearnedFocusPlannerPreference(
            reason="thresholds_not_met",
            **common,
        )
    if not _same_direction_in_halves(comparison):
        return LearnedFocusPlannerPreference(
            reason="inconsistent_halves",
            **common,
        )
    return LearnedFocusPlannerPreference(
        eligible=True,
        reason="eligible",
        window=comparison.preferred_key,
        window_label=comparison.preferred_label,
        evidence_count=len(observations),
        evidence_starts_on=rated_dates[0],
        evidence_ends_on=rated_dates[-1],
        evidence_fingerprint=fingerprint,
    )


def _same_direction_in_halves(comparison: _Comparison) -> bool:
    dates = sorted(comparison.preferred_dates | comparison.comparison_dates)
    if len(dates) < 2:
        return False
    split = len(dates) // 2
    halves = (set(dates[:split]), set(dates[split:]))
    for half in halves:
        preferred = [
            value.useful_progress
            for value in comparison.preferred_values
            if value.local_date in half
        ]
        other = [
            value.useful_progress
            for value in comparison.comparison_values
            if value.local_date in half
        ]
        if not preferred or not other or _median(preferred) <= _median(other):
            return False
    return True


def _correlation_points(
    observations: list[_Observation],
) -> list[PersonalPatternCorrelationPoint]:
    points: list[PersonalPatternCorrelationPoint] = []
    for value in observations[-500:]:
        sleep = value.sleep
        points.append(
            PersonalPatternCorrelationPoint(
                local_date=value.session.local_date,
                local_started_at=value.session.local_started_at,
                focus_quality=value.reflection.focus_quality,
                useful_progress=value.reflection.useful_progress,
                planned_focus_minutes=value.session.planned_minutes,
                actual_focus_minutes=value.session.actual_minutes,
                completed=1 if value.session.status == "completed" else 0,
                sleep_hours=(
                    sleep.estimated_sleep_minutes / 60 if sleep else None
                ),
                sleep_target_deviation_minutes=(
                    sleep.target_deviation_minutes if sleep else None
                ),
                sleep_quality=sleep.sleep_quality if sleep else None,
                morning_energy=(
                    sleep.current_energy
                    if sleep is not None
                    and sleep.captured_at <= value.session.started_at
                    else None
                ),
            ),
        )
    return points


def _obstacle_summary(observations: list[_Observation]) -> str:
    counts: dict[str, int] = defaultdict(int)
    for observation in observations:
        for obstacle in observation.reflection.obstacles:
            counts[obstacle] += 1
    if not counts:
        return (
            "No controlled obstacles were reported in the rated Focus "
            "sessions."
        )
    ordered = sorted(counts.items(), key=lambda value: (-value[1], value[0]))
    labels = [
        f"{key.replace('_', ' ')} ({count})"
        for key, count in ordered[:3]
    ]
    return "Reported obstacles are descriptive only: " + ", ".join(labels) + "."


def _comparison(
    *,
    preferred_key: str,
    preferred_label: str,
    comparison_label: str,
    preferred: list[_RatedValue],
    comparison: list[_RatedValue],
) -> _Comparison:
    return _Comparison(
        preferred_key=preferred_key,
        preferred_label=preferred_label,
        comparison_label=comparison_label,
        preferred=_metrics(preferred),
        comparison=_metrics(comparison),
        preferred_dates=frozenset(value.local_date for value in preferred),
        comparison_dates=frozenset(value.local_date for value in comparison),
        preferred_values=tuple(preferred),
        comparison_values=tuple(comparison),
    )


def _best_generic_comparison(
    values: list[_Comparison],
    labels: dict[str, str],
) -> _Comparison | None:
    if not values:
        return None
    order = {key: index for index, key in enumerate(labels)}
    return sorted(
        values,
        key=lambda value: (-value.useful_delta, order[value.preferred_key]),
    )[0]


def _pattern_evidence(
    comparison: _Comparison,
    *,
    extra_details: list[str],
) -> PersonalPatternEvidence:
    return PersonalPatternEvidence(
        preferred_group=comparison.preferred_label,
        comparison_group=comparison.comparison_label,
        preferred_count=comparison.preferred.count,
        comparison_count=comparison.comparison.count,
        useful_progress_median_delta=round(comparison.useful_delta, 3),
        focus_quality_median_delta=round(comparison.focus_delta, 3),
        completion_rate_delta=round(comparison.completion_delta, 4),
        details=[
            (
                f"Median useful progress "
                f"{comparison.preferred.median_useful_progress:.1f} vs "
                f"{comparison.comparison.median_useful_progress:.1f}."
            ),
            (
                f"Median Focus quality "
                f"{comparison.preferred.median_focus_quality:.1f} vs "
                f"{comparison.comparison.median_focus_quality:.1f}."
            ),
            (
                f"Completion rate "
                f"{comparison.preferred.completion_rate:.0%} vs "
                f"{comparison.comparison.completion_rate:.0%}."
            ),
            *extra_details,
        ][:6],
    )


def _metrics(values: list[_RatedValue]) -> _Metrics:
    return _Metrics(
        count=len(values),
        median_focus_quality=_median(value.focus_quality for value in values),
        median_useful_progress=_median(
            value.useful_progress for value in values
        ),
        completion_rate=_rate(value.completion for value in values),
    )


def _rated(value: _Observation) -> _RatedValue:
    return _RatedValue(
        focus_quality=value.focus_quality,
        useful_progress=value.useful_progress,
        completion=value.completion,
        local_date=value.local_date,
    )


def _summary(
    *,
    status: str,
    rated_count: int,
    patterns: list[PersonalPattern],
) -> str:
    if rated_count < 3:
        remaining = 3 - rated_count
        return (
            f"Rate {remaining} more finished Focus "
            f"{'session' if remaining == 1 else 'sessions'} to show basic "
            "personal evidence."
        )
    if status == "stable":
        return (
            f"A stable baseline now covers {rated_count} rated sessions. "
            + (
                patterns[0].summary
                if patterns
                else "No comparison currently meets the pattern display rules."
            )
        )
    if status == "emerging":
        return (
            f"Early patterns are visible across {rated_count} rated sessions; "
            "they remain observational."
        )
    return (
        f"Basic medians are available from {rated_count} rated sessions. "
        "Keep reflecting to compare groups reliably."
    )


def _evidence_fingerprint(
    *,
    timezone: str,
    window: PersonalPatternsWindow,
    sessions: list[_Session],
    reflections: dict[str, _Reflection],
    episodes: list[DailyCaptureV4SleepEpisode],
) -> str:
    payload = {
        "contract_version": PERSONAL_PATTERNS_CONTRACT_VERSION,
        "timezone": timezone,
        "local_starts_on": window.local_starts_on.isoformat(),
        "local_ends_on": window.local_ends_on.isoformat(),
        "sessions": [
            {
                "id": value.id,
                "status": value.status,
                "started_at": value.started_at.isoformat(),
                "ended_at": value.ended_at.isoformat(),
                "planned_minutes": value.planned_minutes,
                "actual_minutes": value.actual_minutes,
            }
            for value in sessions
        ],
        "reflections": [
            {
                "session_id": value.session_id,
                "focus_quality": value.focus_quality,
                "useful_progress": value.useful_progress,
                "obstacles": list(value.obstacles),
                "updated_at": value.updated_at.isoformat(),
            }
            for value in sorted(
                reflections.values(),
                key=lambda item: item.session_id,
            )
        ],
        "sleep_episodes": [
            {
                "capture_id": value.capture_id,
                "woke_at": value.woke_at.isoformat(),
                "estimated_sleep_minutes": value.estimated_sleep_minutes,
                "sleep_target_minutes": value.sleep_target_minutes,
                "sleep_quality": value.sleep_quality,
                "current_energy": value.current_energy,
                "captured_at": value.captured_at.isoformat(),
            }
            for value in episodes
        ],
    }
    canonical = json.dumps(
        payload,
        ensure_ascii=True,
        separators=(",", ":"),
        sort_keys=True,
    ).encode("utf-8")
    return hashlib.sha256(canonical).hexdigest()


def _zone(value: str) -> ZoneInfo:
    if value in {"localtime", "posixrules"} or value.startswith(
        ("posix/", "right/"),
    ):
        raise PersonalPatternsDataError("Profile timezone is invalid.")
    try:
        zone = ZoneInfo(value)
    except (ValueError, ZoneInfoNotFoundError) as exc:
        raise PersonalPatternsDataError("Profile timezone is invalid.") from exc
    if zone.key != value:
        raise PersonalPatternsDataError("Profile timezone is invalid.")
    return zone


def _time_window(hour: int) -> str:
    if 5 <= hour < 9:
        return "05-09"
    if 9 <= hour < 13:
        return "09-13"
    if 13 <= hour < 18:
        return "13-18"
    if 18 <= hour < 23:
        return "18-23"
    return "night"


def _sleep_bucket(minutes: int) -> str:
    if minutes < 7 * 60:
        return "under_7"
    if minutes < 8 * 60:
        return "7_8"
    if minutes < 9 * 60:
        return "8_9"
    return "9_plus"


def _length_bucket(minutes: int) -> str:
    if minutes < 25:
        return "under_25"
    if minutes < 50:
        return "25_49"
    if minutes < 90:
        return "50_89"
    return "90_plus"


def _median(values: Iterable[float | int]) -> float:
    items = list(values)
    if not items:
        raise PersonalPatternsDataError("Pattern comparison group is empty.")
    return float(median(items))


def _rate(values: Iterable[float]) -> float:
    items = list(values)
    if not items:
        raise PersonalPatternsDataError("Pattern comparison group is empty.")
    return sum(items) / len(items)


def _text(value: object, *, maximum: int) -> str | None:
    if not isinstance(value, str):
        return None
    clean = value.strip()
    return clean if clean and len(clean) <= maximum else None


def _integer(
    value: object,
    *,
    minimum: int,
    maximum: int,
) -> int | None:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        return None
    numeric = float(value)
    if not numeric.is_integer():
        return None
    integer = int(numeric)
    return integer if minimum <= integer <= maximum else None


def _datetime(value: object) -> datetime | None:
    if isinstance(value, datetime):
        parsed = value
    elif isinstance(value, str):
        try:
            parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
        except ValueError:
            return None
    else:
        return None
    if parsed.utcoffset() is None:
        return None
    return parsed.astimezone(UTC)


def _date(value: object) -> date | None:
    if isinstance(value, date) and not isinstance(value, datetime):
        return value
    if not isinstance(value, str):
        return None
    try:
        parsed = date.fromisoformat(value)
    except ValueError:
        return None
    return parsed if parsed.isoformat() == value else None
