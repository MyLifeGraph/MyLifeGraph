import asyncio
from datetime import UTC, date, datetime, time, timedelta
from zoneinfo import ZoneInfo

import pytest

from app.models.learning import LearningPreferencesState
from app.models.sleep_recommendation import SleepRecommendationWindow
from app.services.sleep_recommendation_service import (
    SleepRecommendationDataError,
    SleepRecommendationService,
    _duration_window,
    _episodes,
)


NOW = datetime(2026, 7, 30, 12, tzinfo=UTC)
ZONE = ZoneInfo("Europe/Berlin")


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
        evidence: tuple[list[dict], list[dict], list[dict]],
        *,
        timezone: str = "Europe/Berlin",
    ) -> None:
        self.evidence = evidence
        self.timezone = timezone
        self.calls: list[str] = []

    async def get_profile_timezone(self, *, user_id: str) -> str:
        self.calls.append("timezone")
        return self.timezone

    async def load_evidence(self, **kwargs):
        self.calls.append("evidence")
        return self.evidence


def _evidence(
    count: int,
    *,
    start: date = date(2026, 6, 1),
    candidate_outcomes: tuple[int, int, int, int] = (8, 8, 5, 4),
    comparison_outcomes: tuple[int, int, int, int] = (6, 6, 3, 4),
    alternate: bool = True,
) -> tuple[list[dict], list[dict], list[dict]]:
    sessions: list[dict] = []
    reflections: list[dict] = []
    logs: list[dict] = []
    for index in range(count):
        local_day = start + timedelta(days=index)
        candidate = index % 2 == 0 if alternate else index < count // 2
        quality, energy, progress, focus_quality = (
            candidate_outcomes if candidate else comparison_outcomes
        )
        wake_clock = time(7, index % 3 * 5) if candidate else time(8, 30)
        duration = 480 + index % 3 * 5 if candidate else 420
        woke = datetime.combine(local_day, wake_clock, tzinfo=ZONE)
        started_sleep = woke - timedelta(minutes=duration)
        captured = woke + timedelta(minutes=10)
        session_start = datetime.combine(local_day, time(10), tzinfo=ZONE)
        session_end = session_start + timedelta(minutes=45)
        capture_id = f"morning-{index:03d}"
        session_id = f"focus-{index:03d}"
        logs.append(
            {
                "id": f"log-{index:03d}",
                "entry_date": local_day.isoformat(),
                "updated_at": captured.astimezone(UTC).isoformat(),
                "metadata": {
                    "capture_version": "daily-capture-v5",
                    "captures": {
                        "morning": {
                            "branch_version": "daily-capture-v5",
                            "capture_kind": "morning",
                            "entry_date": local_day.isoformat(),
                            "capture_id": capture_id,
                            "captured_at": captured.astimezone(UTC).isoformat(),
                            "sleep_hours": duration / 60,
                            "sleep_quality": quality,
                            "current_energy": energy,
                            "estimated_sleep_started_at": (
                                started_sleep.astimezone(UTC).isoformat()
                            ),
                            "woke_at": woke.astimezone(UTC).isoformat(),
                            "estimated_sleep_minutes": duration,
                            "sleep_target_minutes": 510,
                            "source_evening_capture_id": None,
                        },
                    },
                },
            },
        )
        sessions.append(
            {
                "id": session_id,
                "status": "completed",
                "started_at": session_start.astimezone(UTC).isoformat(),
                "ended_at": session_end.astimezone(UTC).isoformat(),
                "planned_minutes": 45,
                "actual_minutes": 45,
            },
        )
        reflections.append(
            {
                "focus_session_id": session_id,
                "contract_version": "focus-reflection-v1",
                "focus_quality": focus_quality,
                "useful_progress": progress,
                "obstacles": [],
                "created_at": (session_end + timedelta(minutes=1))
                .astimezone(UTC)
                .isoformat(),
                "updated_at": (session_end + timedelta(minutes=1))
                .astimezone(UTC)
                .isoformat(),
            },
        )
    return sessions, reflections, logs


