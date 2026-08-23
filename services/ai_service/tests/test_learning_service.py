import asyncio
from datetime import UTC, datetime
from uuid import UUID

import pytest

from app.models.learning import (
    FocusReflectionHistoryClearRequest,
    LearningPreferencesUpdateRequest,
)
from app.repositories.learning_repository import (
    LearningPersistenceConflict,
    LearningPersistenceError,
    LearningPersistenceNotFound,
    LearningPersistenceOutcomeUnknown,
)
from app.services.learning_service import (
    LearningConflictError,
    LearningContractError,
    LearningNotFoundError,
    LearningOutcomeUnknownError,
    LearningService,
    LearningUnavailableError,
)


USER_ID = "learning-owner"
REQUEST_ID = UUID("a2000000-0000-4000-8000-000000000001")
NOW = "2026-07-26T08:00:00Z"


class Repository:
    def __init__(self) -> None:
        self.preferences = {
            "contract_version": "learning-preferences-v1",
            "revision": 2,
            "focus_reflection_prompt_enabled": True,
            "personal_pattern_analysis_enabled": True,
            "learned_focus_planning_enabled": False,
            "updated_at": NOW,
        }
        self.profile_present = True
        self.calls: list[tuple] = []
        self.update_result = {
            **self.preferences,
            "revision": 3,
            "focus_reflection_prompt_enabled": False,
            "learned_focus_planning_enabled": True,
            "replayed": False,
        }
        self.clear_result = {
            "contract_version": "focus-reflection-v1",
            "revision": 2,
            "deleted_count": 7,
            "cleared_at": NOW,
            "replayed": False,
        }
        self.get_error: Exception | None = None
        self.profile_error: Exception | None = None
        self.update_error: Exception | None = None
        self.clear_error: Exception | None = None

    async def get_preferences(self, *, user_id: str):
        self.calls.append(("get", user_id))
        if self.get_error is not None:
            raise self.get_error
        return self.preferences

    async def profile_exists(self, *, user_id: str):
        self.calls.append(("profile", user_id))
        if self.profile_error is not None:
            raise self.profile_error
        return self.profile_present

    async def update_preferences(self, **kwargs):
        self.calls.append(("update", kwargs))
        if self.update_error is not None:
            raise self.update_error
        return self.update_result

    async def clear_focus_reflections(self, **kwargs):
        self.calls.append(("clear", kwargs))
        if self.clear_error is not None:
            raise self.clear_error
        return self.clear_result


def test_get_preferences_parses_strict_state_and_default_projection() -> None:
    repository = Repository()
    service = LearningService(repository=repository)
    result = asyncio.run(service.get_preferences(user_id=USER_ID))
    assert result.revision == 2
    assert result.updated_at == datetime(2026, 7, 26, 8, tzinfo=UTC)

    repository.preferences = None
    result = asyncio.run(service.get_preferences(user_id=USER_ID))
    assert result.revision == 0
    assert result.focus_reflection_prompt_enabled is True
    assert result.personal_pattern_analysis_enabled is True
    assert result.learned_focus_planning_enabled is False
    assert result.updated_at is None


def test_update_passes_complete_owner_bound_request_and_validates_result() -> None:
    repository = Repository()
    service = LearningService(repository=repository)
    request = LearningPreferencesUpdateRequest(
        request_id=REQUEST_ID,
        expected_revision=2,
        focus_reflection_prompt_enabled=False,
        personal_pattern_analysis_enabled=True,
        learned_focus_planning_enabled=True,
    )
    result = asyncio.run(
        service.update_preferences(user_id=USER_ID, request=request),
    )
    assert result.revision == 3
    assert result.learned_focus_planning_enabled is True
    assert repository.calls[-1] == (
        "update",
        {
            "user_id": USER_ID,
            "request_id": REQUEST_ID,
            "expected_revision": 2,
            "focus_reflection_prompt_enabled": False,
            "personal_pattern_analysis_enabled": True,
            "learned_focus_planning_enabled": True,
        },
    )

    repository.update_result = {**repository.update_result, "revision": "3"}
    with pytest.raises(LearningContractError):
        asyncio.run(
            service.update_preferences(user_id=USER_ID, request=request),
        )


def test_clear_is_confirmation_bound_and_missing_is_not_zero() -> None:
    repository = Repository()
    service = LearningService(repository=repository)
    request = FocusReflectionHistoryClearRequest(
        request_id=REQUEST_ID,
        expected_revision=2,
        confirmation="CLEAR",
    )
    result = asyncio.run(
        service.clear_focus_reflections(user_id=USER_ID, request=request),
    )
    assert result.deleted_count == 7
    assert result.revision == 2
    assert repository.calls[-1][1]["confirmation"] == "CLEAR"

    repository.clear_result = {
        **repository.clear_result,
        "deleted_count": None,
    }
    with pytest.raises(LearningContractError):
        asyncio.run(
            service.clear_focus_reflections(user_id=USER_ID, request=request),
        )


@pytest.mark.parametrize(
    ("persistence_error", "service_error"),
    [
        (LearningPersistenceConflict("conflict"), LearningConflictError),
        (LearningPersistenceNotFound("missing"), LearningNotFoundError),
        (
            LearningPersistenceOutcomeUnknown("unknown"),
            LearningOutcomeUnknownError,
        ),
        (LearningPersistenceError("unavailable"), LearningUnavailableError),
    ],
)
def test_update_translates_persistence_failures(
    persistence_error: Exception,
    service_error: type[Exception],
) -> None:
    repository = Repository()
    repository.update_error = persistence_error
    service = LearningService(repository=repository)
    request = LearningPreferencesUpdateRequest(
        request_id=REQUEST_ID,
        expected_revision=2,
        focus_reflection_prompt_enabled=False,
        personal_pattern_analysis_enabled=True,
        learned_focus_planning_enabled=True,
    )

    with pytest.raises(service_error):
        asyncio.run(service.update_preferences(user_id=USER_ID, request=request))


def test_read_translates_missing_owner_and_persistence_failure() -> None:
    repository = Repository()
    repository.preferences = None
    repository.profile_present = False
    service = LearningService(repository=repository)

    with pytest.raises(LearningNotFoundError):
        asyncio.run(service.get_preferences(user_id=USER_ID))

    repository.get_error = LearningPersistenceError("provider detail")
    with pytest.raises(LearningUnavailableError):
        asyncio.run(service.get_preferences(user_id=USER_ID))
