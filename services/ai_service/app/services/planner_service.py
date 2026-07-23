from __future__ import annotations

import hashlib
import json
from collections.abc import Callable, Iterable, Mapping, Sequence
from datetime import UTC, date, datetime, time, timedelta
from typing import Any, Protocol
from uuid import NAMESPACE_URL, UUID, uuid5
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from pydantic import TypeAdapter, ValidationError

from app.models.deadline_plans import DeadlinePlansResponse
from app.models.planner import (
    PLANNER_CONTRACT_VERSION,
    PLANNER_PREFERENCES_CONTRACT_VERSION,
    PlannerActionMutationRequest,
    PlannerActionPlan,
    PlannerActionPlanResponse,
    PlannerActionProposalRequest,
    PlannerActionRevision,
    PlannerActionTarget,
    PlannerAttentionItem,
    PlannerCommitment,
    PlannerCommitmentArchiveRequest,
    PlannerCommitmentCreateRequest,
    PlannerCommitmentResponse,
    PlannerCommitmentUpdateRequest,
    PlannerDay,
    PlannerDayItem,
    PlannerHabitSlot,
    PlannerHabitTarget,
    PlannerOverviewResponse,
    PlannerPreferencesResponse,
    PlannerPreferencesUpdateRequest,
    PlannerPreparationSummary,
    PlannerTaskBlock,
    PlannerTaskTarget,
    PlannerUnscheduledItem,
)
from app.repositories.planner_repository import (
    PlannerAvailabilityContext,
    PlannerOverviewContext,
    PlannerPersistenceConflict,
    PlannerPersistenceNotFound,
    PlannerProjection,
    PlannerRepository,
)
from app.services.planning_availability import (
    BusySources,
    allocate_task_intervals,
    choose_recurring_habit_slots,
    recurring_commitment_applies_on,
)


class PlannerConflictError(RuntimeError):
    pass


class PlannerNotFoundError(RuntimeError):
    pass


class PlannerValidationError(ValueError):
    pass


class DeadlinePlanReader(Protocol):
    async def list_plans(self, *, user_id: str) -> DeadlinePlansResponse: ...


