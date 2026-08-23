from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime
from typing import Any, Protocol
from uuid import UUID

import httpx

from app.clients.supabase import SupabaseRestClient
from app.repositories.deadline_plan_repository import (
    DeadlinePlanPersistenceConflict,
    DeadlinePlanPersistenceNotFound,
    ExamPlanHealthSnapshot,
    _parse_exam_plan_health_snapshot,
)


@dataclass(frozen=True, slots=True)
class MultiExamPlanSnapshot:
    health: ExamPlanHealthSnapshot
    context_fingerprint: str
    active_plans: list[dict[str, Any]]


class MultiExamPlanRepository(Protocol):
    async def get_request_identity(
        self,
        *,
        user_id: str,
        request_id: UUID,
    ) -> dict[str, Any] | None: ...

    async def load_snapshot(
        self,
        *,
        user_id: str,
        generated_at: datetime,
    ) -> MultiExamPlanSnapshot: ...

    async def list_balances(self, *, user_id: str) -> dict[str, Any]: ...

    async def get_balance(
        self,
        *,
        user_id: str,
        balance_id: UUID,
    ) -> dict[str, Any]: ...

    async def persist_proposal(
        self,
        *,
        user_id: str,
        outcome: str,
        balance_id: UUID | None,
        request_id: UUID,
        request_fingerprint: str,
        target_plan_id: UUID,
        expected_plan_revision: int,
        context_generated_at: datetime,
        context_fingerprint: str,
        timezone: str,
        learned_timing_pilot_enabled: bool,
        children: list[dict[str, Any]],
        now: datetime,
    ) -> dict[str, Any]: ...

    async def confirm(
        self,
        *,
        user_id: str,
        balance_id: UUID,
        request_id: UUID,
        request_fingerprint: str,
        expected_revision: int,
        learned_timing_pilot_enabled: bool,
        now: datetime,
    ) -> dict[str, Any]: ...

    async def cancel(
        self,
        *,
        user_id: str,
        balance_id: UUID,
        request_id: UUID,
        request_fingerprint: str,
        expected_revision: int,
        now: datetime,
    ) -> dict[str, Any]: ...


