import hashlib
import json
from collections.abc import Callable, Iterable
from datetime import UTC, date, datetime, time, timedelta
from typing import Any
from uuid import NAMESPACE_URL, UUID, uuid5
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from app.models.deadline_plans import (
    DEADLINE_PLAN_CONTRACT_VERSION,
    PREPARATION_WORKLOAD_DETAIL_CONTRACT_VERSION,
    PREPARATION_WORKLOAD_CONTRACT_VERSION,
    DeadlinePlanBlock,
    DeadlinePlanDetail,
    DeadlinePlanIdentity,
    DeadlinePlanMutationRequest,
    DeadlinePlanProgress,
    DeadlinePlanProposalRequest,
    DeadlinePlanResponse,
    DeadlinePlanRevision,
    DeadlinePlansResponse,
    PreparationWorkloadDay,
    PreparationWorkloadContribution,
    PreparationWorkloadDetailResponse,
    PreparationWorkloadResponse,
)
from app.repositories.deadline_plan_repository import (
    DeadlinePlanProjection,
    DeadlinePlanPersistenceConflict,
    DeadlinePlanPersistenceNotFound,
    DeadlinePlanRepository,
    DeadlinePlanningContext,
)
from app.services.planning_availability import (
    ENERGY_WINDOWS as _ENERGY_WINDOWS,
    BusySources,
    allocate_task_intervals,
    recurring_commitment_applies_on,
)


class DeadlinePlanConflictError(RuntimeError):
    pass


class DeadlinePlanNotFoundError(RuntimeError):
    pass


class DeadlinePlanValidationError(ValueError):
    pass


