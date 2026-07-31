from __future__ import annotations

from collections.abc import Callable
from datetime import UTC, datetime
from typing import Any, Protocol
from uuid import NAMESPACE_URL, UUID, uuid5


from app.models.deadline_plans import DeadlinePlansResponse
from app.models.planner import (
    PLANNER_CONTRACT_VERSION,
    PlannerActionMutationRequest,
    PlannerActionPlanResponse,
    PlannerActionProposalRequest,
    PlannerCommitmentArchiveRequest,
    PlannerCommitmentCreateRequest,
    PlannerCommitmentResponse,
    PlannerCommitmentUpdateRequest,
    PlannerOverviewResponse,
    PlannerPreferencesResponse,
    PlannerPreferencesUpdateRequest,
    PlannerTaskTarget,
)
from app.models.planning_timing import PlanningTimingProvenance
from app.repositories.planner_repository import (
    PlannerPersistenceConflict,
    PlannerPersistenceNotFound,
    PlannerRepository,
)
from app.repositories.planning_writes import (
    PlannerHabitSlotWrite,
    PlannerProposalWrite,
    PlannerRevisionWrite,
    PlannerTaskBlockWrite,
)
from app.services.planning_availability import (
    allocate_task_intervals,
    choose_recurring_habit_slots,
    used_setup_timing_fallback,
)
from app.services.learned_timing import LearnedTimingResolver


from app.services.planner_builder import (
    _add_setup_commitments as _add_setup_commitments,
    _availability_sources,
    _attention_items as _attention_items,
    _aware_utc,
    _commitment_from_row,
    _commitment_payload,
    _course_selection_attention as _course_selection_attention,
    _fingerprint,
    _habit_weekdays,
    _int,
    _plan_from_projection,
    _planning_end,
    _preferences_response,
    _require_matching_request,
    _stable_rows,
    _study_rhythm,
    _validate_context_bounds,
    _validate_target_projection,
    _zone,
    build_planner_overview,
)
from app.services.planner_errors import (
    PlannerConflictError,
    PlannerNotFoundError,
    PlannerValidationError,
)


class DeadlinePlanReader(Protocol):
    async def list_plans(self, *, user_id: str) -> DeadlinePlansResponse: ...


