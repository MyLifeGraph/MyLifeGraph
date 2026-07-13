from dataclasses import dataclass
from datetime import date, datetime
from typing import Any, Literal, Protocol
from uuid import UUID

import httpx

from app.clients.supabase import SupabaseRestClient
from app.models.coach import CoachErrorDetail, CoachResponse


CoachClaimState = Literal[
    "pending",
    "completed",
    "failed",
    "deleted",
    "in_progress",
]


class CoachPersistenceConflict(RuntimeError):
    pass


class CoachPersistenceRateLimited(RuntimeError):
    pass


@dataclass(frozen=True)
class CoachClaimResult:
    state: CoachClaimState
    remaining_requests: int
    response: CoachResponse | None
    error: CoachErrorDetail | None


@dataclass(frozen=True)
class CoachMemoryRows:
    available_count: int
    rows: list[dict[str, Any]]


class CoachRepository(Protocol):
    async def claim_request(
        self,
        *,
        user_id: str,
        request_id: UUID,
        message_fingerprint: str,
        context_scope: str,
        local_date: date,
        provider: str,
        provider_mode: str,
        model_requested: str | None,
        model_source: str,
        prompt_version: str,
        context_version: str,
        claimed_at: datetime,
        lease_expires_at: datetime,
        daily_limit: int,
    ) -> CoachClaimResult:
        pass

    async def complete_request(
        self,
        *,
        user_id: str,
        request_id: UUID,
        user_message: str,
        response: CoachResponse,
        used_context: list[dict[str, Any]],
        usage: dict[str, Any],
        completed_at: datetime,
    ) -> CoachResponse:
        pass

    async def fail_request(
        self,
        *,
        user_id: str,
        request_id: UUID,
        error: CoachErrorDetail,
        usage: dict[str, Any],
        failed_at: datetime,
    ) -> CoachErrorDetail:
        pass

    async def list_history(self, *, user_id: str, limit: int) -> list[dict[str, Any]]:
        pass

    async def list_memories(
        self,
        *,
        user_id: str,
        include_memory_id: UUID | None = None,
    ) -> CoachMemoryRows:
        pass

    async def set_memory_selection(
        self,
        *,
        user_id: str,
        memory_id: UUID,
        selected: bool,
        changed_at: datetime,
    ) -> dict[str, Any]:
        pass

    async def delete_history(self, *, user_id: str, deleted_at: datetime) -> int:
        pass

    async def count_usage(self, *, user_id: str, local_date: date) -> int:
        pass