class DeadlinePlanService:
    def __init__(
        self,
        *,
        repository: DeadlinePlanRepository,
        now: Callable[[], datetime] | None = None,
    ) -> None:
        self._repository = repository
        self._now = now or (lambda: datetime.now(UTC))

    async def list_plans(self, *, user_id: str) -> DeadlinePlansResponse:
        projection = await self._repository.load_projection(
            user_id=user_id,
            plan_id=None,
        )
        plan_rows = projection.plans
        if len(plan_rows) > 50:
            raise DeadlinePlanConflictError(
                "Deadline plan count exceeds the V1 response bound.",
            )
        details = await self._details_from_projection(
            user_id=user_id,
            projection=projection,
        )
        return DeadlinePlansResponse(
            contract_version=DEADLINE_PLAN_CONTRACT_VERSION,
            origin="authenticated_backend",
            plans=details,
        )

    async def get_plan(
        self,
        *,
        user_id: str,
        plan_id: UUID,
    ) -> DeadlinePlanResponse:
        projection = await self._repository.load_projection(
            user_id=user_id,
            plan_id=plan_id,
        )
        if not projection.plans:
            raise DeadlinePlanNotFoundError("Deadline plan is unavailable.")
        if len(projection.plans) != 1 or str(projection.plans[0].get("id")) != str(
            plan_id,
        ):
            raise ValueError("Deadline detail projection returned another plan.")
        details = await self._details_from_projection(
            user_id=user_id,
            projection=projection,
        )
        return _response(details[0])

    async def get_workload(self, *, user_id: str) -> PreparationWorkloadResponse:
        generated_at = _aware_utc(self._now())
        try:
            context = await self._repository.load_workload_context(
                user_id=user_id,
                generated_at=generated_at,
            )
        except DeadlinePlanPersistenceNotFound as exc:
            raise DeadlinePlanNotFoundError(str(exc)) from exc
        if len(context.schedule_items) > 1_000:
            raise DeadlinePlanConflictError(
                "Schedule context exceeds the workload bound.",
            )
        if len(context.confirmed_blocks) > 6_000:
            raise DeadlinePlanConflictError(
                "Preparation reservations exceed the workload bound.",
            )
        zone = _zone(context.timezone)
        starts_on = generated_at.astimezone(zone).date()
        budget = context.daily_preparation_budget_minutes
        days: list[PreparationWorkloadDay] = []
        for offset in range(7):
            local_day = starts_on + timedelta(days=offset)
            blocks = [
                row
                for row in context.confirmed_blocks
                if _date(row.get("local_date")) == local_day
            ]
            reserved = sum(_int(row.get("planned_minutes")) for row in blocks)
            days.append(
                PreparationWorkloadDay(
                    local_date=local_day,
                    reserved_preparation_minutes=reserved,
                    remaining_budget_minutes=(
                        None if budget is None else max(0, budget - reserved)
                    ),
                    over_budget_minutes=(
                        0 if budget is None else max(0, reserved - budget)
                    ),
                    active_plan_count=len(
                        {str(row.get("plan_id")) for row in blocks},
                    ),
                    fixed_commitment_minutes=_fixed_commitment_minutes(
                        context.schedule_items,
                        local_day=local_day,
                    ),
                ),
            )
        return PreparationWorkloadResponse(
            contract_version=PREPARATION_WORKLOAD_CONTRACT_VERSION,
            origin="authenticated_backend",
            generated_at=generated_at,
            timezone=context.timezone,
            daily_preparation_budget_minutes=budget,
            days=days,
        )

    async def get_workload_detail(
        self,
        *,
        user_id: str,
        local_date: date,
    ) -> PreparationWorkloadDetailResponse:
        generated_at = _aware_utc(self._now())
        try:
            context = await self._repository.load_workload_detail_context(
                user_id=user_id,
                local_date=local_date,
            )
        except DeadlinePlanPersistenceNotFound as exc:
            raise DeadlinePlanNotFoundError(str(exc)) from exc
        zone = _zone(context.timezone)
        starts_on = generated_at.astimezone(zone).date()
        if local_date < starts_on or local_date > starts_on + timedelta(days=6):
            raise DeadlinePlanValidationError(
                "Workload date must be within the current seven-day view.",
            )
        if len(context.confirmed_blocks) > 6_000:
            raise DeadlinePlanConflictError(
                "Preparation reservations exceed the workload bound.",
            )
        if len(context.plans) > 50:
            raise DeadlinePlanConflictError(
                "Active preparation plans exceed the workload bound.",
            )

        titles: dict[str, str] = {}
        for row in context.plans:
            plan_id = str(UUID(str(row.get("id"))))
            title = row.get("title")
            if (
                not isinstance(title, str)
                or not title
                or title.strip() != title
                or plan_id in titles
            ):
                raise ValueError("Preparation workload plan projection is invalid.")
            titles[plan_id] = title

        grouped: dict[str, tuple[int, int]] = {}
        for row in context.confirmed_blocks:
            if _date(row.get("local_date")) != local_date:
                raise ValueError("Preparation workload block date is invalid.")
            plan_id = str(UUID(str(row.get("plan_id"))))
            minutes = _int(row.get("planned_minutes"))
            if minutes < 5 or minutes > 240:
                raise ValueError("Preparation workload block duration is invalid.")
            total, count = grouped.get(plan_id, (0, 0))
            grouped[plan_id] = (total + minutes, count + 1)

        if set(grouped) != set(titles):
            raise DeadlinePlanConflictError(
                "Preparation reservations changed. Retry the day breakdown.",
            )
        contributions = [
            PreparationWorkloadContribution(
                plan_id=UUID(plan_id),
                title=titles[plan_id],
                reserved_preparation_minutes=total,
                block_count=count,
            )
            for plan_id, (total, count) in grouped.items()
        ]
        contributions.sort(
            key=lambda item: (
                -item.reserved_preparation_minutes,
                item.title.casefold(),
                str(item.plan_id),
            ),
        )
        reserved = sum(
            item.reserved_preparation_minutes for item in contributions
        )
        budget = context.daily_preparation_budget_minutes
        return PreparationWorkloadDetailResponse(
            contract_version=PREPARATION_WORKLOAD_DETAIL_CONTRACT_VERSION,
            origin="authenticated_backend",
            generated_at=generated_at,
            timezone=context.timezone,
            local_date=local_date,
            daily_preparation_budget_minutes=budget,
            reserved_preparation_minutes=reserved,
            remaining_budget_minutes=(
                None if budget is None else max(0, budget - reserved)
            ),
            over_budget_minutes=(
                0 if budget is None else max(0, reserved - budget)
            ),
            contributions=contributions,
        )

    async def propose(
        self,
        *,
        user_id: str,
        request: DeadlinePlanProposalRequest,
    ) -> DeadlinePlanResponse:
        generated_at = _aware_utc(self._now())
        planning_input = {
            key: value
            for key, value in request.model_dump(mode="json").items()
            if key != "request_id"
        }
        request_fingerprint = _fingerprint(planning_input)
        replay = await self._repository.get_request_identity(
            request_id=request.request_id,
        )
        if replay is not None:
            if (
                replay.get("user_id") != user_id
                or replay.get("operation") != "proposal"
                or replay.get("request_fingerprint") != request_fingerprint
                or str(replay.get("plan_id")) != str(request.plan_id)
            ):
                raise DeadlinePlanConflictError(
                    "request_id is already bound to another deadline operation.",
            )
            return await self.get_plan(user_id=user_id, plan_id=request.plan_id)
        if request.deadline_at.astimezone(UTC) <= generated_at:
            raise DeadlinePlanValidationError("deadline_at must be in the future")
        if (request.deadline_at.date() - request.planning_start_on).days > 368:
            raise DeadlinePlanValidationError(
                "deadline planning horizon cannot exceed 366 profile-local days",
            )
        existing = await self._repository.get_plan(
            user_id=user_id,
            plan_id=request.plan_id,
        )
        if existing is None:
            if request.base_revision != 0:
                raise DeadlinePlanConflictError(
                    "A new deadline plan must start at base_revision 0.",
                )
            tracked_focus_minutes = 0
        else:
            if existing.get("status") not in {"draft", "active"}:
                raise DeadlinePlanConflictError(
                    "A terminal deadline plan cannot be replanned.",
                )
            if _int(existing.get("latest_revision")) != request.base_revision:
                raise DeadlinePlanConflictError(
                    "Deadline plan changed. Reload before replanning.",
                )
            tracked_focus_minutes = await self._tracked_focus_minutes(
                user_id=user_id,
                managed_task_id=existing.get("managed_task_id"),
                first_activated_at=existing.get("first_activated_at"),
            )

        # Read profile-owned context only after the cheap optimistic precheck.
        try:
            profile_probe = await self._repository.load_planning_context(
                user_id=user_id,
                plan_id=request.plan_id,
                starts_on=request.planning_start_on,
                range_starts_at=generated_at,
                range_ends_at=request.deadline_at.astimezone(UTC),
                source_calendar_event_id=request.source_calendar_event_id,
                include_calendar_availability=request.use_calendar_availability,
            )
        except DeadlinePlanPersistenceNotFound as exc:
            raise DeadlinePlanNotFoundError(str(exc)) from exc
        if len(profile_probe.schedule_items) > 1_000:
            raise DeadlinePlanConflictError(
                "Schedule context exceeds the V1 planning bound.",
            )
        zone = _zone(profile_probe.timezone)
        local_now = generated_at.astimezone(zone)
        local_deadline = request.deadline_at.astimezone(zone)
        if request.planning_start_on > local_deadline.date():
            raise DeadlinePlanValidationError(
                "planning_start_on cannot be after the profile-local deadline day",
            )
        if (local_deadline.date() - request.planning_start_on).days > 366:
            raise DeadlinePlanValidationError(
                "deadline planning horizon cannot exceed 366 days",
            )
        use_calendar_availability = (
            profile_probe.planner_use_calendar_busy_time
            if profile_probe.planner_use_calendar_busy_time is not None
            else request.use_calendar_availability
        )
        planning_input["use_calendar_availability"] = use_calendar_availability
        if use_calendar_availability and not (
            profile_probe.calendar_availability_current
        ):
            raise DeadlinePlanConflictError(
                "Calendar availability is not current. Reconnect or disable it.",
            )
        _require_current_source(request=request, context=profile_probe)

        effective_start = max(request.planning_start_on, local_now.date())
        remaining = max(
            0,
            request.estimated_total_minutes
            - request.credited_prior_minutes
            - tracked_focus_minutes,
        )
        context_fingerprint_input = _context_fingerprint_input(
            context=profile_probe,
            plan_id=request.plan_id,
            effective_start=effective_start,
            local_deadline=local_deadline,
            generated_at=generated_at,
        )
        planning_fingerprint = _fingerprint(
            {
                "contract_version": DEADLINE_PLAN_CONTRACT_VERSION,
                "input": planning_input,
                "tracked_focus_minutes_at_proposal": tracked_focus_minutes,
                "context": context_fingerprint_input,
            },
        )
        planned_blocks = _plan_blocks(
            request=request,
            context=profile_probe,
            zone=zone,
            local_now=local_now,
            local_deadline=local_deadline,
            effective_start=effective_start,
            remaining_minutes=remaining,
        )
        blocks = [
            {
                "id": str(
                    uuid5(
                        NAMESPACE_URL,
                        f"{DEADLINE_PLAN_CONTRACT_VERSION}:{request.plan_id}:"
                        f"{request.request_id}:{index}",
                    ),
                ),
                "sequence": index,
                "starts_at": starts_at.astimezone(UTC).isoformat(),
                "ends_at": ends_at.astimezone(UTC).isoformat(),
                "local_date": starts_at.date().isoformat(),
                "local_start_time": starts_at.time().replace(tzinfo=None).isoformat(),
                "local_end_time": ends_at.time().replace(tzinfo=None).isoformat(),
                "planned_minutes": minutes,
            }
            for index, (starts_at, ends_at, minutes) in enumerate(
                planned_blocks,
                start=1,
            )
        ]
        planned_minutes = sum(item[2] for item in planned_blocks)
        proposal = {
            **planning_input,
            "timezone": profile_probe.timezone,
            "best_energy_window": profile_probe.best_energy_window,
            "availability_connection_id": (
                str(profile_probe.availability_connection_id)
                if profile_probe.availability_connection_id
                else None
            ),
            "availability_import_id": (
                str(profile_probe.availability_import_id)
                if profile_probe.availability_import_id
                else None
            ),
            "planning_fingerprint": planning_fingerprint,
            "tracked_focus_minutes_at_proposal": tracked_focus_minutes,
            "remaining_minutes_at_proposal": remaining,
            "planned_minutes": planned_minutes,
            "unscheduled_minutes": remaining - planned_minutes,
        }
        try:
            await self._repository.persist_proposal(
                user_id=user_id,
                request_id=request.request_id,
                request_fingerprint=request_fingerprint,
                plan_id=request.plan_id,
                base_revision=request.base_revision,
                proposal=proposal,
                blocks=blocks,
                now=generated_at,
            )
        except DeadlinePlanPersistenceConflict as exc:
            raise DeadlinePlanConflictError(str(exc)) from exc
        except DeadlinePlanPersistenceNotFound as exc:
            raise DeadlinePlanNotFoundError(str(exc)) from exc
        return await self.get_plan(user_id=user_id, plan_id=request.plan_id)

    async def confirm(
        self,
        *,
        user_id: str,
        plan_id: UUID,
        request: DeadlinePlanMutationRequest,
    ) -> DeadlinePlanResponse:
        await self._run_mutation(
            user_id=user_id,
            plan_id=plan_id,
            request=request,
            operation="confirm",
        )
        return await self.get_plan(user_id=user_id, plan_id=plan_id)

    async def complete(
        self,
        *,
        user_id: str,
        plan_id: UUID,
        request: DeadlinePlanMutationRequest,
    ) -> DeadlinePlanResponse:
        await self._run_mutation(
            user_id=user_id,
            plan_id=plan_id,
            request=request,
            operation="complete",
        )
        return await self.get_plan(user_id=user_id, plan_id=plan_id)

    async def cancel(
        self,
        *,
        user_id: str,
        plan_id: UUID,
        request: DeadlinePlanMutationRequest,
    ) -> DeadlinePlanResponse:
        await self._run_mutation(
            user_id=user_id,
            plan_id=plan_id,
            request=request,
            operation="cancel",
        )
        return await self.get_plan(user_id=user_id, plan_id=plan_id)

    async def _run_mutation(
        self,
        *,
        user_id: str,
        plan_id: UUID,
        request: DeadlinePlanMutationRequest,
        operation: str,
    ) -> None:
        fingerprint = _fingerprint(
            {
                "contract_version": DEADLINE_PLAN_CONTRACT_VERSION,
                "operation": operation,
                "plan_id": str(plan_id),
                "expected_revision": request.expected_revision,
            },
        )
        try:
            if operation == "confirm":
                await self._repository.confirm(
                    user_id=user_id,
                    plan_id=plan_id,
                    request_id=request.request_id,
                    request_fingerprint=fingerprint,
                    expected_revision=request.expected_revision,
                    now=_aware_utc(self._now()),
                )
            else:
                await self._repository.mutate_lifecycle(
                    user_id=user_id,
                    plan_id=plan_id,
                    request_id=request.request_id,
                    request_fingerprint=fingerprint,
                    expected_revision=request.expected_revision,
                    action=operation,
                    now=_aware_utc(self._now()),
                )
        except DeadlinePlanPersistenceConflict as exc:
            raise DeadlinePlanConflictError(str(exc)) from exc
        except DeadlinePlanPersistenceNotFound as exc:
            raise DeadlinePlanNotFoundError(str(exc)) from exc

    async def _details_from_projection(
        self,
        *,
        user_id: str,
        projection: DeadlinePlanProjection,
    ) -> list[DeadlinePlanDetail]:
        plan_rows = projection.plans
        plan_ids = [str(row.get("id")) for row in plan_rows]
        if any(value == "None" for value in plan_ids) or len(set(plan_ids)) != len(
            plan_ids,
        ):
            raise ValueError("Deadline projection contains duplicate plans.")
        if len(projection.revisions) > len(plan_rows) * 2:
            raise ValueError("Deadline revision list exceeds its V1 bound.")
        if len(projection.blocks) > len(plan_rows) * 240:
            raise ValueError("Deadline block list exceeds its V1 bound.")
        revisions_by_plan: dict[str, list[dict[str, Any]]] = {}
        revision_keys: set[tuple[str, int]] = set()
        source_event_ids: set[str] = set()
        for row in projection.revisions:
            key = (str(row.get("plan_id")), _int(row.get("revision")))
            if key[0] not in plan_ids or key in revision_keys:
                raise ValueError("Deadline revision projection is inconsistent.")
            revision_keys.add(key)
            revisions_by_plan.setdefault(key[0], []).append(row)
            if row.get("source_calendar_event_id"):
                source_event_ids.add(str(row["source_calendar_event_id"]))
        blocks_by_plan: dict[str, list[dict[str, Any]]] = {}
        block_ids: set[str] = set()
        for row in projection.blocks:
            block_id = str(row.get("id"))
            key = (str(row.get("plan_id")), _int(row.get("revision")))
            if (
                block_id == "None"
                or block_id in block_ids
                or key not in revision_keys
            ):
                raise ValueError("Deadline block projection is inconsistent.")
            block_ids.add(block_id)
            blocks_by_plan.setdefault(key[0], []).append(row)
        focus_by_plan: dict[str, dict[str, Any]] = {}
        for row in projection.focus_totals:
            key = str(row.get("plan_id"))
            if key not in plan_ids or key in focus_by_plan:
                raise ValueError("Deadline focus total projection is inconsistent.")
            if _int(row.get("focus_count")) > 10_000:
                raise ValueError("Deadline focus history exceeds its V1 bound.")
            focus_by_plan[key] = row
        if set(focus_by_plan) != set(plan_ids):
            raise ValueError("Deadline focus total projection is incomplete.")
        if not set(projection.calendar_events).issubset(source_event_ids):
            raise ValueError("Deadline calendar projection contains unrelated rows.")
        details: list[DeadlinePlanDetail] = []
        for row in plan_rows:
            plan_key = str(row["id"])
            details.append(
                await self._detail_from_components(
                    user_id=user_id,
                    plan_row=row,
                    revisions=revisions_by_plan.get(plan_key, []),
                    blocks=blocks_by_plan.get(plan_key, []),
                    tracked=_int(
                        focus_by_plan[plan_key].get("tracked_focus_minutes"),
                    ),
                    calendar_events=projection.calendar_events,
                ),
            )
        return details

    async def _detail_from_components(
        self,
        *,
        user_id: str,
        plan_row: dict[str, Any],
        revisions: list[dict[str, Any]],
        blocks: list[dict[str, Any]],
        tracked: int,
        calendar_events: dict[str, dict[str, Any]] | None,
    ) -> DeadlinePlanDetail:
        active_row = next(
            (row for row in reversed(revisions) if row.get("state") == "active"),
            None,
        )
        pending_row = next(
            (row for row in reversed(revisions) if row.get("state") == "proposed"),
            None,
        )
        current_row = active_row or pending_row
        estimate = (
            _int(current_row["estimated_total_minutes"])
            if current_row is not None
            else _int(plan_row["original_estimated_total_minutes"])
        )
        prior = (
            _int(current_row["credited_prior_minutes"])
            if current_row is not None
            else _int(plan_row["original_credited_prior_minutes"])
        )
        accounted = min(estimate, prior + tracked)
        now = _aware_utc(self._now())
        active_revision = await self._revision_from_row(
            user_id=user_id,
            row=active_row,
            block_rows=blocks,
            tracked_focus_minutes=tracked,
            now=now,
            plan_status=plan_row["status"],
            calendar_events=calendar_events,
        )
        pending_revision = await self._revision_from_row(
            user_id=user_id,
            row=pending_row,
            block_rows=blocks,
            tracked_focus_minutes=0,
            now=now,
            plan_status=plan_row["status"],
            calendar_events=calendar_events,
        )
        return DeadlinePlanDetail(
            plan=_plan_identity(plan_row),
            active_revision=active_revision,
            pending_revision=pending_revision,
            progress=DeadlinePlanProgress(
                estimated_total_minutes=estimate,
                credited_prior_minutes=prior,
                tracked_focus_minutes=tracked,
                accounted_minutes=accounted,
                remaining_minutes=estimate - accounted,
                completion_suggested=accounted >= estimate,
            ),
        )

    async def _revision_from_row(
        self,
        *,
        user_id: str,
        row: dict[str, Any] | None,
        block_rows: list[dict[str, Any]],
        tracked_focus_minutes: int,
        now: datetime,
        plan_status: str,
        calendar_events: dict[str, dict[str, Any]] | None,
    ) -> DeadlinePlanRevision | None:
        if row is None:
            return None
        plan_id = UUID(str(row["plan_id"]))
        revision_number = _int(row["revision"])
        matching_blocks = [
            block
            for block in block_rows
            if _int(block.get("revision")) == revision_number
        ]
        matching_blocks.sort(key=lambda item: (_int(item["sequence"]), str(item["id"])))
        credit_left = (
            max(
                0,
                tracked_focus_minutes
                - _int(row.get("tracked_focus_minutes_at_proposal")),
            )
            if row.get("state") == "active"
            else 0
        )
        rendered_blocks: list[DeadlinePlanBlock] = []
        for block in matching_blocks:
            planned = _int(block["planned_minutes"])
            credit = min(planned, credit_left)
            credit_left -= credit
            starts_at = _datetime(block["starts_at"])
            ends_at = _datetime(block["ends_at"])
            if row.get("state") == "proposed":
                display_state = "proposed"
            elif credit == planned:
                display_state = "completed"
            elif credit > 0:
                display_state = "partial"
            elif plan_status in {"completed", "cancelled"}:
                display_state = "missed"
            elif now >= ends_at:
                display_state = "missed"
            else:
                display_state = "upcoming"
            rendered_blocks.append(
                DeadlinePlanBlock(
                    id=UUID(str(block["id"])),
                    sequence=_int(block["sequence"]),
                    starts_at=starts_at,
                    ends_at=ends_at,
                    local_date=_date(block["local_date"]),
                    local_start_time=_time(block["local_start_time"]),
                    local_end_time=_time(block["local_end_time"]),
                    planned_minutes=planned,
                    credited_tracked_minutes=credit,
                    state=display_state,
                ),
            )
        source_status = "not_applicable"
        event_id = row.get("source_calendar_event_id")
        if row.get("source_kind") == "calendar_event":
            if event_id and calendar_events is not None:
                event = calendar_events.get(str(event_id))
            elif event_id:
                event = await self._repository.get_calendar_event(
                    user_id=user_id,
                    event_id=UUID(str(event_id)),
                )
            else:
                event = None
            if event is None:
                source_status = "unavailable"
            elif _calendar_event_is_current(event) and event.get(
                "source_fingerprint",
            ) == row.get("source_calendar_event_fingerprint"):
                source_status = "current"
            else:
                source_status = "stale"
        return DeadlinePlanRevision(
            plan_id=plan_id,
            revision=revision_number,
            base_revision=_int(row["base_revision"]),
            state=row["state"],
            kind=row["kind"],
            title=row["title"],
            deadline_at=_datetime(row["deadline_at"]),
            estimated_total_minutes=_int(row["estimated_total_minutes"]),
            credited_prior_minutes=_int(row["credited_prior_minutes"]),
            preferred_session_minutes=_int(row["preferred_session_minutes"]),
            max_daily_minutes=_int(row["max_daily_minutes"]),
            planning_start_on=_date(row["planning_start_on"]),
            buffer_days=_int(row["buffer_days"]),
            source_kind=row["source_kind"],
            source_calendar_event_id=(UUID(str(event_id)) if event_id else None),
            source_calendar_event_fingerprint=row.get(
                "source_calendar_event_fingerprint",
            ),
            source_status=source_status,
            use_calendar_availability=row["use_calendar_availability"],
            availability_connection_id=(
                UUID(str(row["availability_connection_id"]))
                if row.get("availability_connection_id")
                else None
            ),
            availability_import_id=(
                UUID(str(row["availability_import_id"]))
                if row.get("availability_import_id")
                else None
            ),
            timezone=row["timezone"],
            best_energy_window=row["best_energy_window"],
            planning_fingerprint=row["planning_fingerprint"],
            tracked_focus_minutes_at_proposal=_int(
                row["tracked_focus_minutes_at_proposal"],
            ),
            remaining_minutes_at_proposal=_int(
                row["remaining_minutes_at_proposal"],
            ),
            planned_minutes=_int(row["planned_minutes"]),
            unscheduled_minutes=_int(row["unscheduled_minutes"]),
            created_at=_datetime(row["created_at"]),
            activated_at=_optional_datetime(row.get("activated_at")),
            superseded_at=_optional_datetime(row.get("superseded_at")),
            blocks=rendered_blocks,
        )

    async def _tracked_focus_minutes(
        self,
        *,
        user_id: str,
        managed_task_id: object,
        first_activated_at: object,
    ) -> int:
        if managed_task_id is None or first_activated_at is None:
            return 0
        rows = await self._repository.list_completed_focus(
            user_id=user_id,
            task_id=UUID(str(managed_task_id)),
            started_at_or_after=_datetime(first_activated_at),
        )
        if len(rows) > 10_000:
            raise ValueError("Deadline focus history exceeds its V1 bound.")
        return sum(max(0, _int(row.get("actual_minutes"))) for row in rows)


