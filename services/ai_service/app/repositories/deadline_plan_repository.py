from dataclasses import dataclass
from datetime import date, datetime, timedelta
from typing import Any, Protocol
from uuid import UUID
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

import httpx

from app.clients.supabase import SupabaseRestClient


class DeadlinePlanPersistenceConflict(RuntimeError):
    pass


class DeadlinePlanPersistenceNotFound(RuntimeError):
    pass


@dataclass(frozen=True)
class DeadlinePlanningContext:
    timezone: str
    best_energy_window: str
    schedule_items: list[dict[str, Any]]
    confirmed_blocks: list[dict[str, Any]]
    timed_calendar_events: list[dict[str, Any]]
    all_day_calendar_events: list[dict[str, Any]]
    source_calendar_event: dict[str, Any] | None
    calendar_availability_current: bool
    availability_connection_id: UUID | None
    availability_import_id: UUID | None
    daily_preparation_budget_minutes: int | None = None
    planner_recurring_commitments: list[dict[str, Any]] | None = None
    planner_timed_intervals: list[dict[str, Any]] | None = None
    planner_use_calendar_busy_time: bool | None = None


@dataclass(frozen=True)
class PreparationWorkloadContext:
    timezone: str
    daily_preparation_budget_minutes: int | None
    schedule_items: list[dict[str, Any]]
    confirmed_blocks: list[dict[str, Any]]


@dataclass(frozen=True)
class PreparationWorkloadDetailContext:
    timezone: str
    daily_preparation_budget_minutes: int | None
    confirmed_blocks: list[dict[str, Any]]
    plans: list[dict[str, Any]]


@dataclass(frozen=True)
class DeadlinePlanProjection:
    plans: list[dict[str, Any]]
    revisions: list[dict[str, Any]]
    blocks: list[dict[str, Any]]
    focus_totals: list[dict[str, Any]]
    calendar_events: dict[str, dict[str, Any]]


class DeadlinePlanRepository(Protocol):
    async def get_request_identity(
        self,
        *,
        request_id: UUID,
    ) -> dict[str, Any] | None: ...

    async def load_projection(
        self,
        *,
        user_id: str,
        plan_id: UUID | None,
    ) -> DeadlinePlanProjection: ...

    async def get_plan(
        self,
        *,
        user_id: str,
        plan_id: UUID,
    ) -> dict[str, Any] | None: ...

    async def list_revisions(
        self,
        *,
        user_id: str,
        plan_id: UUID,
    ) -> list[dict[str, Any]]: ...

    async def list_blocks(
        self,
        *,
        user_id: str,
        plan_id: UUID,
        revisions: list[int],
    ) -> list[dict[str, Any]]: ...

    async def list_completed_focus(
        self,
        *,
        user_id: str,
        task_id: UUID,
        started_at_or_after: datetime,
    ) -> list[dict[str, Any]]: ...

    async def get_calendar_event(
        self,
        *,
        user_id: str,
        event_id: UUID,
    ) -> dict[str, Any] | None: ...

    async def load_workload_context(
        self,
        *,
        user_id: str,
        generated_at: datetime,
    ) -> PreparationWorkloadContext: ...

    async def load_workload_detail_context(
        self,
        *,
        user_id: str,
        local_date: date,
    ) -> PreparationWorkloadDetailContext: ...

    async def load_planning_context(
        self,
        *,
        user_id: str,
        plan_id: UUID,
        starts_on: date,
        range_starts_at: datetime,
        range_ends_at: datetime,
        source_calendar_event_id: UUID | None,
        include_calendar_availability: bool,
    ) -> DeadlinePlanningContext: ...

    async def persist_proposal(
        self,
        *,
        user_id: str,
        request_id: UUID,
        request_fingerprint: str,
        plan_id: UUID,
        base_revision: int,
        proposal: dict[str, Any],
        blocks: list[dict[str, Any]],
        now: datetime,
    ) -> int: ...

    async def confirm(
        self,
        *,
        user_id: str,
        plan_id: UUID,
        request_id: UUID,
        request_fingerprint: str,
        expected_revision: int,
        now: datetime,
    ) -> None: ...

    async def mutate_lifecycle(
        self,
        *,
        user_id: str,
        plan_id: UUID,
        request_id: UUID,
        request_fingerprint: str,
        expected_revision: int,
        action: str,
        now: datetime,
    ) -> None: ...


