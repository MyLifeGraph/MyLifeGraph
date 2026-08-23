from __future__ import annotations

from datetime import datetime
from typing import Any, Protocol
from uuid import UUID

import httpx

from app.clients.supabase import SupabaseRestClient


class FocusPersistenceConflict(RuntimeError):
    pass


class FocusPersistenceNotFound(RuntimeError):
    pass


class FocusRepository(Protocol):
    async def get_start_context(
        self,
        *,
        user_id: str,
        source_kind: str,
        block_id: UUID,
        now: datetime,
    ) -> dict[str, Any]: ...

    async def start(
        self,
        *,
        user_id: str,
        request_id: UUID,
        request_fingerprint: str,
        source_kind: str,
        source_block_id: UUID | None,
        planned_minutes: int,
        recovery_minutes: int,
        target_kind: str | None,
        target_id: UUID | None,
        label: str | None,
        now: datetime,
    ) -> dict[str, Any]: ...

    async def finish(
        self,
        *,
        user_id: str,
        session_id: UUID,
        terminal_status: str,
        now: datetime,
    ) -> dict[str, Any]: ...


class SupabaseFocusRepository:
    def __init__(self, client: SupabaseRestClient) -> None:
        self._client = client

    async def get_start_context(
        self,
        *,
        user_id: str,
        source_kind: str,
        block_id: UUID,
        now: datetime,
    ) -> dict[str, Any]:
        return await self._rpc(
            "get_focus_start_context_v2",
            params={
                "p_user_id": user_id,
                "p_source_kind": source_kind,
                "p_block_id": str(block_id),
                "p_now": now.isoformat(),
            },
        )

    async def start(
        self,
        *,
        user_id: str,
        request_id: UUID,
        request_fingerprint: str,
        source_kind: str,
        source_block_id: UUID | None,
        planned_minutes: int,
        recovery_minutes: int,
        target_kind: str | None,
        target_id: UUID | None,
        label: str | None,
        now: datetime,
    ) -> dict[str, Any]:
        return await self._rpc(
            "start_focus_session_v2",
            params={
                "p_user_id": user_id,
                "p_request_id": str(request_id),
                "p_request_fingerprint": request_fingerprint,
                "p_source_kind": source_kind,
                "p_source_block_id": (
                    str(source_block_id) if source_block_id else None
                ),
                "p_planned_minutes": planned_minutes,
                "p_recovery_minutes": recovery_minutes,
                "p_target_kind": target_kind,
                "p_target_id": str(target_id) if target_id else None,
                "p_label": label,
                "p_now": now.isoformat(),
            },
        )

    async def finish(
        self,
        *,
        user_id: str,
        session_id: UUID,
        terminal_status: str,
        now: datetime,
    ) -> dict[str, Any]:
        return await self._rpc(
            "finish_focus_session_v2",
            params={
                "p_user_id": user_id,
                "p_session_id": str(session_id),
                "p_terminal_status": terminal_status,
                "p_now": now.isoformat(),
            },
        )

    async def _rpc(
        self,
        function: str,
        *,
        params: dict[str, Any],
    ) -> dict[str, Any]:
        try:
            result = await self._client.rpc(function, params=params)
        except httpx.HTTPStatusError as exc:
            code, message = _postgrest_error(exc)
            if code == "PT404":
                raise FocusPersistenceNotFound(message) from exc
            if code == "PT409":
                raise FocusPersistenceConflict(message) from exc
            raise
        if not isinstance(result, dict):
            raise ValueError("Focus persistence returned an invalid object.")
        return result


def _postgrest_error(exc: httpx.HTTPStatusError) -> tuple[str | None, str]:
    try:
        payload = exc.response.json()
    except ValueError:
        return None, "Focus persistence failed."
    if not isinstance(payload, dict):
        return None, "Focus persistence failed."
    code = payload.get("code") if isinstance(payload.get("code"), str) else None
    message = payload.get("message")
    return code, message if isinstance(message, str) else "Focus persistence failed."
