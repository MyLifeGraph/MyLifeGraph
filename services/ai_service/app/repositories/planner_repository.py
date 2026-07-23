from __future__ import annotations

from dataclasses import dataclass
from datetime import date, datetime
from typing import Any, Protocol
from uuid import UUID

import httpx

from app.clients.supabase import SupabaseRestClient


class PlannerPersistenceConflict(RuntimeError):
    pass


class PlannerPersistenceNotFound(RuntimeError):
    pass


@dataclass(frozen=True)
class PlannerProjection:
    plans: list[dict[str, Any]]
    revisions: list[dict[str, Any]]
    task_blocks: list[dict[str, Any]]
    habit_slots: list[dict[str, Any]]


@dataclass(frozen=True)
class PlannerCalendarProjection:
    available: bool
    connection_id: UUID | None
    import_id: UUID | None
    timed_events: list[dict[str, Any]]
    all_day_events: list[dict[str, Any]]


@dataclass(frozen=True)
class PlannerOverviewContext:
    timezone: str
    best_energy_window: str
    preference: dict[str, Any] | None
    calendar: PlannerCalendarProjection
    schedule_items: list[dict[str, Any]]
    commitments: list[dict[str, Any]]
    tasks: list[dict[str, Any]]
    habits: list[dict[str, Any]]
    plans: PlannerProjection
    study_setup: dict[str, Any] | None = None


@dataclass(frozen=True)
class PlannerAvailabilityContext:
    timezone: str
    best_energy_window: str
    preference: dict[str, Any] | None
    calendar: PlannerCalendarProjection
    schedule_items: list[dict[str, Any]]
    commitments: list[dict[str, Any]]
    task_blocks: list[dict[str, Any]]
    habit_slots: list[dict[str, Any]]
    deadline_blocks: list[dict[str, Any]]
    target: dict[str, Any] | None
    study_setup: dict[str, Any] | None = None


@dataclass(frozen=True)
class PlannerPreferenceContext:
    preference: dict[str, Any] | None
    calendar: PlannerCalendarProjection


class PlannerRepository(Protocol):
    async def get_request_identity(self, *, request_id: UUID) -> dict[str, Any] | None:
        ...

    async def load_projection(
        self,
        *,
        user_id: str,
        plan_id: UUID | None,
    ) -> PlannerProjection: ...

    async def load_preference_context(
        self,
        *,
        user_id: str,
    ) -> PlannerPreferenceContext: ...

    async def get_commitment(
        self,
        *,
        user_id: str,
        commitment_id: UUID,
    ) -> dict[str, Any] | None: ...

    async def load_overview_context(
        self,
        *,
        user_id: str,
        generated_at: datetime,
    ) -> PlannerOverviewContext: ...

    async def load_availability_context(
        self,
        *,
        user_id: str,
        plan_id: UUID,
        target_kind: str,
        target_id: UUID,
        starts_on: date,
        ends_on: date,
    ) -> PlannerAvailabilityContext: ...

    async def set_preferences(
        self,
        *,
        user_id: str,
        request_id: UUID,
        expected_updated_at: datetime | None,
        use_calendar_busy_time: bool,
        now: datetime,
    ) -> dict[str, Any]: ...

    async def persist_proposal(
        self,
        *,
        user_id: str,
        request_id: UUID,
        request_fingerprint: str,
        plan_id: UUID,
        base_revision: int,
        target_kind: str,
        target_id: UUID,
        target_payload: dict[str, Any],
        revision_payload: dict[str, Any],
        task_blocks: list[dict[str, Any]],
        habit_slots: list[dict[str, Any]],
        now: datetime,
    ) -> dict[str, Any]: ...

    async def confirm(
        self,
        *,
        user_id: str,
        plan_id: UUID,
        request_id: UUID,
        expected_revision: int,
        request_fingerprint: str,
        now: datetime,
    ) -> dict[str, Any]: ...

    async def cancel(
        self,
        *,
        user_id: str,
        plan_id: UUID,
        request_id: UUID,
        expected_revision: int,
        request_fingerprint: str,
        now: datetime,
    ) -> dict[str, Any]: ...

    async def mutate_commitment(
        self,
        *,
        user_id: str,
        commitment_id: UUID,
        request_id: UUID,
        operation: str,
        request_fingerprint: str,
        expected_updated_at: datetime | None,
        payload: dict[str, Any] | None,
        now: datetime,
    ) -> dict[str, Any]: ...


