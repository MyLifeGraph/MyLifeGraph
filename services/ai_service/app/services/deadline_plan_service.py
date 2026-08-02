from collections.abc import Callable
from datetime import UTC, date, datetime, timedelta
from typing import Any
from uuid import NAMESPACE_URL, UUID, uuid5

from app.models.deadline_plans import (
    DEADLINE_PLAN_CONTRACT_VERSION,
    PREPARATION_WORKLOAD_DETAIL_CONTRACT_VERSION,
    PREPARATION_WORKLOAD_CONTRACT_VERSION,
    DeadlinePlanBlock,
    DeadlinePlanDetail,
    DeadlinePlanMutationRequest,
    DeadlinePlanProgress,
    DeadlinePlanProposalRequest,
    DeadlinePlanResponse,
    DeadlinePlanRevision,
    DeadlinePlansResponse,
    ExamWeekOutlookResponse,
    PreparationWorkloadDay,
    PreparationWorkloadContribution,
    PreparationWorkloadDetailResponse,
    PreparationWorkloadResponse,
)
from app.models.planning_timing import PlanningTimingProvenance
from app.repositories.deadline_plan_repository import (
    DeadlinePlanProjection,
    DeadlinePlanPersistenceConflict,
    DeadlinePlanPersistenceNotFound,
    DeadlinePlanRepository,
)
from app.repositories.planning_writes import (
    DeadlineBlockWrite,
    DeadlineProposalPayload,
    DeadlineProposalWrite,
)
from app.services.planning_availability import (
    used_setup_timing_fallback,
)
from app.services.learned_timing import LearnedTimingResolver
from app.services.exam_week_outlook import (
    ExamWeekOutlookCapacityError,
    build_exam_week_outlook,
)


from app.services.deadline_plan_builder import (
    _aware_utc,
    _calendar_event_has_status_projection,
    _calendar_event_is_current,
    _context_fingerprint_input,
    _date,
    _datetime,
    _deadline_study_rhythm,
    _fingerprint as _fingerprint,
    _fixed_commitment_minutes,
    _int,
    _optional_datetime,
    _plan_blocks as _plan_blocks,
    _plan_identity,
    _require_current_source,
    _response,
    _time,
    _timing_preference_from_row,
    _zone,
)
from app.services.planner_errors import (
    DeadlinePlanConflictError,
    DeadlinePlanNotFoundError,
    DeadlinePlanValidationError,
)


