import asyncio
from datetime import UTC, datetime, timedelta
from uuid import UUID

import pytest

from app.models.learning import LearningPreferencesState
from app.repositories.coach_evidence_repository import (
    CoachEvidenceRows,
    EvidenceRows,
    FocusOptionRows,
)
from app.services.coach_evidence_service import (
    CoachEvidenceAnalysisDisabled,
    CoachEvidenceFocusNotFound,
    CoachEvidenceService,
)


NOW = datetime(2026, 7, 28, 12, tzinfo=UTC)
FOCUS_ID = UUID("11111111-1111-4111-8111-111111111111")


class Learning:
    def __init__(self, enabled: bool = True) -> None:
        self.enabled = enabled

    async def get_preferences(self, *, user_id: str):
        return LearningPreferencesState(
            contract_version="learning-preferences-v1",
            revision=0,
            focus_reflection_prompt_enabled=True,
            personal_pattern_analysis_enabled=self.enabled,
            learned_focus_planning_enabled=False,
            updated_at=None,
        )


class Repository:
    def __init__(
        self,
        *,
        rows: CoachEvidenceRows | None = None,
        option_ids: list[UUID] | None = None,
        selected: dict | None = None,
    ) -> None:
        self.rows = rows or _empty_rows()
        self.option_ids = option_ids if option_ids is not None else [FOCUS_ID]
        self.selected = selected if selected is not None else _selected()
        self.evidence_calls = []
        self.option_calls = 0

    async def load_evidence(self, **kwargs):
        self.evidence_calls.append(kwargs)
        return self.rows

    async def load_focus_options(self, **kwargs):
        self.option_calls += 1
        return FocusOptionRows(
            sessions=[
                {
                    "id": str(value),
                    "status": "completed",
                    "started_at": f"2026-07-{20 - index:02d}T08:00:00Z",
                    "planned_minutes": 25,
                    "actual_minutes": 24,
                    "has_reflection": index == 1,
                }
                for index, value in enumerate(self.option_ids)
            ],
            more_available=False,
        )

    async def load_selected_focus(self, **kwargs):
        return self.selected


def test_patterns_disabled_stops_before_behavioral_evidence() -> None:
    repository = Repository()
    service = _service(repository=repository, learning=Learning(False))

    with pytest.raises(CoachEvidenceAnalysisDisabled):
        asyncio.run(
            service.build_patterns(
                user_id="owner",
                timezone="Europe/Berlin",
                horizon="90_days",
            ),
        )

    assert repository.evidence_calls == []


def test_context_options_default_to_newest_rated_session() -> None:
    second = UUID("22222222-2222-4222-8222-222222222222")
    service = _service(
        repository=Repository(option_ids=[FOCUS_ID, second]),
    )

    result = asyncio.run(
        service.get_context_options(
            user_id="owner",
            timezone="Europe/Berlin",
        ),
    )

    assert result.contract_version == "coach-context-options-v1"
    assert result.default_focus_session_id == second
    assert result.focus_options[0].local_started_at.utcoffset() is not None
    assert result.personal_pattern_analysis_enabled is True


def test_patterns_rereads_evidence_so_cleared_personal_data_is_not_cached() -> None:
    repository = Repository(
        rows=_rows(
            daily=[
                {
                    "id": "daily",
                    "entry_date": "2026-07-27",
                    "sleep_hours": 7.5,
                    "steps": None,
                    "activity_level": None,
                    "mood_score": 7,
                    "energy_level": 6,
                    "stress_level": 4,
                    "sleep_quality": 8,
                },
            ],
        ),
    )
    service = _service(repository=repository)

    first = asyncio.run(
        service.build_patterns(
            user_id="owner",
            timezone="Europe/Berlin",
            horizon="90_days",
        ),
    )
    repository.rows = _empty_rows()
    second = asyncio.run(
        service.build_patterns(
            user_id="owner",
            timezone="Europe/Berlin",
            horizon="90_days",
        ),
    )

    assert first != second
    assert len(repository.evidence_calls) == 2
    assert first.summary_metrics["daily_capture_days"] == 1
    assert second.summary_metrics["daily_capture_days"] == 0
    assert first.evidence_fingerprint


