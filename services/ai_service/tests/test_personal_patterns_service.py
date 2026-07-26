import asyncio
import logging
from datetime import UTC, date, datetime, time, timedelta
from zoneinfo import ZoneInfo

import pytest

from app.models.learning import LearningPreferencesState
from app.services.personal_patterns_service import PersonalPatternsService


NOW = datetime(2026, 7, 26, 12, tzinfo=UTC)


class Learning:
    def __init__(self, *, enabled: bool = True) -> None:
        self.enabled = enabled
        self.calls: list[str] = []

    async def get_preferences(self, *, user_id: str) -> LearningPreferencesState:
        self.calls.append(user_id)
        return LearningPreferencesState(
            contract_version="learning-preferences-v1",
            revision=1,
            focus_reflection_prompt_enabled=True,
            personal_pattern_analysis_enabled=self.enabled,
            learned_focus_planning_enabled=False,
            updated_at=NOW,
        )


class Repository:
    def __init__(
        self,
        *,
        timezone: str = "Europe/Berlin",
        sessions: list[dict] | None = None,
        reflections: list[dict] | None = None,
        daily_logs: list[dict] | None = None,
    ) -> None:
        self.timezone = timezone
        self.sessions = sessions or []
        self.reflections = reflections or []
        self.daily_logs = daily_logs or []
        self.calls: list[tuple] = []

    async def get_profile_timezone(self, *, user_id: str) -> str:
        self.calls.append(("timezone", user_id))
        return self.timezone

    async def load_evidence(self, **kwargs):
        self.calls.append(("evidence", kwargs))
        return self.sessions, self.reflections, self.daily_logs


class EvidenceFailureRepository(Repository):
    async def load_evidence(self, **kwargs):
        self.calls.append(("evidence", kwargs))
        raise RuntimeError("raw provider detail must not be logged")


def _service(
    repository: Repository,
    *,
    enabled: bool = True,
    now: datetime = NOW,
) -> tuple[PersonalPatternsService, Learning]:
    learning = Learning(enabled=enabled)
    return (
        PersonalPatternsService(
            learning=learning,
            repository=repository,
            now=lambda: now,
        ),
        learning,
    )


def _focus(
    *,
    index: int,
    local_day: date,
    hour: int,
    timezone: str = "Europe/Berlin",
    status: str = "completed",
    progress: int | None = 4,
    quality: int = 4,
    actual_minutes: int = 45,
) -> tuple[dict, dict | None]:
    zone = ZoneInfo(timezone)
    started = datetime.combine(local_day, time(hour, 0), tzinfo=zone)
    ended = started + timedelta(minutes=actual_minutes)
    session_id = f"focus-{index:03d}"
    session = {
        "id": session_id,
        "status": status,
        "started_at": started.astimezone(UTC).isoformat(),
        "ended_at": ended.astimezone(UTC).isoformat(),
        "planned_minutes": 45,
        "actual_minutes": actual_minutes,
    }
    if progress is None:
        return session, None
    reflection = {
        "focus_session_id": session_id,
        "contract_version": "focus-reflection-v1",
        "focus_quality": quality,
        "useful_progress": progress,
        "obstacles": [] if progress >= 3 else ["tired"],
        "created_at": (ended + timedelta(minutes=1)).astimezone(UTC).isoformat(),
        "updated_at": (ended + timedelta(minutes=1)).astimezone(UTC).isoformat(),
    }
    return session, reflection


def _rows(
    specifications: list[tuple[date, int, int, int]],
    *,
    timezone: str = "Europe/Berlin",
) -> tuple[list[dict], list[dict]]:
    sessions: list[dict] = []
    reflections: list[dict] = []
    for index, (local_day, hour, progress, quality) in enumerate(specifications):
        session, reflection = _focus(
            index=index,
            local_day=local_day,
            hour=hour,
            timezone=timezone,
            progress=progress,
            quality=quality,
        )
        sessions.append(session)
        assert reflection is not None
        reflections.append(reflection)
    return sessions, reflections


