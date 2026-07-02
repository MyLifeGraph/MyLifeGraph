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
        start_datetime = datetime.combine(
            start_date,
            time.min,
            tzinfo=timezone.utc,
        )
        end_datetime = datetime.combine(
            target_date + timedelta(days=1),
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
                    "source,updated_at",
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
                ("select", "id,event_type,value,unit,occurred_at,source"),
                ("user_id", f"eq.{user_id}"),
                ("occurred_at", f"gte.{start_datetime.isoformat()}"),
                ("occurred_at", f"lt.{end_datetime.isoformat()}"),
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
                "select": "id,title,frequency,active,updated_at",
                "user_id": f"eq.{user_id}",
                "order": "updated_at.desc",
                "limit": "50",
            },
        )
        schedule_items = await self._client.select(
            "schedule_items",
            params={
                "select": "id,title,weekday,starts_at,ends_at,source,updated_at",
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
            schedule_items=schedule_items,
            memory_entries=memory_entries,
        )

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