@pytest.mark.parametrize(
    ("horizon", "window_days"),
    [
        ("90_days", 90),
        ("1_year", 365),
        ("all_available", None),
    ],
)
def test_pattern_horizons_bind_the_exact_retained_evidence_window(
    horizon,
    window_days,
) -> None:
    repository = Repository()

    result = asyncio.run(
        _service(repository=repository).build_patterns(
            user_id="owner",
            timezone="Europe/Berlin",
            horizon=horizon,
        ),
    )

    call = repository.evidence_calls[0]
    expected_start = (
        NOW - timedelta(days=window_days) if window_days is not None else None
    )
    assert call["starts_at"] == expected_start
    assert call["local_starts_on"] == (
        expected_start.date() if expected_start is not None else None
    )
    assert call["ends_at"] == NOW
    assert call["local_ends_on"] == NOW.date()
    assert result.window.horizon == horizon


def test_all_available_adapts_more_than_twenty_four_years_without_truncation() -> None:
    repository = Repository(
        rows=_rows(
            daily=[
                {
                    "id": f"daily-{year}",
                    "entry_date": f"{year}-01-10",
                    "sleep_hours": 7.0,
                    "steps": None,
                    "activity_level": None,
                    "mood_score": 6,
                    "energy_level": 6,
                    "stress_level": 4,
                    "sleep_quality": None,
                }
                for year in range(1976, 2027)
            ],
        ),
    )

    result = asyncio.run(
        _service(repository=repository).build_patterns(
            user_id="owner",
            timezone="Europe/Berlin",
            horizon="all_available",
        ),
    )

    assert len(result.buckets) <= 24
    assert result.buckets[0].starts_on.year == 1976
    assert result.buckets[-1].ends_on.year >= 2026
    assert (
        sum(int(bucket.metrics["daily_capture_days"]) for bucket in result.buckets)
        == 51
    )


def test_focus_is_restricted_to_last_ten_and_selected_counts_in_manifest() -> None:
    repository = Repository(rows=_empty_rows())
    result = asyncio.run(
        _service(repository=repository).build_focus(
            user_id="owner",
            timezone="Europe/Berlin",
            focus_session_id=FOCUS_ID,
        ),
    )
    focus_source = next(
        source for source in result.sources if source.source == "focus_reflections"
    )
    assert focus_source.available_count == 1
    assert focus_source.included_count == 1

    repository.option_ids = []
    with pytest.raises(CoachEvidenceFocusNotFound):
        asyncio.run(
            _service(repository=repository).build_focus(
                user_id="owner",
                timezone="Europe/Berlin",
                focus_session_id=FOCUS_ID,
            ),
        )


def test_review_is_exactly_two_complete_profile_local_iso_weeks() -> None:
    repository = Repository()
    result = asyncio.run(
        _service(repository=repository).build_review(
            user_id="owner",
            timezone="Europe/Berlin",
        ),
    )

    assert result.window.starts_on.isoformat() == "2026-07-13"
    assert result.window.ends_on.isoformat() == "2026-07-26"
    call = repository.evidence_calls[0]
    assert call["local_starts_on"].isoformat() == "2026-07-13"
    assert call["local_ends_on"].isoformat() == "2026-07-26"


def _service(
    *,
    repository: Repository,
    learning: Learning | None = None,
) -> CoachEvidenceService:
    return CoachEvidenceService(
        repository=repository,
        learning=learning or Learning(),
        semaphore=asyncio.Semaphore(4),
        now=lambda: NOW,
    )


def _selected() -> dict:
    return {
        "id": str(FOCUS_ID),
        "status": "completed",
        "started_at": "2026-01-01T08:00:00Z",
        "ended_at": "2026-01-01T08:24:00Z",
        "planned_minutes": 25,
        "actual_minutes": 24,
        "reflection": {
            "focus_session_id": str(FOCUS_ID),
            "contract_version": "focus-reflection-v1",
            "focus_quality": 4,
            "useful_progress": 5,
            "obstacles": [],
            "created_at": "2026-01-01T08:25:00Z",
            "updated_at": "2026-01-01T08:25:00Z",
        },
    }


def _empty() -> EvidenceRows:
    return EvidenceRows(rows=[], available_count=0, partial=False)


def _empty_rows() -> CoachEvidenceRows:
    return CoachEvidenceRows(
        daily_logs=_empty(),
        focus_sessions=_empty(),
        reflections=_empty(),
        habit_outcomes=_empty(),
        weekly_reviews=_empty(),
        task_lifecycle=_empty(),
    )


def _rows(*, daily: list[dict]) -> CoachEvidenceRows:
    empty = _empty()
    return CoachEvidenceRows(
        daily_logs=EvidenceRows(
            rows=daily,
            available_count=len(daily),
            partial=False,
        ),
        focus_sessions=empty,
        reflections=empty,
        habit_outcomes=empty,
        weekly_reviews=empty,
        task_lifecycle=empty,
    )