class SupabaseMultiExamPlanRepository:
    def __init__(self, client: SupabaseRestClient) -> None:
        self._client = client

    async def get_request_identity(
        self,
        *,
        user_id: str,
        request_id: UUID,
    ) -> dict[str, Any] | None:
        result = await self._rpc(
            "get_multi_exam_plan_request_v1",
            params={"p_user_id": user_id, "p_request_id": str(request_id)},
        )
        if result == {"found": False}:
            return None
        if result.get("found") is not True:
            raise ValueError("Exam balance request replay is invalid.")
        return result

    async def load_snapshot(
        self,
        *,
        user_id: str,
        generated_at: datetime,
    ) -> MultiExamPlanSnapshot:
        result = await self._rpc(
            "get_multi_exam_plan_snapshot_v1",
            params={
                "p_user_id": user_id,
                "p_generated_at": generated_at.isoformat(),
            },
        )
        if (
            set(result)
            != {
                "contract_version",
                "context_fingerprint",
                "active_plans",
                "health_snapshot",
            }
            or result.get("contract_version") != "multi-exam-plan-snapshot-v1"
        ):
            raise ValueError("Exam balance snapshot RPC returned an invalid object.")
        fingerprint = result.get("context_fingerprint")
        active_plans = result.get("active_plans")
        if (
            not isinstance(fingerprint, str)
            or len(fingerprint) != 64
            or any(character not in "0123456789abcdef" for character in fingerprint)
            or not isinstance(active_plans, list)
            or any(not isinstance(row, dict) for row in active_plans)
        ):
            raise ValueError("Exam balance snapshot authorities are invalid.")
        plan_ids = [str(row.get("id")) for row in active_plans]
        if any(value == "None" for value in plan_ids) or len(plan_ids) != len(
            set(plan_ids),
        ):
            raise ValueError("Exam balance snapshot contains duplicate plans.")
        return MultiExamPlanSnapshot(
            health=_parse_exam_plan_health_snapshot(result.get("health_snapshot")),
            context_fingerprint=fingerprint,
            active_plans=[dict(row) for row in active_plans],
        )

    async def list_balances(self, *, user_id: str) -> dict[str, Any]:
        return await self._rpc(
            "get_multi_exam_plan_projection_v1",
            params={"p_user_id": user_id},
        )

    async def get_balance(
        self,
        *,
        user_id: str,
        balance_id: UUID,
    ) -> dict[str, Any]:
        return await self._rpc(
            "get_multi_exam_plan_projection_v1",
            params={"p_user_id": user_id, "p_balance_id": str(balance_id)},
        )

    async def persist_proposal(
        self,
        *,
        user_id: str,
        outcome: str,
        balance_id: UUID | None,
        request_id: UUID,
        request_fingerprint: str,
        target_plan_id: UUID,
        expected_plan_revision: int,
        context_generated_at: datetime,
        context_fingerprint: str,
        timezone: str,
        learned_timing_pilot_enabled: bool,
        children: list[dict[str, Any]],
        now: datetime,
    ) -> dict[str, Any]:
        return await self._rpc(
            "propose_multi_exam_plan_v1",
            params={
                "p_user_id": user_id,
                "p_outcome": outcome,
                "p_balance_id": str(balance_id) if balance_id is not None else None,
                "p_request_id": str(request_id),
                "p_request_fingerprint": request_fingerprint,
                "p_target_plan_id": str(target_plan_id),
                "p_expected_plan_revision": expected_plan_revision,
                "p_context_generated_at": context_generated_at.isoformat(),
                "p_context_fingerprint": context_fingerprint,
                "p_timezone": timezone,
                "p_learned_timing_pilot_enabled": learned_timing_pilot_enabled,
                "p_children": children,
                "p_now": now.isoformat(),
            },
        )

    async def confirm(
        self,
        *,
        user_id: str,
        balance_id: UUID,
        request_id: UUID,
        request_fingerprint: str,
        expected_revision: int,
        learned_timing_pilot_enabled: bool,
        now: datetime,
    ) -> dict[str, Any]:
        return await self._rpc(
            "confirm_multi_exam_plan_v1",
            params={
                "p_user_id": user_id,
                "p_balance_id": str(balance_id),
                "p_request_id": str(request_id),
                "p_request_fingerprint": request_fingerprint,
                "p_expected_revision": expected_revision,
                "p_learned_timing_pilot_enabled": learned_timing_pilot_enabled,
                "p_now": now.isoformat(),
            },
        )

    async def cancel(
        self,
        *,
        user_id: str,
        balance_id: UUID,
        request_id: UUID,
        request_fingerprint: str,
        expected_revision: int,
        now: datetime,
    ) -> dict[str, Any]:
        return await self._rpc(
            "cancel_multi_exam_plan_v1",
            params={
                "p_user_id": user_id,
                "p_balance_id": str(balance_id),
                "p_request_id": str(request_id),
                "p_request_fingerprint": request_fingerprint,
                "p_expected_revision": expected_revision,
                "p_now": now.isoformat(),
            },
        )

    async def _rpc(self, function: str, *, params: dict[str, Any]) -> dict[str, Any]:
        try:
            result = await self._client.rpc(function, params=params)
        except httpx.HTTPStatusError as exc:
            code, message = _postgres_error(exc)
            if code in {"23505", "40001", "40P01", "55P03", "PT409"}:
                raise DeadlinePlanPersistenceConflict(message) from exc
            if code == "PT404":
                raise DeadlinePlanPersistenceNotFound(message) from exc
            raise
        if not isinstance(result, dict):
            raise ValueError(f"{function} returned an invalid object.")
        return dict(result)


def _postgres_error(exc: httpx.HTTPStatusError) -> tuple[str | None, str]:
    try:
        data = exc.response.json()
    except ValueError:
        return None, "Exam balance persistence failed."
    if not isinstance(data, dict):
        return None, "Exam balance persistence failed."
    code = data.get("code")
    message = data.get("message")
    return (
        code if isinstance(code, str) else None,
        message if isinstance(message, str) else "Exam balance persistence failed.",
    )
