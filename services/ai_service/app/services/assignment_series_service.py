from collections.abc import Callable
from datetime import UTC, datetime, timedelta
from typing import Any
from uuid import NAMESPACE_URL, UUID, uuid5

from app.models.assignment_series import (
    ASSIGNMENT_SERIES_CONTRACT_VERSION,
    AssignmentSeriesDetail,
    AssignmentSeriesIdentity,
    AssignmentSeriesListResponse,
    AssignmentSeriesMutationRequest,
    AssignmentSeriesOccurrence,
    AssignmentSeriesProposalRequest,
    AssignmentSeriesResponse,
    AssignmentSeriesRevision,
)
from app.models.deadline_plans import (
    DEADLINE_PLAN_CONTRACT_VERSION,
    DeadlinePlanProposalRequest,
)
from app.repositories.assignment_series_repository import (
    AssignmentSeriesProjection,
    AssignmentSeriesRepository,
)
from app.repositories.deadline_plan_repository import (
    DeadlinePlanPersistenceConflict,
    DeadlinePlanPersistenceNotFound,
    DeadlinePlanRepository,
)
from app.services.deadline_plan_builder import (
    _aware_utc,
    _datetime,
    _fingerprint,
    _int,
    _zone,
)
from app.services.deadline_plan_service import DeadlinePlanService
from app.services.local_time import LocalTimeResolutionError, resolve_local_datetime
from app.services.planner_errors import (
    DeadlinePlanConflictError,
    DeadlinePlanNotFoundError,
    DeadlinePlanValidationError,
)