def _plan_blocks(
    *,
    request: DeadlinePlanProposalRequest,
    context: DeadlinePlanningContext,
    zone: ZoneInfo,
    local_now: datetime,
    local_deadline: datetime,
    effective_start: date,
    remaining_minutes: int,
) -> list[tuple[datetime, datetime, int]]:
    deadline_day = local_deadline.date()
    last_preferred_day = (
        deadline_day
        if request.buffer_days == 0
        else deadline_day - timedelta(days=request.buffer_days + 1)
    )
    reserved_by_day = _confirmed_preparation_minutes_by_day(context)
    intervals = allocate_task_intervals(
        starts_on=effective_start,
        ends_on=last_preferred_day,
        total_minutes=remaining_minutes,
        preferred_session_minutes=request.preferred_session_minutes,
        max_daily_minutes=request.max_daily_minutes,
        zone=zone,
        local_now=local_now,
        energy_window=context.best_energy_window,
        busy_sources=BusySources(
            recurring_commitments=[
                *context.schedule_items,
                *(context.planner_recurring_commitments or []),
            ],
            timed_intervals=[
                *context.confirmed_blocks,
                *(context.planner_timed_intervals or []),
                *context.timed_calendar_events,
            ],
            all_day_intervals=context.all_day_calendar_events,
        ),
        deadline_at=local_deadline,
        daily_reserved_minutes=reserved_by_day,
        account_daily_budget_minutes=context.daily_preparation_budget_minutes,
        max_blocks=120,
        # Deadline Planner V1 permits an exact final minute remainder. Planner
        # Action V1 below opts into the stricter five-minute duration grid.
        duration_increment_minutes=1,
    )
    return [
        (interval.starts_at, interval.ends_at, interval.minutes)
        for interval in intervals
    ]


