from __future__ import annotations

from dataclasses import dataclass, field
from datetime import date, datetime, timedelta
from typing import Any, Protocol

from app.clients.supabase import SupabaseRestClient
from app.repositories.repository_pagination import select_offset_pages


@dataclass(frozen=True, slots=True)
class WeekPreparationRows:
    plans: list[dict[str, Any]]
    blocks: list[dict[str, Any]]
    revisions: list[dict[str, Any]] = field(default_factory=list)
    credit_blocks: list[dict[str, Any]] = field(default_factory=list)
    focus_facts: list[dict[str, Any]] = field(default_factory=list)


@dataclass(frozen=True, slots=True)
class WeekCalendarRows:
    source_label: str | None
    events: list[dict[str, Any]]


@dataclass(frozen=True, slots=True)
class WeekTaskRows:
    plans: list[dict[str, Any]]
    blocks: list[dict[str, Any]]
    tasks: list[dict[str, Any]]


@dataclass(frozen=True, slots=True)
class WeekHabitRows:
    plans: list[dict[str, Any]]
    slots: list[dict[str, Any]]
    habits: list[dict[str, Any]]
    logs: list[dict[str, Any]]


class TodayWeekAgendaRepository(Protocol):
    async def get_profile_timezone(self, *, user_id: str) -> str: ...

    async def list_setup(self, *, user_id: str) -> list[dict[str, Any]]: ...

    async def load_preparation(
        self,
        *,
        user_id: str,
        week_starts_on: date,
        week_ends_on: date,
    ) -> WeekPreparationRows: ...

    async def load_calendar(
        self,
        *,
        user_id: str,
        week_starts_on: date,
        week_ends_on: date,
        range_starts_at: datetime,
        range_ends_at: datetime,
    ) -> WeekCalendarRows: ...

    async def list_focus(
        self,
        *,
        user_id: str,
        range_starts_at: datetime,
        range_ends_at: datetime,
    ) -> list[dict[str, Any]]: ...

    async def load_tasks(
        self,
        *,
        user_id: str,
        week_starts_on: date,
        week_ends_on: date,
    ) -> WeekTaskRows: ...

    async def load_habits(
        self,
        *,
        user_id: str,
        week_starts_on: date,
        week_ends_on: date,
    ) -> WeekHabitRows: ...

    async def list_fixed_commitments(
        self,
        *,
        user_id: str,
        range_starts_at: datetime,
        range_ends_at: datetime,
    ) -> list[dict[str, Any]]: ...


