from dataclasses import dataclass
from typing import Any, Protocol
from uuid import UUID

import httpx

from app.clients.supabase import SupabaseRestClient


class IntakeClaimConflict(RuntimeError):
    """Raised when another request claimed the same user revision first."""


class IntakeApplyConflict(RuntimeError):
    """Raised when a pending revision is no longer safe to apply."""


class SetupOwnershipConflict(RuntimeError):
    """Raised rather than overwriting a non-Setup row with a stable Setup id."""


@dataclass(frozen=True)
class SetupMaterialization:
    goals: list[dict[str, Any]]
    habits: list[dict[str, Any]]
    schedule_items: list[dict[str, Any]]
    memory_entries: list[dict[str, Any]]


@dataclass(frozen=True)
class AtomicSetupApply:
    completed_at: str
    notification_preferences: dict[str, Any]
    materialization: SetupMaterialization
    snapshot: dict[str, Any]
    intake_metadata: dict[str, Any]


class IntakeRepository(Protocol):
    async def load_intake_by_request(
        self,
        *,
        user_id: str,
        request_id: UUID,
    ) -> dict[str, Any] | None:
        pass

    async def load_latest_intake(
        self,
        *,
        user_id: str,
    ) -> dict[str, Any] | None:
        pass

    async def load_latest_applied_intake(
        self,
        *,
        user_id: str,
    ) -> dict[str, Any] | None:
        pass

    async def insert_pending_intake(
        self,
        *,
        user_id: str,
        row: dict[str, Any],
    ) -> dict[str, Any]:
        pass

    async def apply_setup_revision(
        self,
        *,
        user_id: str,
        intake_response_id: str,
        request_id: UUID,
        base_revision: int,
        revision: int,
        apply: AtomicSetupApply,
    ) -> dict[str, Any]:
        pass

    async def load_latest_onboarding_snapshot(
        self,
        *,
        user_id: str,
    ) -> dict[str, Any] | None:
        pass


class SupabaseIntakeRepository:
    def __init__(self, client: SupabaseRestClient) -> None:
        self._client = client

    async def load_intake_by_request(
        self,
        *,
        user_id: str,
        request_id: UUID,
    ) -> dict[str, Any] | None:
        rows = await self._client.select(
            "intake_responses",
            params={
                "select": "*",
                "user_id": f"eq.{user_id}",
                "request_id": f"eq.{request_id}",
                "version": "eq.intake-v1",
                "limit": "1",
            },
        )
        return rows[0] if rows else None

    async def load_latest_intake(
        self,
        *,
        user_id: str,
    ) -> dict[str, Any] | None:
        return await self._load_latest_intake(user_id=user_id)

    async def load_latest_applied_intake(
        self,
        *,
        user_id: str,
    ) -> dict[str, Any] | None:
        return await self._load_latest_intake(user_id=user_id, state="applied")

    async def _load_latest_intake(
        self,
        *,
        user_id: str,
        state: str | None = None,
    ) -> dict[str, Any] | None:
        params = {
            "select": "*",
            "user_id": f"eq.{user_id}",
            "version": "eq.intake-v1",
            "order": "revision.desc,updated_at.desc",
            "limit": "1",
        }
        if state is not None:
            params["state"] = f"eq.{state}"
        rows = await self._client.select("intake_responses", params=params)
        return rows[0] if rows else None

    async def insert_pending_intake(
        self,
        *,
        user_id: str,
        row: dict[str, Any],
    ) -> dict[str, Any]:
        try:
            inserted = await self._client.insert(
                "intake_responses",
                rows=[{"user_id": user_id, **row}],
            )
        except httpx.HTTPStatusError as exc:
            if exc.response.status_code == 409:
                raise IntakeClaimConflict from exc
            raise
        return inserted[0]

    async def apply_setup_revision(
        self,
        *,
        user_id: str,
        intake_response_id: str,
        request_id: UUID,
        base_revision: int,
        revision: int,
        apply: AtomicSetupApply,
    ) -> dict[str, Any]:
        try:
            result = await self._client.rpc(
                "apply_intake_v1_setup_revision",
                params={
                    "p_user_id": user_id,
                    "p_intake_response_id": intake_response_id,
                    "p_request_id": str(request_id),
                    "p_base_revision": base_revision,
                    "p_revision": revision,
                    "p_completed_at": apply.completed_at,
                    "p_notification_preferences": apply.notification_preferences,
                    "p_goals": apply.materialization.goals,
                    "p_habits": apply.materialization.habits,
                    "p_schedule_items": apply.materialization.schedule_items,
                    "p_memory_entries": apply.materialization.memory_entries,
                    "p_snapshot": apply.snapshot,
                    "p_intake_metadata": apply.intake_metadata,
                },
            )
        except httpx.HTTPStatusError as exc:
            code, message = _postgres_error(exc)
            if code == "40001":
                raise IntakeApplyConflict(message) from exc
            if code == "23505" and "collides with a non-Setup row" in message:
                raise SetupOwnershipConflict(message) from exc
            raise
        if not isinstance(result, dict):
            raise ValueError("Atomic Intake V1 apply RPC returned a non-object.")
        return result

    async def load_latest_onboarding_snapshot(
        self,
        *,
        user_id: str,
    ) -> dict[str, Any] | None:
        rows = await self._client.select(
            "user_state_snapshots",
            params={
                "select": "id,period_key,summary,generated_at,metadata",
                "user_id": f"eq.{user_id}",
                "scope": "eq.onboarding",
                "order": "generated_at.desc",
                "limit": "1",
            },
        )
        return rows[0] if rows else None


def _postgres_error(exc: httpx.HTTPStatusError) -> tuple[str | None, str]:
    try:
        body = exc.response.json()
    except ValueError:
        return None, str(exc)
    if not isinstance(body, dict):
        return None, str(exc)
    code = body.get("code")
    message = body.get("message")
    return (
        str(code) if code is not None else None,
        str(message) if message is not None else str(exc),
    )