def _busy_intervals_by_day(
    *,
    days: list[date],
    context: DeadlinePlanningContext,
    zone: ZoneInfo,
    local_now: datetime,
) -> dict[date, list[tuple[datetime, datetime]]]:
    result: dict[date, list[tuple[datetime, datetime]]] = {day: [] for day in days}
    day_set = set(days)
    for day in days:
        if day == local_now.date():
            rounded_now = _round_up_quarter_hour(
                local_now + timedelta(minutes=15),
            )
            result[day].append(
                (datetime.combine(day, time.min, tzinfo=zone), rounded_now),
            )
    for item in context.schedule_items:
        weekday = _int(item.get("weekday"))
        starts = _time(item.get("starts_at"))
        ends = _time(item.get("ends_at"))
        if ends <= starts:
            continue
        for day in days:
            if day.isoweekday() == weekday and recurring_commitment_applies_on(
                item,
                day,
            ):
                result[day].append(
                    (
                        datetime.combine(day, starts, tzinfo=zone),
                        datetime.combine(day, ends, tzinfo=zone),
                    ),
                )
    for item in [*context.confirmed_blocks, *context.timed_calendar_events]:
        starts_at = _datetime(item.get("starts_at")).astimezone(zone)
        ends_at = _datetime(item.get("ends_at")).astimezone(zone)
        cursor = starts_at.date()
        while cursor <= ends_at.date():
            if cursor in day_set:
                result[cursor].append((starts_at, ends_at))
            cursor += timedelta(days=1)
    for item in context.all_day_calendar_events:
        starts_on = _date(item.get("starts_on"))
        ends_on = _date(item.get("ends_on"))
        cursor = starts_on
        while cursor < ends_on:
            if cursor in day_set:
                result[cursor].append(
                    (
                        datetime.combine(cursor, time.min, tzinfo=zone),
                        datetime.combine(
                            cursor + timedelta(days=1),
                            time.min,
                            tzinfo=zone,
                        ),
                    ),
                )
            cursor += timedelta(days=1)
    return {day: _merge_intervals(intervals) for day, intervals in result.items()}