def _get(
    evidence: tuple[list[dict], list[dict], list[dict]],
    *,
    enabled: bool = True,
    now: datetime = NOW,
    timezone: str = "Europe/Berlin",
):
    learning = Learning(enabled=enabled)
    repository = Repository(evidence, timezone=timezone)
    service = SleepRecommendationService(
        learning=learning,
        repository=repository,
        now=lambda: now,
    )
    result = asyncio.run(service.get_recommendation(user_id="owner"))
    return result, learning, repository


def test_disabled_short_circuits_before_sleep_or_focus_history() -> None:
    result, learning, repository = _get(_evidence(30), enabled=False)

    assert result.status == "disabled"
    assert result.reason == "analysis_disabled"
    assert result.sample.progress == "0/30"
    assert learning.calls == ["owner"]
    assert repository.calls == ["timezone"]
    assert result.limitations == ["No sleep or Focus history was read."]


@pytest.mark.parametrize(("count", "progress"), [(29, "29/30"), (30, "30/30")])
def test_exact_29_and_30_day_maturity_boundary(count: int, progress: str) -> None:
    result, _, _ = _get(_evidence(count))

    assert result.sample.progress == progress
    assert result.status == ("collecting" if count == 29 else "ready")


def test_ready_aggregates_sessions_by_day_and_warns_below_confirmed_target() -> None:
    sessions, reflections, logs = _evidence(30)
    duplicate = dict(sessions[0])
    duplicate["id"] = "focus-extra"
    duplicate["started_at"] = (
        datetime.fromisoformat(sessions[0]["started_at"]) + timedelta(hours=2)
    ).isoformat()
    duplicate["ended_at"] = (
        datetime.fromisoformat(duplicate["started_at"]) + timedelta(minutes=45)
    ).isoformat()
    sessions.append(duplicate)
    reflection = dict(reflections[0])
    reflection["focus_session_id"] = "focus-extra"
    reflection["created_at"] = (
        datetime.fromisoformat(duplicate["ended_at"]) + timedelta(minutes=1)
    ).isoformat()
    reflection["updated_at"] = reflection["created_at"]
    reflections.append(reflection)

    result, _, _ = _get((sessions, reflections, logs))

    assert result.status == "ready"
    assert result.sample.eligible_focus_days == 30
    assert result.sample.rated_sessions == 31
    assert result.recommendation is not None
    assert result.recommendation.evidence.candidate_days == 15
    assert result.recommendation.warning == "below_confirmed_sleep_target"
    assert result.recommendation.bedtime.width_minutes <= 60
    assert result.recommendation.wake_day_offset == 1
    assert "associated with" in result.summary


@pytest.mark.parametrize(
    ("minutes", "expected_minimum", "expected_maximum"),
    (
        (1, 0, 15),
        (14, 0, 15),
        (15, 15, 15),
    ),
)
def test_duration_window_preserves_outward_rounding_at_lower_boundary(
    minutes: int,
    expected_minimum: int,
    expected_maximum: int,
) -> None:
    result = _duration_window([minutes] * 10)

    assert result.minimum_minutes == expected_minimum
    assert result.maximum_minutes == expected_maximum


def test_mixed_same_and_next_day_windows_do_not_pool() -> None:
    sessions, reflections, logs = _evidence(30)
    for index, row in enumerate(logs):
        local_day = date.fromisoformat(row["entry_date"])
        if index % 2 == 0:
            started = datetime.combine(local_day, time(0, 10), tzinfo=ZONE)
            woke = datetime.combine(local_day, time(5, 10), tzinfo=ZONE)
        else:
            started = datetime.combine(
                local_day - timedelta(days=1),
                time(23, 50),
                tzinfo=ZONE,
            )
            woke = datetime.combine(local_day, time(4, 50), tzinfo=ZONE)
        morning = row["metadata"]["captures"]["morning"]
        captured = woke + timedelta(minutes=10)
        morning["captured_at"] = captured.astimezone(UTC).isoformat()
        morning["estimated_sleep_started_at"] = started.astimezone(UTC).isoformat()
        morning["woke_at"] = woke.astimezone(UTC).isoformat()
        morning["estimated_sleep_minutes"] = 300
        morning["sleep_hours"] = 5
        row["updated_at"] = captured.astimezone(UTC).isoformat()

    result, _, _ = _get((sessions, reflections, logs))

    assert result.status == "ready"
    assert result.recommendation is not None
    assert result.recommendation.evidence.candidate_days == 15
    assert result.recommendation.evidence.comparison_days == 15
    assert result.recommendation.wake_day_offset == 0


