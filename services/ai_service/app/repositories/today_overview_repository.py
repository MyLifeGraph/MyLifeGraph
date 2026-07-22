from __future__ import annotations

from dataclasses import dataclass
from datetime import date, datetime, timedelta
from typing import Any, Protocol

from app.clients.supabase import SupabaseRestClient


@dataclass(frozen=True)
class TodayHabitRows:
    habits: list[dict[str, Any]]
    logs: list[dict[str, Any]]


@dataclass(frozen=True)
class TodayCalendarRows:
    source_label: str | None
    events: list[dict[str, Any]]


class TodayOverviewRepository(Protocol):
    async def get_profile_timezone(self, *, user_id: str) -> str: ...

    async def list_daily_logs_page(
        self,
        *,
        user_id: str,
        offset: int,
        limit: int,
    ) -> list[dict[str, Any]]: ...

    async def list_tasks(self, *, user_id: str) -> list[dict[str, Any]]: ...

    async def load_habits(
        self,
        *,
        user_id: str,
        week_starts_on: date,
        local_date: date,
    ) -> TodayHabitRows: ...

    async def list_schedule_items(
        self,
        *,
        user_id: str,
    ) -> list[dict[str, Any]]: ...

    async def list_focus_sessions(
        self,
        *,
        user_id: str,
        range_starts_at: datetime,
        range_ends_at: datetime,
    ) -> list[dict[str, Any]]: ...

    async def load_current_calendar(
        self,
        *,
        user_id: str,
    ) -> TodayCalendarRows: ...