class SupabaseDeadlinePlanRepository:
    _page_size = 1_000

    def __init__(self, client: SupabaseRestClient) -> None:
        self._client = client

    async def _select_pages(
        self,
        table: str,
        *,
        params: dict[str, Any],
        max_rows: int,
    ) -> list[dict[str, Any]]:
        rows: list[dict[str, Any]] = []
        while len(rows) < max_rows:
            page_limit = min(self._page_size, max_rows - len(rows))
            page = await self._client.select(
                table,
                params={
                    **params,
                    "limit": str(page_limit),
                    "offset": str(len(rows)),
                },
            )
            if len(page) > page_limit:
                raise ValueError("PostgREST returned more rows than requested.")
            rows.extend(page)
            if len(page) < page_limit:
                break
        return rows

    async def get_request_identity(
        self,
        *,
        request_id: UUID,
    ) -> dict[str, Any] | None:
        rows = await self._client.select(
            "deadline_plan_request_identities",
            params={
                "select": "request_id,user_id,operation,request_fingerprint,"
                "plan_id,result_revision,result_status",
                "request_id": f"eq.{request_id}",
                "limit": "1",
            },
        )
        return rows[0] if rows else None

    async def load_projection(
        self,
        *,
        user_id: str,
        plan_id: UUID | None,
    ) -> DeadlinePlanProjection:
        params: dict[str, Any] = {"p_user_id": user_id}
        if plan_id is not None:
            params["p_plan_id"] = str(plan_id)
        result = await self._client.rpc(
            "get_deadline_plan_projection_v1",
            params=params,
        )
        return _parse_projection(result)

    async def get_plan(
        self,
        *,
        user_id: str,
        plan_id: UUID,
    ) -> dict[str, Any] | None:
        rows = await self._client.select(
            "deadline_plans",
            params={
                "select": "*",
                "user_id": f"eq.{user_id}",
                "id": f"eq.{plan_id}",
                "limit": "1",
            },
        )
        return rows[0] if rows else None

    async def list_revisions(
        self,
        *,
        user_id: str,
        plan_id: UUID,
    ) -> list[dict[str, Any]]:
        return await self._client.select(
            "deadline_plan_revisions",
            params={
                "select": "*",
                "user_id": f"eq.{user_id}",
                "plan_id": f"eq.{plan_id}",
                "state": "in.(proposed,active)",
                "order": "revision.asc",
                "limit": "3",
            },
        )

    async def list_blocks(
        self,
        *,
        user_id: str,
        plan_id: UUID,
        revisions: list[int],
    ) -> list[dict[str, Any]]:
        if not revisions:
            return []
        return await self._client.select(
            "deadline_plan_blocks",
            params={
                "select": "*",
                "user_id": f"eq.{user_id}",
                "plan_id": f"eq.{plan_id}",
                "revision": f"in.({','.join(str(value) for value in revisions)})",
                "order": "revision.asc,sequence.asc",
                "limit": "241",
            },
        )

    async def list_completed_focus(
        self,
        *,
        user_id: str,
        task_id: UUID,
        started_at_or_after: datetime,
    ) -> list[dict[str, Any]]:
        return await self._select_pages(
            "focus_sessions",
            params={
                "select": "id,started_at,ended_at,actual_minutes,status",
                "user_id": f"eq.{user_id}",
                "task_id": f"eq.{task_id}",
                "status": "eq.completed",
                "started_at": f"gte.{started_at_or_after.isoformat()}",
                "order": "started_at.asc,id.asc",
            },
            max_rows=10_001,
        )

    async def get_calendar_event(
        self,
        *,
        user_id: str,
        event_id: UUID,
    ) -> dict[str, Any] | None:
        rows = await self._client.select(
            "calendar_events",
            params={
                "select": "id,user_id,connection_id,import_id,source_fingerprint",
                "user_id": f"eq.{user_id}",
                "id": f"eq.{event_id}",
                "limit": "1",
            },
        )
        if not rows:
            return None
        return await self._with_connection_state(rows[0])

    async def load_workload_context(
        self,
        *,
        user_id: str,
        generated_at: datetime,
    ) -> PreparationWorkloadContext:
        profile_rows = await self._client.select(
            "profiles",
            params={
                "select": "timezone,daily_preparation_budget_minutes",
                "id": f"eq.{user_id}",
                "limit": "1",
            },
        )
        if not profile_rows:
            raise DeadlinePlanPersistenceNotFound("Profile is unavailable.")
        timezone = _profile_timezone(profile_rows[0])
        budget = _profile_daily_preparation_budget(profile_rows[0])
        try:
            zone = ZoneInfo(timezone)
        except ZoneInfoNotFoundError as exc:
            raise ValueError("Profile timezone is invalid.") from exc
        starts_on = generated_at.astimezone(zone).date()
        ends_on = starts_on + timedelta(days=6)
        schedule_items = await self._select_pages(
            "schedule_items",
            params={
                "select": "id,weekday,starts_at,ends_at",
                "user_id": f"eq.{user_id}",
                "order": "weekday.asc,starts_at.asc,id.asc",
            },
            max_rows=1_001,
        )
        confirmed_blocks = await self._select_pages(
            "deadline_plan_blocks",
            params={
                "select": "id,plan_id,local_date,planned_minutes,starts_at,ends_at",
                "user_id": f"eq.{user_id}",
                "reservation_state": "eq.active",
                "and": (
                    f"(local_date.gte.{starts_on.isoformat()},"
                    f"local_date.lte.{ends_on.isoformat()})"
                ),
                "order": "local_date.asc,starts_at.asc,id.asc",
            },
            max_rows=6_001,
        )
        return PreparationWorkloadContext(
            timezone=timezone,
            daily_preparation_budget_minutes=budget,
            schedule_items=schedule_items,
            confirmed_blocks=confirmed_blocks,
        )

    async def load_workload_detail_context(
        self,
        *,
        user_id: str,
        local_date: date,
    ) -> PreparationWorkloadDetailContext:
        profile_rows = await self._client.select(
            "profiles",
            params={
                "select": "timezone,daily_preparation_budget_minutes",
                "id": f"eq.{user_id}",
                "limit": "1",
            },
        )
        if not profile_rows:
            raise DeadlinePlanPersistenceNotFound("Profile is unavailable.")
        timezone = _profile_timezone(profile_rows[0])
        budget = _profile_daily_preparation_budget(profile_rows[0])
        confirmed_blocks = await self._select_pages(
            "deadline_plan_blocks",
            params={
                "select": "id,plan_id,local_date,planned_minutes,starts_at,ends_at",
                "user_id": f"eq.{user_id}",
                "reservation_state": "eq.active",
                "local_date": f"eq.{local_date.isoformat()}",
                "order": "starts_at.asc,id.asc",
            },
            max_rows=6_001,
        )
        plan_ids = sorted(
            {
                str(UUID(str(row.get("plan_id"))))
                for row in confirmed_blocks
            },
        )
        plans: list[dict[str, Any]] = []
        if plan_ids:
            plans = await self._select_pages(
                "deadline_plans",
                params={
                    "select": "id,title",
                    "user_id": f"eq.{user_id}",
                    "id": f"in.({','.join(plan_ids)})",
                    "order": "id.asc",
                },
                max_rows=51,
            )
        return PreparationWorkloadDetailContext(
            timezone=timezone,
            daily_preparation_budget_minutes=budget,
            confirmed_blocks=confirmed_blocks,
            plans=plans,
        )

    async def load_planning_context(
        self,
        *,
        user_id: str,
        plan_id: UUID,
        starts_on: date,
        range_starts_at: datetime,
        range_ends_at: datetime,
        source_calendar_event_id: UUID | None,
        include_calendar_availability: bool,
    ) -> DeadlinePlanningContext:
        profile_rows = await self._client.select(
            "profiles",
            params={
                "select": "timezone,daily_preparation_budget_minutes",
                "id": f"eq.{user_id}",
                "limit": "1",
            },
        )
        if not profile_rows:
            raise DeadlinePlanPersistenceNotFound("Profile is unavailable.")
        timezone = _profile_timezone(profile_rows[0])
        daily_preparation_budget_minutes = _profile_daily_preparation_budget(
            profile_rows[0],
        )
        try:
            profile_zone = ZoneInfo(timezone)
        except ZoneInfoNotFoundError as exc:
            raise ValueError("Profile timezone is invalid.") from exc
        context_starts_on = max(
            starts_on,
            range_starts_at.astimezone(profile_zone).date(),
        )
        context_ends_on = range_ends_at.astimezone(profile_zone).date()

        intake_rows = await self._client.select(
            "intake_responses",
            params={
                "select": "responses",
                "user_id": f"eq.{user_id}",
                "version": "eq.intake-v1",
                "state": "eq.applied",
                "order": "revision.desc,updated_at.desc",
                "limit": "1",
            },
        )
        best_energy_window = "variable"
        if intake_rows and isinstance(intake_rows[0].get("responses"), dict):
            candidate = intake_rows[0]["responses"].get("best_energy_window")
            if candidate in {
                "early_morning",
                "morning",
                "afternoon",
                "evening",
                "variable",
            }:
                best_energy_window = candidate

        schedule_items = await self._select_pages(
            "schedule_items",
            params={
                "select": "id,weekday,starts_at,ends_at,updated_at",
                "user_id": f"eq.{user_id}",
                "order": "weekday.asc,starts_at.asc,id.asc",
            },
            max_rows=1_001,
        )
        confirmed_blocks = await self._select_pages(
            "deadline_plan_blocks",
            params={
                "select": "id,plan_id,local_date,planned_minutes,starts_at,ends_at",
                "user_id": f"eq.{user_id}",
                "plan_id": f"neq.{plan_id}",
                "reservation_state": "eq.active",
                "and": (
                    f"(local_date.gte.{context_starts_on.isoformat()},"
                    f"local_date.lte.{context_ends_on.isoformat()})"
                ),
                "order": "starts_at.asc,id.asc",
            },
            max_rows=6_000,
        )

        preference_rows = await self._client.select(
            "planner_preferences",
            params={
                "select": "use_calendar_busy_time",
                "user_id": f"eq.{user_id}",
                "limit": "1",
            },
        )
        planner_use_calendar_busy_time = bool(
            preference_rows
            and preference_rows[0].get("use_calendar_busy_time") is True
        )
        # Deadline Planner keeps its V1 request field for wire compatibility,
        # but Planner V1 owns the one explicit account preference.
        include_calendar_availability = planner_use_calendar_busy_time

        planner_task_blocks = await self._select_pages(
            "planner_task_blocks",
            params={
                "select": "id,plan_id,starts_at,ends_at,local_date,planned_minutes",
                "user_id": f"eq.{user_id}",
                "state": "eq.active",
                "and": (
                    f"(local_date.gte.{context_starts_on.isoformat()},"
                    f"local_date.lte.{context_ends_on.isoformat()})"
                ),
                "order": "starts_at.asc,id.asc",
            },
            max_rows=10_001,
        )
        planner_habit_slots = await self._select_pages(
            "planner_habit_slots",
            params={
                "select": "id,plan_id,weekday,starts_at,ends_at,duration_minutes",
                "user_id": f"eq.{user_id}",
                "state": "eq.active",
                "order": "weekday.asc,starts_at.asc,id.asc",
            },
            max_rows=1_001,
        )
        planner_commitments = await self._select_pages(
            "planner_commitments",
            params={
                "select": "id,recurrence,starts_at,ends_at,weekday,"
                "local_starts_at,local_ends_at",
                "user_id": f"eq.{user_id}",
                "status": "eq.active",
                "order": "created_at.asc,id.asc",
            },
            max_rows=1_001,
        )
        planner_recurring_commitments = [
            {
                "id": row.get("id"),
                "weekday": row.get("weekday"),
                "starts_at": row.get("starts_at"),
                "ends_at": row.get("ends_at"),
            }
            for row in planner_habit_slots
        ]
        planner_timed_intervals = list(planner_task_blocks)
        for row in planner_commitments:
            if row.get("recurrence") == "weekly":
                planner_recurring_commitments.append(
                    {
                        "id": row.get("id"),
                        "weekday": row.get("weekday"),
                        "starts_at": row.get("local_starts_at"),
                        "ends_at": row.get("local_ends_at"),
                    },
                )
            elif row.get("recurrence") == "one_off":
                planner_timed_intervals.append(
                    {
                        "id": row.get("id"),
                        "starts_at": row.get("starts_at"),
                        "ends_at": row.get("ends_at"),
                    },
                )
            else:
                raise ValueError("Planner commitment recurrence is invalid.")

        source_calendar_event = None
        if source_calendar_event_id is not None:
            source_rows = await self._client.select(
                "calendar_events",
                params={
                    "select": "id,user_id,connection_id,import_id,source_fingerprint",
                    "user_id": f"eq.{user_id}",
                    "id": f"eq.{source_calendar_event_id}",
                    "limit": "1",
                },
            )
            source_calendar_event = (
                await self._with_connection_state(source_rows[0])
                if source_rows
                else None
            )

        timed_events: list[dict[str, Any]] = []
        all_day_events: list[dict[str, Any]] = []
        calendar_availability_current = False
        if include_calendar_availability:
            connection_rows = await self._client.select(
                "calendar_connections",
                params={
                    "select": "id,last_import_id,status,imported_data_deleted_at",
                    "user_id": f"eq.{user_id}",
                    "status": "eq.connected",
                    "imported_data_deleted_at": "is.null",
                    "order": "updated_at.desc,id.desc",
                    "limit": "1",
                },
            )
            current_connection = connection_rows[0] if connection_rows else None
            current_import_id = (
                current_connection.get("last_import_id") if current_connection else None
            )
            calendar_availability_current = current_import_id is not None
        if include_calendar_availability and calendar_availability_current:
            assert current_connection is not None
            timed_events = await self._select_pages(
                "calendar_events",
                params={
                    "select": "id,event_kind,busy_status,starts_at,ends_at",
                    "user_id": f"eq.{user_id}",
                    "connection_id": f"eq.{current_connection['id']}",
                    "import_id": f"eq.{current_import_id}",
                    "event_kind": "eq.timed",
                    "busy_status": "eq.busy",
                    "ends_at": f"gt.{range_starts_at.isoformat()}",
                    "starts_at": f"lt.{range_ends_at.isoformat()}",
                    "order": "starts_at.asc,id.asc",
                },
                max_rows=2_000,
            )
            all_day_events = await self._select_pages(
                "calendar_events",
                params={
                    "select": "id,event_kind,busy_status,starts_on,ends_on",
                    "user_id": f"eq.{user_id}",
                    "connection_id": f"eq.{current_connection['id']}",
                    "import_id": f"eq.{current_import_id}",
                    "event_kind": "eq.all_day",
                    "busy_status": "eq.busy",
                    "ends_on": f"gt.{starts_on.isoformat()}",
                    "starts_on": f"lt.{range_ends_at.date().isoformat()}",
                    "order": "starts_on.asc,id.asc",
                },
                max_rows=2_000,
            )

        return DeadlinePlanningContext(
            timezone=timezone,
            best_energy_window=best_energy_window,
            schedule_items=schedule_items,
            confirmed_blocks=confirmed_blocks,
            timed_calendar_events=timed_events,
            all_day_calendar_events=all_day_events,
            source_calendar_event=source_calendar_event,
            calendar_availability_current=calendar_availability_current,
            availability_connection_id=(
                UUID(str(current_connection["id"]))
                if include_calendar_availability and calendar_availability_current
                else None
            ),
            availability_import_id=(
                UUID(str(current_import_id))
                if include_calendar_availability and calendar_availability_current
                else None
            ),
            daily_preparation_budget_minutes=daily_preparation_budget_minutes,
            planner_recurring_commitments=planner_recurring_commitments,
            planner_timed_intervals=planner_timed_intervals,
            planner_use_calendar_busy_time=planner_use_calendar_busy_time,
        )

    async def _with_connection_state(
        self,
        event: dict[str, Any],
    ) -> dict[str, Any]:
        connection_id = event.get("connection_id")
        if connection_id is None:
            return event
        rows = await self._client.select(
            "calendar_connections",
            params={
                "select": "id,status,last_import_id,imported_data_deleted_at",
                "id": f"eq.{connection_id}",
                "user_id": f"eq.{event.get('user_id')}",
                "limit": "1",
            },
        )
        connection = rows[0] if rows else None
        return {
            **event,
            "_connection_status": connection.get("status") if connection else None,
            "_connection_last_import_id": (
                connection.get("last_import_id") if connection else None
            ),
            "_connection_imported_data_deleted_at": (
                connection.get("imported_data_deleted_at") if connection else None
            ),
        }

    async def persist_proposal(
        self,
        *,
        user_id: str,
        request_id: UUID,
        request_fingerprint: str,
        plan_id: UUID,
        base_revision: int,
        proposal: dict[str, Any],
        blocks: list[dict[str, Any]],
        now: datetime,
    ) -> int:
        result = await self._rpc(
            "propose_deadline_plan_v1",
            params={
                "p_user_id": user_id,
                "p_request_id": str(request_id),
                "p_request_fingerprint": request_fingerprint,
                "p_plan_id": str(plan_id),
                "p_base_revision": base_revision,
                "p_proposal": proposal,
                "p_blocks": blocks,
                "p_now": now.isoformat(),
            },
        )
        revision = result.get("revision")
        if isinstance(revision, bool) or not isinstance(revision, int) or revision < 1:
            raise ValueError("Deadline proposal RPC returned an invalid revision.")
        return revision

    async def confirm(
        self,
        *,
        user_id: str,
        plan_id: UUID,
        request_id: UUID,
        request_fingerprint: str,
        expected_revision: int,
        now: datetime,
    ) -> None:
        await self._rpc(
            "confirm_deadline_plan_v1",
            params={
                "p_user_id": user_id,
                "p_plan_id": str(plan_id),
                "p_request_id": str(request_id),
                "p_request_fingerprint": request_fingerprint,
                "p_expected_revision": expected_revision,
                "p_now": now.isoformat(),
            },
        )

    async def mutate_lifecycle(
        self,
        *,
        user_id: str,
        plan_id: UUID,
        request_id: UUID,
        request_fingerprint: str,
        expected_revision: int,
        action: str,
        now: datetime,
    ) -> None:
        await self._rpc(
            "mutate_deadline_plan_lifecycle_v1",
            params={
                "p_user_id": user_id,
                "p_plan_id": str(plan_id),
                "p_request_id": str(request_id),
                "p_request_fingerprint": request_fingerprint,
                "p_expected_revision": expected_revision,
                "p_action": action,
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
            raise ValueError(f"Deadline plan RPC {function} returned a non-object.")
        return result


def _profile_timezone(row: dict[str, Any]) -> str:
    timezone = row.get("timezone")
    if not isinstance(timezone, str) or not timezone:
        raise ValueError("Profile timezone is invalid.")
    return timezone


def _profile_daily_preparation_budget(row: dict[str, Any]) -> int | None:
    value = row.get("daily_preparation_budget_minutes")
    if value is None:
        return None
    if (
        type(value) is not int
        or value < 25
        or value > 480
        or value % 5 != 0
    ):
        raise ValueError("Profile daily preparation budget is invalid.")
    return value


def _postgres_error(exc: httpx.HTTPStatusError) -> tuple[str | None, str]:
    try:
        payload = exc.response.json()
    except ValueError:
        return None, "Deadline plan persistence failed."
    if not isinstance(payload, dict):
        return None, "Deadline plan persistence failed."
    code = payload.get("code") if isinstance(payload.get("code"), str) else None
    message = payload.get("message")
    if not isinstance(message, str) or not message:
        message = "Deadline plan persistence failed."
    return code, message


_PROJECTION_ARRAYS = (
    "plans",
    "revisions",
    "blocks",
    "focus_totals",
    "calendar_events",
)
_PROJECTION_KEYS = {
    key
    for name in _PROJECTION_ARRAYS
    for key in (f"{name.removesuffix('s')}_count", name)
}


def _parse_projection(result: object) -> DeadlinePlanProjection:
    if not isinstance(result, dict) or set(result) != _PROJECTION_KEYS:
        raise ValueError("Deadline projection RPC returned an invalid object.")
    parsed: dict[str, list[dict[str, Any]]] = {}
    for name in _PROJECTION_ARRAYS:
        count = result[f"{name.removesuffix('s')}_count"]
        rows = result[name]
        if (
            isinstance(count, bool)
            or not isinstance(count, int)
            or count < 0
            or not isinstance(rows, list)
            or count != len(rows)
            or any(not isinstance(row, dict) for row in rows)
        ):
            raise ValueError(
                f"Deadline projection RPC returned invalid {name} rows.",
            )
        parsed[name] = [dict(row) for row in rows]
    event_rows = parsed["calendar_events"]
    events = {str(row.get("id")): row for row in event_rows}
    if any(row.get("id") is None for row in event_rows) or len(events) != len(
        event_rows,
    ):
        raise ValueError("Deadline projection contains duplicate calendar events.")
    return DeadlinePlanProjection(
        plans=parsed["plans"],
        revisions=parsed["revisions"],
        blocks=parsed["blocks"],
        focus_totals=parsed["focus_totals"],
        calendar_events=events,
    )