def test_v5_container_reads_untouched_v4_compatibility_morning() -> None:
    sessions, reflections, logs = _evidence(30)
    morning = logs[0]["metadata"]["captures"]["morning"]
    morning["branch_version"] = "daily-capture-v4"
    morning["compatibility"] = True
    morning["day_shape"] = "constrained"

    result, _, _ = _get((sessions, reflections, logs))

    assert result.status == "ready"
    assert result.sample.eligible_focus_days == 30


@pytest.mark.parametrize(
    ("container_version", "branch_version"),
    (
        ("daily-capture-v4", "daily-capture-v5"),
        ("daily-capture-v5", "daily-capture-v4"),
    ),
)
def test_mismatched_container_branch_identity_is_not_sleep_evidence(
    container_version: str,
    branch_version: str,
) -> None:
    sessions, reflections, logs = _evidence(30)
    metadata = logs[0]["metadata"]
    metadata["capture_version"] = container_version
    morning = metadata["captures"]["morning"]
    morning["branch_version"] = branch_version
    if branch_version == "daily-capture-v4":
        morning["day_shape"] = "normal"

    result, _, _ = _get((sessions, reflections, logs))

    assert result.status == "collecting"
    assert result.sample.valid_nights == 29
    assert result.sample.eligible_focus_days == 29


def test_sleep_episode_window_is_closed_open_on_morning_capture() -> None:
    starts_at = NOW - timedelta(days=90)
    window = SleepRecommendationWindow(
        rolling_days=90,
        starts_at=starts_at,
        ends_at=NOW,
        local_starts_on=starts_at.astimezone(ZONE).date(),
        local_ends_on=NOW.astimezone(ZONE).date(),
    )
    lower = _episode_row(
        captured_at=starts_at,
        woke_at=starts_at - timedelta(minutes=10),
        started_at=starts_at - timedelta(hours=8, minutes=10),
        updated_at=starts_at,
    )
    before_lower = _episode_row(
        captured_at=starts_at - timedelta(microseconds=1),
        woke_at=starts_at - timedelta(minutes=10),
        started_at=starts_at - timedelta(hours=8, minutes=10),
        updated_at=starts_at,
    )
    at_upper_capture = _episode_row(
        captured_at=NOW,
        woke_at=NOW - timedelta(minutes=10),
        started_at=NOW - timedelta(hours=8, minutes=10),
        updated_at=NOW,
    )
    at_upper_wake = _episode_row(
        captured_at=NOW - timedelta(minutes=1),
        woke_at=NOW,
        started_at=NOW - timedelta(hours=8),
        updated_at=NOW,
    )

    episodes = _episodes([lower], generated_at=NOW, window=window)

    assert len(episodes) == 1
    assert next(iter(episodes.values())).estimated_sleep_started_at < starts_at
    assert _episodes([before_lower], generated_at=NOW, window=window) == {}
    assert _episodes([at_upper_capture], generated_at=NOW, window=window) == {}
    assert _episodes([at_upper_wake], generated_at=NOW, window=window) == {}


@pytest.mark.parametrize("updated_at", (None, "not-a-timestamp"))
def test_sleep_episode_requires_valid_updated_at(updated_at: object) -> None:
    starts_at = NOW - timedelta(days=90)
    window = SleepRecommendationWindow(
        rolling_days=90,
        starts_at=starts_at,
        ends_at=NOW,
        local_starts_on=starts_at.astimezone(ZONE).date(),
        local_ends_on=NOW.astimezone(ZONE).date(),
    )
    row = _episode_row(
        captured_at=starts_at + timedelta(days=1),
        woke_at=starts_at + timedelta(days=1, minutes=-10),
        started_at=starts_at + timedelta(hours=16, minutes=-10),
        updated_at=updated_at,
    )

    assert _episodes([row], generated_at=NOW, window=window) == {}


