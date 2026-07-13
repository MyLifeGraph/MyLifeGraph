import asyncio
from dataclasses import dataclass
from typing import Any, Protocol

from app.clients.supabase import SupabaseRestClient


@dataclass(frozen=True)
class BoundedRows:
    available_count: int
    rows: list[dict[str, Any]]


@dataclass(frozen=True)
class CoachProfileContext:
    timezone: str
    role: str = "user"
    auth_provider: str = "email"

    @property
    def is_eligible_authenticated_account(self) -> bool:
        return self.role in {"user", "vip", "admin"} and self.auth_provider not in {
            "anonymous",
            "guest",
        }


@dataclass(frozen=True)
class CoachRawContext:
    profile: CoachProfileContext
    onboarding_snapshot: dict[str, Any] | None
    daily_snapshot: dict[str, Any] | None
    goals: BoundedRows
    tasks: BoundedRows
    habits: BoundedRows
    focus_sessions: BoundedRows
    selected_memories: BoundedRows
    history: BoundedRows


class CoachContextRepository(Protocol):
    async def get_profile(self, *, user_id: str) -> CoachProfileContext:
        pass

    async def load_today_context(
        self,
        *,
        user_id: str,
        local_date: str,
    ) -> CoachRawContext:
        pass


class SupabaseCoachContextRepository:
    _GOAL_CAP = 6
    _TASK_CAP = 10
    _HABIT_CAP = 8
    _FOCUS_CAP = 6
    _MEMORY_CAP = 8
    _HISTORY_CAP = 6

    def __init__(self, client: SupabaseRestClient) -> None:
        self._client = client

    async def get_profile(self, *, user_id: str) -> CoachProfileContext:
        rows = await self._client.select(
            "profiles",
            params={
                "select": "timezone,role,auth_provider",
                "id": f"eq.{user_id}",
                "limit": "1",
            },
        )
        if not rows:
            raise ValueError("Profile is unavailable for Coach context.")
        timezone = rows[0].get("timezone")
        if not isinstance(timezone, str) or not timezone.strip():
            raise ValueError("Profile timezone is invalid.")
        role = rows[0].get("role")
        if role not in {"user", "vip", "admin", "guest"}:
            raise ValueError("Profile role is invalid.")
        auth_provider = rows[0].get("auth_provider")
        if not isinstance(auth_provider, str) or not auth_provider.strip():
            raise ValueError("Profile auth provider is invalid.")
        return CoachProfileContext(
            timezone=timezone,
            role=role,
            auth_provider=auth_provider.strip().lower(),
        )

    async def load_today_context(
        self,
        *,
        user_id: str,
        local_date: str,
    ) -> CoachRawContext:
        (
            profile,
            onboarding,
            snapshot,
            goals,
            tasks,
            habits,
            focus,
            memories,
            history,
        ) = await asyncio.gather(
            self.get_profile(user_id=user_id),
            self._onboarding_snapshot(user_id=user_id),
            self._daily_snapshot(user_id=user_id, local_date=local_date),
            self._bounded(
                "goals",
                params=[
                    ("select", "id,title,status,progress,due_date,updated_at"),
                    ("user_id", f"eq.{user_id}"),
                    ("status", "eq.active"),
                    ("order", "updated_at.desc,id.asc"),
                ],
                cap=self._GOAL_CAP,
            ),
            self._bounded(
                "tasks",
                params=[
                    (
                        "select",
                        "id,title,status,priority,deadline,"
                        "estimated_minutes,updated_at",
                    ),
                    ("user_id", f"eq.{user_id}"),
                    ("status", "in.(todo,in_progress)"),
                    ("order", "deadline.asc.nullslast,created_at.asc,id.asc"),
                ],
                cap=self._TASK_CAP,
            ),
            self._bounded(
                "habits",
                params=[
                    (
                        "select",
                        "id,title,frequency,target,active,metadata,updated_at",
                    ),
                    ("user_id", f"eq.{user_id}"),
                    ("active", "eq.true"),
                    ("order", "updated_at.desc,id.asc"),
                ],
                cap=self._HABIT_CAP,
            ),
            self._bounded(
                "focus_sessions",
                params=[
                    (
                        "select",
                        "id,status,task_id,habit_id,planned_minutes,actual_minutes,"
                        "started_at,ended_at,updated_at",
                    ),
                    ("user_id", f"eq.{user_id}"),
                    ("order", "started_at.desc,id.asc"),
                ],
                cap=self._FOCUS_CAP,
            ),
            self._selected_memories(user_id=user_id),
            self._history(user_id=user_id),
        )
        return CoachRawContext(
            profile=profile,
            onboarding_snapshot=onboarding,
            daily_snapshot=snapshot,
            goals=goals,
            tasks=tasks,
            habits=habits,
            focus_sessions=focus,
            selected_memories=memories,
            history=history,
        )

    async def _onboarding_snapshot(
        self,
        *,
        user_id: str,
    ) -> dict[str, Any] | None:
        rows = await self._client.select(
            "user_state_snapshots",
            params={
                "select": "summary,generated_at",
                "user_id": f"eq.{user_id}",
                "scope": "eq.onboarding",
                "period_key": "eq.setup:intake-v1",
                "order": "generated_at.desc,id.desc",
                "limit": "1",
            },
        )
        return rows[0] if rows else None

    async def _daily_snapshot(
        self,
        *,
        user_id: str,
        local_date: str,
    ) -> dict[str, Any] | None:
        rows = await self._client.select(
            "user_state_snapshots",
            params={
                "select": "id,period_key,summary,generated_at,metadata",
                "user_id": f"eq.{user_id}",
                "scope": "eq.daily",
                "period_key": f"eq.{local_date}",
                "limit": "1",
            },
        )
        return rows[0] if rows else None

    async def _selected_memories(self, *, user_id: str) -> BoundedRows:
        selections = await self._client.select(
            "coach_memory_selections",
            params={
                "select": "memory_id,selected_at",
                "user_id": f"eq.{user_id}",
                "order": "selected_at.desc,memory_id.asc",
                "limit": str(self._MEMORY_CAP + 1),
            },
        )
        selections = selections[: self._MEMORY_CAP]
        if not selections:
            return BoundedRows(available_count=0, rows=[])
        selection_by_id = {
            str(row.get("memory_id")): row.get("selected_at") for row in selections
        }
        ids = list(selection_by_id)
        memories = await self._client.select(
            "memory_entries",
            params={
                "select": "id,type,title,content,metadata,updated_at",
                "user_id": f"eq.{user_id}",
                "type": "neq.preference",
                "id": f"in.({','.join(ids)})",
                "limit": str(self._MEMORY_CAP),
            },
        )
        by_id = {str(row.get("id")): row for row in memories}
        ordered = [
            {**by_id[memory_id], "selected_at": selection_by_id[memory_id]}
            for memory_id in ids
            if memory_id in by_id
        ]
        return BoundedRows(available_count=len(ordered), rows=ordered)

    async def _history(self, *, user_id: str) -> BoundedRows:
        requests: list[dict[str, Any]] = []
        available_count = 0
        offset = 0
        page_size = 200
        while True:
            page = await self._client.select(
                "coach_requests",
                params={
                    "select": "request_id,response,completed_at",
                    "user_id": f"eq.{user_id}",
                    "state": "eq.completed",
                    "order": "completed_at.desc,request_id.asc",
                    "limit": str(page_size),
                    "offset": str(offset),
                },
            )
            available_count += len(page)
            if len(requests) < self._HISTORY_CAP:
                requests.extend(page[: self._HISTORY_CAP - len(requests)])
            if len(page) < page_size:
                break
            offset += len(page)
        if not requests:
            return BoundedRows(available_count=0, rows=[])
        ids = [str(row.get("request_id")) for row in requests]
        messages = await self._client.select(
            "coach_messages",
            params={
                "select": "request_id,content",
                "user_id": f"eq.{user_id}",
                "role": "eq.user",
                "request_id": f"in.({','.join(ids)})",
                "limit": str(self._HISTORY_CAP),
            },
        )
        message_by_id = {
            str(row.get("request_id")): row.get("content") for row in messages
        }
        rows = [
            {**row, "message": message_by_id.get(str(row.get("request_id")))}
            for row in reversed(requests)
            if isinstance(message_by_id.get(str(row.get("request_id"))), str)
        ]
        return BoundedRows(available_count=available_count, rows=rows)

    async def _bounded(
        self,
        table: str,
        *,
        params: list[tuple[str, str]],
        cap: int,
    ) -> BoundedRows:
        rows: list[dict[str, Any]] = []
        available_count = 0
        offset = 0
        page_size = 200
        while True:
            page = await self._client.select(
                table,
                params=[
                    *params,
                    ("limit", str(page_size)),
                    ("offset", str(offset)),
                ],
            )
            available_count += len(page)
            if len(rows) < cap:
                rows.extend(page[: cap - len(rows)])
            if len(page) < page_size:
                break
            offset += len(page)
        return BoundedRows(available_count=available_count, rows=rows)
