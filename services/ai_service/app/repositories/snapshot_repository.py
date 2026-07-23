from dataclasses import dataclass
from datetime import date, datetime, time, timedelta, timezone
from typing import Any, Protocol

from app.clients.supabase import SupabaseRestClient


@dataclass(frozen=True)
class SnapshotInputRows:
    daily_logs: list[dict[str, Any]]
    behavioral_events: list[dict[str, Any]]
    tasks: list[dict[str, Any]]
    goals: list[dict[str, Any]]
    habits: list[dict[str, Any]]
    habit_logs: list[dict[str, Any]]
    focus_sessions: list[dict[str, Any]]
    schedule_items: list[dict[str, Any]]
    memory_entries: list[dict[str, Any]]


class SnapshotRepository(Protocol):
    async def load_snapshot_inputs(
        self,
        *,
        user_id: str,
        target_date: date,
        window_days: int,
    ) -> SnapshotInputRows:
        pass

    async def persist_user_state_snapshot(
        self,
        *,
        user_id: str,
        scope: str,
        period_key: str,
        row: dict[str, Any],
    ) -> dict[str, Any]:
        pass


class SupabaseSnapshotRepository:
    def __init__(self, client: SupabaseRestClient) -> None:
        self._client = client

    async def load_snapshot_inputs(
        self,
        *,
        user_id: str,
        target_date: date,
        window_days: int,
    ) -> SnapshotInputRows:
        start_date = target_date - timedelta(days=window_days - 1)
        event_start_datetime = datetime.combine(
            start_date - timedelta(days=1),
            time.min,
            tzinfo=timezone.utc,
        )
        event_end_datetime = datetime.combine(
            target_date + timedelta(days=2),
            time.min,
            tzinfo=timezone.utc,
        )
        focus_start_datetime = datetime.combine(
            start_date - timedelta(days=1),
            time.min,
            tzinfo=timezone.utc,
        )
        focus_end_datetime = datetime.combine(
            target_date + timedelta(days=2),
            time.min,
            tzinfo=timezone.utc,
        )
        daily_logs = await self._client.select(
            "daily_logs",
            params=[
                (
                    "select",
                    "id,entry_date,sleep_hours,steps,activity_level,"
                    "focus_minutes,mood_score,energy_level,stress_level,"
                    "source,metadata,updated_at",
                ),
                ("user_id", f"eq.{user_id}"),
                ("entry_date", f"gte.{start_date.isoformat()}"),
                ("entry_date", f"lte.{target_date.isoformat()}"),
                ("order", "entry_date.desc"),
                ("limit", str(max(window_days, 1))),
            ],
        )
        behavioral_events = await self._client.select(
            "behavioral_events",
            params=[
                (
                    "select",
                    "id,event_type,value,unit,occurred_at,source,metadata",
                ),
                ("user_id", f"eq.{user_id}"),
                ("occurred_at", f"gte.{event_start_datetime.isoformat()}"),
                ("occurred_at", f"lt.{event_end_datetime.isoformat()}"),
                ("order", "occurred_at.desc"),
                ("limit", "200"),
            ],
        )
        tasks = await self._client.select(
            "tasks",
            params={
                "select": "id,status,priority,deadline,metadata,updated_at",
                "user_id": f"eq.{user_id}",
                "order": "deadline.asc.nullslast,updated_at.desc",
                "limit": "100",
            },
        )
        goals = await self._client.select(
            "goals",
            params={
                "select": "id,title,status,progress,due_date,updated_at",
                "user_id": f"eq.{user_id}",
                "order": "updated_at.desc",
                "limit": "50",
            },
        )
        habits = await self._client.select(
            "habits",
            params={
                "select": "id,title,frequency,target,active,metadata,updated_at",
                "user_id": f"eq.{user_id}",
                "order": "updated_at.desc",
                "limit": "50",
            },
        )
        habit_logs = await self._select_all_pages(
            "habit_logs",
            params=[
                (
                    "select",
                    "id,habit_id,entry_date,status,value,created_at",
                ),
                ("user_id", f"eq.{user_id}"),
                ("entry_date", f"gte.{start_date.isoformat()}"),
                ("entry_date", f"lte.{target_date.isoformat()}"),
                ("order", "entry_date.desc,created_at.desc,id.asc"),
            ],
        )
        focus_sessions = await self._select_all_pages(
            "focus_sessions",
            params=[
                (
                    "select",
                    "id,status,started_at,ended_at,planned_minutes,"
                    "actual_minutes,task_id,habit_id,metadata,created_at,updated_at",
                ),
                ("user_id", f"eq.{user_id}"),
                ("started_at", f"gte.{focus_start_datetime.isoformat()}"),
                ("started_at", f"lt.{focus_end_datetime.isoformat()}"),
                ("order", "started_at.desc,id.asc"),
            ],
        )
        schedule_items = await self._client.select(
            "schedule_items",
            params={
                "select": (
                    "id,title,weekday,starts_at,ends_at,source,updated_at,metadata"
                ),
                "user_id": f"eq.{user_id}",
                "order": "weekday.asc,starts_at.asc",
                "limit": "50",
            },
        )
        memory_entries = await self._client.select(
            "memory_entries",
            params={
                "select": "id,type,title,strength,last_seen_at,updated_at",
                "user_id": f"eq.{user_id}",
                "order": "last_seen_at.desc",
                "limit": "50",
            },
        )

        return SnapshotInputRows(
            daily_logs=daily_logs,
            behavioral_events=behavioral_events,
            tasks=tasks,
            goals=goals,
            habits=habits,
            habit_logs=habit_logs,
            focus_sessions=focus_sessions,
            schedule_items=schedule_items,
            memory_entries=memory_entries,
        )

    async def _select_all_pages(
        self,
        table: str,
        *,
        params: list[tuple[str, str]],
        page_size: int = 1000,
    ) -> list[dict[str, Any]]:
        rows: list[dict[str, Any]] = []
        offset = 0
        while True:
            page = await self._client.select(
                table,
                params=[
                    *params,
                    ("limit", str(page_size)),
                    ("offset", str(offset)),
                ],
            )
            rows.extend(page)
            if len(page) < page_size:
                return rows
            offset += len(page)

    async def persist_user_state_snapshot(
        self,
        *,
        user_id: str,
        scope: str,
        period_key: str,
        row: dict[str, Any],
    ) -> dict[str, Any]:
        upserted = await self._client.upsert(
            "user_state_snapshots",
            rows=[row],
            on_conflict="user_id,scope,period_key",
        )
        return upserted[0]