def _subtract_intervals(
    starts_at: datetime,
    ends_at: datetime,
    busy: list[tuple[datetime, datetime]],
) -> list[tuple[datetime, datetime]]:
    gaps: list[tuple[datetime, datetime]] = []
    cursor = starts_at
    for busy_start, busy_end in busy:
        clipped_start = max(starts_at, busy_start)
        clipped_end = min(ends_at, busy_end)
        if clipped_end <= cursor or clipped_start >= ends_at:
            continue
        if clipped_start > cursor:
            gaps.append((cursor, clipped_start))
        cursor = max(cursor, clipped_end)
    if cursor < ends_at:
        gaps.append((cursor, ends_at))
    return gaps


def _merge_intervals(
    intervals: Iterable[tuple[datetime, datetime]],
) -> list[tuple[datetime, datetime]]:
    merged: list[tuple[datetime, datetime]] = []
    for starts_at, ends_at in sorted(intervals, key=lambda value: value[0]):
        if ends_at <= starts_at:
            continue
        if not merged or starts_at > merged[-1][1]:
            merged.append((starts_at, ends_at))
        else:
            merged[-1] = (merged[-1][0], max(merged[-1][1], ends_at))
    return merged


def _confirmed_preparation_minutes_by_day(
    context: DeadlinePlanningContext,
) -> dict[date, int]:
    totals: dict[date, int] = {}
    for row in context.confirmed_blocks:
        local_day = _date(row.get("local_date"))
        minutes = _int(row.get("planned_minutes"))
        if minutes < 5 or minutes > 240:
            raise ValueError("Confirmed preparation duration is invalid.")
        totals[local_day] = totals.get(local_day, 0) + minutes
    return totals


