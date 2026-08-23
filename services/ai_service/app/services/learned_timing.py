from __future__ import annotations

from typing import Protocol

from app.models.learning import LearningPreferencesState
from app.models.personal_patterns import PersonalPatternsResponse
from app.models.planning_timing import PlanningTimingProvenance


class LearningReader(Protocol):
    async def get_preferences(self, *, user_id: str) -> LearningPreferencesState: ...


class PersonalPatternsReader(Protocol):
    async def get_patterns(self, *, user_id: str) -> PersonalPatternsResponse: ...


class LearnedTimingResolver:
    def __init__(
        self,
        *,
        learning: LearningReader,
        patterns: PersonalPatternsReader,
        pilot_enabled: bool,
    ) -> None:
        self._learning = learning
        self._patterns = patterns
        self._pilot_enabled = pilot_enabled

    @property
    def pilot_enabled(self) -> bool:
        """Return the deployment authority used for proposal and confirm guards."""

        return self._pilot_enabled

    async def resolve(self, *, user_id: str) -> PlanningTimingProvenance:
        if not self._pilot_enabled:
            return PlanningTimingProvenance(source="setup")
        try:
            preferences = await self._learning.get_preferences(user_id=user_id)
        except Exception:
            return _fallback(unavailable=True)
        if not (
            preferences.personal_pattern_analysis_enabled
            and preferences.learned_focus_planning_enabled
        ):
            return PlanningTimingProvenance(source="setup")
        try:
            response = await self._patterns.get_patterns(user_id=user_id)
        except Exception:
            return _fallback(unavailable=True)
        preference = response.planner_preference
        if not preference.eligible:
            return _fallback(unavailable=False)
        assert preference.window is not None
        assert preference.evidence_starts_on is not None
        assert preference.evidence_ends_on is not None
        assert preference.evidence_fingerprint is not None
        return PlanningTimingProvenance(
            source="learned_personal_pattern",
            window=preference.window,
            evidence_count=preference.evidence_count,
            evidence_starts_on=preference.evidence_starts_on,
            evidence_ends_on=preference.evidence_ends_on,
            evidence_fingerprint=preference.evidence_fingerprint,
        )

    async def learned_confirmation_is_allowed(self, *, user_id: str) -> bool:
        if not self._pilot_enabled:
            return False
        try:
            preferences = await self._learning.get_preferences(user_id=user_id)
        except Exception:
            return False
        return (
            preferences.personal_pattern_analysis_enabled
            and preferences.learned_focus_planning_enabled
        )


def _fallback(*, unavailable: bool) -> PlanningTimingProvenance:
    return PlanningTimingProvenance(
        source="setup",
        fell_back_to_setup=True,
        warning=("personal_patterns_unavailable" if unavailable else None),
    )