def test_invalid_profile_timezone_becomes_typed_data_error() -> None:
    with pytest.raises(
        SleepRecommendationDataError,
        match="profile timezone is invalid",
    ):
        _get(_evidence(30), timezone="Invalid/Timezone")


def test_session_must_follow_wake_capture_and_have_post_session_reflection() -> None:
    sessions, reflections, logs = _evidence(30)
    sessions[0]["started_at"] = logs[0]["metadata"]["captures"]["morning"]["woke_at"]
    sessions[0]["ended_at"] = (
        datetime.fromisoformat(sessions[0]["started_at"]) + timedelta(minutes=45)
    ).isoformat()
    reflections[1]["created_at"] = sessions[1]["started_at"]

    result, _, _ = _get((sessions, reflections, logs))

    assert result.status == "collecting"
    assert result.sample.eligible_focus_days == 28


@pytest.mark.parametrize(
    ("candidate", "comparison", "expected_reason"),
    [
        ((6, 6, 5, 4), (6, 6, 3, 4), "mixed_morning_outcomes"),
        ((8, 8, 3, 4), (6, 6, 3, 4), "mixed_focus_outcomes"),
    ],
)
def test_mixed_outcomes_report_typed_unstable_reasons(
    candidate: tuple[int, int, int, int],
    comparison: tuple[int, int, int, int],
    expected_reason: str,
) -> None:
    result, _, _ = _get(
        _evidence(
            30,
            candidate_outcomes=candidate,
            comparison_outcomes=comparison,
        ),
    )

    assert result.status == "unstable"
    assert result.reason == expected_reason
    assert result.recommendation is None


def test_reports_no_recurring_pattern_when_every_cluster_is_too_small() -> None:
    sessions, reflections, logs = _evidence(30)
    durations = (360, 480, 600, 720)
    for index, row in enumerate(logs):
        morning = row["metadata"]["captures"]["morning"]
        woke = datetime.combine(
            date.fromisoformat(row["entry_date"]),
            time(7),
            tzinfo=ZONE,
        )
        duration = durations[index % len(durations)]
        morning["woke_at"] = woke.astimezone(UTC).isoformat()
        morning["estimated_sleep_started_at"] = (
            (woke - timedelta(minutes=duration)).astimezone(UTC).isoformat()
        )
        morning["estimated_sleep_minutes"] = duration
        morning["sleep_hours"] = duration / 60

    result, _, _ = _get((sessions, reflections, logs))

    assert result.status == "unstable"
    assert result.reason == "no_recurring_pattern"


def test_reports_insufficient_comparison_when_all_days_share_one_pattern() -> None:
    sessions, reflections, logs = _evidence(30)
    for index, row in enumerate(logs):
        morning = row["metadata"]["captures"]["morning"]
        woke = datetime.combine(
            date.fromisoformat(row["entry_date"]),
            time(7, index % 3 * 5),
            tzinfo=ZONE,
        )
        duration = 480 + index % 3 * 5
        morning["woke_at"] = woke.astimezone(UTC).isoformat()
        morning["estimated_sleep_started_at"] = (
            (woke - timedelta(minutes=duration)).astimezone(UTC).isoformat()
        )
        morning["estimated_sleep_minutes"] = duration
        morning["sleep_hours"] = duration / 60

    result, _, _ = _get((sessions, reflections, logs))

    assert result.status == "unstable"
    assert result.reason == "insufficient_comparison_days"