def _fixed_commitment_minutes(
    schedule_items: list[dict[str, Any]],
    *,
    local_day: date,
) -> int:
    intervals: list[tuple[int, int]] = []
    for row in schedule_items:
        if (
            _int(row.get("weekday")) != local_day.isoweekday()
            or not recurring_commitment_applies_on(row, local_day)
        ):
            continue
        starts = _time(row.get("starts_at"))
        ends = _time(row.get("ends_at"))
        start_minute = starts.hour * 60 + starts.minute
        end_minute = ends.hour * 60 + ends.minute
        if end_minute > start_minute:
            intervals.append((start_minute, end_minute))
    merged: list[tuple[int, int]] = []
    for starts, ends in sorted(intervals):
        if not merged or starts > merged[-1][1]:
            merged.append((starts, ends))
        else:
            merged[-1] = (merged[-1][0], max(merged[-1][1], ends))
    return sum(ends - starts for starts, ends in merged)


def _days(starts_on: date, ends_on: date) -> Iterable[date]:
    cursor = starts_on
    while cursor <= ends_on:
        yield cursor
        cursor += timedelta(days=1)


def _context_fingerprint_input(
    *,
    context: DeadlinePlanningContext,
    plan_id: UUID,
    effective_start: date,
    local_deadline: datetime,
    generated_at: datetime,
) -> dict[str, Any]:
    return {
        "timezone": context.timezone,
        "best_energy_window": context.best_energy_window,
        "daily_preparation_budget_minutes": (
            context.daily_preparation_budget_minutes
        ),
        "availability_connection_id": context.availability_connection_id,
        "availability_import_id": context.availability_import_id,
        "effective_start": effective_start.isoformat(),
        "local_deadline_day": local_deadline.date().isoformat(),
        "captured_at": generated_at.isoformat(),
        "schedule_items": context.schedule_items,
        "confirmed_blocks": [
            item
            for item in context.confirmed_blocks
            if str(item.get("plan_id")) != str(plan_id)
        ],
        "timed_calendar_events": context.timed_calendar_events,
        "all_day_calendar_events": context.all_day_calendar_events,
        "source_calendar_event": context.source_calendar_event,
        "planner_recurring_commitments": (
            context.planner_recurring_commitments or []
        ),
        "planner_timed_intervals": context.planner_timed_intervals or [],
        "planner_use_calendar_busy_time": (
            context.planner_use_calendar_busy_time
        ),
    }