class AssignmentSeriesService:
    def __init__(
        self,
        *,
        repository: AssignmentSeriesRepository,
        deadline_repository: DeadlinePlanRepository,
        deadline_plans: DeadlinePlanService,
        now: Callable[[], datetime] | None = None,
    ) -> None:
        self._repository = repository
        self._deadline_repository = deadline_repository
        self._deadline_plans = deadline_plans
        self._now = now or (lambda: datetime.now(UTC))

    async def list_series(self, *, user_id: str) -> AssignmentSeriesListResponse:
        projection = await self._repository.load_projection(
            user_id=user_id,
            series_id=None,
        )
        if len(projection.series) > 20:
            raise DeadlinePlanConflictError(
                "Assignment series count exceeds the V1 response bound.",
            )
        return AssignmentSeriesListResponse(
            contract_version=ASSIGNMENT_SERIES_CONTRACT_VERSION,
            origin="authenticated_backend",
            assignment_series=self._details_from_projection(projection),
        )

    async def get_series(
        self,
        *,
        user_id: str,
        series_id: UUID,
    ) -> AssignmentSeriesResponse:
        projection = await self._repository.load_projection(
            user_id=user_id,
            series_id=series_id,
        )
        if not projection.series:
            raise DeadlinePlanNotFoundError("Assignment series is unavailable.")
        details = self._details_from_projection(projection)
        if len(details) != 1 or details[0].series.id != series_id:
            raise ValueError("Assignment series projection returned another series.")
        return AssignmentSeriesResponse(
            contract_version=ASSIGNMENT_SERIES_CONTRACT_VERSION,
            origin="authenticated_backend",
            assignment_series=details[0],
        )

    async def propose(
        self,
        *,
        user_id: str,
        request: AssignmentSeriesProposalRequest,
    ) -> AssignmentSeriesResponse:
        generated_at = _aware_utc(self._now())
        request_fingerprint = _fingerprint(
            {
                key: value
                for key, value in request.model_dump(mode="json").items()
                if key != "request_id"
            },
        )
        replay = await self._repository.get_request_identity(
            request_id=request.request_id,
        )
        if replay is not None:
            self._require_replay(
                replay,
                user_id=user_id,
                operation="proposal",
                request_fingerprint=request_fingerprint,
                series_id=request.series_id,
                expected_revision=None,
            )
            return await self.get_series(
                user_id=user_id,
                series_id=request.series_id,
            )
        if request.next_deadline_at.astimezone(UTC) <= generated_at:
            raise DeadlinePlanValidationError(
                "The next assignment deadline must be in the future.",
            )

        projection = await self._repository.load_projection(
            user_id=user_id,
            series_id=request.series_id,
        )
        existing_detail: AssignmentSeriesDetail | None = None
        if projection.series:
            existing_details = self._details_from_projection(projection)
            if len(existing_details) != 1:
                raise ValueError("Assignment series projection is inconsistent.")
            existing_detail = existing_details[0]
            if existing_detail.series.status not in {"draft", "active"}:
                raise DeadlinePlanConflictError(
                    "A cancelled assignment series cannot be replanned.",
                )
            if existing_detail.series.latest_revision != request.base_revision:
                raise DeadlinePlanConflictError(
                    "Assignment series changed. Reload before editing it.",
                )
        elif request.base_revision != 0:
            raise DeadlinePlanConflictError(
                "A new assignment series must start at base_revision 0.",
            )

        base_revision = None
        if existing_detail is not None:
            candidates = (
                existing_detail.pending_revision,
                existing_detail.active_revision,
            )
            base_revision = next(
                (
                    value
                    for value in candidates
                    if value is not None and value.revision == request.base_revision
                ),
                None,
            )
            if base_revision is None:
                raise DeadlinePlanConflictError(
                    "Assignment series revision changed. Reload before editing it.",
                )

        base_occurrences = (
            list(base_revision.occurrences) if base_revision is not None else []
        )
        base_plan_ids = tuple(item.plan_id for item in base_occurrences)
        plan_rows = await self._repository.get_deadline_plans(
            user_id=user_id,
            plan_ids=base_plan_ids,
        )
        plans_by_id = {UUID(str(row["id"])): row for row in plan_rows}
        if set(plans_by_id) != set(base_plan_ids):
            raise DeadlinePlanConflictError(
                "An assignment occurrence changed. Reload before editing the series.",
            )

        frozen: list[AssignmentSeriesOccurrence] = []
        reusable: list[AssignmentSeriesOccurrence] = []
        for occurrence in sorted(base_occurrences, key=lambda item: item.position):
            plan = plans_by_id[occurrence.plan_id]
            terminal = plan.get("status") in {"completed", "cancelled"}
            past_active = (
                occurrence.deadline_at.astimezone(UTC) <= generated_at
                and plan.get("status") == "active"
            )
            if occurrence.action != "cancel" and (terminal or past_active):
                frozen.append(occurrence)
            elif plan.get("status") in {"draft", "active"}:
                reusable.append(occurrence)

        all_known_positions = [item.position for item in base_occurrences]
        next_position = max(all_known_positions, default=0) + 1
        desired: list[tuple[int, UUID, dict[str, Any] | None]] = []
        for index in range(request.remaining_occurrences):
            if index < len(reusable):
                occurrence = reusable[index]
                desired.append(
                    (
                        occurrence.position,
                        occurrence.plan_id,
                        plans_by_id[occurrence.plan_id],
                    ),
                )
            else:
                position = next_position
                next_position += 1
                if position > 200:
                    raise DeadlinePlanConflictError(
                        "Assignment series history exceeds the V1 position bound.",
                    )
                plan_id = uuid5(
                    NAMESPACE_URL,
                    f"{ASSIGNMENT_SERIES_CONTRACT_VERSION}:"
                    f"{request.series_id}:{position}",
                )
                existing_plan = await self._deadline_repository.get_plan(
                    user_id=user_id,
                    plan_id=plan_id,
                )
                if existing_plan is not None:
                    raise DeadlinePlanConflictError(
                        "Assignment occurrence identity is already in use.",
                    )
                desired.append((position, plan_id, None))

        approximate_range_end = request.next_deadline_at.astimezone(UTC) + timedelta(
            days=7 * (request.remaining_occurrences - 1) + 2,
        )
        context_plan_id = desired[0][1] if desired else UUID(int=0)
        try:
            planning_context = await self._deadline_repository.load_planning_context(
                user_id=user_id,
                plan_id=context_plan_id,
                starts_on=generated_at.date(),
                range_starts_at=generated_at,
                range_ends_at=approximate_range_end,
                source_calendar_event_id=None,
                include_calendar_availability=request.use_calendar_availability,
            )
        except DeadlinePlanPersistenceNotFound as exc:
            raise DeadlinePlanNotFoundError(str(exc)) from exc
        zone = _zone(planning_context.timezone)
        local_now = generated_at.astimezone(zone)
        local_first = request.next_deadline_at.astimezone(zone)
        due_at: list[datetime] = []
        try:
            for index in range(request.remaining_occurrences):
                due_at.append(
                    resolve_local_datetime(
                        local_date=local_first.date() + timedelta(days=7 * index),
                        local_time=local_first.time().replace(tzinfo=None),
                        zone=zone,
                        source_id=f"assignment-series:{request.series_id}:{index + 1}",
                    ),
                )
        except LocalTimeResolutionError as exc:
            raise DeadlinePlanValidationError(
                "A weekly deadline falls in an ambiguous or unavailable local time. "
                "Choose another deadline time.",
            ) from exc
        if due_at[-1].astimezone(UTC) > generated_at + timedelta(days=366):
            raise DeadlinePlanValidationError(
                "Assignment series cannot extend beyond 366 days.",
            )

        frozen_end = max(
            (
                item.deadline_at.astimezone(zone).date() + timedelta(days=1)
                for item in frozen
            ),
            default=local_now.date(),
        )
        first_planning_day = max(local_now.date(), frozen_end)
        affected_plan_ids = frozenset(
            [item.plan_id for item in reusable] + [plan_id for _, plan_id, _ in desired]
        )
        timing_preference = await self._deadline_plans.resolve_timing_preference(
            user_id=user_id,
        )
        items: list[dict[str, Any]] = []
        planned_total = 0
        unscheduled_total = 0

        for occurrence in frozen:
            plan = plans_by_id[occurrence.plan_id]
            plan_revision = (
                _int(plan.get("current_revision"))
                if _int(plan.get("current_revision")) > 0
                else _int(plan.get("latest_revision"))
            )
            items.append(
                {
                    "position": occurrence.position,
                    "action": "retain",
                    "plan_id": str(occurrence.plan_id),
                    "plan_revision": plan_revision,
                    "deadline_at": occurrence.deadline_at.astimezone(UTC).isoformat(),
                },
            )

        for index, (position, plan_id, plan) in enumerate(desired):
            deadline = due_at[index]
            planning_start = (
                first_planning_day
                if index == 0
                else due_at[index - 1].date() + timedelta(days=1)
            )
            plan_base_revision = (
                _int(plan.get("latest_revision")) if plan is not None else 0
            )
            proposal_request_id = uuid5(
                NAMESPACE_URL,
                f"{ASSIGNMENT_SERIES_CONTRACT_VERSION}:{request.request_id}:"
                f"proposal:{plan_id}",
            )
            deadline_request = DeadlinePlanProposalRequest.model_validate(
                {
                    "request_id": str(proposal_request_id),
                    "plan_id": str(plan_id),
                    "base_revision": plan_base_revision,
                    "kind": "assignment",
                    "title": request.title,
                    "deadline_at": deadline.isoformat(),
                    "estimated_total_minutes": request.estimated_total_minutes,
                    "credited_prior_minutes": 0,
                    "preferred_session_minutes": request.preferred_session_minutes,
                    "max_daily_minutes": request.max_daily_minutes,
                    "planning_start_on": planning_start.isoformat(),
                    "buffer_days": request.buffer_days,
                    "source_kind": "manual",
                    "use_calendar_availability": (
                        request.use_calendar_availability
                    ),
                },
            )
            prepared = await self._deadline_plans.prepare_proposal(
                user_id=user_id,
                request=deadline_request,
                generated_at=generated_at,
                planning_context=planning_context,
                excluded_plan_ids=affected_plan_ids,
                timing_preference=timing_preference,
            )
            plan_revision = plan_base_revision + 1
            confirm_request_id = uuid5(
                NAMESPACE_URL,
                f"{ASSIGNMENT_SERIES_CONTRACT_VERSION}:{request.request_id}:"
                f"confirm:{plan_id}:{plan_revision}",
            )
            confirm_fingerprint = _deadline_mutation_fingerprint(
                operation="confirm",
                plan_id=plan_id,
                expected_revision=plan_revision,
            )
            planned_total += prepared.write.proposal.planned_minutes
            unscheduled_total += prepared.write.proposal.unscheduled_minutes
            items.append(
                {
                    "position": position,
                    "action": "upsert",
                    "plan_id": str(plan_id),
                    "plan_revision": plan_revision,
                    "deadline_at": deadline.astimezone(UTC).isoformat(),
                    "proposal_request_id": str(proposal_request_id),
                    "proposal_request_fingerprint": prepared.request_fingerprint,
                    "proposal": prepared.write.proposal_json(),
                    "blocks": prepared.write.blocks_json(),
                    "mutation_request_id": str(confirm_request_id),
                    "mutation_request_fingerprint": confirm_fingerprint,
                },
            )

        desired_ids = {plan_id for _, plan_id, _ in desired}
        for occurrence in reusable:
            if occurrence.plan_id in desired_ids:
                continue
            plan = plans_by_id[occurrence.plan_id]
            expected_revision = (
                _int(plan.get("current_revision"))
                if plan.get("status") == "active"
                else _int(plan.get("latest_revision"))
            )
            cancel_request_id = uuid5(
                NAMESPACE_URL,
                f"{ASSIGNMENT_SERIES_CONTRACT_VERSION}:{request.request_id}:"
                f"cancel:{occurrence.plan_id}:{expected_revision}",
            )
            items.append(
                {
                    "position": occurrence.position,
                    "action": "cancel",
                    "plan_id": str(occurrence.plan_id),
                    "plan_revision": expected_revision,
                    "deadline_at": occurrence.deadline_at.astimezone(UTC).isoformat(),
                    "mutation_request_id": str(cancel_request_id),
                    "mutation_request_fingerprint": _deadline_mutation_fingerprint(
                        operation="cancel",
                        plan_id=occurrence.plan_id,
                        expected_revision=expected_revision,
                    ),
                },
            )

        items.sort(key=lambda value: (int(value["position"]), str(value["plan_id"])))
        use_calendar = (
            planning_context.planner_use_calendar_busy_time
            if planning_context.planner_use_calendar_busy_time is not None
            else request.use_calendar_availability
        )
        series_payload = {
            "title": request.title,
            "next_deadline_at": due_at[0].astimezone(UTC).isoformat(),
            "remaining_occurrences": request.remaining_occurrences,
            "estimated_total_minutes": request.estimated_total_minutes,
            "preferred_session_minutes": (
                items
                and next(
                    (
                        int(item["proposal"]["preferred_session_minutes"])
                        for item in items
                        if item["action"] == "upsert"
                    ),
                    request.preferred_session_minutes,
                )
            ),
            "max_daily_minutes": request.max_daily_minutes,
            "buffer_days": request.buffer_days,
            "use_calendar_availability": use_calendar,
            "timezone": planning_context.timezone,
            "planned_minutes": planned_total,
            "unscheduled_minutes": unscheduled_total,
        }
        try:
            await self._repository.persist_proposal(
                user_id=user_id,
                request_id=request.request_id,
                request_fingerprint=request_fingerprint,
                series_id=request.series_id,
                base_revision=request.base_revision,
                series_payload=series_payload,
                items=items,
                now=generated_at,
            )
        except DeadlinePlanPersistenceConflict as exc:
            raise DeadlinePlanConflictError(str(exc)) from exc
        except DeadlinePlanPersistenceNotFound as exc:
            raise DeadlinePlanNotFoundError(str(exc)) from exc
        return await self.get_series(user_id=user_id, series_id=request.series_id)

    async def confirm(
        self,
        *,
        user_id: str,
        series_id: UUID,
        request: AssignmentSeriesMutationRequest,
    ) -> AssignmentSeriesResponse:
        fingerprint = _fingerprint(
            {
                "contract_version": ASSIGNMENT_SERIES_CONTRACT_VERSION,
                "operation": "confirm",
                "series_id": str(series_id),
                "expected_revision": request.expected_revision,
            },
        )
        replay = await self._repository.get_request_identity(
            request_id=request.request_id,
        )
        if replay is not None:
            self._require_replay(
                replay,
                user_id=user_id,
                operation="confirm",
                request_fingerprint=fingerprint,
                series_id=series_id,
                expected_revision=request.expected_revision,
            )
            return await self.get_series(user_id=user_id, series_id=series_id)
        response = await self.get_series(user_id=user_id, series_id=series_id)
        pending = response.assignment_series.pending_revision
        if pending is None or pending.revision != request.expected_revision:
            raise DeadlinePlanConflictError(
                "Assignment series preview changed. Reload before confirmation.",
            )
        for occurrence in pending.occurrences:
            if occurrence.action == "upsert":
                await self._deadline_plans.require_confirmation_allowed(
                    user_id=user_id,
                    plan_id=occurrence.plan_id,
                    expected_revision=occurrence.plan_revision,
                )
        try:
            await self._repository.confirm(
                user_id=user_id,
                series_id=series_id,
                request_id=request.request_id,
                request_fingerprint=fingerprint,
                expected_revision=request.expected_revision,
                now=_aware_utc(self._now()),
            )
        except DeadlinePlanPersistenceConflict as exc:
            raise DeadlinePlanConflictError(str(exc)) from exc
        except DeadlinePlanPersistenceNotFound as exc:
            raise DeadlinePlanNotFoundError(str(exc)) from exc
        return await self.get_series(user_id=user_id, series_id=series_id)

    async def cancel_future(
        self,
        *,
        user_id: str,
        series_id: UUID,
        request: AssignmentSeriesMutationRequest,
    ) -> AssignmentSeriesResponse:
        fingerprint = _fingerprint(
            {
                "contract_version": ASSIGNMENT_SERIES_CONTRACT_VERSION,
                "operation": "cancel_future",
                "series_id": str(series_id),
                "expected_revision": request.expected_revision,
            },
        )
        replay = await self._repository.get_request_identity(
            request_id=request.request_id,
        )
        if replay is not None:
            self._require_replay(
                replay,
                user_id=user_id,
                operation="cancel_future",
                request_fingerprint=fingerprint,
                series_id=series_id,
                expected_revision=request.expected_revision,
            )
            return await self.get_series(user_id=user_id, series_id=series_id)
        response = await self.get_series(user_id=user_id, series_id=series_id)
        detail = response.assignment_series
        revision = detail.pending_revision or detail.active_revision
        if revision is None or revision.revision != request.expected_revision:
            raise DeadlinePlanConflictError(
                "Assignment series changed. Reload before cancelling it.",
            )
        now = _aware_utc(self._now())
        occurrence_by_plan = {
            occurrence.plan_id: occurrence for occurrence in revision.occurrences
        }
        plan_rows = await self._repository.get_deadline_plans(
            user_id=user_id,
            plan_ids=tuple(occurrence_by_plan),
        )
        items: list[dict[str, Any]] = []
        for plan in plan_rows:
            plan_id = UUID(str(plan["id"]))
            occurrence = occurrence_by_plan[plan_id]
            if (
                plan.get("status") not in {"draft", "active"}
                or occurrence.deadline_at.astimezone(UTC) <= now
            ):
                continue
            expected_revision = (
                _int(plan.get("current_revision"))
                if plan.get("status") == "active"
                else _int(plan.get("latest_revision"))
            )
            mutation_request_id = uuid5(
                NAMESPACE_URL,
                f"{ASSIGNMENT_SERIES_CONTRACT_VERSION}:{request.request_id}:"
                f"cancel-future:{plan_id}:{expected_revision}",
            )
            items.append(
                {
                    "plan_id": str(plan_id),
                    "expected_revision": expected_revision,
                    "request_id": str(mutation_request_id),
                    "request_fingerprint": _deadline_mutation_fingerprint(
                        operation="cancel",
                        plan_id=plan_id,
                        expected_revision=expected_revision,
                    ),
                },
            )
        if not items:
            raise DeadlinePlanConflictError(
                "This assignment series has no open future occurrences to cancel.",
            )
        items.sort(key=lambda item: str(item["plan_id"]))
        try:
            await self._repository.cancel_future(
                user_id=user_id,
                series_id=series_id,
                request_id=request.request_id,
                request_fingerprint=fingerprint,
                expected_revision=request.expected_revision,
                items=items,
                now=now,
            )
        except DeadlinePlanPersistenceConflict as exc:
            raise DeadlinePlanConflictError(str(exc)) from exc
        except DeadlinePlanPersistenceNotFound as exc:
            raise DeadlinePlanNotFoundError(str(exc)) from exc
        return await self.get_series(user_id=user_id, series_id=series_id)

    def _details_from_projection(
        self,
        projection: AssignmentSeriesProjection,
    ) -> list[AssignmentSeriesDetail]:
        series_ids = {str(row.get("id")) for row in projection.series}
        if "None" in series_ids or len(series_ids) != len(projection.series):
            raise ValueError("Assignment series identities are inconsistent.")
        revisions: dict[str, list[dict[str, Any]]] = {}
        revision_keys: set[tuple[str, int]] = set()
        for row in projection.revisions:
            key = (str(row.get("series_id")), _int(row.get("revision")))
            if key[0] not in series_ids or key in revision_keys:
                raise ValueError("Assignment series revisions are inconsistent.")
            revision_keys.add(key)
            revisions.setdefault(key[0], []).append(row)
        occurrences: dict[tuple[str, int], list[dict[str, Any]]] = {}
        occurrence_keys: set[tuple[str, int, str]] = set()
        for row in projection.occurrences:
            revision_key = (
                str(row.get("series_id")),
                _int(row.get("series_revision")),
            )
            key = (*revision_key, str(row.get("plan_id")))
            if revision_key not in revision_keys or key in occurrence_keys:
                raise ValueError("Assignment series occurrences are inconsistent.")
            occurrence_keys.add(key)
            occurrences.setdefault(revision_key, []).append(row)
        details: list[AssignmentSeriesDetail] = []
        for series_row in projection.series:
            series_id = str(series_row["id"])
            revision_rows = revisions.get(series_id, [])
            active_row = next(
                (row for row in revision_rows if row.get("state") == "active"),
                None,
            )
            pending_row = next(
                (row for row in revision_rows if row.get("state") == "proposed"),
                None,
            )
            details.append(
                AssignmentSeriesDetail(
                    series=AssignmentSeriesIdentity(
                        id=UUID(series_id),
                        status=series_row["status"],
                        title=series_row["title"],
                        current_revision=_int(series_row["current_revision"]),
                        latest_revision=_int(series_row["latest_revision"]),
                        created_at=_datetime(series_row["created_at"]),
                        updated_at=_datetime(series_row["updated_at"]),
                        first_activated_at=(
                            _datetime(series_row["first_activated_at"])
                            if series_row.get("first_activated_at") is not None
                            else None
                        ),
                        cancelled_at=(
                            _datetime(series_row["cancelled_at"])
                            if series_row.get("cancelled_at") is not None
                            else None
                        ),
                    ),
                    active_revision=self._revision_from_row(
                        active_row,
                        occurrences.get(
                            (series_id, _int(active_row["revision"])),
                            [],
                        )
                        if active_row is not None
                        else [],
                    ),
                    pending_revision=self._revision_from_row(
                        pending_row,
                        occurrences.get(
                            (series_id, _int(pending_row["revision"])),
                            [],
                        )
                        if pending_row is not None
                        else [],
                    ),
                ),
            )
        return details

    def _revision_from_row(
        self,
        row: dict[str, Any] | None,
        item_rows: list[dict[str, Any]],
    ) -> AssignmentSeriesRevision | None:
        if row is None:
            return None
        rendered = [
            AssignmentSeriesOccurrence(
                position=_int(item["position"]),
                action=item["action"],
                plan_id=UUID(str(item["plan_id"])),
                plan_revision=_int(item["plan_revision"]),
                deadline_at=_datetime(item["deadline_at"]),
            )
            for item in item_rows
        ]
        rendered.sort(key=lambda item: (item.position, str(item.plan_id)))
        return AssignmentSeriesRevision(
            series_id=UUID(str(row["series_id"])),
            revision=_int(row["revision"]),
            base_revision=_int(row["base_revision"]),
            state=row["state"],
            title=row["title"],
            next_deadline_at=_datetime(row["next_deadline_at"]),
            remaining_occurrences=_int(row["remaining_occurrences"]),
            estimated_total_minutes=_int(row["estimated_total_minutes"]),
            preferred_session_minutes=_int(row["preferred_session_minutes"]),
            max_daily_minutes=_int(row["max_daily_minutes"]),
            buffer_days=_int(row["buffer_days"]),
            use_calendar_availability=bool(row["use_calendar_availability"]),
            timezone=row["timezone"],
            planned_minutes=_int(row["planned_minutes"]),
            unscheduled_minutes=_int(row["unscheduled_minutes"]),
            created_at=_datetime(row["created_at"]),
            activated_at=(
                _datetime(row["activated_at"])
                if row.get("activated_at") is not None
                else None
            ),
            superseded_at=(
                _datetime(row["superseded_at"])
                if row.get("superseded_at") is not None
                else None
            ),
            occurrences=rendered,
        )

    @staticmethod
    def _require_replay(
        replay: dict[str, Any],
        *,
        user_id: str,
        operation: str,
        request_fingerprint: str,
        series_id: UUID,
        expected_revision: int | None,
    ) -> None:
        if (
            replay.get("user_id") != user_id
            or replay.get("operation") != operation
            or replay.get("request_fingerprint") != request_fingerprint
            or str(replay.get("series_id")) != str(series_id)
            or (
                expected_revision is not None
                and _int(replay.get("result_revision")) != expected_revision
            )
        ):
            raise DeadlinePlanConflictError(
                "request_id is already bound to another assignment series operation.",
            )


def _deadline_mutation_fingerprint(
    *,
    operation: str,
    plan_id: UUID,
    expected_revision: int,
) -> str:
    return _fingerprint(
        {
            "contract_version": DEADLINE_PLAN_CONTRACT_VERSION,
            "operation": operation,
            "plan_id": str(plan_id),
            "expected_revision": expected_revision,
        },
    )
