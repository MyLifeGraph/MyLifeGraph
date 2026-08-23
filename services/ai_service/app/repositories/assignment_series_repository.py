from dataclasses import dataclass
from datetime import datetime
from typing import Any, Protocol
from uuid import UUID

import httpx

from app.clients.supabase import SupabaseRestClient
from app.repositories.deadline_plan_repository import (
    DeadlinePlanPersistenceConflict,
    DeadlinePlanPersistenceNotFound,
)
from app.repositories.repository_pagination import select_offset_pages


@dataclass(frozen=True, slots=True)
class AssignmentSeriesProjection:
    series: list[dict[str, Any]]
    revisions: list[dict[str, Any]]
    occurrences: list[dict[str, Any]]


class AssignmentSeriesRepository(Protocol):
    async def get_request_identity(
        self,
        *,
        request_id: UUID,
    ) -> dict[str, Any] | None: ...

    async def load_projection(
        self,
        *,
        user_id: str,
        series_id: UUID | None,
    ) -> AssignmentSeriesProjection: ...

    async def get_deadline_plans(
        self,
        *,
        user_id: str,
        plan_ids: tuple[UUID, ...],
    ) -> list[dict[str, Any]]: ...

    async def persist_proposal(
        self,
        *,
        user_id: str,
        request_id: UUID,
        request_fingerprint: str,
        series_id: UUID,
        base_revision: int,
        series_payload: dict[str, Any],
        items: list[dict[str, Any]],
        now: datetime,
    ) -> int: ...

    async def confirm(
        self,
        *,
        user_id: str,
        series_id: UUID,
        request_id: UUID,
        request_fingerprint: str,
        expected_revision: int,
        now: datetime,
    ) -> None: ...

    async def cancel_future(
        self,
        *,
        user_id: str,
        series_id: UUID,
        request_id: UUID,
        request_fingerprint: str,
        expected_revision: int,
        items: list[dict[str, Any]],
        now: datetime,
    ) -> None: ...