def _require_current_source(
    *,
    request: DeadlinePlanProposalRequest,
    context: DeadlinePlanningContext,
) -> None:
    if request.source_kind == "manual":
        return
    event = context.source_calendar_event
    if event is None:
        raise DeadlinePlanConflictError(
            "Selected calendar source is unavailable. Reload before planning.",
        )
    if not _calendar_event_is_current(event) or event.get(
        "source_fingerprint",
    ) != request.source_calendar_event_fingerprint:
        raise DeadlinePlanConflictError(
            "Selected calendar source changed. Reload before planning.",
        )


def _calendar_event_is_current(event: dict[str, Any]) -> bool:
    return (
        event.get("_connection_status") == "connected"
        and event.get("_connection_imported_data_deleted_at") is None
        and event.get("import_id") is not None
        and str(event.get("import_id"))
        == str(event.get("_connection_last_import_id"))
    )


def _round_up_quarter_hour(value: datetime) -> datetime:
    rounded = value.replace(second=0, microsecond=0)
    remainder = rounded.minute % 15
    if value.second or value.microsecond or remainder:
        rounded += timedelta(minutes=(15 - remainder) if remainder else 15)
    return rounded


def _ceil_local_five_minutes(value: datetime) -> datetime:
    rounded = value.replace(second=0, microsecond=0)
    remainder = rounded.minute % 5
    if value.second or value.microsecond or remainder:
        rounded += timedelta(minutes=(5 - remainder) if remainder else 5)
    return rounded