def _sleep_row(
    local_day: date,
    *,
    minutes: int,
    timezone: str = "Europe/Berlin",
) -> dict:
    zone = ZoneInfo(timezone)
    woke = datetime.combine(local_day, time(7), tzinfo=zone)
    started = woke - timedelta(minutes=minutes)
    capture_id = f"morning-{local_day.isoformat()}"
    return {
        "id": f"log-{local_day.isoformat()}",
        "entry_date": local_day.isoformat(),
        "metadata": {
            "capture_version": "daily-capture-v4",
            "captures": {
                "morning": {
                    "branch_version": "daily-capture-v4",
                    "capture_kind": "morning",
                    "entry_date": local_day.isoformat(),
                    "capture_id": capture_id,
                    "captured_at": woke.astimezone(UTC).isoformat(),
                    "estimated_sleep_started_at": (
                        started.astimezone(UTC).isoformat()
                    ),
                    "woke_at": woke.astimezone(UTC).isoformat(),
                    "estimated_sleep_minutes": minutes,
                    "sleep_target_minutes": 480,
                    "source_evening_capture_id": None,
                    "sleep_hours": minutes / 60,
                    "sleep_quality": 7,
                    "current_energy": 6,
                    "day_shape": "normal",
                },
            },
        },
    }


def test_disabled_stops_before_behavioral_evidence_read(caplog) -> None:
    repository = Repository()
    service, learning = _service(repository, enabled=False)

    with caplog.at_level(logging.INFO):
        result = asyncio.run(service.get_patterns(user_id="owner"))

    assert result.status == "disabled"
    assert result.evidence_fingerprint is None
    assert result.sample.rated_sessions == 0
    assert learning.calls == ["owner"]
    assert repository.calls == [("timezone", "owner")]
    assert "contract_version=personal-patterns-v1 status=disabled" in caplog.text
    assert "terminal_sessions=0 rated_sessions=0" in caplog.text


def test_failure_log_contains_only_bounded_stage_and_counts(caplog) -> None:
    service, _ = _service(EvidenceFailureRepository())

    with caplog.at_level(logging.WARNING), pytest.raises(
        RuntimeError,
        match="raw provider detail",
    ):
        asyncio.run(service.get_patterns(user_id="owner"))

    assert "error_stage=evidence_read" in caplog.text
    assert "contract_version=personal-patterns-v1 status=error" in caplog.text
    assert "raw provider detail" not in caplog.text


def test_collecting_exposes_baseline_only_after_three_ratings() -> None:
    start = date(2026, 7, 20)
    sessions, reflections = _rows(
        [
            (start, 9, 4, 4),
            (start + timedelta(days=1), 14, 3, 3),
            (start + timedelta(days=2), 9, 5, 4),
        ],
    )
    repository = Repository(sessions=sessions, reflections=reflections)
    service, _ = _service(repository)

    result = asyncio.run(service.get_patterns(user_id="owner"))

    assert result.status == "collecting"
    assert result.sample.rated_sessions == 3
    assert result.baseline is not None
    assert result.baseline.median_useful_progress == 4
    assert result.patterns == []
    assert result.planner_preference.reason == "baseline_not_stable"
    evidence_call = next(
        call for call in repository.calls if call[0] == "evidence"
    )
    assert evidence_call[1]["ends_at"] == NOW


def test_emerging_and_stable_maturity_boundaries_are_exact() -> None:
    start = date(2026, 6, 15)
    emerging_spec = [
        (start + timedelta(days=index), 9 if index % 2 == 0 else 14, 5, 4)
        if index % 2 == 0
        else (start + timedelta(days=index), 14, 3, 4)
        for index in range(14)
    ]
    emerging_sessions, emerging_reflections = _rows(emerging_spec)
    emerging, _ = _service(
        Repository(
            sessions=emerging_sessions,
            reflections=emerging_reflections,
        ),
    )

    emerging_result = asyncio.run(emerging.get_patterns(user_id="owner"))

    assert emerging_result.status == "emerging"
    assert emerging_result.patterns[0].kind == "focus_timing"
    assert emerging_result.patterns[0].maturity == "emerging"

    stable_spec = [
        (
            start + timedelta(days=index * 2),
            9 if index % 2 == 0 else 14,
            5 if index % 2 == 0 else 3,
            4,
        )
        for index in range(20)
    ]
    stable_sessions, stable_reflections = _rows(stable_spec)
    stable, _ = _service(
        Repository(
            sessions=stable_sessions,
            reflections=stable_reflections,
        ),
    )

    stable_result = asyncio.run(stable.get_patterns(user_id="owner"))

    assert stable_result.status == "stable"
    assert stable_result.planner_preference.eligible is True
    assert stable_result.planner_preference.window == "09-13"
    assert stable_result.planner_preference.evidence_count == 20