class SupabaseCoachRepository:
    def __init__(self, client: SupabaseRestClient) -> None:
        self._client = client

    async def claim_request(
        self,
        *,
        user_id: str,
        request_id: UUID,
        message_fingerprint: str,
        context_scope: str,
        local_date: date,
        provider: str,
        provider_mode: str,
        model_requested: str | None,
        model_source: str,
        prompt_version: str,
        context_version: str,
        claimed_at: datetime,
        lease_expires_at: datetime,
        daily_limit: int,
    ) -> CoachClaimResult:
        result = await self._rpc(
            "claim_coach_request_v1",
            params={
                "p_user_id": user_id,
                "p_request_id": str(request_id),
                "p_message_fingerprint": message_fingerprint,
                "p_context_scope": context_scope,
                "p_local_date": local_date.isoformat(),
                "p_provider": provider,
                "p_provider_mode": provider_mode,
                "p_model_requested": model_requested,
                "p_model_source": model_source,
                "p_prompt_version": prompt_version,
                "p_context_version": context_version,
                "p_claimed_at": claimed_at.isoformat(),
                "p_lease_expires_at": lease_expires_at.isoformat(),
                "p_daily_limit": daily_limit,
            },
        )
        if set(result) != {"state", "remaining_requests", "response", "error"}:
            raise ValueError("Coach claim RPC returned an invalid envelope.")
        state = result["state"]
        if state not in {
            "pending",
            "completed",
            "failed",
            "deleted",
            "in_progress",
        }:
            raise ValueError("Coach claim RPC returned an invalid state.")
        remaining = result["remaining_requests"]
        if (
            isinstance(remaining, bool)
            or not isinstance(remaining, int)
            or remaining < 0
        ):
            raise ValueError("Coach claim RPC returned an invalid remaining count.")
        response = (
            CoachResponse.model_validate(result["response"])
            if result["response"] is not None
            else None
        )
        error = (
            CoachErrorDetail.model_validate(result["error"])
            if result["error"] is not None
            else None
        )
        if (state == "completed") != (response is not None):
            raise ValueError("Coach claim response does not match its state.")
        if state in {"failed", "deleted"} and error is None:
            raise ValueError("Terminal Coach claim lacks its error.")
        if state in {"pending", "in_progress"} and (
            response is not None or error is not None
        ):
            raise ValueError("Active Coach claim contains terminal data.")
        return CoachClaimResult(
            state=state,
            remaining_requests=remaining,
            response=response,
            error=error,
        )

    async def complete_request(
        self,
        *,
        user_id: str,
        request_id: UUID,
        user_message: str,
        response: CoachResponse,
        used_context: list[dict[str, Any]],
        usage: dict[str, Any],
        completed_at: datetime,
    ) -> CoachResponse:
        result = await self._rpc(
            "complete_coach_request_v1",
            params={
                "p_user_id": user_id,
                "p_request_id": str(request_id),
                "p_user_message": user_message,
                "p_response": response.model_dump(mode="json"),
                "p_used_context": used_context,
                "p_usage": usage,
                "p_completed_at": completed_at.isoformat(),
            },
        )
        if set(result) != {"state", "response"} or result["state"] != "completed":
            raise ValueError("Coach completion RPC returned an invalid envelope.")
        persisted = CoachResponse.model_validate(result["response"])
        if persisted.request_id != request_id:
            raise ValueError("Coach completion RPC returned another request.")
        return persisted

    async def fail_request(
        self,
        *,
        user_id: str,
        request_id: UUID,
        error: CoachErrorDetail,
        usage: dict[str, Any],
        failed_at: datetime,
    ) -> CoachErrorDetail:
        result = await self._rpc(
            "fail_coach_request_v1",
            params={
                "p_user_id": user_id,
                "p_request_id": str(request_id),
                "p_error": error.model_dump(mode="json"),
                "p_usage": usage,
                "p_failed_at": failed_at.isoformat(),
            },
        )
        if set(result) != {"state", "error"} or result["state"] != "failed":
            raise ValueError("Coach failure RPC returned an invalid envelope.")
        return CoachErrorDetail.model_validate(result["error"])

    async def list_history(self, *, user_id: str, limit: int) -> list[dict[str, Any]]:
        requests = await self._client.select(
            "coach_requests",
            params={
                "select": "request_id,response,created_at",
                "user_id": f"eq.{user_id}",
                "state": "eq.completed",
                "order": "created_at.desc,request_id.asc",
                "limit": str(limit),
            },
        )
        if not requests:
            return []
        request_ids = [str(row.get("request_id")) for row in requests]
        messages = await self._client.select(
            "coach_messages",
            params={
                "select": "request_id,content,created_at",
                "user_id": f"eq.{user_id}",
                "role": "eq.user",
                "request_id": f"in.({','.join(request_ids)})",
                "order": "created_at.asc,id.asc",
                "limit": str(limit),
            },
        )
        by_request = {str(row.get("request_id")): row for row in messages}
        result: list[dict[str, Any]] = []
        for row in reversed(requests):
            request_id = str(row.get("request_id"))
            message = by_request.get(request_id)
            if message is None:
                raise ValueError("Completed Coach request lacks its user message.")
            result.append(
                {
                    "request_id": request_id,
                    "message": message.get("content"),
                    "response": row.get("response"),
                    "created_at": row.get("created_at"),
                },
            )
        return result

    async def list_memories(
        self,
        *,
        user_id: str,
        include_memory_id: UUID | None = None,
    ) -> CoachMemoryRows:
        memories: list[dict[str, Any]] = []
        available_count = 0
        offset = 0
        page_size = 200
        while True:
            page = await self._client.select(
                "memory_entries",
                params=[
                    ("select", "id,type,title,content,metadata,updated_at"),
                    ("user_id", f"eq.{user_id}"),
                    ("type", "neq.preference"),
                    ("order", "updated_at.desc,id.asc"),
                    ("limit", str(page_size)),
                    ("offset", str(offset)),
                ],
            )
            available_count += len(page)
            if len(memories) < 100:
                memories.extend(page[: 100 - len(memories)])
            if len(page) < page_size:
                break
            offset += len(page)
        selections = await self._client.select(
            "coach_memory_selections",
            params={
                "select": "memory_id,selected_at",
                "user_id": f"eq.{user_id}",
                "order": "selected_at.desc,memory_id.asc",
                "limit": "8",
            },
        )
        selected = {
            str(row.get("memory_id")): row.get("selected_at") for row in selections
        }
        by_id = {str(row.get("id")): row for row in memories}
        required_ids = [
            memory_id for memory_id in selected if memory_id not in by_id
        ]
        include_id = str(include_memory_id) if include_memory_id is not None else None
        if include_id is not None and include_id not in by_id and include_id not in required_ids:
            required_ids.append(include_id)
        if required_ids:
            required_rows = await self._client.select(
                "memory_entries",
                params={
                    "select": "id,type,title,content,metadata,updated_at",
                    "user_id": f"eq.{user_id}",
                    "type": "neq.preference",
                    "id": f"in.({','.join(required_ids)})",
                    "limit": str(len(required_ids)),
                },
            )
            by_id.update({str(row.get("id")): row for row in required_rows})
        selected_rows = [
            {**by_id[memory_id], "selected_at": selected[memory_id]}
            for memory_id in selected
            if memory_id in by_id
        ]
        unselected_rows = [
            {**row, "selected_at": None}
            for row in memories
            if str(row.get("id")) not in selected
        ]
        included_ids = {
            str(row.get("id")) for row in [*selected_rows, *unselected_rows]
        }
        explicitly_included_rows = [
            {**by_id[include_id], "selected_at": selected.get(include_id)}
            for include_id in [include_id]
            if include_id is not None
            and include_id in by_id
            and include_id not in included_ids
        ]
        return CoachMemoryRows(
            available_count=available_count,
            rows=[*selected_rows, *unselected_rows, *explicitly_included_rows],
        )

    async def set_memory_selection(
        self,
        *,
        user_id: str,
        memory_id: UUID,
        selected: bool,
        changed_at: datetime,
    ) -> dict[str, Any]:
        result = await self._rpc(
            "set_coach_memory_selection_v1",
            params={
                "p_user_id": user_id,
                "p_memory_id": str(memory_id),
                "p_selected": selected,
                "p_changed_at": changed_at.isoformat(),
            },
        )
        if set(result) != {"state", "selected_count"}:
            raise ValueError("Coach memory RPC returned an invalid envelope.")
        if result["state"] not in {
            "selected",
            "unselected",
            "not_found",
            "limit_reached",
        }:
            raise ValueError("Coach memory RPC returned an invalid state.")
        count = result["selected_count"]
        if isinstance(count, bool) or not isinstance(count, int) or not 0 <= count <= 8:
            raise ValueError("Coach memory RPC returned an invalid count.")
        return result

    async def delete_history(self, *, user_id: str, deleted_at: datetime) -> int:
        result = await self._rpc(
            "delete_coach_history_v1",
            params={
                "p_user_id": user_id,
                "p_deleted_at": deleted_at.isoformat(),
            },
        )
        if set(result) != {"state", "deleted_count"} or result["state"] != "deleted":
            raise ValueError("Coach history deletion RPC returned an invalid envelope.")
        count = result["deleted_count"]
        if isinstance(count, bool) or not isinstance(count, int) or count < 0:
            raise ValueError("Coach history deletion RPC returned an invalid count.")
        return count

    async def count_usage(self, *, user_id: str, local_date: date) -> int:
        requests = await self._client.select(
            "coach_requests",
            params={
                "select": "request_id",
                "user_id": f"eq.{user_id}",
                "local_date": f"eq.{local_date.isoformat()}",
                "limit": "101",
            },
        )
        return len(requests)

    async def _rpc(self, function: str, *, params: dict[str, Any]) -> dict[str, Any]:
        try:
            result = await self._client.rpc(function, params=params)
        except httpx.HTTPStatusError as exc:
            code, message = _postgres_error(exc)
            if code == "PT409":
                raise CoachPersistenceConflict(message) from exc
            if code == "PT429":
                raise CoachPersistenceRateLimited(message) from exc
            raise
        if not isinstance(result, dict):
            raise ValueError(f"Coach RPC {function} returned a non-object.")
        return result

def _postgres_error(exc: httpx.HTTPStatusError) -> tuple[str | None, str]:
    try:
        body = exc.response.json()
    except ValueError:
        return None, "Coach persistence request failed."
    if not isinstance(body, dict):
        return None, "Coach persistence request failed."
    code = body.get("code")
    message = body.get("message")
    return (
        str(code) if code is not None else None,
        str(message) if message is not None else "Coach persistence request failed.",
    )