def _floor_local_five_minutes(value: datetime) -> datetime:
    return value.replace(
        minute=value.minute - (value.minute % 5),
        second=0,
        microsecond=0,
    )


def _safe_fixed_offset_interval(
    starts_at: datetime,
    ends_at: datetime,
    zone: ZoneInfo,
) -> bool:
    if ends_at <= starts_at or starts_at.utcoffset() != ends_at.utcoffset():
        return False
    return _is_unambiguous_local(starts_at, zone) and _is_unambiguous_local(
        ends_at,
        zone,
    )


def _is_unambiguous_local(value: datetime, zone: ZoneInfo) -> bool:
    naive = value.replace(tzinfo=None)
    instants = {
        candidate.astimezone(UTC)
        for fold in (0, 1)
        if (
            candidate := naive.replace(tzinfo=zone, fold=fold)
        ).astimezone(UTC).astimezone(zone).replace(tzinfo=None)
        == naive
    }
    return len(instants) == 1


def _plan_identity(row: dict[str, Any]) -> DeadlinePlanIdentity:
    return DeadlinePlanIdentity(
        id=UUID(str(row["id"])),
        status=row["status"],
        kind=row["kind"],
        title=row["title"],
        managed_task_id=(
            UUID(str(row["managed_task_id"])) if row.get("managed_task_id") else None
        ),
        original_estimated_total_minutes=_int(
            row["original_estimated_total_minutes"],
        ),
        original_credited_prior_minutes=_int(row["original_credited_prior_minutes"]),
        current_revision=_int(row["current_revision"]),
        latest_revision=_int(row["latest_revision"]),
        created_at=_datetime(row["created_at"]),
        updated_at=_datetime(row["updated_at"]),
        completed_at=_optional_datetime(row.get("completed_at")),
        cancelled_at=_optional_datetime(row.get("cancelled_at")),
    )


def _response(detail: DeadlinePlanDetail) -> DeadlinePlanResponse:
    return DeadlinePlanResponse(
        contract_version=DEADLINE_PLAN_CONTRACT_VERSION,
        origin="authenticated_backend",
        plan=detail.plan,
        active_revision=detail.active_revision,
        pending_revision=detail.pending_revision,
        progress=detail.progress,
    )


def _fingerprint(value: Any) -> str:
    encoded = json.dumps(
        value,
        sort_keys=True,
        separators=(",", ":"),
        ensure_ascii=False,
        default=_json_default,
    ).encode("utf-8")
    return hashlib.sha256(encoded).hexdigest()


def _json_default(value: Any) -> str:
    if isinstance(value, (date, datetime, time, UUID)):
        return value.isoformat() if not isinstance(value, UUID) else str(value)
    raise TypeError(f"Unsupported canonical JSON value: {type(value)!r}")


def _zone(value: str) -> ZoneInfo:
    try:
        return ZoneInfo(value)
    except ZoneInfoNotFoundError as exc:
        raise DeadlinePlanValidationError("Profile timezone is invalid.") from exc


def _aware_utc(value: datetime) -> datetime:
    if value.tzinfo is None or value.utcoffset() is None:
        raise ValueError("Deadline service clock must be timezone-aware.")
    return value.astimezone(UTC)


def _datetime(value: object) -> datetime:
    if isinstance(value, datetime):
        parsed = value
    elif isinstance(value, str):
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    else:
        raise ValueError("Deadline timestamp is invalid.")
    if parsed.tzinfo is None or parsed.utcoffset() is None:
        raise ValueError("Deadline timestamp must be timezone-aware.")
    return parsed


def _optional_datetime(value: object) -> datetime | None:
    return None if value is None else _datetime(value)


def _date(value: object) -> date:
    if isinstance(value, date) and not isinstance(value, datetime):
        return value
    if isinstance(value, str):
        return date.fromisoformat(value)
    raise ValueError("Deadline local date is invalid.")


def _time(value: object) -> time:
    if isinstance(value, time):
        return value.replace(tzinfo=None)
    if isinstance(value, str):
        return time.fromisoformat(value).replace(tzinfo=None)
    raise ValueError("Deadline local time is invalid.")


def _int(value: object) -> int:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise ValueError("Deadline integer is invalid.")
    if int(value) != value:
        raise ValueError("Deadline integer is invalid.")
    return int(value)