class SupabaseTodayOverviewRepository:
    _page_size = 1_000

    def __init__(self, client: SupabaseRestClient) -> None:
        self._client = client

    async def get_profile_timezone(self, *, user_id: str) -> str:
        rows = await self._client.select(
            "profiles",
            params={
                "select": "timezone",
                "id": f"eq.{user_id}",
                "limit": "1",
            },
        )
        if not rows:
            raise ValueError("Today profile is unavailable.")
        timezone = rows[0].get("timezone")
        if not isinstance(timezone, str) or not timezone.strip():
            raise ValueError("Today profile timezone is invalid.")
        return timezone

    async def list_daily_logs_page(
        self,
        *,
        user_id: str,
        offset: int,
        limit: int,
    ) -> list[dict[str, Any]]:
        return await self._client.select(
            "daily_logs",
            params={
                "select": "id,entry_date,sleep_hours,mood_score,energy_level,"
                "stress_level,source,metadata,updated_at",
                "user_id": f"eq.{user_id}",
                "order": "entry_date.desc,id.asc",
                "offset": str(offset),
                "limit": str(limit),
            },
        )

    async def list_tasks(self, *, user_id: str) -> list[dict[str, Any]]:
        return await self._select_pages(
            "tasks",
            params={
                "select": "id,title,description,status,priority,deadline,"
                "estimated_minutes,completed_at,source,metadata,updated_at",
                "user_id": f"eq.{user_id}",
                "status": "neq.archived",
                "order": "updated_at.desc,id.asc",
            },
            max_rows=1_001,
        )

    async def load_habits(
        self,
        *,
        user_id: str,
        week_starts_on: date,
        local_date: date,
    ) -> TodayHabitRows:
        habits = await self._select_pages(
            "habits",
            params={
                "select": "id,title,description,frequency,target,active,metadata,"
                "created_at,updated_at",
                "user_id": f"eq.{user_id}",
                "active": "eq.true",
                "order": "updated_at.desc,id.asc",
            },
            max_rows=501,
        )
        logs = await self._select_pages(
            "habit_logs",
            params=[
                (
                    "select",
                    "id,habit_id,entry_date,status,value,created_at,updated_at",
                ),
                ("user_id", f"eq.{user_id}"),
                ("entry_date", f"gte.{week_starts_on.isoformat()}"),
                ("entry_date", f"lte.{local_date.isoformat()}"),
                ("order", "entry_date.asc,habit_id.asc,id.asc"),
            ],
            max_rows=5_001,
        )
        return TodayHabitRows(habits=habits, logs=logs)

    async def list_schedule_items(
        self,
        *,
        user_id: str,
    ) -> list[dict[str, Any]]:
        return await self._select_pages(
            "schedule_items",
            params={
                "select": "id,title,location,weekday,starts_at,ends_at,source",
                "user_id": f"eq.{user_id}",
                "order": "weekday.asc,starts_at.asc,id.asc",
            },
            max_rows=1_001,
        )

    async def list_focus_sessions(
        self,
        *,
        user_id: str,
        range_starts_at: datetime,
        range_ends_at: datetime,
    ) -> list[dict[str, Any]]:
        # A terminal session can cross midnight. The product only permits one
        # active session, and normal planned sessions are bounded to four hours;
        # the extra day also keeps legacy cross-midnight rows visible.
        return await self._select_pages(
            "focus_sessions",
            params=[
                (
                    "select",
                    "id,status,started_at,ended_at,planned_minutes,actual_minutes,"
                    "label,task_id,habit_id,metadata",
                ),
                ("user_id", f"eq.{user_id}"),
                (
                    "started_at",
                    f"gte.{(range_starts_at - timedelta(days=1)).isoformat()}",
                ),
                ("started_at", f"lt.{range_ends_at.isoformat()}"),
                ("order", "started_at.asc,id.asc"),
            ],
            max_rows=1_001,
        )

    async def load_current_calendar(
        self,
        *,
        user_id: str,
    ) -> TodayCalendarRows:
        connections = await self._client.select(
            "calendar_connections",
            params={
                "select": "id,source_label,status,last_import_id,"
                "imported_data_deleted_at",
                "user_id": f"eq.{user_id}",
                "status": "eq.connected",
                "imported_data_deleted_at": "is.null",
                "order": "created_at.desc,id.desc",
                "limit": "2",
            },
        )
        if not connections:
            return TodayCalendarRows(source_label=None, events=[])
        if len(connections) != 1:
            raise ValueError("Today calendar connection projection is ambiguous.")
        connection = connections[0]
        source_label = connection.get("source_label")
        if not isinstance(source_label, str) or not source_label.strip():
            raise ValueError("Today calendar source label is invalid.")
        import_id = connection.get("last_import_id")
        if import_id is None:
            return TodayCalendarRows(source_label=source_label, events=[])
        events = await self._select_pages(
            "calendar_events",
            params={
                "select": "id,title,location,event_kind,busy_status,event_status,"
                "starts_at,ends_at,starts_on,ends_on,import_id",
                "user_id": f"eq.{user_id}",
                "connection_id": f"eq.{connection['id']}",
                "import_id": f"eq.{import_id}",
                "order": "sort_date.asc,sort_time.asc,id.asc",
            },
            max_rows=501,
        )
        return TodayCalendarRows(source_label=source_label, events=events)

    async def _select_pages(
        self,
        table: str,
        *,
        params: dict[str, Any] | list[tuple[str, str]],
        max_rows: int,
    ) -> list[dict[str, Any]]:
        rows: list[dict[str, Any]] = []
        while len(rows) < max_rows:
            page_limit = min(self._page_size, max_rows - len(rows))
            if isinstance(params, list):
                page_params: dict[str, Any] | list[tuple[str, str]] = [
                    *params,
                    ("limit", str(page_limit)),
                    ("offset", str(len(rows))),
                ]
            else:
                page_params = {
                    **params,
                    "limit": str(page_limit),
                    "offset": str(len(rows)),
                }
            page = await self._client.select(table, params=page_params)
            if len(page) > page_limit:
                raise ValueError("PostgREST returned more Today rows than requested.")
            rows.extend(page)
            if len(page) < page_limit:
                break
        return rows