class DeadlinePlanService:
    def __init__(
        self,
        *,
        repository: DeadlinePlanRepository,
        learned_timing: LearnedTimingResolver | None = None,
        now: Callable[[], datetime] | None = None,
    ) -> None:
        self._repository = repository
        self._learned_timing = learned_timing
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

    async def get_exam_week_outlook(
        self,
        *,
        user_id: str,
    ) -> ExamWeekOutlookResponse:
        generated_at = _aware_utc(self._now())
        projection = await self._repository.load_projection(
            user_id=user_id,
            plan_id=None,
        )
        if len(projection.plans) > 50:
            raise DeadlinePlanConflictError(
                "Deadline plan count exceeds the outlook bound.",
            )
        try:
            context = await self._repository.load_planning_context(
                user_id=user_id,
                plan_id=UUID(int=0),
                starts_on=(generated_at - timedelta(days=1)).date(),
                range_starts_at=generated_at,
                range_ends_at=generated_at + timedelta(days=17),
                source_calendar_event_id=None,
                include_calendar_availability=True,
            )
        except DeadlinePlanPersistenceNotFound as exc:
            raise DeadlinePlanNotFoundError(str(exc)) from exc
        details = await self._details_from_projection(
            user_id=user_id,
            projection=projection,
        )
        sleep_rows = await self._repository.list_sleep_capture_logs(
            user_id=user_id,
        )
        if len(sleep_rows) > 5_000:
            raise DeadlinePlanConflictError(
                "Daily capture history exceeds the outlook bound.",
            )

        try:
            return build_exam_week_outlook(
                generated_at=generated_at,
                context=context,
                details=details,
                sleep_rows=sleep_rows,
            )
        except ExamWeekOutlookCapacityError as exc:
            raise DeadlinePlanConflictError(str(exc)) from exc

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
        reserved = sum(item.reserved_preparation_minutes for item in contributions)
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
            over_budget_minutes=(0 if budget is None else max(0, reserved - budget)),
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
        study_rhythm = _deadline_study_rhythm(profile_probe.study_setup)
        effective_request = request
        study_setup_revision: int | None = None
        recovery_minutes = 0
        if study_rhythm is not None:
            study_setup_revision, focus_minutes, recovery_minutes = study_rhythm
            if request.max_daily_minutes < focus_minutes:
                raise DeadlinePlanValidationError(
                    "The daily preparation limit is shorter than the Study rhythm.",
                )
            effective_request = request.model_copy(
                update={"preferred_session_minutes": focus_minutes},
            )
            planning_input["preferred_session_minutes"] = focus_minutes

        effective_start = max(request.planning_start_on, local_now.date())
        timing_preference = (
            await self._learned_timing.resolve(user_id=user_id)
            if self._learned_timing is not None
            else PlanningTimingProvenance(source="setup")
        )
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
        planned_blocks = _plan_blocks(
            request=effective_request,
            context=profile_probe,
            zone=zone,
            local_now=local_now,
            local_deadline=local_deadline,
            effective_start=effective_start,
            remaining_minutes=remaining,
            learned_focus_window=(
                timing_preference.window
                if timing_preference.source == "learned_personal_pattern"
                else None
            ),
        )
        if (
            timing_preference.source == "learned_personal_pattern"
            and used_setup_timing_fallback(
                planned_blocks,
                learned_focus_window=timing_preference.window,
            )
        ):
            timing_preference = timing_preference.model_copy(
                update={"fell_back_to_setup": True},
            )
        planning_fingerprint = _fingerprint(
            {
                "contract_version": DEADLINE_PLAN_CONTRACT_VERSION,
                "input": planning_input,
                "tracked_focus_minutes_at_proposal": tracked_focus_minutes,
                "context": context_fingerprint_input,
                "timing_preference": timing_preference.model_dump(mode="json"),
            },
        )
        blocks = tuple(
            DeadlineBlockWrite(
                id=uuid5(
                    NAMESPACE_URL,
                    f"{DEADLINE_PLAN_CONTRACT_VERSION}:{request.plan_id}:"
                    f"{request.request_id}:{index}",
                ),
                sequence=index,
                starts_at=interval.starts_at.astimezone(UTC),
                ends_at=interval.ends_at.astimezone(UTC),
                recovery_minutes=interval.recovery_minutes,
                reserved_ends_at=(
                    interval.reserved_ends_at or interval.ends_at
                ).astimezone(UTC),
                local_date=interval.starts_at.date(),
                local_start_time=interval.starts_at.time().replace(tzinfo=None),
                local_end_time=interval.ends_at.time().replace(tzinfo=None),
                planned_minutes=interval.minutes,
            )
            for index, interval in enumerate(
                planned_blocks,
                start=1,
            )
        )
        planned_minutes = sum(item.minutes for item in planned_blocks)
        write = DeadlineProposalWrite(
            proposal=DeadlineProposalPayload(
                plan_id=request.plan_id,
                base_revision=request.base_revision,
                kind=request.kind,
                title=request.title,
                deadline_at=request.deadline_at,
                estimated_total_minutes=request.estimated_total_minutes,
                credited_prior_minutes=request.credited_prior_minutes,
                preferred_session_minutes=effective_request.preferred_session_minutes,
                max_daily_minutes=request.max_daily_minutes,
                planning_start_on=request.planning_start_on,
                buffer_days=request.buffer_days,
                source_kind=request.source_kind,
                source_calendar_event_id=request.source_calendar_event_id,
                source_calendar_event_fingerprint=(
                    request.source_calendar_event_fingerprint
                ),
                use_calendar_availability=use_calendar_availability,
                timezone=profile_probe.timezone,
                best_energy_window=profile_probe.best_energy_window,
                availability_connection_id=profile_probe.availability_connection_id,
                availability_import_id=profile_probe.availability_import_id,
                planning_fingerprint=planning_fingerprint,
                timing_preference=timing_preference,
                study_setup_revision=study_setup_revision,
                recovery_minutes=recovery_minutes,
                tracked_focus_minutes_at_proposal=tracked_focus_minutes,
                remaining_minutes_at_proposal=remaining,
                planned_minutes=planned_minutes,
                unscheduled_minutes=remaining - planned_minutes,
            ),
            blocks=blocks,
        )
        try:
            await self._repository.persist_proposal(
                user_id=user_id,
                request_id=request.request_id,
                request_fingerprint=request_fingerprint,
                plan_id=request.plan_id,
                base_revision=request.base_revision,
                write=write,
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
                await self._require_learned_confirmation_allowed(
                    user_id=user_id,
                    plan_id=plan_id,
                    expected_revision=request.expected_revision,
                )
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
            raise DeadlinePlanConflictError(
                "Learned Focus planning was turned off. Request a new preview.",
            )

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
            if block_id == "None" or block_id in block_ids or key not in revision_keys:
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
        focus_facts_by_plan: dict[str, list[dict[str, Any]]] = {}
        focus_fact_ids: set[str] = set()
        for row in projection.focus_facts:
            plan_key = str(row.get("plan_id"))
            fact_id = str(row.get("id"))
            if (
                plan_key not in plan_ids
                or fact_id == "None"
                or fact_id in focus_fact_ids
            ):
                raise ValueError("Deadline focus fact projection is inconsistent.")
            focus_fact_ids.add(fact_id)
            focus_facts_by_plan.setdefault(plan_key, []).append(row)
        if any(len(rows) > 10_000 for rows in focus_facts_by_plan.values()):
            raise ValueError("Deadline focus history exceeds its V2 bound.")
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
                    focus_facts=focus_facts_by_plan.get(plan_key, []),
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
        focus_facts: list[dict[str, Any]],
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
        if (
            sum(
                max(0, _int(row.get("actual_minutes")))
                for row in focus_facts
            )
            != tracked
        ):
            raise ValueError("Deadline focus facts do not match the tracked total.")
        now = _aware_utc(self._now())
        active_revision = await self._revision_from_row(
            user_id=user_id,
            row=active_row,
            block_rows=blocks,
            tracked_focus_minutes=tracked,
            focus_facts=focus_facts,
            now=now,
            plan_status=plan_row["status"],
            calendar_events=calendar_events,
        )
        pending_revision = await self._revision_from_row(
            user_id=user_id,
            row=pending_row,
            block_rows=blocks,
            tracked_focus_minutes=0,
            focus_facts=[],
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
        focus_facts: list[dict[str, Any]] | None = None,
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
        credit_facts = focus_facts
        if credit_facts is None:
            credit_facts = (
                [
                    {
                        "id": "legacy-total",
                        "started_at": row.get("activated_at")
                        or row.get("created_at"),
                        "actual_minutes": tracked_focus_minutes,
                        "deadline_plan_block_id": None,
                    },
                ]
                if tracked_focus_minutes > 0
                else []
            )
        credits = (
            _deadline_block_credits(
                matching_blocks,
                credit_facts,
                tracked_focus_minutes_at_proposal=_int(
                    row.get("tracked_focus_minutes_at_proposal"),
                ),
            )
            if row.get("state") == "active"
            else {}
        )
        rendered_blocks: list[DeadlinePlanBlock] = []
        for block in matching_blocks:
            planned = _int(block["planned_minutes"])
            credit = credits.get(str(block["id"]), 0)
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
                    recovery_minutes=_int(block.get("recovery_minutes", 0)),
                    reserved_ends_at=_datetime(
                        block.get("reserved_ends_at", block["ends_at"]),
                    ),
                    credited_tracked_minutes=credit,
                    state=display_state,
                ),
            )
        source_status = "not_applicable"
        event_id = row.get("source_calendar_event_id")
        if row.get("source_kind") == "calendar_event":
            if event_id and calendar_events is not None:
                event = calendar_events.get(str(event_id))
                if event is None or not _calendar_event_has_status_projection(
                    event,
                ):
                    event = await self._repository.get_calendar_event(
                        user_id=user_id,
                        event_id=UUID(str(event_id)),
                    )
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
            timing_preference=_timing_preference_from_row(row),
            study_setup_revision=(
                _int(row["study_setup_revision"])
                if row.get("study_setup_revision") is not None
                else None
            ),
            recovery_minutes=_int(row.get("recovery_minutes", 0)),
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