class PlannerService:
    def __init__(
        self,
        *,
        repository: PlannerRepository,
        deadline_plans: DeadlinePlanReader | None = None,
        now: Callable[[], datetime] | None = None,
    ) -> None:
        self._repository = repository
        self._deadline_plans = deadline_plans
        self._now = now or (lambda: datetime.now(UTC))

    async def get_preferences(self, *, user_id: str) -> PlannerPreferencesResponse:
        try:
            context = await self._repository.load_preference_context(user_id=user_id)
        except PlannerPersistenceNotFound as exc:
            raise PlannerNotFoundError(str(exc)) from exc
        return _preferences_response(
            preference=context.preference,
            calendar_import_id=context.calendar.import_id,
            calendar_available=context.calendar.available,
        )

    async def update_preferences(
        self,
        *,
        user_id: str,
        request: PlannerPreferencesUpdateRequest,
    ) -> PlannerPreferencesResponse:
        now = _aware_utc(self._now())
        try:
            await self._repository.set_preferences(
                user_id=user_id,
                request_id=request.request_id,
                expected_updated_at=request.expected_updated_at,
                use_calendar_busy_time=request.use_calendar_busy_time,
                now=now,
            )
        except PlannerPersistenceConflict as exc:
            raise PlannerConflictError(str(exc)) from exc
        except PlannerPersistenceNotFound as exc:
            raise PlannerNotFoundError(str(exc)) from exc
        return await self.get_preferences(user_id=user_id)

    async def get_action_plan(
        self,
        *,
        user_id: str,
        plan_id: UUID,
    ) -> PlannerActionPlanResponse:
        projection = await self._repository.load_projection(
            user_id=user_id,
            plan_id=plan_id,
        )
        if not projection.plans:
            raise PlannerNotFoundError("Planner action plan is unavailable.")
        if len(projection.plans) != 1:
            raise ValueError("Planner action plan projection is ambiguous.")
        plan = _plan_from_projection(projection=projection, plan_id=plan_id)
        return PlannerActionPlanResponse(
            contract_version=PLANNER_CONTRACT_VERSION,
            origin="authenticated_backend",
            plan=plan,
        )

    async def propose(
        self,
        *,
        user_id: str,
        request: PlannerActionProposalRequest,
    ) -> PlannerActionPlanResponse:
        now = _aware_utc(self._now())
        request_input = {
            key: value
            for key, value in request.model_dump(mode="json").items()
            if key != "request_id"
        }
        request_fingerprint = _fingerprint(
            {
                "contract_version": PLANNER_CONTRACT_VERSION,
                "operation": "proposal",
                "input": request_input,
            },
        )
        replay = await self._repository.get_request_identity(
            request_id=request.request_id,
        )
        if replay is not None:
            _require_matching_request(
                replay,
                user_id=user_id,
                operation="proposal",
                resource_id=request.plan_id,
                fingerprint=request_fingerprint,
            )
            return await self.get_action_plan(user_id=user_id, plan_id=request.plan_id)

        current = await self._repository.load_projection(
            user_id=user_id,
            plan_id=request.plan_id,
        )
        if not current.plans:
            if request.base_revision != 0:
                raise PlannerConflictError(
                    "A new action plan must start at base_revision 0.",
                )
        else:
            if len(current.plans) != 1:
                raise ValueError("Planner action plan projection is ambiguous.")
            row = current.plans[0]
            if row.get("status") == "cancelled":
                raise PlannerConflictError("A cancelled action plan cannot be changed.")
            if _int(row.get("latest_revision")) != request.base_revision:
                raise PlannerConflictError(
                    "The action plan changed. Reload before planning again.",
                )
            if (
                str(row.get("target_id")) != str(request.target.target_id)
                or row.get("target_kind") != request.target.kind
            ):
                raise PlannerConflictError(
                    "The action plan is already bound to another target.",
                )

        planning_ends_on = _planning_end(request=request, generated_at=now)
        # This cheap precheck intentionally leaves one day of UTC/local-date
        # tolerance. The exact 366-day profile-local bound is checked after
        # loading the owner's timezone below.
        if (planning_ends_on - request.planning_start_on).days > 367:
            raise PlannerValidationError(
                "Planner previews are bounded to 366 profile-local days.",
            )
        try:
            context = await self._repository.load_availability_context(
                user_id=user_id,
                plan_id=request.plan_id,
                target_kind=request.target.kind,
                target_id=request.target.target_id,
                starts_on=request.planning_start_on,
                ends_on=planning_ends_on,
            )
        except PlannerPersistenceNotFound as exc:
            raise PlannerNotFoundError(str(exc)) from exc
        _validate_context_bounds(context)
        zone = _zone(context.timezone)
        local_now = now.astimezone(zone)
        effective_start = max(request.planning_start_on, local_now.date())
        if isinstance(request.target, PlannerTaskTarget) and request.target.deadline_at:
            local_planning_end = request.target.deadline_at.astimezone(zone).date()
            if (local_planning_end - request.planning_start_on).days > 365:
                raise PlannerValidationError(
                    "Planner previews are bounded to 366 profile-local days.",
                )
        else:
            local_planning_end = planning_ends_on
        if local_planning_end < effective_start:
            raise PlannerValidationError("The planning window has already ended.")
        _validate_target_projection(request.target, context.target)
        study_rhythm = _study_rhythm(context.study_setup)
        use_study_rhythm = (
            isinstance(request.target, PlannerTaskTarget)
            and request.target.use_study_rhythm
        )
        if use_study_rhythm:
            if study_rhythm is None:
                raise PlannerConflictError(
                    "Configure a Study rhythm before using it for a Task.",
                )
            if request.target.preferred_session_minutes != study_rhythm[1]:
                raise PlannerValidationError(
                    "The Task session duration must match the current Study rhythm.",
                )
        study_setup_revision = study_rhythm[0] if use_study_rhythm else None
        recovery_minutes = study_rhythm[2] if use_study_rhythm else 0

        calendar_enabled = bool(
            context.preference
            and context.preference.get("use_calendar_busy_time") is True
        )
        if calendar_enabled and not context.calendar.available:
            raise PlannerConflictError(
                "Calendar busy time is enabled, but no current import is available.",
            )
        sources = _availability_sources(
            context=context,
            calendar_enabled=calendar_enabled,
        )
        task_blocks: list[dict[str, Any]] = []
        habit_slots: list[dict[str, Any]] = []
        planned_minutes = 0
        unscheduled_minutes = 0

        if isinstance(request.target, PlannerTaskTarget):
            all_scheduling_inputs = all(
                value is not None
                for value in (
                    request.target.estimated_minutes,
                    request.target.deadline_at,
                    request.target.preferred_session_minutes,
                )
            )
            if all_scheduling_inputs:
                assert request.target.estimated_minutes is not None
                assert request.target.deadline_at is not None
                assert request.target.preferred_session_minutes is not None
                if request.target.deadline_at.astimezone(UTC) <= now:
                    raise PlannerValidationError(
                        "The task deadline must be in the future.",
                    )
                if request.target.deadline_at.astimezone(zone).date() < effective_start:
                    raise PlannerValidationError(
                        "The task deadline precedes the planning window.",
                    )
                intervals = allocate_task_intervals(
                    starts_on=effective_start,
                    ends_on=request.target.deadline_at.astimezone(zone).date(),
                    total_minutes=request.target.estimated_minutes,
                    preferred_session_minutes=request.target.preferred_session_minutes,
                    max_daily_minutes=480,
                    zone=zone,
                    local_now=local_now,
                    energy_window=context.best_energy_window,
                    busy_sources=sources,
                    deadline_at=request.target.deadline_at,
                    max_blocks=1_500,
                    duration_increment_minutes=5,
                    recovery_minutes=recovery_minutes,
                    exact_session_blocks=use_study_rhythm,
                )
                for sequence, interval in enumerate(intervals, start=1):
                    task_blocks.append(
                        {
                            "id": str(
                                uuid5(
                                    NAMESPACE_URL,
                                    f"{PLANNER_CONTRACT_VERSION}:{request.plan_id}:"
                                    f"{request.request_id}:task:{sequence}",
                                ),
                            ),
                            "sequence": sequence,
                            "starts_at": interval.starts_at.astimezone(UTC).isoformat(),
                            "ends_at": interval.ends_at.astimezone(UTC).isoformat(),
                            "recovery_minutes": interval.recovery_minutes,
                            "reserved_ends_at": (
                                interval.reserved_ends_at or interval.ends_at
                            ).astimezone(UTC).isoformat(),
                            "local_date": interval.starts_at.date().isoformat(),
                            "planned_minutes": interval.minutes,
                        },
                    )
                planned_minutes = sum(item["planned_minutes"] for item in task_blocks)
                unscheduled_minutes = request.target.estimated_minutes - planned_minutes
            else:
                unscheduled_minutes = request.target.estimated_minutes or 0
        else:
            weekdays = _habit_weekdays(request.target)
            selected, unplaced = choose_recurring_habit_slots(
                weekdays=weekdays,
                duration_minutes=request.target.duration_minutes,
                horizon_starts_on=effective_start,
                horizon_days=28,
                zone=zone,
                local_now=local_now,
                energy_window=context.best_energy_window,
                busy_sources=sources,
            )
            for slot in selected:
                habit_slots.append(
                    {
                        "id": str(
                            uuid5(
                                NAMESPACE_URL,
                                f"{PLANNER_CONTRACT_VERSION}:{request.plan_id}:"
                                f"{request.request_id}:habit:{slot.weekday}",
                            ),
                        ),
                        "weekday": slot.weekday,
                        "starts_at": slot.starts_at.isoformat(),
                        "ends_at": slot.ends_at.isoformat(),
                        "duration_minutes": slot.minutes,
                    },
                )
            planned_minutes = sum(item["duration_minutes"] for item in habit_slots)
            unscheduled_minutes = len(unplaced) * request.target.duration_minutes

        context_fingerprint = _fingerprint(
            {
                "timezone": context.timezone,
                "best_energy_window": context.best_energy_window,
                "effective_start": effective_start.isoformat(),
                "calendar_import_id": (
                    str(context.calendar.import_id)
                    if calendar_enabled and context.calendar.import_id
                    else None
                ),
                "schedule_items": _stable_rows(context.schedule_items),
                "commitments": _stable_rows(context.commitments),
                "task_blocks": _stable_rows(context.task_blocks),
                "habit_slots": _stable_rows(context.habit_slots),
                "deadline_blocks": _stable_rows(context.deadline_blocks),
                "calendar_timed": (
                    _stable_rows(context.calendar.timed_events)
                    if calendar_enabled
                    else []
                ),
                "calendar_all_day": (
                    _stable_rows(context.calendar.all_day_events)
                    if calendar_enabled
                    else []
                ),
                "study_setup": (
                    {
                        "setup_revision": study_setup_revision,
                        "focus_minutes": study_rhythm[1],
                        "recovery_minutes": recovery_minutes,
                    }
                    if use_study_rhythm and study_rhythm is not None
                    else None
                ),
            },
        )
        target_payload = request.target.model_dump(mode="json")
        revision_payload = {
            "revision": request.base_revision + 1,
            "base_revision": request.base_revision,
            "target": target_payload,
            "timezone": context.timezone,
            "best_energy_window": context.best_energy_window,
            "planning_start_on": request.planning_start_on.isoformat(),
            "planning_fingerprint": _fingerprint(
                {
                    "contract_version": PLANNER_CONTRACT_VERSION,
                    "request": request_input,
                    "context_fingerprint": context_fingerprint,
                    "task_blocks": task_blocks,
                    "habit_slots": habit_slots,
                },
            ),
            "calendar_import_id": (
                str(context.calendar.import_id)
                if calendar_enabled and context.calendar.import_id
                else None
            ),
            "study_setup_revision": study_setup_revision,
            "recovery_minutes": recovery_minutes,
            "planned_minutes": planned_minutes,
            "unscheduled_minutes": unscheduled_minutes,
        }
        try:
            await self._repository.persist_proposal(
                user_id=user_id,
                request_id=request.request_id,
                request_fingerprint=request_fingerprint,
                plan_id=request.plan_id,
                base_revision=request.base_revision,
                target_kind=request.target.kind,
                target_id=request.target.target_id,
                target_payload=target_payload,
                revision_payload=revision_payload,
                task_blocks=task_blocks,
                habit_slots=habit_slots,
                now=now,
            )
        except PlannerPersistenceConflict as exc:
            raise PlannerConflictError(str(exc)) from exc
        except PlannerPersistenceNotFound as exc:
            raise PlannerNotFoundError(str(exc)) from exc
        return await self.get_action_plan(user_id=user_id, plan_id=request.plan_id)

    async def confirm(
        self,
        *,
        user_id: str,
        plan_id: UUID,
        request: PlannerActionMutationRequest,
    ) -> PlannerActionPlanResponse:
        await self._mutate_plan(
            user_id=user_id,
            plan_id=plan_id,
            request=request,
            operation="confirm",
        )
        return await self.get_action_plan(user_id=user_id, plan_id=plan_id)

    async def cancel(
        self,
        *,
        user_id: str,
        plan_id: UUID,
        request: PlannerActionMutationRequest,
    ) -> PlannerActionPlanResponse:
        await self._mutate_plan(
            user_id=user_id,
            plan_id=plan_id,
            request=request,
            operation="cancel",
        )
        return await self.get_action_plan(user_id=user_id, plan_id=plan_id)

    async def _mutate_plan(
        self,
        *,
        user_id: str,
        plan_id: UUID,
        request: PlannerActionMutationRequest,
        operation: str,
    ) -> None:
        fingerprint = _fingerprint(
            {
                "contract_version": PLANNER_CONTRACT_VERSION,
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
                    expected_revision=request.expected_revision,
                    request_fingerprint=fingerprint,
                    now=_aware_utc(self._now()),
                )
            else:
                await self._repository.cancel(
                    user_id=user_id,
                    plan_id=plan_id,
                    request_id=request.request_id,
                    expected_revision=request.expected_revision,
                    request_fingerprint=fingerprint,
                    now=_aware_utc(self._now()),
                )
        except PlannerPersistenceConflict as exc:
            raise PlannerConflictError(str(exc)) from exc
        except PlannerPersistenceNotFound as exc:
            raise PlannerNotFoundError(str(exc)) from exc

    async def create_commitment(
        self,
        *,
        user_id: str,
        request: PlannerCommitmentCreateRequest,
    ) -> PlannerCommitmentResponse:
        return await self._mutate_commitment(
            user_id=user_id,
            commitment_id=request.commitment_id,
            request_id=request.request_id,
            operation="create",
            expected_updated_at=None,
            payload=_commitment_payload(request),
        )

    async def update_commitment(
        self,
        *,
        user_id: str,
        commitment_id: UUID,
        request: PlannerCommitmentUpdateRequest,
    ) -> PlannerCommitmentResponse:
        if request.commitment_id != commitment_id:
            raise PlannerValidationError(
                "The commitment path and request identity do not match.",
            )
        return await self._mutate_commitment(
            user_id=user_id,
            commitment_id=commitment_id,
            request_id=request.request_id,
            operation="update",
            expected_updated_at=request.expected_updated_at,
            payload=_commitment_payload(request),
        )

    async def archive_commitment(
        self,
        *,
        user_id: str,
        commitment_id: UUID,
        request: PlannerCommitmentArchiveRequest,
    ) -> PlannerCommitmentResponse:
        return await self._mutate_commitment(
            user_id=user_id,
            commitment_id=commitment_id,
            request_id=request.request_id,
            operation="archive",
            expected_updated_at=request.expected_updated_at,
            payload=None,
        )

    async def _mutate_commitment(
        self,
        *,
        user_id: str,
        commitment_id: UUID,
        request_id: UUID,
        operation: str,
        expected_updated_at: datetime | None,
        payload: dict[str, Any] | None,
    ) -> PlannerCommitmentResponse:
        fingerprint = _fingerprint(
            {
                "contract_version": PLANNER_CONTRACT_VERSION,
                "operation": operation,
                "commitment_id": str(commitment_id),
                "expected_updated_at": (
                    expected_updated_at.isoformat() if expected_updated_at else None
                ),
                "payload": payload,
            },
        )
        replay = await self._repository.get_request_identity(request_id=request_id)
        if replay is not None:
            _require_matching_request(
                replay,
                user_id=user_id,
                operation=f"commitment_{operation}",
                resource_id=commitment_id,
                fingerprint=fingerprint,
            )
            commitment = await self._repository.get_commitment(
                user_id=user_id,
                commitment_id=commitment_id,
            )
            if commitment is None:
                raise PlannerNotFoundError("Planner commitment is unavailable.")
            return PlannerCommitmentResponse(
                contract_version=PLANNER_CONTRACT_VERSION,
                origin="authenticated_backend",
                commitment=_commitment_from_row(commitment),
                affected_plan_ids=[],
                replayed=True,
            )
        try:
            result = await self._repository.mutate_commitment(
                user_id=user_id,
                commitment_id=commitment_id,
                request_id=request_id,
                operation=operation,
                request_fingerprint=fingerprint,
                expected_updated_at=expected_updated_at,
                payload=payload,
                now=_aware_utc(self._now()),
            )
        except PlannerPersistenceConflict as exc:
            raise PlannerConflictError(str(exc)) from exc
        except PlannerPersistenceNotFound as exc:
            raise PlannerNotFoundError(str(exc)) from exc
        commitment = await self._repository.get_commitment(
            user_id=user_id,
            commitment_id=commitment_id,
        )
        if commitment is None:
            raise PlannerNotFoundError("Planner commitment is unavailable.")
        raw_affected = result.get("affected_plan_ids", [])
        if not isinstance(raw_affected, list) or len(raw_affected) > 100:
            raise ValueError("Planner commitment conflict projection is invalid.")
        affected = sorted({UUID(str(value)) for value in raw_affected}, key=str)
        return PlannerCommitmentResponse(
            contract_version=PLANNER_CONTRACT_VERSION,
            origin="authenticated_backend",
            commitment=_commitment_from_row(commitment),
            affected_plan_ids=affected,
            replayed=False,
        )

    async def get_overview(self, *, user_id: str) -> PlannerOverviewResponse:
        generated_at = _aware_utc(self._now())
        try:
            context = await self._repository.load_overview_context(
                user_id=user_id,
                generated_at=generated_at,
            )
        except PlannerPersistenceNotFound as exc:
            raise PlannerNotFoundError(str(exc)) from exc
        _validate_overview_bounds(context)
        zone = _zone(context.timezone)
        local_date = generated_at.astimezone(zone).date()
        days = [local_date + timedelta(days=offset) for offset in range(7)]
        action_plans = _plans_from_projection(context.plans)
        plan_by_id = {str(plan.id): plan for plan in action_plans}
        task_titles = _title_map(context.tasks)
        habit_titles = _title_map(context.habits)
        day_items: dict[date, list[PlannerDayItem]] = {day: [] for day in days}

        _add_setup_commitments(
            day_items=day_items,
            rows=context.schedule_items,
            days=days,
            zone=zone,
        )
        _add_manual_commitments(
            day_items=day_items,
            rows=context.commitments,
            days=days,
            zone=zone,
        )
        _add_action_reservations(
            day_items=day_items,
            plans=action_plans,
            days=days,
            zone=zone,
            task_titles=task_titles,
            habit_titles=habit_titles,
        )
        _add_calendar_items(
            day_items=day_items,
            context=context,
            days=days,
            zone=zone,
        )

        deadline_response = (
            await self._deadline_plans.list_plans(user_id=user_id)
            if self._deadline_plans is not None
            else DeadlinePlansResponse(
                contract_version="deadline-plan-v1",
                origin="authenticated_backend",
                plans=[],
            )
        )
        ongoing_preparation: list[PlannerPreparationSummary] = []
        for detail in deadline_response.plans:
            projection = detail.active_revision or detail.pending_revision
            next_block: datetime | None = None
            if detail.active_revision is not None:
                upcoming = [
                    block
                    for block in detail.active_revision.blocks
                    if block.ends_at > generated_at
                ]
                if upcoming:
                    next_block = min(block.starts_at for block in upcoming)
                for block in detail.active_revision.blocks:
                    if block.local_date not in day_items:
                        continue
                    day_items[block.local_date].append(
                        PlannerDayItem(
                            id=block.id,
                            kind="preparation",
                            title=detail.plan.title,
                            source_id=detail.plan.id,
                            starts_at=block.starts_at,
                            ends_at=block.ends_at,
                            recovery_minutes=block.recovery_minutes,
                            reserved_ends_at=block.reserved_ends_at,
                            all_day=False,
                            state=block.state,
                        ),
                    )
            if detail.plan.status in {"draft", "active"}:
                ongoing_preparation.append(
                    PlannerPreparationSummary(
                        plan_id=detail.plan.id,
                        title=detail.plan.title,
                        status=detail.plan.status,
                        remaining_minutes=detail.progress.remaining_minutes,
                        next_block_starts_at=next_block,
                        has_pending_preview=detail.pending_revision is not None,
                    ),
                )
            if projection is None and detail.plan.status == "active":
                raise ValueError("Active preparation projection is incomplete.")

        attention_days = _attention_horizon(
            local_date=local_date,
            context=context,
            plans=action_plans,
            deadline_response=deadline_response,
            zone=zone,
        )
        attention = _attention_items(
            context=context,
            plans=action_plans,
            days=attention_days,
            zone=zone,
        )
        attention.extend(
            _preparation_attention_items(
                context=context,
                deadline_response=deadline_response,
                days=attention_days,
                zone=zone,
                generated_at=generated_at,
            ),
        )
        attention = sorted(
            {item.id: item for item in attention}.values(),
            key=lambda item: (item.kind, item.title.casefold(), item.id),
        )[:500]
        unscheduled, history = _unscheduled_items(
            context=context,
            plans=action_plans,
            plan_by_id=plan_by_id,
        )
        rendered_days: list[PlannerDay] = []
        for day in days:
            values = day_items[day]
            values.sort(
                key=lambda item: (
                    item.starts_at or datetime.combine(day, time.min, tzinfo=zone),
                    _kind_order(item.kind),
                    item.title.casefold(),
                    str(item.id),
                ),
            )
            rendered_days.append(PlannerDay(local_date=day, items=values))
        ongoing_preparation.sort(
            key=lambda item: (
                item.next_block_starts_at or datetime.max.replace(tzinfo=UTC),
                item.title.casefold(),
                str(item.plan_id),
            ),
        )
        return PlannerOverviewResponse(
            contract_version=PLANNER_CONTRACT_VERSION,
            origin="authenticated_backend",
            generated_at=generated_at,
            timezone=context.timezone,
            local_date=local_date,
            preferences=_preferences_response(
                preference=context.preference,
                calendar_import_id=context.calendar.import_id,
                calendar_available=context.calendar.available,
            ),
            action_plans=action_plans,
            commitments=[
                _commitment_from_row(row) for row in context.commitments
            ],
            needs_attention=attention,
            days=rendered_days,
            ongoing_preparation=ongoing_preparation,
            unscheduled=unscheduled,
            history=history,
        )


_TARGET_ADAPTER = TypeAdapter(PlannerActionTarget)


def _plan_from_projection(
    *,
    projection: PlannerProjection,
    plan_id: UUID,
) -> PlannerActionPlan:
    plans = _plans_from_projection(projection)
    match = [plan for plan in plans if plan.id == plan_id]
    if len(match) != 1:
        raise ValueError("Planner action plan projection is inconsistent.")
    return match[0]


def _plans_from_projection(projection: PlannerProjection) -> list[PlannerActionPlan]:
    if len(projection.plans) > 1_000:
        raise PlannerConflictError("Planner action plan count exceeds its bound.")
    plan_ids: set[str] = set()
    for row in projection.plans:
        value = str(row.get("id"))
        if value == "None" or value in plan_ids:
            raise ValueError("Planner action plan identity is invalid.")
        plan_ids.add(value)
    revisions_by_plan: dict[str, list[dict[str, Any]]] = {}
    revision_keys: set[tuple[str, int]] = set()
    for row in projection.revisions:
        key = (str(row.get("plan_id")), _int(row.get("revision")))
        if key[0] not in plan_ids or key in revision_keys:
            raise ValueError("Planner revision projection is invalid.")
        revision_keys.add(key)
        revisions_by_plan.setdefault(key[0], []).append(row)
    blocks_by_key: dict[tuple[str, int], list[dict[str, Any]]] = {}
    block_ids: set[str] = set()
    for row in projection.task_blocks:
        key = (str(row.get("plan_id")), _int(row.get("revision")))
        value = str(row.get("id"))
        if key not in revision_keys or value == "None" or value in block_ids:
            raise ValueError("Planner task block projection is invalid.")
        block_ids.add(value)
        blocks_by_key.setdefault(key, []).append(row)
    slots_by_key: dict[tuple[str, int], list[dict[str, Any]]] = {}
    slot_ids: set[str] = set()
    for row in projection.habit_slots:
        key = (str(row.get("plan_id")), _int(row.get("revision")))
        value = str(row.get("id"))
        if key not in revision_keys or value == "None" or value in slot_ids:
            raise ValueError("Planner habit slot projection is invalid.")
        slot_ids.add(value)
        slots_by_key.setdefault(key, []).append(row)

    result: list[PlannerActionPlan] = []
    for plan_row in projection.plans:
        key = str(plan_row["id"])
        revision_rows = revisions_by_plan.get(key, [])
        active_rows = [row for row in revision_rows if row.get("state") == "active"]
        pending_rows = [
            row for row in revision_rows if row.get("state") == "proposed"
        ]
        if len(active_rows) > 1 or len(pending_rows) > 1:
            raise ValueError("Planner revision lifecycle projection is ambiguous.")
        active = (
            _revision_from_row(
                active_rows[0],
                task_blocks=blocks_by_key.get(
                    (key, _int(active_rows[0]["revision"])),
                    [],
                ),
                habit_slots=slots_by_key.get(
                    (key, _int(active_rows[0]["revision"])),
                    [],
                ),
            )
            if active_rows
            else None
        )
        pending = (
            _revision_from_row(
                pending_rows[0],
                task_blocks=blocks_by_key.get(
                    (key, _int(pending_rows[0]["revision"])),
                    [],
                ),
                habit_slots=slots_by_key.get(
                    (key, _int(pending_rows[0]["revision"])),
                    [],
                ),
            )
            if pending_rows
            else None
        )
        reasons = plan_row.get("attention_reasons", [])
        if not isinstance(reasons, list) or any(
            not isinstance(value, str) or not value or len(value) > 80
            for value in reasons
        ):
            raise ValueError("Planner attention projection is invalid.")
        result.append(
            PlannerActionPlan(
                id=UUID(key),
                target_kind=plan_row["target_kind"],
                target_id=UUID(str(plan_row["target_id"])),
                status=plan_row["status"],
                current_revision=_int(plan_row["current_revision"]),
                latest_revision=_int(plan_row["latest_revision"]),
                needs_attention=bool(reasons),
                attention_reasons=list(dict.fromkeys(reasons)),
                active_revision=active,
                pending_revision=pending,
            ),
        )
    result.sort(key=lambda value: str(value.id))
    return result


def _revision_from_row(
    row: Mapping[str, Any],
    *,
    task_blocks: Sequence[Mapping[str, Any]],
    habit_slots: Sequence[Mapping[str, Any]],
) -> PlannerActionRevision:
    raw_target = row.get("target_payload")
    if not isinstance(raw_target, dict):
        raise ValueError("Planner target projection is invalid.")
    try:
        target = _TARGET_ADAPTER.validate_json(
            json.dumps(raw_target, separators=(",", ":")),
        )
    except ValidationError as exc:
        raise ValueError("Planner target projection is invalid.") from exc
    rendered_blocks = [
        PlannerTaskBlock(
            id=UUID(str(block["id"])),
            sequence=_int(block["sequence"]),
            starts_at=_datetime(block["starts_at"]),
            ends_at=_datetime(block["ends_at"]),
            local_date=_date(block["local_date"]),
            planned_minutes=_int(block["planned_minutes"]),
            recovery_minutes=_int(block.get("recovery_minutes", 0)),
            reserved_ends_at=_datetime(
                block.get("reserved_ends_at", block["ends_at"]),
            ),
            state=block["state"],
        )
        for block in sorted(
            task_blocks,
            key=lambda value: (_int(value["sequence"]), str(value["id"])),
        )
    ]
    rendered_slots = [
        PlannerHabitSlot(
            id=UUID(str(slot["id"])),
            weekday=_int(slot["weekday"]),
            starts_at=_time(slot["starts_at"]),
            ends_at=_time(slot["ends_at"]),
            duration_minutes=_int(slot["duration_minutes"]),
            state=slot["state"],
        )
        for slot in sorted(
            habit_slots,
            key=lambda value: (
                _int(value["weekday"]),
                str(value["starts_at"]),
                str(value["id"]),
            ),
        )
    ]
    return PlannerActionRevision(
        revision=_int(row["revision"]),
        base_revision=_int(row["base_revision"]),
        state=row["state"],
        target=target,
        timezone=row["timezone"],
        best_energy_window=row["best_energy_window"],
        planning_start_on=_date(row["planning_start_on"]),
        planning_fingerprint=row["planning_fingerprint"],
        calendar_import_id=(
            UUID(str(row["calendar_import_id"]))
            if row.get("calendar_import_id")
            else None
        ),
        study_setup_revision=(
            _int(row["study_setup_revision"])
            if row.get("study_setup_revision") is not None
            else None
        ),
        recovery_minutes=_int(row.get("recovery_minutes", 0)),
        planned_minutes=_int(row["planned_minutes"]),
        unscheduled_minutes=_int(row["unscheduled_minutes"]),
        task_blocks=rendered_blocks,
        habit_slots=rendered_slots,
        created_at=_datetime(row["created_at"]),
        activated_at=_optional_datetime(row.get("activated_at")),
        superseded_at=_optional_datetime(row.get("superseded_at")),
    )


def _preferences_response(
    *,
    preference: Mapping[str, Any] | None,
    calendar_import_id: UUID | None,
    calendar_available: bool,
) -> PlannerPreferencesResponse:
    return PlannerPreferencesResponse(
        contract_version=PLANNER_PREFERENCES_CONTRACT_VERSION,
        origin="authenticated_backend",
        use_calendar_busy_time=bool(
            preference and preference.get("use_calendar_busy_time") is True
        ),
        updated_at=(
            _datetime(preference["updated_at"])
            if preference and preference.get("updated_at")
            else None
        ),
        current_calendar_import_id=calendar_import_id,
        calendar_available=calendar_available,
    )


def _planning_end(
    *,
    request: PlannerActionProposalRequest,
    generated_at: datetime,
) -> date:
    if isinstance(request.target, PlannerTaskTarget) and request.target.deadline_at:
        # The profile zone is not loaded yet. The UTC date is only a bounded
        # repository hint; the definitive local-date validation runs later.
        return request.target.deadline_at.astimezone(UTC).date() + timedelta(days=1)
    if isinstance(request.target, PlannerHabitTarget):
        return request.planning_start_on + timedelta(days=27)
    return max(request.planning_start_on, generated_at.date())


def _validate_target_projection(
    target: PlannerActionTarget,
    row: Mapping[str, Any] | None,
) -> None:
    if target.operation == "create":
        if row is not None:
            raise PlannerConflictError("The new target id is already in use.")
        return
    if row is None:
        raise PlannerNotFoundError("The target to plan is unavailable.")
    updated = _datetime(row.get("updated_at"))
    if updated != target.expected_updated_at:
        raise PlannerConflictError("The target changed. Reload before planning it.")
    if isinstance(target, PlannerTaskTarget):
        if row.get("status") not in {"todo", "in_progress"}:
            raise PlannerConflictError("A terminal task cannot be planned.")
        return
    metadata = row.get("metadata")
    if not isinstance(metadata, dict):
        raise ValueError("Habit metadata is invalid.")
    if row.get("active") is not True:
        raise PlannerConflictError("A paused or archived habit cannot be planned.")
    if metadata.get("managed_by") == "setup":
        existing = _habit_definition_from_row(row)
        proposed = {
            "title": target.title,
            "description": target.description,
            "cadence": target.cadence.model_dump(mode="json"),
        }
        if existing != proposed:
            raise PlannerConflictError(
                "Setup-owned habit definitions can only be changed in Settings.",
            )


def _habit_definition_from_row(row: Mapping[str, Any]) -> dict[str, Any]:
    metadata = row.get("metadata")
    if not isinstance(metadata, dict):
        raise ValueError("Habit metadata is invalid.")
    cadence = metadata.get("cadence")
    if cadence == "weekdays":
        weekdays = metadata.get("scheduled_weekdays")
        if not isinstance(weekdays, list):
            raise ValueError("Habit cadence is invalid.")
        value = {
            "kind": "weekdays",
            "scheduled_weekdays": weekdays,
            "weekly_target": 1,
        }
    elif cadence == "weekly_target" or (
        cadence is None and row.get("frequency") == "weekly"
    ):
        value = {
            "kind": "weekly_target",
            "scheduled_weekdays": [],
            "weekly_target": _int(row.get("target")),
        }
    else:
        value = {
            "kind": "daily",
            "scheduled_weekdays": [],
            "weekly_target": 1,
        }
    return {
        "title": row.get("title"),
        "description": row.get("description"),
        "cadence": value,
    }


def _habit_weekdays(target: PlannerHabitTarget) -> list[int]:
    if target.cadence.kind == "daily":
        return list(range(1, 8))
    if target.cadence.kind == "weekdays":
        return sorted(target.cadence.scheduled_weekdays)
    # Spread a weekly target before filling adjacent weekdays. This is stable,
    # deterministic, and never infers a cadence the user did not choose.
    return [1, 3, 5, 7, 2, 4, 6][: target.cadence.weekly_target]


def _availability_sources(
    *,
    context: PlannerAvailabilityContext,
    calendar_enabled: bool,
) -> BusySources:
    recurring: list[dict[str, Any]] = []
    timed: list[dict[str, Any]] = []
    all_day: list[dict[str, Any]] = []
    for row in context.schedule_items:
        recurring.append(
            {
                "weekday": row.get("weekday"),
                "starts_at": row.get("starts_at"),
                "ends_at": row.get("ends_at"),
                "metadata": row.get("metadata"),
            },
        )
    for row in context.commitments:
        if row.get("recurrence") == "weekly":
            recurring.append(
                {
                    "weekday": row.get("weekday"),
                    "starts_at": row.get("local_starts_at"),
                    "ends_at": row.get("local_ends_at"),
                },
            )
        elif row.get("recurrence") == "one_off":
            timed.append(
                {"starts_at": row.get("starts_at"), "ends_at": row.get("ends_at")},
            )
        else:
            raise ValueError("Planner commitment recurrence is invalid.")
    recurring.extend(
        {
            "weekday": row.get("weekday"),
            "starts_at": row.get("starts_at"),
            "ends_at": row.get("ends_at"),
        }
        for row in context.habit_slots
    )
    timed.extend(
        {
            "starts_at": row.get("starts_at"),
            "ends_at": row.get("ends_at"),
            "reserved_ends_at": row.get("reserved_ends_at", row.get("ends_at")),
        }
        for row in [*context.task_blocks, *context.deadline_blocks]
    )
    if calendar_enabled:
        timed.extend(
            {"starts_at": row.get("starts_at"), "ends_at": row.get("ends_at")}
            for row in context.calendar.timed_events
            if row.get("busy_status") == "busy"
        )
        all_day.extend(
            {"starts_on": row.get("starts_on"), "ends_on": row.get("ends_on")}
            for row in context.calendar.all_day_events
            if row.get("busy_status") == "busy"
        )
    return BusySources(
        recurring_commitments=recurring,
        timed_intervals=timed,
        all_day_intervals=all_day,
    )


def _study_rhythm(
    row: Mapping[str, Any] | None,
) -> tuple[int, int, int] | None:
    if row is None:
        return None
    revision = _int(row.get("setup_revision"))
    focus = row.get("focus_minutes")
    recovery = row.get("recovery_minutes")
    if focus is None and recovery is None:
        return None
    focus_minutes = _int(focus)
    recovery_minutes = _int(recovery)
    if (
        revision < 1
        or focus_minutes < 25
        or focus_minutes > 180
        or focus_minutes % 5 != 0
        or recovery_minutes < 5
        or recovery_minutes > 60
        or recovery_minutes % 5 != 0
    ):
        raise ValueError("Study Setup rhythm projection is invalid.")
    return revision, focus_minutes, recovery_minutes


def _commitment_payload(
    value: PlannerCommitmentCreateRequest | PlannerCommitmentUpdateRequest,
) -> dict[str, Any]:
    payload = value.model_dump(mode="json")
    for key in ("request_id", "commitment_id", "expected_updated_at"):
        payload.pop(key, None)
    return payload


def _commitment_from_row(row: Mapping[str, Any]) -> PlannerCommitment:
    return PlannerCommitment(
        id=UUID(str(row["id"])),
        title=row["title"],
        location=row.get("location"),
        recurrence=row["recurrence"],
        status=row["status"],
        starts_at=_optional_datetime(row.get("starts_at")),
        ends_at=_optional_datetime(row.get("ends_at")),
        weekday=_optional_int(row.get("weekday")),
        local_starts_at=_optional_time(row.get("local_starts_at")),
        local_ends_at=_optional_time(row.get("local_ends_at")),
        created_at=_datetime(row["created_at"]),
        updated_at=_datetime(row["updated_at"]),
        archived_at=_optional_datetime(row.get("archived_at")),
    )


def _add_setup_commitments(
    *,
    day_items: dict[date, list[PlannerDayItem]],
    rows: Sequence[Mapping[str, Any]],
    days: Sequence[date],
    zone: ZoneInfo,
) -> None:
    for row in rows:
        weekday = _int(row.get("weekday"))
        starts = _time(row.get("starts_at"))
        ends = _time(row.get("ends_at"))
        for day in days:
            if (
                day.isoweekday() != weekday
                or not recurring_commitment_applies_on(row, day)
            ):
                continue
            starts_at = datetime.combine(day, starts, tzinfo=zone)
            ends_at = datetime.combine(day, ends, tzinfo=zone)
            if ends_at <= starts_at:
                ends_at += timedelta(days=1)
            source_id = UUID(str(row["id"]))
            day_items[day].append(
                PlannerDayItem(
                    id=_occurrence_id("setup", source_id, day),
                    kind="setup_commitment",
                    title=_title(row),
                    source_id=source_id,
                    starts_at=starts_at,
                    ends_at=ends_at,
                    recovery_minutes=0,
                    reserved_ends_at=ends_at,
                    all_day=False,
                ),
            )


def _add_manual_commitments(
    *,
    day_items: dict[date, list[PlannerDayItem]],
    rows: Sequence[Mapping[str, Any]],
    days: Sequence[date],
    zone: ZoneInfo,
) -> None:
    day_set = set(days)
    for row in rows:
        if row.get("status") != "active":
            continue
        source_id = UUID(str(row["id"]))
        if row.get("recurrence") == "one_off":
            starts = _datetime(row.get("starts_at"))
            ends = _datetime(row.get("ends_at"))
            local_day = starts.astimezone(zone).date()
            if local_day not in day_set:
                continue
            day_items[local_day].append(
                PlannerDayItem(
                    id=source_id,
                    kind="manual_commitment",
                    title=_title(row),
                    source_id=source_id,
                    starts_at=starts,
                    ends_at=ends,
                    recovery_minutes=0,
                    reserved_ends_at=ends,
                    all_day=False,
                ),
            )
            continue
        weekday = _int(row.get("weekday"))
        starts_local = _time(row.get("local_starts_at"))
        ends_local = _time(row.get("local_ends_at"))
        for day in days:
            if day.isoweekday() != weekday:
                continue
            starts = datetime.combine(day, starts_local, tzinfo=zone)
            ends = datetime.combine(day, ends_local, tzinfo=zone)
            day_items[day].append(
                PlannerDayItem(
                    id=_occurrence_id("commitment", source_id, day),
                    kind="manual_commitment",
                    title=_title(row),
                    source_id=source_id,
                    starts_at=starts,
                    ends_at=ends,
                    recovery_minutes=0,
                    reserved_ends_at=ends,
                    all_day=False,
                ),
            )


def _add_action_reservations(
    *,
    day_items: dict[date, list[PlannerDayItem]],
    plans: Sequence[PlannerActionPlan],
    days: Sequence[date],
    zone: ZoneInfo,
    task_titles: Mapping[str, str],
    habit_titles: Mapping[str, str],
) -> None:
    day_set = set(days)
    for plan in plans:
        revision = plan.active_revision
        if revision is None:
            continue
        if isinstance(revision.target, PlannerTaskTarget):
            title = task_titles.get(str(plan.target_id), revision.target.title)
            for block in revision.task_blocks:
                if block.state != "active" or block.local_date not in day_set:
                    continue
                day_items[block.local_date].append(
                    PlannerDayItem(
                        id=block.id,
                        kind="task_block",
                        title=title,
                        source_id=plan.target_id,
                        starts_at=block.starts_at,
                        ends_at=block.ends_at,
                        recovery_minutes=block.recovery_minutes,
                        reserved_ends_at=block.reserved_ends_at,
                        all_day=False,
                        state=block.state,
                    ),
                )
        else:
            title = habit_titles.get(str(plan.target_id), revision.target.title)
            for slot in revision.habit_slots:
                if slot.state != "active":
                    continue
                for day in days:
                    if day.isoweekday() != slot.weekday:
                        continue
                    starts = datetime.combine(day, slot.starts_at, tzinfo=zone)
                    ends = datetime.combine(day, slot.ends_at, tzinfo=zone)
                    day_items[day].append(
                        PlannerDayItem(
                            id=_occurrence_id("habit", slot.id, day),
                            kind="habit_slot",
                            title=title,
                            source_id=plan.target_id,
                            starts_at=starts,
                            ends_at=ends,
                            recovery_minutes=0,
                            reserved_ends_at=ends,
                            all_day=False,
                            state=slot.state,
                        ),
                    )


def _add_calendar_items(
    *,
    day_items: dict[date, list[PlannerDayItem]],
    context: PlannerOverviewContext,
    days: Sequence[date],
    zone: ZoneInfo,
) -> None:
    day_set = set(days)
    for row in context.calendar.timed_events:
        starts = _datetime(row.get("starts_at"))
        ends = _datetime(row.get("ends_at"))
        day = starts.astimezone(zone).date()
        if day not in day_set:
            continue
        source_id = UUID(str(row["id"]))
        day_items[day].append(
            PlannerDayItem(
                id=source_id,
                kind="calendar_event",
                title=_title(row),
                source_id=source_id,
                starts_at=starts,
                ends_at=ends,
                recovery_minutes=0,
                reserved_ends_at=ends,
                all_day=False,
                state=row.get("busy_status"),
            ),
        )
    for row in context.calendar.all_day_events:
        starts_on = _date(row.get("starts_on"))
        ends_on = _date(row.get("ends_on"))
        source_id = UUID(str(row["id"]))
        for day in days:
            if starts_on <= day < ends_on:
                day_items[day].append(
                    PlannerDayItem(
                        id=_occurrence_id("calendar", source_id, day),
                        kind="calendar_event",
                        title=_title(row),
                        source_id=source_id,
                        starts_at=None,
                        ends_at=None,
                        recovery_minutes=0,
                        reserved_ends_at=None,
                        all_day=True,
                        state=row.get("busy_status"),
                    ),
                )


def _attention_items(
    *,
    context: PlannerOverviewContext,
    plans: Sequence[PlannerActionPlan],
    days: Sequence[date],
    zone: ZoneInfo,
) -> list[PlannerAttentionItem]:
    result = _course_selection_attention(
        context.study_setup,
        local_date=days[0],
    )
    current_study = _study_rhythm(context.study_setup)
    current_study_revision = current_study[0] if current_study else None
    calendar_enabled = bool(
        context.preference and context.preference.get("use_calendar_busy_time") is True
    )
    authoritative = _authoritative_intervals(
        context=context,
        days=days,
        zone=zone,
        calendar_enabled=calendar_enabled,
    )
    for plan in plans:
        revision = plan.active_revision
        title = (
            revision.target.title
            if revision is not None
            else (
                plan.pending_revision.target.title
                if plan.pending_revision is not None
                else "Planned action"
            )
        )
        for reason in plan.attention_reasons:
            kind = (
                "study_rhythm_changed"
                if reason == "study_rhythm_changed"
                else "conflict"
            )
            result.append(
                PlannerAttentionItem(
                    id=f"{plan.id}:persisted:{reason}",
                    kind=kind,
                    target="plan",
                    title=title,
                    detail=_attention_detail(reason),
                    plan_id=plan.id,
                    unplaced_minutes=0,
                ),
            )
        pending = plan.pending_revision
        if pending is not None:
            if pending.unscheduled_minutes:
                result.append(
                    PlannerAttentionItem(
                        id=f"{plan.id}:unscheduled:{pending.revision}",
                        kind="unscheduled",
                        target="plan",
                        title=pending.target.title,
                        detail=(
                            f"{pending.unscheduled_minutes} minutes could not "
                            "be placed."
                        ),
                        plan_id=plan.id,
                        unplaced_minutes=pending.unscheduled_minutes,
                    ),
                )
            preview_uses_calendar = pending.calendar_import_id is not None
            if preview_uses_calendar != calendar_enabled or (
                preview_uses_calendar
                and (
                    not context.calendar.available
                    or pending.calendar_import_id != context.calendar.import_id
                )
            ):
                result.append(
                    PlannerAttentionItem(
                        id=f"{plan.id}:calendar-stale:{pending.revision}",
                        kind="stale_preview",
                        target="plan",
                        title=pending.target.title,
                        detail=(
                            "The Planner calendar setting or current import changed. "
                            "Create a new preview."
                        ),
                        plan_id=plan.id,
                        unplaced_minutes=0,
                    ),
                )
            if _pending_target_is_stale(pending.target, context=context):
                result.append(
                    PlannerAttentionItem(
                        id=f"{plan.id}:target-stale:{pending.revision}",
                        kind="stale_preview",
                        target="plan",
                        title=pending.target.title,
                        detail="The Task or Habit changed. Create a new preview.",
                        plan_id=plan.id,
                        unplaced_minutes=0,
                    ),
                )
            if (
                isinstance(pending.target, PlannerTaskTarget)
                and pending.target.use_study_rhythm
                and pending.study_setup_revision != current_study_revision
            ):
                result.append(
                    PlannerAttentionItem(
                        id=f"{plan.id}:study-stale:{pending.revision}",
                        kind="stale_preview",
                        target="plan",
                        title=pending.target.title,
                        detail=(
                            "The Study rhythm changed. Create a new preview "
                            "before confirming."
                        ),
                        plan_id=plan.id,
                        unplaced_minutes=0,
                    ),
                )
        if revision is not None and _revision_conflicts(
            plan_id=plan.id,
            revision=revision,
            days=days,
            zone=zone,
            authoritative=authoritative,
        ):
            result.append(
                PlannerAttentionItem(
                    id=f"{plan.id}:current-conflict:{revision.revision}",
                    kind="conflict",
                    target="plan",
                    title=title,
                    detail="A current commitment now overlaps this plan.",
                    plan_id=plan.id,
                    unplaced_minutes=0,
                ),
            )
        if (
            revision is not None
            and isinstance(revision.target, PlannerTaskTarget)
            and revision.target.use_study_rhythm
            and revision.study_setup_revision != current_study_revision
            and "study_rhythm_changed" not in plan.attention_reasons
        ):
            result.append(
                PlannerAttentionItem(
                    id=f"{plan.id}:study-changed:{revision.revision}",
                    kind="study_rhythm_changed",
                    target="plan",
                    title=title,
                    detail=(
                        "The Study rhythm changed. Review and confirm a new "
                        "preview before reservations change."
                    ),
                    plan_id=plan.id,
                    unplaced_minutes=0,
                ),
            )
    unique: dict[str, PlannerAttentionItem] = {item.id: item for item in result}
    values = list(unique.values())
    values.sort(key=lambda item: (item.kind, item.title.casefold(), item.id))
    return values[:500]


def _pending_target_is_stale(
    target: PlannerActionTarget,
    *,
    context: PlannerOverviewContext,
) -> bool:
    rows = context.tasks if isinstance(target, PlannerTaskTarget) else context.habits
    matching = [row for row in rows if str(row.get("id")) == str(target.target_id)]
    if len(matching) > 1:
        raise ValueError("Planner target overview projection is ambiguous.")
    if target.operation == "create":
        return bool(matching)
    if not matching:
        return True
    row = matching[0]
    if _datetime(row.get("updated_at")) != target.expected_updated_at:
        return True
    if isinstance(target, PlannerTaskTarget):
        return row.get("status") not in {"todo", "in_progress"}
    metadata = row.get("metadata")
    if not isinstance(metadata, dict):
        raise ValueError("Habit metadata is invalid.")
    return (
        row.get("active") is not True
        or metadata.get("lifecycle", "active") != "active"
    )


def _course_selection_attention(
    study_setup: Mapping[str, Any] | None,
    *,
    local_date: date,
) -> list[PlannerAttentionItem]:
    if study_setup is None or study_setup.get("next_semester") is None:
        return []
    semester = study_setup.get("next_semester")
    if not isinstance(semester, Mapping):
        raise ValueError("Next semester projection is invalid.")
    completed = semester.get("course_selection_completed")
    if not isinstance(completed, bool):
        raise ValueError("Course selection state is invalid.")
    if completed:
        return []
    starts_on = _date(semester.get("course_selection_starts_on"))
    ends_on = _date(semester.get("course_selection_ends_on"))
    if local_date < starts_on:
        return []
    overdue = local_date > ends_on
    return [
        PlannerAttentionItem(
            id=f"study-setup:course-selection:{starts_on.isoformat()}",
            kind=(
                "course_selection_overdue"
                if overdue
                else "course_selection_open"
            ),
            target="study_setup",
            title="Choose next semester courses",
            detail=(
                "The course selection window has ended. Review Study Setup."
                if overdue
                else "The course selection window is open. Review Study Setup."
            ),
            plan_id=None,
            unplaced_minutes=0,
        ),
    ]


def _attention_horizon(
    *,
    local_date: date,
    context: PlannerOverviewContext,
    plans: Sequence[PlannerActionPlan],
    deadline_response: DeadlinePlansResponse,
    zone: ZoneInfo,
) -> list[date]:
    last_date = local_date + timedelta(days=365)
    values = {
        local_date + timedelta(days=offset)
        for offset in range(28)
    }

    def add(candidate: date) -> None:
        if local_date <= candidate <= last_date:
            values.add(candidate)

    for plan in plans:
        if plan.active_revision is None:
            continue
        for block in plan.active_revision.task_blocks:
            if block.state == "active":
                add(block.local_date)
    for detail in deadline_response.plans:
        if detail.active_revision is None:
            continue
        for block in detail.active_revision.blocks:
            add(block.local_date)
    for row in context.commitments:
        if row.get("status") == "active" and row.get("recurrence") == "one_off":
            add(_datetime(row.get("starts_at")).astimezone(zone).date())
    for row in context.calendar.timed_events:
        add(_datetime(row.get("starts_at")).astimezone(zone).date())
    for row in context.calendar.all_day_events:
        starts_on = _date(row.get("starts_on"))
        ends_on = _date(row.get("ends_on"))
        # Seven representative days are enough to cover every recurring
        # Habit weekday; Task and Preparation dates were added above.
        for offset in range(min(7, max(0, (ends_on - starts_on).days))):
            add(starts_on + timedelta(days=offset))
    return sorted(values)


def _preparation_attention_items(
    *,
    context: PlannerOverviewContext,
    deadline_response: DeadlinePlansResponse,
    days: Sequence[date],
    zone: ZoneInfo,
    generated_at: datetime,
) -> list[PlannerAttentionItem]:
    authoritative = _authoritative_intervals(
        context=context,
        days=days,
        zone=zone,
        calendar_enabled=bool(
            context.preference
            and context.preference.get("use_calendar_busy_time") is True
        ),
    )
    result: list[PlannerAttentionItem] = []
    current_study = _study_rhythm(context.study_setup)
    current_study_revision = current_study[0] if current_study else None
    for detail in deadline_response.plans:
        revision = detail.active_revision
        pending = detail.pending_revision
        if (
            pending is not None
            and pending.study_setup_revision != current_study_revision
        ):
            result.append(
                PlannerAttentionItem(
                    id=(
                        f"deadline:{detail.plan.id}:study-stale:"
                        f"{pending.revision}"
                    ),
                    kind="stale_preview",
                    target="plan",
                    title=detail.plan.title,
                    detail=(
                        "The Study rhythm changed. Create a new preparation "
                        "preview before confirming."
                    ),
                    plan_id=detail.plan.id,
                    unplaced_minutes=0,
                ),
            )
        if revision is None:
            continue
        conflicts = any(
            block.reserved_ends_at > generated_at
            and any(
                max(block.starts_at, starts_at)
                < min(block.reserved_ends_at, ends_at)
                for starts_at, ends_at in authoritative
            )
            for block in revision.blocks
        )
        if conflicts:
            result.append(
                PlannerAttentionItem(
                    id=(
                        f"deadline:{detail.plan.id}:current-conflict:"
                        f"{revision.revision}"
                    ),
                    kind="conflict",
                    target="plan",
                    title=detail.plan.title,
                    detail="A current commitment now overlaps this preparation plan.",
                    plan_id=detail.plan.id,
                    unplaced_minutes=0,
                ),
            )
        if revision.study_setup_revision != current_study_revision:
            result.append(
                PlannerAttentionItem(
                    id=(
                        f"deadline:{detail.plan.id}:study-changed:"
                        f"{revision.revision}"
                    ),
                    kind="study_rhythm_changed",
                    target="plan",
                    title=detail.plan.title,
                    detail=(
                        "The Study rhythm changed. Review and confirm a new "
                        "preparation preview before reservations change."
                    ),
                    plan_id=detail.plan.id,
                    unplaced_minutes=0,
                ),
            )
    return result


def _authoritative_intervals(
    *,
    context: PlannerOverviewContext,
    days: Sequence[date],
    zone: ZoneInfo,
    calendar_enabled: bool,
) -> list[tuple[datetime, datetime]]:
    intervals: list[tuple[datetime, datetime]] = []
    for row in context.schedule_items:
        weekday = _int(row.get("weekday"))
        starts = _time(row.get("starts_at"))
        ends = _time(row.get("ends_at"))
        for day in days:
            if day.isoweekday() == weekday and recurring_commitment_applies_on(
                row,
                day,
            ):
                intervals.append(
                    (
                        datetime.combine(day, starts, tzinfo=zone),
                        datetime.combine(day, ends, tzinfo=zone),
                    ),
                )
    for row in context.commitments:
        if row.get("status") != "active":
            continue
        if row.get("recurrence") == "one_off":
            intervals.append(
                (_datetime(row.get("starts_at")), _datetime(row.get("ends_at"))),
            )
        else:
            weekday = _int(row.get("weekday"))
            starts = _time(row.get("local_starts_at"))
            ends = _time(row.get("local_ends_at"))
            for day in days:
                if day.isoweekday() == weekday:
                    intervals.append(
                        (
                            datetime.combine(day, starts, tzinfo=zone),
                            datetime.combine(day, ends, tzinfo=zone),
                        ),
                    )
    if calendar_enabled:
        intervals.extend(
            (_datetime(row.get("starts_at")), _datetime(row.get("ends_at")))
            for row in context.calendar.timed_events
            if row.get("busy_status") == "busy"
        )
        for row in context.calendar.all_day_events:
            if row.get("busy_status") != "busy":
                continue
            starts_on = _date(row.get("starts_on"))
            ends_on = _date(row.get("ends_on"))
            intervals.append(
                (
                    datetime.combine(starts_on, time.min, tzinfo=zone),
                    datetime.combine(ends_on, time.min, tzinfo=zone),
                ),
            )
    return intervals


def _revision_conflicts(
    *,
    plan_id: UUID,
    revision: PlannerActionRevision,
    days: Sequence[date],
    zone: ZoneInfo,
    authoritative: Sequence[tuple[datetime, datetime]],
) -> bool:
    del plan_id
    candidates: list[tuple[datetime, datetime]] = []
    candidates.extend(
        (block.starts_at, block.reserved_ends_at)
        for block in revision.task_blocks
        if block.state == "active" and block.local_date in days
    )
    for slot in revision.habit_slots:
        if slot.state != "active":
            continue
        candidates.extend(
            (
                datetime.combine(day, slot.starts_at, tzinfo=zone),
                datetime.combine(day, slot.ends_at, tzinfo=zone),
            )
            for day in days
            if day.isoweekday() == slot.weekday
        )
    return any(
        max(start, busy_start) < min(end, busy_end)
        for start, end in candidates
        for busy_start, busy_end in authoritative
    )


def _unscheduled_items(
    *,
    context: PlannerOverviewContext,
    plans: Sequence[PlannerActionPlan],
    plan_by_id: Mapping[str, PlannerActionPlan],
) -> tuple[list[PlannerUnscheduledItem], list[PlannerUnscheduledItem]]:
    del plan_by_id
    active_targets = {
        (plan.target_kind, str(plan.target_id))
        for plan in plans
        if plan.active_revision is not None
    }
    released_targets = {
        (plan.target_kind, str(plan.target_id))
        for plan in plans
        if plan.status == "unscheduled"
    }
    unscheduled: list[PlannerUnscheduledItem] = []
    history: list[PlannerUnscheduledItem] = []
    known: set[tuple[str, str]] = set()
    for kind, rows in (("task", context.tasks), ("habit", context.habits)):
        for row in rows:
            target_id = str(row.get("id"))
            key = (kind, target_id)
            if target_id == "None" or key in known:
                raise ValueError("Planner target overview projection is invalid.")
            known.add(key)
            terminal = (
                row.get("status") in {"done", "cancelled", "archived"}
                if kind == "task"
                else row.get("active") is not True
            )
            item = PlannerUnscheduledItem(
                id=UUID(target_id),
                kind=kind,
                title=_title(row),
                reason=(
                    "released"
                    if key in released_targets
                    else "not_planned"
                ),
                **_target_summary(kind=kind, row=row),
            )
            if terminal:
                history.append(item)
            elif key not in active_targets:
                unscheduled.append(item)
    for plan in plans:
        pending = plan.pending_revision
        if pending is None or pending.target.operation != "create":
            continue
        key = (plan.target_kind, str(plan.target_id))
        if key in known:
            continue
        unscheduled.append(
            PlannerUnscheduledItem(
                id=plan.target_id,
                kind=plan.target_kind,
                title=pending.target.title,
                reason=(
                    "missing_scheduling_inputs"
                    if isinstance(pending.target, PlannerTaskTarget)
                    and (
                        pending.target.estimated_minutes is None
                        or pending.target.deadline_at is None
                        or pending.target.preferred_session_minutes is None
                    )
                    else "not_planned"
                ),
                **_target_summary_from_target(pending.target),
            ),
        )
    unscheduled.sort(key=lambda item: (item.kind, item.title.casefold(), str(item.id)))
    history.sort(key=lambda item: (item.kind, item.title.casefold(), str(item.id)))
    return unscheduled[:1_000], history[:1_000]


def _target_summary(
    *,
    kind: str,
    row: Mapping[str, Any],
) -> dict[str, Any]:
    updated_at = _datetime(row.get("updated_at"))
    description = row.get("description")
    if description is not None and not isinstance(description, str):
        raise ValueError("Planner target description is invalid.")
    if kind == "task":
        metadata = row.get("metadata")
        if metadata is None:
            metadata = {}
        if not isinstance(metadata, dict):
            raise ValueError("Planner Task metadata is invalid.")
        preferred = metadata.get("preferred_session_minutes")
        return {
            "expected_updated_at": updated_at,
            "description": description,
            "priority": row.get("priority"),
            "estimated_minutes": _optional_int(row.get("estimated_minutes")),
            "deadline_at": _optional_datetime(row.get("deadline")),
            "preferred_session_minutes": _optional_int(preferred),
            "use_study_rhythm": metadata.get("use_study_rhythm") is True,
            "cadence": None,
            "duration_minutes": None,
        }
    definition = _habit_definition_from_row(row)
    metadata = row.get("metadata")
    assert isinstance(metadata, dict)
    return {
        "expected_updated_at": updated_at,
        "description": description,
        "priority": None,
        "estimated_minutes": None,
        "deadline_at": None,
        "preferred_session_minutes": None,
        "use_study_rhythm": False,
        "cadence": definition["cadence"],
        "duration_minutes": _optional_int(
            metadata.get("planner_duration_minutes"),
        ),
    }


def _target_summary_from_target(target: PlannerActionTarget) -> dict[str, Any]:
    if isinstance(target, PlannerTaskTarget):
        return {
            "expected_updated_at": target.expected_updated_at,
            "description": target.description,
            "priority": target.priority,
            "estimated_minutes": target.estimated_minutes,
            "deadline_at": target.deadline_at,
            "preferred_session_minutes": target.preferred_session_minutes,
            "use_study_rhythm": target.use_study_rhythm,
            "cadence": None,
            "duration_minutes": None,
        }
    return {
        "expected_updated_at": target.expected_updated_at,
        "description": target.description,
        "priority": None,
        "estimated_minutes": None,
        "deadline_at": None,
        "preferred_session_minutes": None,
        "use_study_rhythm": False,
        "cadence": target.cadence,
        "duration_minutes": target.duration_minutes,
    }


def _validate_context_bounds(context: PlannerAvailabilityContext) -> None:
    values = (
        (context.schedule_items, 1_000, "Setup commitments"),
        (context.commitments, 1_000, "Planner commitments"),
        (context.task_blocks, 10_000, "Task reservations"),
        (context.habit_slots, 1_000, "Habit reservations"),
        (context.deadline_blocks, 10_000, "Preparation reservations"),
        (context.calendar.timed_events, 2_000, "Calendar events"),
        (context.calendar.all_day_events, 2_000, "Calendar events"),
    )
    for rows, maximum, label in values:
        if len(rows) > maximum:
            raise PlannerConflictError(f"{label} exceed the Planner bound.")


def _validate_overview_bounds(context: PlannerOverviewContext) -> None:
    values = (
        (context.schedule_items, 1_000, "Setup commitments"),
        (context.commitments, 1_000, "Planner commitments"),
        (context.tasks, 1_000, "Tasks"),
        (context.habits, 1_000, "Habits"),
        (context.calendar.timed_events, 2_000, "Calendar events"),
        (context.calendar.all_day_events, 2_000, "Calendar events"),
    )
    for rows, maximum, label in values:
        if len(rows) > maximum:
            raise PlannerConflictError(f"{label} exceed the Planner overview bound.")


def _require_matching_request(
    row: Mapping[str, Any],
    *,
    user_id: str,
    operation: str,
    resource_id: UUID,
    fingerprint: str,
) -> None:
    if (
        row.get("user_id") != user_id
        or row.get("operation") != operation
        or str(row.get("resource_id")) != str(resource_id)
        or row.get("request_fingerprint") != fingerprint
    ):
        raise PlannerConflictError(
            "request_id is already bound to another Planner operation.",
        )


def _stable_rows(rows: Iterable[Mapping[str, Any]]) -> list[dict[str, Any]]:
    values = [
        {str(key): _json_value(value) for key, value in sorted(row.items())}
        for row in rows
    ]
    values.sort(key=lambda row: json.dumps(row, sort_keys=True, separators=(",", ":")))
    return values


def _json_value(value: Any) -> Any:
    if isinstance(value, (datetime, date, time, UUID)):
        return value.isoformat() if hasattr(value, "isoformat") else str(value)
    if isinstance(value, dict):
        return {str(key): _json_value(item) for key, item in sorted(value.items())}
    if isinstance(value, list):
        return [_json_value(item) for item in value]
    return value


def _fingerprint(value: Mapping[str, Any]) -> str:
    encoded = json.dumps(
        _json_value(dict(value)),
        sort_keys=True,
        separators=(",", ":"),
        ensure_ascii=False,
    ).encode()
    return hashlib.sha256(encoded).hexdigest()


def _attention_detail(reason: str) -> str:
    return {
        "commitment_conflict": "A fixed commitment overlaps this plan.",
        "target_released": "The target changed and its future slots were released.",
        "calendar_changed": "Calendar busy time changed. Create a new preview.",
        "study_rhythm_changed": (
            "The Study rhythm changed. Create and confirm a new preview."
        ),
    }.get(reason, "This plan needs a new preview before its times can be trusted.")


def _kind_order(value: str) -> int:
    return {
        "setup_commitment": 0,
        "manual_commitment": 1,
        "task_block": 2,
        "habit_slot": 3,
        "preparation": 4,
        "calendar_event": 5,
    }[value]


def _title_map(rows: Sequence[Mapping[str, Any]]) -> dict[str, str]:
    result: dict[str, str] = {}
    for row in rows:
        key = str(row.get("id"))
        if key == "None" or key in result:
            raise ValueError("Planner target title projection is invalid.")
        result[key] = _title(row)
    return result


def _title(row: Mapping[str, Any]) -> str:
    value = row.get("title")
    if not isinstance(value, str) or not value or value.strip() != value:
        raise ValueError("Planner source title is invalid.")
    return value


def _occurrence_id(prefix: str, source_id: UUID, day: date) -> UUID:
    return uuid5(
        NAMESPACE_URL,
        f"{PLANNER_CONTRACT_VERSION}:{prefix}:{source_id}:{day.isoformat()}",
    )


def _aware_utc(value: datetime) -> datetime:
    if value.tzinfo is None or value.utcoffset() is None:
        raise ValueError("Planner clock must be timezone-aware.")
    return value.astimezone(UTC)


def _zone(value: str) -> ZoneInfo:
    try:
        return ZoneInfo(value)
    except ZoneInfoNotFoundError as exc:
        raise ValueError("Planner profile timezone is invalid.") from exc


def _datetime(value: Any) -> datetime:
    if isinstance(value, datetime):
        result = value
    elif isinstance(value, str):
        result = datetime.fromisoformat(value.replace("Z", "+00:00"))
    else:
        raise ValueError("Planner timestamp is invalid.")
    if result.tzinfo is None or result.utcoffset() is None:
        raise ValueError("Planner timestamp must be timezone-aware.")
    return result


def _optional_datetime(value: Any) -> datetime | None:
    return None if value is None else _datetime(value)


def _date(value: Any) -> date:
    if isinstance(value, datetime):
        raise ValueError("Planner date is invalid.")
    if isinstance(value, date):
        return value
    if isinstance(value, str):
        return date.fromisoformat(value)
    raise ValueError("Planner date is invalid.")


def _time(value: Any) -> time:
    if isinstance(value, time):
        result = value
    elif isinstance(value, str):
        result = time.fromisoformat(value)
    else:
        raise ValueError("Planner time is invalid.")
    if result.tzinfo is not None:
        raise ValueError("Planner wall-clock time must not contain a timezone.")
    return result


def _optional_time(value: Any) -> time | None:
    return None if value is None else _time(value)


def _int(value: Any) -> int:
    if isinstance(value, bool) or not isinstance(value, int):
        raise ValueError("Planner integer projection is invalid.")
    return value


def _optional_int(value: Any) -> int | None:
    return None if value is None else _int(value)