class SupabasePlannerRepository:
    _page_size = 1_000

    def __init__(self, client: SupabaseRestClient) -> None:
        self._client = client

    async def get_request_identity(self, *, request_id: UUID) -> dict[str, Any] | None:
        rows = await self._client.select(
            "planner_request_identities",
            params={
                "select": "request_id,user_id,operation,resource_id,request_fingerprint",
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
    ) -> PlannerProjection:
        plan_params: dict[str, str] = {
            "select": "*",
            "user_id": f"eq.{user_id}",
            "order": "updated_at.desc,id.asc",
        }
        if plan_id is not None:
            plan_params["id"] = f"eq.{plan_id}"
        plans = await self._select_pages(
            "planner_action_plans",
            params=plan_params,
            max_rows=1_001,
        )
        plan_ids = [str(row["id"]) for row in plans]
        if not plan_ids:
            return PlannerProjection([], [], [], [])
        in_filter = f"in.({','.join(plan_ids)})"
        revisions = await self._select_pages(
            "planner_action_plan_revisions",
            params={
                "select": "*",
                "user_id": f"eq.{user_id}",
                "plan_id": in_filter,
                "order": "plan_id.asc,revision.asc",
            },
            max_rows=5_001,
        )
        blocks = await self._select_pages(
            "planner_task_blocks",
            params={
                "select": "*",
                "user_id": f"eq.{user_id}",
                "plan_id": in_filter,
                "order": "plan_id.asc,revision.asc,sequence.asc,id.asc",
            },
            max_rows=10_001,
        )
        slots = await self._select_pages(
            "planner_habit_slots",
            params={
                "select": "*",
                "user_id": f"eq.{user_id}",
                "plan_id": in_filter,
                "order": "plan_id.asc,revision.asc,weekday.asc,starts_at.asc,id.asc",
            },
            max_rows=5_001,
        )
        return PlannerProjection(plans, revisions, blocks, slots)

    async def load_preference_context(
        self,
        *,
        user_id: str,
    ) -> PlannerPreferenceContext:
        # The profile probe keeps an absent canonical profile distinct from an
        # ordinary preference default. Planner GETs must never fabricate an
        # authenticated owner projection.
        await self._profile(user_id=user_id)
        return PlannerPreferenceContext(
            preference=await self._preference(user_id=user_id),
            calendar=await self._calendar(user_id=user_id, include_events=False),
        )

    async def get_commitment(
        self,
        *,
        user_id: str,
        commitment_id: UUID,
    ) -> dict[str, Any] | None:
        rows = await self._client.select(
            "planner_commitments",
            params={
                "select": "*",
                "id": f"eq.{commitment_id}",
                "user_id": f"eq.{user_id}",
                "limit": "1",
            },
        )
        return rows[0] if rows else None

    async def load_overview_context(
        self,
        *,
        user_id: str,
        generated_at: datetime,
    ) -> PlannerOverviewContext:
        del generated_at
        timezone, energy = await self._profile(user_id=user_id)
        preference = await self._preference(user_id=user_id)
        calendar = await self._calendar(
            user_id=user_id,
            include_events=True,
        )
        schedule_items = await self._select_pages(
            "schedule_items",
            params={
                "select": "id,title,location,weekday,starts_at,ends_at,source,metadata",
                "user_id": f"eq.{user_id}",
                "order": "weekday.asc,starts_at.asc,id.asc",
            },
            max_rows=1_001,
        )
        commitments = await self._select_pages(
            "planner_commitments",
            params={
                "select": "*",
                "user_id": f"eq.{user_id}",
                "order": "created_at.asc,id.asc",
            },
            max_rows=1_001,
        )
        tasks = await self._select_pages(
            "tasks",
            params={
                "select": "id,title,description,status,priority,source,metadata,updated_at,deadline,estimated_minutes",
                "user_id": f"eq.{user_id}",
                "order": "created_at.asc,id.asc",
            },
            max_rows=1_001,
        )
        habits = await self._select_pages(
            "habits",
            params={
                "select": "id,title,description,frequency,target,active,metadata,updated_at",
                "user_id": f"eq.{user_id}",
                "order": "created_at.asc,id.asc",
            },
            max_rows=1_001,
        )
        projection = await self.load_projection(user_id=user_id, plan_id=None)
        return PlannerOverviewContext(
            timezone=timezone,
            best_energy_window=energy,
            preference=preference,
            calendar=calendar,
            schedule_items=schedule_items,
            commitments=commitments,
            tasks=tasks,
            habits=habits,
            plans=projection,
            study_setup=await self._study_setup(user_id=user_id),
        )

    async def load_availability_context(
        self,
        *,
        user_id: str,
        plan_id: UUID,
        target_kind: str,
        target_id: UUID,
        starts_on: date,
        ends_on: date,
    ) -> PlannerAvailabilityContext:
        timezone, energy = await self._profile(user_id=user_id)
        preference = await self._preference(user_id=user_id)
        schedule_items = await self._select_pages(
            "schedule_items",
            params={
                "select": "id,weekday,starts_at,ends_at,metadata",
                "user_id": f"eq.{user_id}",
                "order": "weekday.asc,starts_at.asc,id.asc",
            },
            max_rows=1_001,
        )
        commitments = await self._select_pages(
            "planner_commitments",
            params={
                "select": "id,recurrence,starts_at,ends_at,weekday,local_starts_at,local_ends_at",
                "user_id": f"eq.{user_id}",
                "status": "eq.active",
                "order": "created_at.asc,id.asc",
            },
            max_rows=1_001,
        )
        task_blocks = await self._select_pages(
            "planner_task_blocks",
            params=[
                (
                    "select",
                    "id,plan_id,starts_at,ends_at,reserved_ends_at,"
                    "local_date,planned_minutes,recovery_minutes",
                ),
                ("user_id", f"eq.{user_id}"),
                ("state", "eq.active"),
                ("plan_id", f"neq.{plan_id}"),
                ("local_date", f"gte.{starts_on.isoformat()}"),
                ("local_date", f"lte.{ends_on.isoformat()}"),
                ("order", "starts_at.asc,id.asc"),
            ],
            max_rows=10_001,
        )
        habit_slots = await self._select_pages(
            "planner_habit_slots",
            params={
                "select": "id,plan_id,weekday,starts_at,ends_at,duration_minutes",
                "user_id": f"eq.{user_id}",
                "state": "eq.active",
                "plan_id": f"neq.{plan_id}",
                "order": "weekday.asc,starts_at.asc,id.asc",
            },
            max_rows=1_001,
        )
        deadline_blocks = await self._select_pages(
            "deadline_plan_blocks",
            params=[
                (
                    "select",
                    "id,starts_at,ends_at,reserved_ends_at,local_date,"
                    "planned_minutes,recovery_minutes",
                ),
                ("user_id", f"eq.{user_id}"),
                ("reservation_state", "eq.active"),
                ("local_date", f"gte.{starts_on.isoformat()}"),
                ("local_date", f"lte.{ends_on.isoformat()}"),
                ("order", "starts_at.asc,id.asc"),
            ],
            max_rows=10_001,
        )
        target_rows = await self._client.select(
            "tasks" if target_kind == "task" else "habits",
            params={
                "select": "*",
                "id": f"eq.{target_id}",
                "user_id": f"eq.{user_id}",
                "limit": "1",
            },
        )
        calendar = await self._calendar(
            user_id=user_id,
            include_events=bool(
                preference and preference.get("use_calendar_busy_time") is True
            ),
        )
        return PlannerAvailabilityContext(
            timezone=timezone,
            best_energy_window=energy,
            preference=preference,
            calendar=calendar,
            schedule_items=schedule_items,
            commitments=commitments,
            task_blocks=task_blocks,
            habit_slots=habit_slots,
            deadline_blocks=deadline_blocks,
            target=target_rows[0] if target_rows else None,
            study_setup=await self._study_setup(user_id=user_id),
        )

    async def set_preferences(
        self,
        *,
        user_id: str,
        request_id: UUID,
        expected_updated_at: datetime | None,
        use_calendar_busy_time: bool,
        now: datetime,
    ) -> dict[str, Any]:
        return await self._rpc(
            "set_planner_preferences_v1",
            params={
                "p_user_id": user_id,
                "p_request_id": str(request_id),
                "p_expected_updated_at": _iso(expected_updated_at),
                "p_use_calendar_busy_time": use_calendar_busy_time,
                "p_now": now.isoformat(),
            },
        )

    async def persist_proposal(
        self,
        *,
        user_id: str,
        request_id: UUID,
        request_fingerprint: str,
        plan_id: UUID,
        base_revision: int,
        target_kind: str,
        target_id: UUID,
        target_payload: dict[str, Any],
        revision_payload: dict[str, Any],
        task_blocks: list[dict[str, Any]],
        habit_slots: list[dict[str, Any]],
        now: datetime,
    ) -> dict[str, Any]:
        return await self._rpc(
            "propose_planner_action_plan_v1",
            params={
                "p_user_id": user_id,
                "p_request_id": str(request_id),
                "p_request_fingerprint": request_fingerprint,
                "p_plan_id": str(plan_id),
                "p_base_revision": base_revision,
                "p_target_kind": target_kind,
                "p_target_id": str(target_id),
                "p_target_payload": target_payload,
                "p_revision_payload": revision_payload,
                "p_task_blocks": task_blocks,
                "p_habit_slots": habit_slots,
                "p_now": now.isoformat(),
            },
        )

    async def confirm(
        self,
        *,
        user_id: str,
        plan_id: UUID,
        request_id: UUID,
        expected_revision: int,
        request_fingerprint: str,
        now: datetime,
    ) -> dict[str, Any]:
        return await self._rpc(
            "confirm_planner_action_plan_v1",
            params={
                "p_user_id": user_id,
                "p_plan_id": str(plan_id),
                "p_request_id": str(request_id),
                "p_expected_revision": expected_revision,
                "p_request_fingerprint": request_fingerprint,
                "p_now": now.isoformat(),
            },
        )

    async def cancel(
        self,
        *,
        user_id: str,
        plan_id: UUID,
        request_id: UUID,
        expected_revision: int,
        request_fingerprint: str,
        now: datetime,
    ) -> dict[str, Any]:
        return await self._rpc(
            "cancel_planner_action_plan_v1",
            params={
                "p_user_id": user_id,
                "p_plan_id": str(plan_id),
                "p_request_id": str(request_id),
                "p_expected_revision": expected_revision,
                "p_request_fingerprint": request_fingerprint,
                "p_now": now.isoformat(),
            },
        )

    async def mutate_commitment(
        self,
        *,
        user_id: str,
        commitment_id: UUID,
        request_id: UUID,
        operation: str,
        request_fingerprint: str,
        expected_updated_at: datetime | None,
        payload: dict[str, Any] | None,
        now: datetime,
    ) -> dict[str, Any]:
        return await self._rpc(
            "mutate_planner_commitment_v1",
            params={
                "p_user_id": user_id,
                "p_commitment_id": str(commitment_id),
                "p_request_id": str(request_id),
                "p_operation": operation,
                "p_request_fingerprint": request_fingerprint,
                "p_expected_updated_at": _iso(expected_updated_at),
                "p_payload": payload,
                "p_now": now.isoformat(),
            },
        )

    async def _profile(self, *, user_id: str) -> tuple[str, str]:
        profile_rows = await self._client.select(
            "profiles",
            params={
                "select": "timezone",
                "id": f"eq.{user_id}",
                "limit": "1",
            },
        )
        if not profile_rows:
            raise PlannerPersistenceNotFound("Planner profile is unavailable.")
        timezone = profile_rows[0].get("timezone")
        if not isinstance(timezone, str) or not timezone:
            raise ValueError("Planner profile timezone is invalid.")
        intake = await self._client.select(
            "intake_responses",
            params={
                "select": "responses",
                "user_id": f"eq.{user_id}",
                "version": "eq.intake-v1",
                "state": "eq.applied",
                "order": "revision.desc",
                "limit": "1",
            },
        )
        energy = "variable"
        if intake and isinstance(intake[0].get("responses"), dict):
            candidate = intake[0]["responses"].get("best_energy_window")
            if candidate in {
                "early_morning",
                "morning",
                "afternoon",
                "evening",
                "variable",
            }:
                energy = candidate
        return timezone, energy

    async def _preference(self, *, user_id: str) -> dict[str, Any] | None:
        rows = await self._client.select(
            "planner_preferences",
            params={
                "select": "user_id,use_calendar_busy_time,updated_at",
                "user_id": f"eq.{user_id}",
                "limit": "1",
            },
        )
        return rows[0] if rows else None

    async def _study_setup(self, *, user_id: str) -> dict[str, Any] | None:
        rows = await self._client.select(
            "study_setup_profiles",
            params={
                "select": "user_id,focus_minutes,recovery_minutes,"
                "preparation_items,current_semester,next_semester,"
                "setup_revision,updated_at",
                "user_id": f"eq.{user_id}",
                "limit": "1",
            },
        )
        return rows[0] if rows else None

    async def _calendar(
        self,
        *,
        user_id: str,
        include_events: bool,
    ) -> PlannerCalendarProjection:
        rows = await self._client.select(
            "calendar_connections",
            params={
                "select": "id,last_import_id,status,imported_data_deleted_at",
                "user_id": f"eq.{user_id}",
                "status": "eq.connected",
                "imported_data_deleted_at": "is.null",
                "order": "created_at.desc,id.desc",
                "limit": "2",
            },
        )
        if not rows:
            return PlannerCalendarProjection(False, None, None, [], [])
        if len(rows) != 1:
            raise ValueError("Planner calendar source is ambiguous.")
        connection = rows[0]
        import_value = connection.get("last_import_id")
        if import_value is None:
            return PlannerCalendarProjection(
                False,
                UUID(str(connection["id"])),
                None,
                [],
                [],
            )
        connection_id = UUID(str(connection["id"]))
        import_id = UUID(str(import_value))
        if not include_events:
            return PlannerCalendarProjection(True, connection_id, import_id, [], [])
        events = await self._select_pages(
            "calendar_events",
            params={
                "select": "id,title,event_kind,busy_status,event_status,starts_at,ends_at,starts_on,ends_on",
                "user_id": f"eq.{user_id}",
                "connection_id": f"eq.{connection_id}",
                "import_id": f"eq.{import_id}",
                "event_status": "eq.confirmed",
                "order": "sort_date.asc,sort_time.asc,id.asc",
            },
            max_rows=2_001,
        )
        timed = [row for row in events if row.get("event_kind") == "timed"]
        all_day = [row for row in events if row.get("event_kind") == "all_day"]
        return PlannerCalendarProjection(True, connection_id, import_id, timed, all_day)

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
                raise ValueError("Planner source returned more rows than requested.")
            rows.extend(page)
            if len(page) < page_limit:
                break
        return rows

    async def _rpc(self, function: str, *, params: dict[str, Any]) -> dict[str, Any]:
        try:
            result = await self._client.rpc(function, params=params)
        except httpx.HTTPStatusError as exc:
            code, message = _postgres_error(exc)
            if code == "PT409" or exc.response.status_code == 409:
                raise PlannerPersistenceConflict(message) from exc
            if code == "P0002" or exc.response.status_code == 404:
                raise PlannerPersistenceNotFound(message) from exc
            raise
        if not isinstance(result, dict):
            raise ValueError("Planner persistence returned an invalid response.")
        return result


def _postgres_error(exc: httpx.HTTPStatusError) -> tuple[str | None, str]:
    try:
        value = exc.response.json()
    except ValueError:
        return None, "Planner persistence is unavailable."
    if not isinstance(value, dict):
        return None, "Planner persistence is unavailable."
    code = value.get("code") if isinstance(value.get("code"), str) else None
    message = value.get("message")
    return code, message if isinstance(message, str) else "Planner persistence failed."


def _iso(value: datetime | None) -> str | None:
    return value.isoformat() if value is not None else None
