import asyncio
from datetime import UTC, date, datetime, timedelta

import pytest
from pydantic import ValidationError

from app.models.learning import LearningPreferencesState
from app.models.personal_patterns import (
    LearnedFocusPlannerPreference,
    PersonalPatternsResponse,
    PersonalPatternsSample,
    PersonalPatternsWindow,
)
from app.models.planning_timing import PlanningTimingProvenance
from app.services.learned_timing import LearnedTimingResolver


NOW = datetime(2026, 7, 26, 12, tzinfo=UTC)


class Learning:
    def __init__(
        self,
        *,
        analysis: bool = True,
        planning: bool = True,
        error: Exception | None = None,
    ) -> None:
        self.analysis = analysis
        self.planning = planning
        self.error = error
        self.calls = 0

    async def get_preferences(self, *, user_id: str) -> LearningPreferencesState:
        self.calls += 1
        if self.error is not None:
            raise self.error
        return LearningPreferencesState(
            contract_version="learning-preferences-v1",
            revision=2,
            focus_reflection_prompt_enabled=True,
            personal_pattern_analysis_enabled=self.analysis,
            learned_focus_planning_enabled=self.planning,
            updated_at=NOW,
        )


class Patterns:
    def __init__(
        self,
        *,
        eligible: bool = True,
        error: Exception | None = None,
    ) -> None:
        self.eligible = eligible
        self.error = error
        self.calls = 0

    async def get_patterns(self, *, user_id: str) -> PersonalPatternsResponse:
        self.calls += 1
        if self.error is not None:
            raise self.error
        preference = LearnedFocusPlannerPreference(
            eligible=self.eligible,
            reason="eligible" if self.eligible else "thresholds_not_met",
            window="09-13",
            window_label="09:00–13:00",
            evidence_count=24,
            evidence_starts_on=date(2026, 6, 1),
            evidence_ends_on=date(2026, 7, 25),
            evidence_fingerprint="a" * 64,
        )
        return PersonalPatternsResponse(
            contract_version="personal-patterns-v1",
            status="stable",
            generated_at=NOW,
            timezone="Europe/Berlin",
            window=PersonalPatternsWindow(
                rolling_days=90,
                starts_at=NOW - timedelta(days=90),
                ends_at=NOW,
                local_starts_on=date(2026, 4, 27),
                local_ends_on=date(2026, 7, 26),
            ),
            summary="A stable personal baseline is available.",
            sample=PersonalPatternsSample(
                terminal_sessions=24,
                rated_sessions=24,
                rated_local_days=24,
                rating_coverage=1,
                first_rated_local_date=date(2026, 6, 1),
                last_rated_local_date=date(2026, 7, 25),
            ),
            baseline=None,
            patterns=[],
            planner_preference=preference,
            limitations=["Associations are not causes."],
            correlation_points=[],
            evidence_fingerprint="a" * 64,
        )


def test_rollout_and_user_permission_are_independent_gates() -> None:
    learning = Learning()
    patterns = Patterns()
    disabled_rollout = LearnedTimingResolver(
        learning=learning,
        patterns=patterns,
        pilot_enabled=False,
    )

    rollout_result = asyncio.run(disabled_rollout.resolve(user_id="owner"))

    assert rollout_result.source == "setup"
    assert learning.calls == 0
    assert patterns.calls == 0

    user_off = LearnedTimingResolver(
        learning=Learning(planning=False),
        patterns=patterns,
        pilot_enabled=True,
    )
    user_result = asyncio.run(user_off.resolve(user_id="owner"))

    assert user_result.source == "setup"
    assert patterns.calls == 0


def test_eligible_pattern_returns_exact_immutable_evidence() -> None:
    resolver = LearnedTimingResolver(
        learning=Learning(),
        patterns=Patterns(),
        pilot_enabled=True,
    )

    result = asyncio.run(resolver.resolve(user_id="owner"))

    assert result.source == "learned_personal_pattern"
    assert result.window == "09-13"
    assert result.evidence_count == 24
    assert result.evidence_starts_on == date(2026, 6, 1)
    assert result.evidence_ends_on == date(2026, 7, 25)
    assert result.evidence_fingerprint == "a" * 64
    assert result.fell_back_to_setup is False


def test_learned_evidence_remains_valid_when_allocation_uses_setup_fallback() -> None:
    provenance = PlanningTimingProvenance(
        source="learned_personal_pattern",
        window="09-13",
        evidence_count=24,
        evidence_starts_on=date(2026, 6, 1),
        evidence_ends_on=date(2026, 7, 25),
        evidence_fingerprint="a" * 64,
        fell_back_to_setup=True,
    )

    assert provenance.source == "learned_personal_pattern"
    assert provenance.fell_back_to_setup is True
    assert provenance.warning is None


def test_learned_evidence_rejects_a_reversed_date_range() -> None:
    with pytest.raises(ValidationError):
        PlanningTimingProvenance(
            source="learned_personal_pattern",
            window="09-13",
            evidence_count=24,
            evidence_starts_on=date(2026, 7, 25),
            evidence_ends_on=date(2026, 6, 1),
            evidence_fingerprint="a" * 64,
        )


def test_ineligible_pattern_and_outage_fall_back_differently() -> None:
    immature = LearnedTimingResolver(
        learning=Learning(),
        patterns=Patterns(eligible=False),
        pilot_enabled=True,
    )
    unavailable = LearnedTimingResolver(
        learning=Learning(),
        patterns=Patterns(error=RuntimeError("offline")),
        pilot_enabled=True,
    )

    immature_result = asyncio.run(immature.resolve(user_id="owner"))
    unavailable_result = asyncio.run(unavailable.resolve(user_id="owner"))

    assert immature_result.source == "setup"
    assert immature_result.fell_back_to_setup is True
    assert immature_result.warning is None
    assert unavailable_result.source == "setup"
    assert unavailable_result.fell_back_to_setup is True
    assert unavailable_result.warning == "personal_patterns_unavailable"


def test_confirmation_rechecks_current_permission_without_recomputing_pattern() -> None:
    learning = Learning(planning=False)
    patterns = Patterns()
    resolver = LearnedTimingResolver(
        learning=learning,
        patterns=patterns,
        pilot_enabled=True,
    )

    allowed = asyncio.run(
        resolver.learned_confirmation_is_allowed(user_id="owner"),
    )

    assert allowed is False
    assert learning.calls == 1
    assert patterns.calls == 0