def test_multiple_supported_candidates_use_stable_clock_tie_breaking() -> None:
    sessions, reflections, logs = _evidence(30)
    wake_times = (time(7), time(7, 30), time(8))
    for index, row in enumerate(logs):
        group = index % 3
        morning = row["metadata"]["captures"]["morning"]
        woke = datetime.combine(
            date.fromisoformat(row["entry_date"]),
            wake_times[group],
            tzinfo=ZONE,
        )
        morning["woke_at"] = woke.astimezone(UTC).isoformat()
        morning["estimated_sleep_started_at"] = (
            (woke - timedelta(minutes=480)).astimezone(UTC).isoformat()
        )
        morning["estimated_sleep_minutes"] = 480
        morning["sleep_hours"] = 8
        morning["sleep_quality"] = 8 if group == 1 else 6
        morning["current_energy"] = 8 if group == 1 else 6
        reflections[index]["useful_progress"] = 5 if group == 1 else 3
        reflections[index]["focus_quality"] = 5 if group == 1 else 4

    forward, _, _ = _get((sessions, reflections, logs))
    reverse, _, _ = _get(
        (list(reversed(sessions)), list(reversed(reflections)), list(reversed(logs))),
    )

    assert forward.status == reverse.status == "ready"
    assert forward.recommendation is not None
    assert reverse.recommendation is not None
    assert forward.recommendation.bedtime.start_local_time == "23:00"
    assert forward.recommendation.bedtime.end_local_time == "23:30"
    assert (
        forward.recommendation.evidence_fingerprint
        == reverse.recommendation.evidence_fingerprint
    )


def test_temporal_direction_must_repeat_in_both_halves() -> None:
    sessions, reflections, logs = _evidence(40)
    for index, reflection in enumerate(reflections):
        if index < 20 and index % 2 == 1:
            reflection["useful_progress"] = 1
        elif index >= 20:
            reflection["useful_progress"] = 3 if index % 2 == 0 else 4

    result, _, _ = _get((sessions, reflections, logs))

    assert result.status == "unstable"
    assert result.reason == "temporally_unstable_pattern"


def test_midnight_and_dst_clocks_are_transferred_explicitly() -> None:
    evidence = _evidence(30, start=date(2026, 3, 10))
    _, _, logs = evidence
    for index, row in enumerate(logs):
        if index % 2 == 0:
            morning = row["metadata"]["captures"]["morning"]
            local_day = date.fromisoformat(row["entry_date"])
            woke = datetime.combine(local_day, time(8), tzinfo=ZONE)
            started = datetime.combine(
                local_day - timedelta(days=1),
                time(23, 55 if index % 4 == 0 else 50),
                tzinfo=ZONE,
            )
            minutes = int(
                (woke.astimezone(UTC) - started.astimezone(UTC)).total_seconds() // 60
            )
            morning["estimated_sleep_started_at"] = started.astimezone(UTC).isoformat()
            morning["woke_at"] = woke.astimezone(UTC).isoformat()
            morning["estimated_sleep_minutes"] = minutes
            morning["sleep_hours"] = minutes / 60
    for row in logs:
        morning = row["metadata"]["captures"]["morning"]
        woke = datetime.fromisoformat(morning["woke_at"])
        started = woke - timedelta(minutes=morning["estimated_sleep_minutes"])
        morning["estimated_sleep_started_at"] = started.isoformat()

    result, _, _ = _get(evidence, now=datetime(2026, 4, 15, 12, tzinfo=UTC))

    assert result.status == "ready"
    assert result.recommendation is not None
    assert result.recommendation.wake_day_offset == 1
    assert result.recommendation.bedtime.start_local_time.startswith("23:")


def _episode_row(
    *,
    captured_at: datetime,
    woke_at: datetime,
    started_at: datetime,
    updated_at: object,
) -> dict:
    row_date = captured_at.astimezone(ZONE).date()
    duration = int((woke_at - started_at).total_seconds() // 60)
    return {
        "id": f"boundary-{captured_at.isoformat()}",
        "entry_date": row_date.isoformat(),
        "updated_at": updated_at,
        "metadata": {
            "capture_version": "daily-capture-v5",
            "captures": {
                "morning": {
                    "branch_version": "daily-capture-v5",
                    "capture_kind": "morning",
                    "entry_date": row_date.isoformat(),
                    "capture_id": f"morning-{captured_at.isoformat()}",
                    "captured_at": captured_at.isoformat(),
                    "sleep_hours": duration / 60,
                    "sleep_quality": 7,
                    "current_energy": 7,
                    "estimated_sleep_started_at": started_at.isoformat(),
                    "woke_at": woke_at.isoformat(),
                    "estimated_sleep_minutes": duration,
                    "sleep_target_minutes": 480,
                    "source_evening_capture_id": None,
                },
            },
        },
    }