class SupabaseAssignmentSeriesRepository:
    _page_size = 1_000

    def __init__(self, client: SupabaseRestClient) -> None:
        self._client = client

    async def get_request_identity(
        self,
        *,
        request_id: UUID,
    ) -> dict[str, Any] | None:
        rows = await self._client.select(
            "assignment_series_request_identities",
            params={
                "select": "request_id,user_id,operation,request_fingerprint,"
                "series_id,result_revision,result_status",
                "request_id": f"eq.{request_id}",
                "limit": "1",
            },
        )
        return rows[0] if rows else None

    async def load_projection(
        self,
        *,
        user_id: str,
        series_id: UUID | None,
    ) -> AssignmentSeriesProjection:
        series_params: dict[str, Any] = {
            "select": "*",
            "user_id": f"eq.{user_id}",
            "order": "updated_at.desc,id.asc",
            "limit": "21",
        }
        if series_id is not None:
            series_params["id"] = f"eq.{series_id}"
            series_params["limit"] = "1"
        series = await self._client.select(
            "assignment_series",
            params=series_params,
        )
        if not series:
            return AssignmentSeriesProjection(series=[], revisions=[], occurrences=[])
        ids = sorted(str(UUID(str(row["id"]))) for row in series)
        revisions = await select_offset_pages(
            self._client,
            "assignment_series_revisions",
            params={
                "select": "*",
                "user_id": f"eq.{user_id}",
                "series_id": f"in.({','.join(ids)})",
                "state": "in.(proposed,active)",
                "order": "series_id.asc,revision.asc,id.asc",
            },
            page_size=self._page_size,
            max_rows=41,
            overfull_error="Assignment series revisions exceed their read bound.",
        )
        revision_pairs = [
            (str(UUID(str(row["series_id"]))), int(row["revision"]))
            for row in revisions
        ]
        occurrences: list[dict[str, Any]] = []
        for target_series_id, revision in revision_pairs:
            rows = await self._client.select(
                "assignment_series_revision_items",
                params={
                    "select": "*",
                    "user_id": f"eq.{user_id}",
                    "series_id": f"eq.{target_series_id}",
                    "series_revision": f"eq.{revision}",
                    "order": "position.asc,plan_id.asc",
                    "limit": "41",
                },
            )
            if len(rows) > 40:
                raise ValueError("Assignment series occurrences exceed their bound.")
            occurrences.extend(rows)
        return AssignmentSeriesProjection(
            series=series,
            revisions=revisions,
            occurrences=occurrences,
        )

    async def get_deadline_plans(
        self,
        *,
        user_id: str,
        plan_ids: tuple[UUID, ...],
    ) -> list[dict[str, Any]]:
        if not plan_ids:
            return []
        ids = ",".join(sorted(str(value) for value in set(plan_ids)))
        return await self._client.select(
            "deadline_plans",
            params={
                "select": "*",
                "user_id": f"eq.{user_id}",
                "id": f"in.({ids})",
                "order": "id.asc",
                "limit": "41",
            },
        )

    async def persist_proposal(
        self,
        *,
        user_id: str,
        request_id: UUID,
        request_fingerprint: str,
        series_id: UUID,
        base_revision: int,
        series_payload: dict[str, Any],
        items: list[dict[str, Any]],
        now: datetime,
    ) -> int:
        result = await self._rpc(
            "propose_assignment_series_v1",
            params={
                "p_user_id": user_id,
                "p_request_id": str(request_id),
                "p_request_fingerprint": request_fingerprint,
                "p_series_id": str(series_id),
                "p_base_revision": base_revision,
                "p_series": series_payload,
                "p_items": items,
                "p_now": now.isoformat(),
            },
        )
        revision = result.get("revision")
        if isinstance(revision, bool) or not isinstance(revision, int):
            raise ValueError("Assignment series proposal returned an invalid revision.")
        return revision

    async def confirm(
        self,
        *,
        user_id: str,
        series_id: UUID,
        request_id: UUID,
        request_fingerprint: str,
        expected_revision: int,
        now: datetime,
    ) -> None:
        await self._rpc(
            "confirm_assignment_series_v1",
            params={
                "p_user_id": user_id,
                "p_series_id": str(series_id),
                "p_request_id": str(request_id),
                "p_request_fingerprint": request_fingerprint,
                "p_expected_revision": expected_revision,
                "p_now": now.isoformat(),
            },
        )

    async def cancel_future(
        self,
        *,
        user_id: str,
        series_id: UUID,
        request_id: UUID,
        request_fingerprint: str,
        expected_revision: int,
        items: list[dict[str, Any]],
        now: datetime,
    ) -> None:
        await self._rpc(
            "cancel_assignment_series_future_v1",
            params={
                "p_user_id": user_id,
                "p_series_id": str(series_id),
                "p_request_id": str(request_id),
                "p_request_fingerprint": request_fingerprint,
                "p_expected_revision": expected_revision,
                "p_items": items,
                "p_now": now.isoformat(),
            },
        )

    async def _rpc(self, function: str, *, params: dict[str, Any]) -> dict[str, Any]:
        try:
            result = await self._client.rpc(function, params=params)
        except httpx.HTTPStatusError as exc:
            code, message = _postgres_error(exc)
            if code in {"23505", "40001", "PT409"}:
                raise DeadlinePlanPersistenceConflict(message) from exc
            if code in {"PT404", "22023"} and "unavailable" in message.lower():
                raise DeadlinePlanPersistenceNotFound(message) from exc
            raise
        if not isinstance(result, dict):
            raise ValueError(f"Assignment series RPC {function} returned a non-object.")
        return result


def _postgres_error(exc: httpx.HTTPStatusError) -> tuple[str | None, str]:
    try:
        payload = exc.response.json()
    except ValueError:
        return None, "Assignment series persistence failed."
    if not isinstance(payload, dict):
        return None, "Assignment series persistence failed."
    code = payload.get("code") if isinstance(payload.get("code"), str) else None
    message = payload.get("message")
    return code, message if isinstance(message, str) else "Persistence failed."