def test_sleep_groups_can_reach_emerging_without_a_time_window_comparison() -> None:
    start = date(2026, 6, 20)
    sessions: list[dict] = []
    reflections: list[dict] = []
    daily_logs: list[dict] = []
    for index in range(14):
        local_day = start + timedelta(days=index * 2)
        longer_sleep = index < 7
        daily_logs.append(
            _sleep_row(local_day, minutes=450 if longer_sleep else 360),
        )
        session, reflection = _focus(
            index=index,
            local_day=local_day,
            hour=9,
            progress=5 if longer_sleep else 3,
            quality=4,
        )
        sessions.append(session)
        assert reflection is not None
        reflections.append(reflection)
    service, _ = _service(
        Repository(
            sessions=sessions,
            reflections=reflections,
            daily_logs=daily_logs,
        ),
    )

    result = asyncio.run(service.get_patterns(user_id="owner"))

    assert result.status == "emerging"
    assert [pattern.kind for pattern in result.patterns] == ["sleep"]


def test_planner_selects_a_threshold_safe_window_not_the_mixed_top_delta() -> None:
    start = date(2026, 6, 1)
    specifications = []
    for index in range(30):
        group = index % 3
        specifications.append(
            (
                start + timedelta(days=index),
                (9, 14, 19)[group],
                (5, 5, 2)[group],
                (1, 4, 4)[group],
            ),
        )
    sessions, reflections = _rows(specifications)
    service, _ = _service(
        Repository(sessions=sessions, reflections=reflections),
    )

    result = asyncio.run(service.get_patterns(user_id="owner"))

    assert result.status == "stable"
    assert result.planner_preference.eligible is True
    assert result.planner_preference.window == "13-18"
    assert result.patterns[0].evidence.preferred_group == "13:00–18:00"


def test_planner_preference_requires_coverage_and_consistent_halves() -> None:
    start = date(2026, 6, 1)
    specifications = []
    for index in range(20):
        first_half = index < 10
        preferred = index % 2 == 0
        progress = (
            5
            if preferred and first_half
            else 2
            if not preferred and first_half
            else 4
            if preferred
            else 5
        )
        specifications.append(
            (
                start + timedelta(days=index * 2),
                9 if preferred else 14,
                progress,
                4,
            ),
        )
    sessions, reflections = _rows(specifications)
    service, _ = _service(
        Repository(sessions=sessions, reflections=reflections),
    )

    inconsistent = asyncio.run(service.get_patterns(user_id="owner"))

    assert inconsistent.status == "stable"
    assert inconsistent.planner_preference.reason == "inconsistent_halves"

    unrated = [
        _focus(
            index=100 + index,
            local_day=start + timedelta(days=index * 2 + 1),
            hour=17,
            progress=None,
        )[0]
        for index in range(10)
    ]
    low_coverage, _ = _service(
        Repository(
            sessions=[*sessions, *unrated],
            reflections=reflections,
        ),
    )

    coverage_result = asyncio.run(
        low_coverage.get_patterns(user_id="owner"),
    )

    assert coverage_result.sample.rating_coverage == 20 / 30
    assert coverage_result.planner_preference.reason == "coverage_too_low"


def test_night_sessions_are_evidence_but_never_a_planner_window() -> None:
    start = date(2026, 6, 1)
    specifications = [
        (
            start + timedelta(days=index),
            1 if index < 20 else 9 if index % 2 == 0 else 14,
            5 if index < 20 else 3,
            5,
        )
        for index in range(40)
    ]
    sessions, reflections = _rows(specifications)
    service, _ = _service(
        Repository(sessions=sessions, reflections=reflections),
    )

    result = asyncio.run(service.get_patterns(user_id="owner"))

    assert result.sample.rated_sessions == 40
    assert result.planner_preference.window in {"09-13", "13-18"}
    assert result.planner_preference.eligible is False
    assert all(
        pattern.evidence.preferred_group != "night"
        for pattern in result.patterns
    )