class PlannerService:
    def __init__(
        self,
        *,
        repository: PlannerRepository,
        deadline_plans: DeadlinePlanReader | None = None,
        learned_timing: LearnedTimingResolver | None = None,
        now: Callable[[], datetime] | None = None,
    ) -> None:
        self._repository = repository
        self._deadline_plans = deadline_plans
        self._learned_timing = learned_timing
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
        task_blocks: list[PlannerTaskBlockWrite] = []
        habit_slots: list[PlannerHabitSlotWrite] = []
        planned_minutes = 0
        unscheduled_minutes = 0
        timing_preference = PlanningTimingProvenance(source="setup")

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
                if self._learned_timing is not None:
                    timing_preference = await self._learned_timing.resolve(
                        user_id=user_id,
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
                    learned_focus_window=(
                        timing_preference.window
                        if timing_preference.source == "learned_personal_pattern"
                        else None
                    ),
                )
                if (
                    timing_preference.source == "learned_personal_pattern"
                    and used_setup_timing_fallback(
                        intervals,
                        learned_focus_window=timing_preference.window,
                    )
                ):
                    timing_preference = timing_preference.model_copy(
                        update={"fell_back_to_setup": True},
                    )
                for sequence, interval in enumerate(intervals, start=1):
                    task_blocks.append(
                        PlannerTaskBlockWrite(
                            id=uuid5(
                                NAMESPACE_URL,
                                f"{PLANNER_CONTRACT_VERSION}:{request.plan_id}:"
                                f"{request.request_id}:task:{sequence}",
                            ),
                            sequence=sequence,
                            starts_at=interval.starts_at.astimezone(UTC),
                            ends_at=interval.ends_at.astimezone(UTC),
                            recovery_minutes=interval.recovery_minutes,
                            reserved_ends_at=(
                                interval.reserved_ends_at or interval.ends_at
                            ).astimezone(UTC),
                            local_date=interval.starts_at.date(),
                            planned_minutes=interval.minutes,
                        ),
                    )
                planned_minutes = sum(item.planned_minutes for item in task_blocks)
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
                    PlannerHabitSlotWrite(
                        id=uuid5(
                            NAMESPACE_URL,
                            f"{PLANNER_CONTRACT_VERSION}:{request.plan_id}:"
                            f"{request.request_id}:habit:{slot.weekday}",
                        ),
                        weekday=slot.weekday,
                        starts_at=slot.starts_at,
                        ends_at=slot.ends_at,
                        duration_minutes=slot.minutes,
                    ),
                )
            planned_minutes = sum(item.duration_minutes for item in habit_slots)
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
                "timing_preference": timing_preference.model_dump(mode="json"),
            },
        )
        write = PlannerProposalWrite(
            target_kind=request.target.kind,
            target_id=request.target.target_id,
            target=request.target,
            revision=PlannerRevisionWrite(
                revision=request.base_revision + 1,
                base_revision=request.base_revision,
                target=request.target,
                timezone=context.timezone,
                best_energy_window=context.best_energy_window,
                planning_start_on=request.planning_start_on,
                planning_fingerprint=_fingerprint(
                    {
                        "contract_version": PLANNER_CONTRACT_VERSION,
                        "request": request_input,
                        "context_fingerprint": context_fingerprint,
                        "task_blocks": [
                            item.model_dump(mode="json") for item in task_blocks
                        ],
                        "habit_slots": [
                            item.model_dump(mode="json") for item in habit_slots
                        ],
                    },
                ),
                timing_preference=timing_preference,
                calendar_import_id=(
                    context.calendar.import_id
                    if calendar_enabled and context.calendar.import_id
                    else None
                ),
                study_setup_revision=study_setup_revision,
                recovery_minutes=recovery_minutes,
                planned_minutes=planned_minutes,
                unscheduled_minutes=unscheduled_minutes,
            ),
            task_blocks=tuple(task_blocks),
            habit_slots=tuple(habit_slots),
        )
        try:
            await self._repository.persist_proposal(
                user_id=user_id,
                request_id=request.request_id,
                request_fingerprint=request_fingerprint,
                plan_id=request.plan_id,
                base_revision=request.base_revision,
                write=write,
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
                await self._require_learned_confirmation_allowed(
                    user_id=user_id,
                    plan_id=plan_id,
                    expected_revision=request.expected_revision,
                )
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

    async def _require_learned_confirmation_allowed(
        self,
        *,
        user_id: str,
        plan_id: UUID,
        expected_revision: int,
    ) -> None:
        projection = await self._repository.load_projection(
            user_id=user_id,
            plan_id=plan_id,
        )
        pending = [
            row
            for row in projection.revisions
            if _int(row.get("revision")) == expected_revision
            and row.get("state") == "proposed"
        ]
        if len(pending) != 1:
            return
        if (
            pending[0].get("timing_preference_source", "setup")
            != "learned_personal_pattern"
        ):
            return
        if self._learned_timing is None or not (
            await self._learned_timing.learned_confirmation_is_allowed(
                user_id=user_id,
            )
        ):
            raise PlannerConflictError(
                "Learned Focus planning was turned off. Request a new preview.",
            )

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
        deadline_response = (
            await self._deadline_plans.list_plans(user_id=user_id)
            if self._deadline_plans is not None
            else DeadlinePlansResponse(
                contract_version="deadline-plan-v1",
                origin="authenticated_backend",
                plans=[],
            )
        )
        return build_planner_overview(
            generated_at=generated_at,
            context=context,
            deadline_response=deadline_response,
        )
