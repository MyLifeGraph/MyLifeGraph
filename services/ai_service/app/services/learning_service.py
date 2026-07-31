from datetime import datetime
from typing import Any

from pydantic import ValidationError

from app.models.learning import (
    FOCUS_REFLECTION_CONTRACT_VERSION,
    LEARNING_PREFERENCES_CONTRACT_VERSION,
    FocusReflectionHistoryClearRequest,
    FocusReflectionHistoryClearResponse,
    LearningPreferencesState,
    LearningPreferencesUpdateRequest,
    LearningPreferencesUpdateResponse,
)
from app.repositories.learning_repository import (
    LearningPersistenceConflict,
    LearningPersistenceError,
    LearningPersistenceNotFound,
    LearningPersistenceOutcomeUnknown,
    LearningRepository,
)


class LearningContractError(ValueError):
    pass


class LearningConflictError(RuntimeError):
    pass


class LearningNotFoundError(RuntimeError):
    pass


class LearningOutcomeUnknownError(RuntimeError):
    pass


class LearningUnavailableError(RuntimeError):
    pass


class LearningService:
    def __init__(self, *, repository: LearningRepository) -> None:
        self._repository = repository

    async def get_preferences(self, *, user_id: str) -> LearningPreferencesState:
        try:
            row = await self._repository.get_preferences(user_id=user_id)
        except LearningPersistenceNotFound as exc:
            raise LearningNotFoundError(str(exc)) from exc
        except LearningPersistenceError as exc:
            raise LearningUnavailableError(
                "Personal learning settings could not be loaded.",
            ) from exc
        if row is None:
            try:
                profile_exists = await self._repository.profile_exists(user_id=user_id)
            except LearningPersistenceError as exc:
                raise LearningUnavailableError(
                    "Personal learning settings could not be loaded.",
                ) from exc
            if not profile_exists:
                raise LearningNotFoundError(
                    "Personal learning settings are unavailable.",
                )
            return LearningPreferencesState(
                contract_version=LEARNING_PREFERENCES_CONTRACT_VERSION,
                revision=0,
                focus_reflection_prompt_enabled=True,
                personal_pattern_analysis_enabled=True,
                learned_focus_planning_enabled=False,
                updated_at=None,
            )
        return _parse_preferences(row)

    async def update_preferences(
        self,
        *,
        user_id: str,
        request: LearningPreferencesUpdateRequest,
    ) -> LearningPreferencesUpdateResponse:
        try:
            row = await self._repository.update_preferences(
                user_id=user_id,
                request_id=request.request_id,
                expected_revision=request.expected_revision,
                focus_reflection_prompt_enabled=(
                    request.focus_reflection_prompt_enabled
                ),
                personal_pattern_analysis_enabled=(
                    request.personal_pattern_analysis_enabled
                ),
                learned_focus_planning_enabled=(
                    request.learned_focus_planning_enabled
                ),
            )
        except LearningPersistenceConflict as exc:
            raise LearningConflictError(str(exc)) from exc
        except LearningPersistenceNotFound as exc:
            raise LearningNotFoundError(str(exc)) from exc
        except LearningPersistenceOutcomeUnknown as exc:
            raise LearningOutcomeUnknownError(str(exc)) from exc
        except LearningPersistenceError as exc:
            raise LearningUnavailableError(
                "Personal learning settings could not be updated.",
            ) from exc
        try:
            return LearningPreferencesUpdateResponse.model_validate(
                {
                    **row,
                    "updated_at": _optional_datetime(row.get("updated_at")),
                },
                strict=True,
            )
        except ValidationError as exc:
            raise LearningContractError(
                "Personal learning persistence returned an invalid result.",
            ) from exc

    async def clear_focus_reflections(
        self,
        *,
        user_id: str,
        request: FocusReflectionHistoryClearRequest,
    ) -> FocusReflectionHistoryClearResponse:
        try:
            row = await self._repository.clear_focus_reflections(
                user_id=user_id,
                request_id=request.request_id,
                expected_revision=request.expected_revision,
                confirmation=request.confirmation,
            )
        except LearningPersistenceConflict as exc:
            raise LearningConflictError(str(exc)) from exc
        except LearningPersistenceNotFound as exc:
            raise LearningNotFoundError(str(exc)) from exc
        except LearningPersistenceOutcomeUnknown as exc:
            raise LearningOutcomeUnknownError(str(exc)) from exc
        except LearningPersistenceError as exc:
            raise LearningUnavailableError(
                "Focus reflection history could not be cleared.",
            ) from exc
        try:
            response = FocusReflectionHistoryClearResponse.model_validate(
                {
                    **row,
                    "cleared_at": _required_datetime(row.get("cleared_at")),
                },
                strict=True,
            )
        except ValidationError as exc:
            raise LearningContractError(
                "Focus reflection clear returned an invalid result.",
            ) from exc
        if response.contract_version != FOCUS_REFLECTION_CONTRACT_VERSION:
            raise LearningContractError(
                "Focus reflection clear returned an invalid contract.",
            )
        return response


def _parse_preferences(row: dict[str, Any]) -> LearningPreferencesState:
    try:
        return LearningPreferencesState.model_validate(
            {
                **row,
                "updated_at": _optional_datetime(row.get("updated_at")),
            },
            strict=True,
        )
    except ValidationError as exc:
        raise LearningContractError(
            "Personal learning preferences are invalid.",
        ) from exc


def _optional_datetime(value: Any) -> datetime | None:
    if value is None:
        return None
    return _required_datetime(value)


def _required_datetime(value: Any) -> datetime:
    if isinstance(value, datetime):
        parsed = value
    elif isinstance(value, str):
        try:
            parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
        except ValueError as exc:
            raise LearningContractError(
                "Personal learning timestamp is invalid.",
            ) from exc
    else:
        raise LearningContractError("Personal learning timestamp is invalid.")
    if parsed.utcoffset() is None:
        raise LearningContractError("Personal learning timestamp is invalid.")
    return parsed