def test_sleep_comparison_counts_each_episode_once() -> None:
    start = date(2026, 6, 18)
    sessions: list[dict] = []
    reflections: list[dict] = []
    daily_logs: list[dict] = []
    for day_index in range(10):
        local_day = start + timedelta(days=day_index * 4)
        high_sleep = day_index < 5
        daily_logs.append(
            _sleep_row(local_day, minutes=450 if high_sleep else 360),
        )
        for offset, hour in enumerate((9, 14)):
            session, reflection = _focus(
                index=day_index * 2 + offset,
                local_day=local_day,
                hour=hour,
                progress=5 if high_sleep else 3,
                quality=4,
            )
            sessions.append(session)
            assert reflection is not None
            reflections.append(reflection)
    service, _ = _service(
        Repository(
            sessions=sessions,
            reflections=reflections,
            daily_logs=daily_logs,
        ),
    )

    result = asyncio.run(service.get_patterns(user_id="owner"))

    sleep_pattern = next(
        pattern for pattern in result.patterns if pattern.kind == "sleep"
    )
    assert sleep_pattern.evidence.preferred_count == 5
    assert sleep_pattern.evidence.comparison_count == 5
    assert "associated" in sleep_pattern.summary


def test_profile_timezone_handles_dst_and_energy_is_not_backfilled() -> None:
    now = datetime(2026, 4, 5, 12, tzinfo=UTC)
    specifications = [
        (date(2026, 3, 28), 9, 4, 4),
        (date(2026, 3, 30), 9, 4, 4),
        (date(2026, 4, 1), 14, 3, 3),
    ]
    sessions, reflections = _rows(specifications)
    daily_log = _sleep_row(date(2026, 4, 1), minutes=450)
    daily_log["metadata"]["captures"]["morning"]["captured_at"] = (
        datetime(2026, 4, 1, 15, tzinfo=UTC).isoformat()
    )
    service, _ = _service(
        Repository(
            sessions=sessions,
            reflections=reflections,
            daily_logs=[daily_log],
        ),
        now=now,
    )

    result = asyncio.run(service.get_patterns(user_id="owner"))

    starts = result.correlation_points
    assert starts[0].local_started_at.hour == 9
    assert starts[1].local_started_at.hour == 9
    assert starts[0].local_started_at.utcoffset() == timedelta(hours=1)
    assert starts[1].local_started_at.utcoffset() == timedelta(hours=2)
    assert starts[-1].morning_energy is None


def test_fingerprint_is_deterministic_and_ignores_out_of_window_reflections() -> None:
    start = date(2026, 7, 20)
    sessions, reflections = _rows(
        [
            (start, 9, 5, 4),
            (start + timedelta(days=1), 14, 3, 4),
            (start + timedelta(days=2), 9, 5, 4),
        ],
    )
    unrelated = dict(reflections[0])
    unrelated["focus_session_id"] = "outside-window"
    first, _ = _service(
        Repository(
            sessions=sessions,
            reflections=[*reflections, unrelated],
        ),
    )
    second, _ = _service(
        Repository(
            sessions=list(reversed(sessions)),
            reflections=list(reversed(reflections)),
        ),
    )

    first_result = asyncio.run(first.get_patterns(user_id="owner"))
    second_result = asyncio.run(second.get_patterns(user_id="owner"))

    assert first_result.evidence_fingerprint == second_result.evidence_fingerprint
    assert len(first_result.evidence_fingerprint or "") == 64


def test_fingerprint_ignores_sleep_episodes_not_linked_to_a_rated_session() -> None:
    start = date(2026, 7, 20)
    sessions, reflections = _rows(
        [
            (start, 9, 5, 4),
            (start + timedelta(days=1), 14, 3, 4),
            (start + timedelta(days=2), 9, 5, 4),
        ],
    )
    without_sleep, _ = _service(
        Repository(sessions=sessions, reflections=reflections),
    )
    with_unlinked_sleep, _ = _service(
        Repository(
            sessions=sessions,
            reflections=reflections,
            daily_logs=[_sleep_row(date(2026, 7, 10), minutes=450)],
        ),
    )

    first = asyncio.run(without_sleep.get_patterns(user_id="owner"))
    second = asyncio.run(with_unlinked_sleep.get_patterns(user_id="owner"))

    assert first.evidence_fingerprint == second.evidence_fingerprint
    assert second.correlation_points[0].planned_focus_minutes == 45
