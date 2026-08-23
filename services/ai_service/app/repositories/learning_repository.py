from typing import Any, Protocol
from uuid import UUID

import httpx

from app.clients.supabase import SupabaseRestClient


class LearningPersistenceError(RuntimeError):
    pass


class LearningPersistenceConflict(LearningPersistenceError):
    pass


class LearningPersistenceNotFound(LearningPersistenceError):
    pass


class LearningPersistenceOutcomeUnknown(LearningPersistenceError):
    pass


class LearningRepository(Protocol):
    async def get_preferences(self, *, user_id: str) -> dict[str, Any] | None: ...

    async def profile_exists(self, *, user_id: str) -> bool: ...

    async def update_preferences(
        self,
        *,
        user_id: str,
        request_id: UUID,
        expected_revision: int,
        focus_reflection_prompt_enabled: bool,
        personal_pattern_analysis_enabled: bool,
        learned_focus_planning_enabled: bool,
    ) -> dict[str, Any]: ...

    async def clear_focus_reflections(
        self,
        *,
        user_id: str,
        request_id: UUID,
        expected_revision: int,
        confirmation: str,
    ) -> dict[str, Any]: ...


class SupabaseLearningRepository:
    def __init__(self, client: SupabaseRestClient) -> None:
        self._client = client

    async def get_preferences(self, *, user_id: str) -> dict[str, Any] | None:
        try:
            rows = await self._client.select(
                "learning_preferences",
                params={
                    "select": (
                        "contract_version,revision,"
                        "focus_reflection_prompt_enabled,"
                        "personal_pattern_analysis_enabled,"
                        "learned_focus_planning_enabled,updated_at"
                    ),
                    "user_id": f"eq.{user_id}",
                    "limit": "1",
                },
            )
        except (httpx.HTTPError, ValueError) as exc:
            raise LearningPersistenceError(
                "Personal learning preferences could not be loaded.",
            ) from exc
        if len(rows) > 1:
            raise LearningPersistenceError(
                "Personal learning preferences returned an invalid result.",
            )
        return rows[0] if rows else None

    async def profile_exists(self, *, user_id: str) -> bool:
        try:
            rows = await self._client.select(
                "profiles",
                params={"select": "id", "id": f"eq.{user_id}", "limit": "1"},
            )
        except (httpx.HTTPError, ValueError) as exc:
            raise LearningPersistenceError(
                "Personal learning owner could not be verified.",
            ) from exc
        if len(rows) > 1:
            raise LearningPersistenceError(
                "Personal learning owner returned an invalid result.",
            )
        return bool(rows)

    async def update_preferences(
        self,
        *,
        user_id: str,
        request_id: UUID,
        expected_revision: int,
        focus_reflection_prompt_enabled: bool,
        personal_pattern_analysis_enabled: bool,
        learned_focus_planning_enabled: bool,
    ) -> dict[str, Any]:
        return await self._retry_safe_rpc(
            function="update_learning_preferences_v1",
            params={
                "p_user_id": user_id,
                "p_request_id": str(request_id),
                "p_expected_revision": expected_revision,
                "p_focus_reflection_prompt_enabled":
                    focus_reflection_prompt_enabled,
                "p_personal_pattern_analysis_enabled":
                    personal_pattern_analysis_enabled,
                "p_learned_focus_planning_enabled":
                    learned_focus_planning_enabled,
            },
            outcome_message=(
                "Personal learning preference outcome could not be determined."
            ),
        )

    async def clear_focus_reflections(
        self,
        *,
        user_id: str,
        request_id: UUID,
        expected_revision: int,
        confirmation: str,
    ) -> dict[str, Any]:
        return await self._retry_safe_rpc(
            function="clear_focus_reflection_history_v1",
            params={
                "p_user_id": user_id,
                "p_request_id": str(request_id),
                "p_expected_revision": expected_revision,
                "p_confirmation": confirmation,
            },
            outcome_message=(
                "Focus reflection history clear outcome could not be determined."
            ),
        )

    async def _retry_safe_rpc(
        self,
        *,
        function: str,
        params: dict[str, Any],
        outcome_message: str,
    ) -> dict[str, Any]:
        ambiguous_error: Exception | None = None
        for attempt in range(2):
            try:
                result = await self._client.rpc(function, params=params)
            except httpx.HTTPStatusError as exc:
                code, message = _postgres_error(exc)
                if code == "PT409" or exc.response.status_code == 409:
                    raise LearningPersistenceConflict(
                        _safe_conflict_message(message),
                    ) from exc
                if code == "PT404" or exc.response.status_code == 404:
                    raise LearningPersistenceNotFound(
                        "Personal learning settings are unavailable.",
                    ) from exc
                if exc.response.status_code < 500:
                    raise LearningPersistenceError(
                        "Personal learning persistence rejected the request.",
                    ) from exc
                ambiguous_error = exc
            except (httpx.HTTPError, ValueError) as exc:
                ambiguous_error = exc
            else:
                if isinstance(result, dict):
                    return result
                ambiguous_error = ValueError(
                    "Personal learning persistence returned invalid JSON.",
                )
            if attempt == 0:
                continue
        raise LearningPersistenceOutcomeUnknown(outcome_message) from ambiguous_error


def _postgres_error(exc: httpx.HTTPStatusError) -> tuple[str | None, str]:
    try:
        payload = exc.response.json()
    except ValueError:
        return None, ""
    if not isinstance(payload, dict):
        return None, ""
    code = payload.get("code")
    message = payload.get("message")
    return (
        code if isinstance(code, str) else None,
        message if isinstance(message, str) else "",
    )


def _safe_conflict_message(message: str) -> str:
    if "request id" in message.lower():
        return "Personal learning request id was already used."
    return "Personal learning settings changed since they were loaded."