class SupabaseTodayWeekAgendaRepository:
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
        if len(rows) != 1:
            raise ValueError("Week agenda profile is unavailable.")
        timezone = rows[0].get("timezone")
        if not isinstance(timezone, str) or not timezone.strip():
            raise ValueError("Week agenda profile timezone is invalid.")
        return timezone

    async def list_setup(self, *, user_id: str) -> list[dict[str, Any]]:
        return await self._pages(
            "schedule_items",
            params={
                "select": "id,title,location,weekday,starts_at,ends_at,source,metadata",
                "user_id": f"eq.{user_id}",
                "order": "weekday.asc,starts_at.asc,id.asc",
            },
            max_rows=1_001,
        )

    async def load_preparation(
        self,
        *,
        user_id: str,
        week_starts_on: date,
        week_ends_on: date,
    ) -> WeekPreparationRows:
        plans = await self._pages(
            "deadline_plans",
            params={
                "select": "id,title,status,current_revision,managed_task_id,"
                "first_activated_at",
                "user_id": f"eq.{user_id}",
                "status": "in.(active,completed)",
                "order": "id.asc",
            },
            max_rows=1_001,
        )
        if not plans:
            return WeekPreparationRows(plans=[], blocks=[])
        blocks = await self._pages(
            "deadline_plan_blocks",
            params=[
                (
                    "select",
                    "id,plan_id,revision,local_date,starts_at,ends_at,"
                    "planned_minutes,reservation_state",
                ),
                ("user_id", f"eq.{user_id}"),
                ("reservation_state", "in.(active,superseded)"),
                ("local_date", f"gte.{week_starts_on.isoformat()}"),
                ("local_date", f"lte.{week_ends_on.isoformat()}"),
                ("order", "local_date.asc,starts_at.asc,id.asc"),
            ],
            max_rows=10_001,
        )
        plan_revisions = {
            (str(row.get("id")), row.get("current_revision")) for row in plans
        }
        revision_rows = await self._pages(
            "deadline_plan_revisions",
            params={
                "select": "plan_id,revision,state,tracked_focus_minutes_at_proposal",
                "user_id": f"eq.{user_id}",
                "state": "eq.active",
                "order": "plan_id.asc,revision.asc",
            },
            max_rows=1_001,
        )
        revisions = [
            row
            for row in revision_rows
            if (str(row.get("plan_id")), row.get("revision")) in plan_revisions
        ]
        credit_block_rows = await self._pages(
            "deadline_plan_blocks",
            params={
                "select": "id,plan_id,revision,sequence,local_date,starts_at,"
                "ends_at,planned_minutes,reservation_state",
                "user_id": f"eq.{user_id}",
                "reservation_state": "in.(active,superseded)",
                "order": "plan_id.asc,revision.asc,sequence.asc,id.asc",
            },
            max_rows=120_001,
        )
        credit_blocks = [
            row
            for row in credit_block_rows
            if (str(row.get("plan_id")), row.get("revision")) in plan_revisions
        ]

        task_to_plan = {
            str(row.get("managed_task_id")): str(row.get("id"))
            for row in plans
            if row.get("managed_task_id") is not None
        }
        focus_rows: list[dict[str, Any]] = []
        first_activated = [
            row.get("first_activated_at")
            for row in plans
            if row.get("first_activated_at") is not None
        ]
        if task_to_plan and first_activated:
            earliest = min(
                _aware_datetime(value) for value in first_activated
            ).isoformat()
            candidate_focus_rows = await self._pages(
                "focus_sessions",
                params={
                    "select": "id,task_id,started_at,actual_minutes,status",
                    "user_id": f"eq.{user_id}",
                    "status": "eq.completed",
                    "started_at": f"gte.{earliest}",
                    "order": "started_at.asc,id.asc",
                },
                max_rows=10_001,
            )
            focus_rows = [
                row
                for row in candidate_focus_rows
                if str(row.get("task_id")) in task_to_plan
            ]
        sources_by_focus: dict[str, str | None] = {}
        focus_ids = {str(row.get("id")) for row in focus_rows}
        if focus_ids:
            source_rows = await self._pages(
                "focus_session_schedule_sources",
                params={
                    "select": "focus_session_id,deadline_plan_block_id",
                    "user_id": f"eq.{user_id}",
                    "source_kind": "eq.deadline_plan_block",
                    "created_at": f"gte.{earliest}",
                    "order": "focus_session_id.asc",
                },
                max_rows=10_001,
            )
            for row in source_rows:
                focus_id = str(row.get("focus_session_id"))
                if focus_id not in focus_ids:
                    continue
                if focus_id in sources_by_focus:
                    raise ValueError(
                        "Week agenda Preparation provenance is ambiguous.",
                    )
                block_id = row.get("deadline_plan_block_id")
                sources_by_focus[focus_id] = (
                    str(block_id) if block_id is not None else None
                )
        focus_facts = [
            {
                "id": row.get("id"),
                "plan_id": task_to_plan.get(str(row.get("task_id"))),
                "started_at": row.get("started_at"),
                "actual_minutes": row.get("actual_minutes"),
                "deadline_plan_block_id": sources_by_focus.get(str(row.get("id"))),
            }
            for row in focus_rows
        ]
        return WeekPreparationRows(
            plans=plans,
            blocks=blocks,
            revisions=revisions,
            credit_blocks=credit_blocks,
            focus_facts=focus_facts,
        )

    async def load_calendar(
        self,
        *,
        user_id: str,
        week_starts_on: date,
        week_ends_on: date,
        range_starts_at: datetime,
        range_ends_at: datetime,
    ) -> WeekCalendarRows:
        connections = await self._client.select(
            "calendar_connections",
            params={
                "select": "id,source_label,status,last_import_id,imported_data_deleted_at",
                "user_id": f"eq.{user_id}",
                "status": "eq.connected",
                "imported_data_deleted_at": "is.null",
                "order": "created_at.desc,id.desc",
                "limit": "2",
            },
        )
        if not connections:
            return WeekCalendarRows(source_label=None, events=[])
        if len(connections) != 1:
            raise ValueError("Week agenda calendar connection is ambiguous.")
        connection = connections[0]
        source_label = connection.get("source_label")
        if not isinstance(source_label, str) or not source_label.strip():
            raise ValueError("Week agenda calendar source label is invalid.")
        import_id = connection.get("last_import_id")
        if import_id is None:
            raise ValueError("Week agenda calendar import is not current.")
        imports = await self._client.select(
            "calendar_imports",
            params={
                "select": "id,planning_status",
                "id": f"eq.{import_id}",
                "user_id": f"eq.{user_id}",
                "connection_id": f"eq.{connection['id']}",
                "limit": "2",
            },
        )
        if len(imports) != 1 or imports[0].get("planning_status") != "current":
            raise ValueError("Week agenda calendar import is not current.")
        week_ends_exclusive = week_ends_on + timedelta(days=1)
        overlap_filter = (
            "(and(event_kind.eq.timed,"
            f"starts_at.lt.{range_ends_at.isoformat()},"
            f"ends_at.gt.{range_starts_at.isoformat()}),"
            "and(event_kind.eq.all_day,"
            f"starts_on.lt.{week_ends_exclusive.isoformat()},"
            f"ends_on.gt.{week_starts_on.isoformat()}))"
        )
        events = await self._pages(
            "calendar_events",
            params=[
                (
                    "select",
                    "id,title,location,event_kind,busy_status,event_status,"
                    "starts_at,ends_at,starts_on,ends_on,import_id",
                ),
                ("user_id", f"eq.{user_id}"),
                ("connection_id", f"eq.{connection['id']}"),
                ("import_id", f"eq.{import_id}"),
                ("or", overlap_filter),
                ("order", "sort_date.asc,sort_time.asc,id.asc"),
            ],
            max_rows=5_001,
        )
        return WeekCalendarRows(source_label=source_label, events=events)

    async def list_focus(
        self,
        *,
        user_id: str,
        range_starts_at: datetime,
        range_ends_at: datetime,
    ) -> list[dict[str, Any]]:
        return await self._pages(
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
                ("started_at", f"lt.{(range_ends_at + timedelta(days=1)).isoformat()}"),
                ("order", "started_at.asc,id.asc"),
            ],
            max_rows=5_001,
        )

    async def load_tasks(
        self,
        *,
        user_id: str,
        week_starts_on: date,
        week_ends_on: date,
    ) -> WeekTaskRows:
        plans = await self._active_plans(user_id=user_id, target_kind="task")
        blocks = await self._pages(
            "planner_task_blocks",
            params=[
                (
                    "select",
                    "id,plan_id,revision,local_date,starts_at,ends_at,"
                    "planned_minutes,state",
                ),
                ("user_id", f"eq.{user_id}"),
                ("state", "eq.active"),
                ("local_date", f"gte.{week_starts_on.isoformat()}"),
                ("local_date", f"lte.{week_ends_on.isoformat()}"),
                ("order", "local_date.asc,starts_at.asc,id.asc"),
            ],
            max_rows=10_001,
        )
        tasks = await self._pages(
            "tasks",
            params={
                "select": "id,title,description,status,source",
                "user_id": f"eq.{user_id}",
                "order": "created_at.asc,id.asc",
            },
            max_rows=1_001,
        )
        return WeekTaskRows(plans=plans, blocks=blocks, tasks=tasks)

    async def load_habits(
        self,
        *,
        user_id: str,
        week_starts_on: date,
        week_ends_on: date,
    ) -> WeekHabitRows:
        plans = await self._active_plans(user_id=user_id, target_kind="habit")
        slots = await self._pages(
            "planner_habit_slots",
            params={
                "select": "id,plan_id,revision,weekday,starts_at,ends_at,"
                "duration_minutes,state",
                "user_id": f"eq.{user_id}",
                "state": "eq.active",
                "order": "weekday.asc,starts_at.asc,id.asc",
            },
            max_rows=5_001,
        )
        habits = await self._pages(
            "habits",
            params={
                "select": "id,title,description,frequency,target,active,metadata",
                "user_id": f"eq.{user_id}",
                "active": "eq.true",
                "order": "created_at.asc,id.asc",
            },
            max_rows=1_001,
        )
        logs = await self._pages(
            "habit_logs",
            params=[
                ("select", "id,habit_id,entry_date,status,value"),
                ("user_id", f"eq.{user_id}"),
                ("entry_date", f"gte.{week_starts_on.isoformat()}"),
                ("entry_date", f"lte.{week_ends_on.isoformat()}"),
                ("order", "entry_date.asc,habit_id.asc,id.asc"),
            ],
            max_rows=5_001,
        )
        return WeekHabitRows(plans=plans, slots=slots, habits=habits, logs=logs)

    async def list_fixed_commitments(
        self,
        *,
        user_id: str,
        range_starts_at: datetime,
        range_ends_at: datetime,
    ) -> list[dict[str, Any]]:
        overlap_filter = (
            "(recurrence.eq.weekly,"
            "and(recurrence.eq.one_off,"
            f"starts_at.lt.{range_ends_at.isoformat()},"
            f"ends_at.gt.{range_starts_at.isoformat()}))"
        )
        return await self._pages(
            "planner_commitments",
            params=[
                (
                    "select",
                    "id,title,location,recurrence,status,starts_at,ends_at,"
                    "weekday,local_starts_at,local_ends_at",
                ),
                ("user_id", f"eq.{user_id}"),
                ("status", "eq.active"),
                ("or", overlap_filter),
                ("order", "created_at.asc,id.asc"),
            ],
            max_rows=1_001,
        )

    async def _active_plans(
        self,
        *,
        user_id: str,
        target_kind: str,
    ) -> list[dict[str, Any]]:
        return await self._pages(
            "planner_action_plans",
            params={
                "select": "id,target_kind,target_id,status,current_revision",
                "user_id": f"eq.{user_id}",
                "target_kind": f"eq.{target_kind}",
                "status": "eq.active",
                "order": "created_at.asc,id.asc",
            },
            max_rows=1_001,
        )

    async def _pages(
        self,
        table: str,
        *,
        params: dict[str, Any] | list[tuple[str, str]],
        max_rows: int,
    ) -> list[dict[str, Any]]:
        return await select_offset_pages(
            self._client,
            table,
            params=params,
            page_size=self._page_size,
            max_rows=max_rows,
            overfull_error="PostgREST returned more Week agenda rows than requested.",
        )


def _aware_datetime(value: object) -> datetime:
    if isinstance(value, datetime):
        parsed = value
    elif isinstance(value, str):
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    else:
        raise ValueError("Week agenda Preparation timestamp is invalid.")
    if parsed.tzinfo is None or parsed.utcoffset() is None:
        raise ValueError("Week agenda Preparation timestamp must be aware.")
    return parsed