def _deadline_block_credits(
    blocks: list[dict[str, Any]],
    focus_facts: list[dict[str, Any]],
    *,
    tracked_focus_minutes_at_proposal: int,
) -> dict[str, int]:
    ordered_blocks = sorted(
        blocks,
        key=lambda block: (_int(block["sequence"]), str(block["id"])),
    )
    capacities = {
        str(block["id"]): _int(block["planned_minutes"])
        for block in ordered_blocks
    }
    credits = {block_id: 0 for block_id in capacities}
    proposal_credit_left = max(0, tracked_focus_minutes_at_proposal)
    generic_credit = 0
    ordered_facts = sorted(
        focus_facts,
        key=lambda fact: (_datetime(fact["started_at"]), str(fact["id"])),
    )
    for fact in ordered_facts:
        minutes = max(0, _int(fact.get("actual_minutes")))
        already_considered = min(minutes, proposal_credit_left)
        proposal_credit_left -= already_considered
        minutes -= already_considered
        if minutes <= 0:
            continue
        source_block_id = fact.get("deadline_plan_block_id")
        source_key = str(source_block_id) if source_block_id is not None else None
        if source_key in capacities:
            source_available = capacities[source_key] - credits[source_key]
            source_credit = min(minutes, max(0, source_available))
            credits[source_key] += source_credit
            minutes -= source_credit
        generic_credit += minutes

    for block in ordered_blocks:
        if generic_credit <= 0:
            break
        block_key = str(block["id"])
        available = capacities[block_key] - credits[block_key]
        applied = min(generic_credit, max(0, available))
        credits[block_key] += applied
        generic_credit -= applied
    return credits
