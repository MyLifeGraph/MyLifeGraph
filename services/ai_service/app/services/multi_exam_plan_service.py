from __future__ import annotations

import json
import math
from collections.abc import Callable, Iterator
from datetime import UTC, datetime
from typing import Any
from uuid import UUID, uuid5

from app.models.multi_exam_plans import (
    MULTI_EXAM_PLAN_CONTRACT_VERSION,
    MultiExamPlanBatchProposalResponse,
    MultiExamPlanBatchResponse,
    MultiExamPlanListResponse,
    MultiExamPlanMutationRequest,
    MultiExamPlanNoChangeResponse,
    MultiExamPlanProposalRequest,
    MultiExamPlanProposalResponse,
    MultiExamPlanSingleResponse,
)
from app.repositories.deadline_plan_repository import (
    DeadlinePlanPersistenceConflict,
    DeadlinePlanPersistenceNotFound,
)
from app.repositories.multi_exam_plan_repository import (
    MultiExamPlanRepository,
    MultiExamPlanSnapshot,
)
from app.services.deadline_plan_builder import _aware_utc, _fingerprint
from app.services.deadline_plan_service import DeadlinePlanService
from app.services.multi_exam_plan_builder import (
    MAX_MULTI_EXAM_CHANGED_PLANS,
    MAX_MULTI_EXAM_SEARCH_NODES,
    MULTI_EXAM_BALANCE_NAMESPACE,
    MultiExamCandidate,
    PreparedMultiExamItem,
    as_confirmed_rows,
    colliding_candidates,
    current_review_blocks,
    deadline_request,
    existing_plan_row,
    normalize_review_positions,
    planning_context,
    require_target,
    retained_blocks,
    subset_tie_key,
    timing_preference,
)
from app.services.planner_errors import (
    DeadlinePlanConflictError,
    DeadlinePlanNotFoundError,
    DeadlinePlanValidationError,
)


class MultiExamPlanService:
    def __init__(
        self,
        *,
        repository: MultiExamPlanRepository,
        deadline_plans: DeadlinePlanService,
        now: Callable[[], datetime] | None = None,
    ) -> None:
        self._repository = repository
        self._deadline_plans = deadline_plans
        self._now = now or (lambda: datetime.now(UTC))

    @property
    def _learned_timing_pilot_enabled(self) -> bool:
        return bool(
            getattr(self._deadline_plans, "learned_timing_pilot_enabled", False),
        )

    async def list_balances(self, *, user_id: str) -> MultiExamPlanListResponse:
        try:
            raw = await self._repository.list_balances(user_id=user_id)
            return MultiExamPlanListResponse.model_validate_json(json.dumps(raw))
        except DeadlinePlanPersistenceNotFound as exc:
            raise DeadlinePlanNotFoundError(str(exc)) from exc
        except ValueError as exc:
            raise DeadlinePlanConflictError(
                "Exam balance projection is inconsistent.",
            ) from exc

    async def get_balance(
        self,
        *,
        user_id: str,
        balance_id: UUID,
    ) -> MultiExamPlanBatchResponse:
        try:
            raw = await self._repository.get_balance(
                user_id=user_id,
                balance_id=balance_id,
            )
            return MultiExamPlanBatchResponse.model_validate_json(json.dumps(raw))
        except DeadlinePlanPersistenceNotFound as exc:
            raise DeadlinePlanNotFoundError(str(exc)) from exc
        except ValueError as exc:
            raise DeadlinePlanConflictError(
                "Exam balance projection is inconsistent.",
            ) from exc

    async def propose(
        self,
        *,
        user_id: str,
        request: MultiExamPlanProposalRequest,
    ) -> MultiExamPlanProposalResponse:
        generated_at = _aware_utc(self._now())
        request_fingerprint = _fingerprint(
            request.model_dump(mode="json", exclude={"request_id"}),
        )
        try:
            replay = await self._repository.get_request_identity(
                user_id=user_id,
                request_id=request.request_id,
            )
        except DeadlinePlanPersistenceConflict as exc:
            raise DeadlinePlanConflictError(str(exc)) from exc
        if replay is not None:
            return await self._proposal_replay(
                user_id=user_id,
                request=request,
                request_fingerprint=request_fingerprint,
                replay=replay,
            )

        try:
            snapshot = await self._repository.load_snapshot(
                user_id=user_id,
                generated_at=generated_at,
            )
        except DeadlinePlanPersistenceNotFound as exc:
            raise DeadlinePlanNotFoundError(str(exc)) from exc
        except ValueError as exc:
            raise DeadlinePlanConflictError(
                "Exam balance source data is inconsistent.",
            ) from exc
        try:
            target = require_target(
                snapshot,
                target_plan_id=request.target_plan_id,
                expected_revision=request.expected_plan_revision,
            )
        except ValueError as exc:
            raise DeadlinePlanConflictError(str(exc)) from exc

        try:
            prepared = await self._choose_minimal_balance(
                user_id=user_id,
                outer_request_id=request.request_id,
                snapshot=snapshot,
                target=target,
            )
        except ValueError as exc:
            raise DeadlinePlanConflictError(
                "Exam balance source data is inconsistent.",
            ) from exc
        outcome = (
            "no_change"
            if not prepared
            else "single_plan"
            if len(prepared) == 1
            else "multi_exam_batch"
        )
        balance_id = (
            uuid5(
                MULTI_EXAM_BALANCE_NAMESPACE,
                f"balance:{user_id}:{request.request_id}",
            )
            if outcome == "multi_exam_batch"
            else None
        )
        children = normalize_review_positions(prepared) if prepared else []
        try:
            persisted = await self._repository.persist_proposal(
                user_id=user_id,
                outcome=outcome,
                balance_id=balance_id,
                request_id=request.request_id,
                request_fingerprint=request_fingerprint,
                target_plan_id=request.target_plan_id,
                expected_plan_revision=request.expected_plan_revision,
                context_generated_at=generated_at,
                context_fingerprint=snapshot.context_fingerprint,
                timezone=str(snapshot.health.profile.get("timezone")),
                learned_timing_pilot_enabled=self._learned_timing_pilot_enabled,
                children=children,
                now=generated_at,
            )
        except DeadlinePlanPersistenceConflict as exc:
            raise DeadlinePlanConflictError(str(exc)) from exc
        except DeadlinePlanPersistenceNotFound as exc:
            raise DeadlinePlanNotFoundError(str(exc)) from exc

        persisted_outcome = persisted.get("outcome")
        if persisted_outcome != outcome:
            raise DeadlinePlanConflictError(
                "Exam balance persistence returned another outcome.",
            )
        result_status = persisted.get("result_status")
        result_plan_id = persisted.get("result_plan_id")
        result_revision = persisted.get("result_revision")
        persisted_balance_id = persisted.get("balance_id")
        if outcome == "no_change":
            if any(
                value is not None
                for value in (persisted_balance_id, result_plan_id, result_revision)
            ) or result_status != "unchanged":
                raise DeadlinePlanConflictError(
                    "Exam balance persistence returned an inconsistent result.",
                )
            return MultiExamPlanNoChangeResponse(
                contract_version=MULTI_EXAM_PLAN_CONTRACT_VERSION,
                origin="authenticated_backend",
                outcome="no_change",
                target_plan_id=request.target_plan_id,
                reason="already_balanced",
            )
        if outcome == "single_plan":
            expected_plan_id = prepared[0].candidate.plan_id
            expected_revision = prepared[0].request.base_revision + 1
            if (
                persisted_balance_id is not None
                or str(result_plan_id) != str(expected_plan_id)
                or result_revision != expected_revision
                or result_status != "proposed"
            ):
                raise DeadlinePlanConflictError(
                    "Exam balance persistence returned an inconsistent result.",
                )
            plan = await self._deadline_plans.get_plan(
                user_id=user_id,
                plan_id=expected_plan_id,
            )
            return MultiExamPlanSingleResponse(
                contract_version=MULTI_EXAM_PLAN_CONTRACT_VERSION,
                origin="authenticated_backend",
                outcome="single_plan",
                plan=plan,
            )
        assert balance_id is not None
        if (
            str(persisted_balance_id) != str(balance_id)
            or result_plan_id is not None
            or result_revision != 1
            or result_status != "proposed"
        ):
            raise DeadlinePlanConflictError(
                "Exam balance persistence returned an inconsistent result.",
            )
        detail = await self.get_balance(user_id=user_id, balance_id=balance_id)
        if (
            detail.balance.id != balance_id
            or detail.balance.target_plan_id != request.target_plan_id
            or detail.balance.revision != 1
            or detail.balance.status != "proposed"
        ):
            raise DeadlinePlanConflictError(
                "Exam balance persistence returned an inconsistent projection.",
            )
        return MultiExamPlanBatchProposalResponse(
            contract_version=MULTI_EXAM_PLAN_CONTRACT_VERSION,
            origin="authenticated_backend",
            outcome="multi_exam_batch",
            balance=detail.balance,
        )

    async def confirm(
        self,
        *,
        user_id: str,
        balance_id: UUID,
        request: MultiExamPlanMutationRequest,
    ) -> MultiExamPlanBatchResponse:
        fingerprint = _fingerprint(
            {
                "contract_version": MULTI_EXAM_PLAN_CONTRACT_VERSION,
                "operation": "confirm",
                "balance_id": str(balance_id),
                "expected_revision": request.expected_revision,
            },
        )
        try:
            await self._repository.confirm(
                user_id=user_id,
                balance_id=balance_id,
                request_id=request.request_id,
                request_fingerprint=fingerprint,
                expected_revision=request.expected_revision,
                learned_timing_pilot_enabled=self._learned_timing_pilot_enabled,
                now=_aware_utc(self._now()),
            )
        except DeadlinePlanPersistenceConflict as exc:
            raise DeadlinePlanConflictError(str(exc)) from exc
        except DeadlinePlanPersistenceNotFound as exc:
            raise DeadlinePlanNotFoundError(str(exc)) from exc
        return await self.get_balance(user_id=user_id, balance_id=balance_id)

    async def cancel(
        self,
        *,
        user_id: str,
        balance_id: UUID,
        request: MultiExamPlanMutationRequest,
    ) -> MultiExamPlanBatchResponse:
        fingerprint = _fingerprint(
            {
                "contract_version": MULTI_EXAM_PLAN_CONTRACT_VERSION,
                "operation": "cancel",
                "balance_id": str(balance_id),
                "expected_revision": request.expected_revision,
            },
        )
        try:
            await self._repository.cancel(
                user_id=user_id,
                balance_id=balance_id,
                request_id=request.request_id,
                request_fingerprint=fingerprint,
                expected_revision=request.expected_revision,
                now=_aware_utc(self._now()),
            )
        except DeadlinePlanPersistenceConflict as exc:
            raise DeadlinePlanConflictError(str(exc)) from exc
        except DeadlinePlanPersistenceNotFound as exc:
            raise DeadlinePlanNotFoundError(str(exc)) from exc
        return await self.get_balance(user_id=user_id, balance_id=balance_id)

    async def _choose_minimal_balance(
        self,
        *,
        user_id: str,
        outer_request_id: UUID,
        snapshot: MultiExamPlanSnapshot,
        target: MultiExamCandidate,
    ) -> list[PreparedMultiExamItem]:
        visited = 0
        if visited >= MAX_MULTI_EXAM_SEARCH_NODES:
            raise DeadlinePlanConflictError("balance_search_limit")
        visited += 1
        retained = await self._evaluate(
            user_id=user_id,
            outer_request_id=outer_request_id,
            snapshot=snapshot,
            selected=(target,),
            retain_target=True,
        )
        if retained is not None:
            return retained
        if visited >= MAX_MULTI_EXAM_SEARCH_NODES:
            raise DeadlinePlanConflictError("balance_search_limit")
        visited += 1
        redistributed = await self._evaluate(
            user_id=user_id,
            outer_request_id=outer_request_id,
            snapshot=snapshot,
            selected=(target,),
            retain_target=False,
        )
        if redistributed is not None:
            return redistributed

        colliders = colliding_candidates(snapshot, target=target)
        max_additional = min(
            len(colliders),
            MAX_MULTI_EXAM_CHANGED_PLANS - 1,
        )
        for cardinality in range(1, max_additional + 1):
            cardinality_nodes = math.comb(len(colliders), cardinality)
            if visited + cardinality_nodes > MAX_MULTI_EXAM_SEARCH_NODES:
                raise DeadlinePlanConflictError(
                    "balance_search_limit",
                )
            successes: list[list[PreparedMultiExamItem]] = []
            for subset in _combinations(colliders, cardinality):
                visited += 1
                result = await self._evaluate(
                    user_id=user_id,
                    outer_request_id=outer_request_id,
                    snapshot=snapshot,
                    selected=(target, *subset),
                    retain_target=False,
                )
                if (
                    result is not None
                    and 1 < len(result) <= MAX_MULTI_EXAM_CHANGED_PLANS
                    and any(
                        item.candidate.plan_id == target.plan_id for item in result
                    )
                ):
                    successes.append(result)
            if successes:
                return min(
                    successes,
                    key=lambda result: subset_tie_key(
                        result,
                        target_plan_id=target.plan_id,
                    ),
                )
        if len(colliders) > max_additional:
            raise DeadlinePlanConflictError(
                "balance_search_limit",
            )
        raise DeadlinePlanConflictError(
            "No complete Exam balance fits current capacity.",
        )

    async def _evaluate(
        self,
        *,
        user_id: str,
        outer_request_id: UUID,
        snapshot: MultiExamPlanSnapshot,
        selected: tuple[MultiExamCandidate, ...],
        retain_target: bool,
    ) -> list[PreparedMultiExamItem] | None:
        ordered = tuple(sorted(selected, key=lambda candidate: candidate.priority))
        excluded_ids = frozenset(candidate.plan_id for candidate in ordered)
        tracked = {
            UUID(str(row.get("plan_id"))): int(row.get("actual_minutes", 0))
            for row in snapshot.health.focus_totals
        }
        dynamic: tuple[dict[str, Any], ...] = ()
        result: list[PreparedMultiExamItem] = []
        target_id = selected[0].plan_id
        for candidate in ordered:
            request = deadline_request(candidate, outer_request_id=outer_request_id)
            retained = (
                retained_blocks(
                    snapshot,
                    candidate=candidate,
                    outer_request_id=outer_request_id,
                )
                if retain_target and candidate.plan_id == target_id
                else ()
            )
            context = planning_context(snapshot, candidate=candidate)
            try:
                prepared = await self._deadline_plans.prepare_proposal(
                    user_id=user_id,
                    request=request,
                    generated_at=snapshot.health.generated_at,
                    planning_context=context,
                    excluded_plan_ids=excluded_ids,
                    timing_preference=timing_preference(candidate),
                    existing_plan_override=existing_plan_row(candidate),
                    tracked_focus_minutes_override=tracked.get(candidate.plan_id, 0),
                    retained_blocks=retained,
                    additional_confirmed_blocks=dynamic,
                )
            except DeadlinePlanValidationError:
                return None
            if prepared.write.proposal.unscheduled_minutes != 0:
                return None
            item = PreparedMultiExamItem(
                candidate=candidate,
                request=request,
                request_fingerprint=prepared.request_fingerprint,
                write=prepared.write,
                current_blocks=current_review_blocks(snapshot, candidate),
            )
            dynamic = (*dynamic, *as_confirmed_rows(item))
            if item.changed:
                result.append(item)
        if result and not any(item.candidate.plan_id == target_id for item in result):
            return None
        return result

    async def _proposal_replay(
        self,
        *,
        user_id: str,
        request: MultiExamPlanProposalRequest,
        request_fingerprint: str,
        replay: dict[str, Any],
    ) -> MultiExamPlanProposalResponse:
        if (
            replay.get("operation") != "proposal"
            or replay.get("request_fingerprint") != request_fingerprint
            or str(replay.get("target_plan_id")) != str(request.target_plan_id)
        ):
            raise DeadlinePlanConflictError(
                "request_id is already bound to another Exam balance operation.",
            )
        outcome = replay.get("outcome")
        if outcome == "no_change":
            return MultiExamPlanNoChangeResponse(
                contract_version=MULTI_EXAM_PLAN_CONTRACT_VERSION,
                origin="authenticated_backend",
                outcome="no_change",
                target_plan_id=request.target_plan_id,
                reason="already_balanced",
            )
        if outcome == "single_plan":
            if replay.get("result_status") != "proposed":
                raise DeadlinePlanConflictError(
                    "Original Exam balance proposal is no longer pending.",
                )
            try:
                plan_id = UUID(str(replay.get("result_plan_id")))
                result_revision = int(replay.get("result_revision"))
            except (TypeError, ValueError) as exc:
                raise DeadlinePlanConflictError(
                    "Exam balance replay result is invalid.",
                ) from exc
            plan = await self._deadline_plans.get_plan(user_id=user_id, plan_id=plan_id)
            if (
                plan.plan.id != plan_id
                or plan.plan.kind != "exam"
                or plan.pending_revision is None
                or plan.pending_revision.revision != result_revision
            ):
                raise DeadlinePlanConflictError(
                    "Original Exam balance proposal is no longer pending.",
                )
            return MultiExamPlanSingleResponse(
                contract_version=MULTI_EXAM_PLAN_CONTRACT_VERSION,
                origin="authenticated_backend",
                outcome="single_plan",
                plan=plan,
            )
        if outcome == "multi_exam_batch":
            if replay.get("result_status") != "proposed":
                raise DeadlinePlanConflictError(
                    "Original Exam balance proposal is no longer pending.",
                )
            try:
                balance_id = UUID(str(replay.get("balance_id")))
                result_revision = int(replay.get("result_revision"))
            except (TypeError, ValueError) as exc:
                raise DeadlinePlanConflictError(
                    "Exam balance replay result is invalid.",
                ) from exc
            detail = await self.get_balance(user_id=user_id, balance_id=balance_id)
            if (
                detail.balance.id != balance_id
                or detail.balance.target_plan_id != request.target_plan_id
                or detail.balance.revision != result_revision
                or detail.balance.status != "proposed"
            ):
                raise DeadlinePlanConflictError(
                    "Original Exam balance proposal is no longer pending.",
                )
            return MultiExamPlanBatchProposalResponse(
                contract_version=MULTI_EXAM_PLAN_CONTRACT_VERSION,
                origin="authenticated_backend",
                outcome="multi_exam_batch",
                balance=detail.balance,
            )
        raise DeadlinePlanConflictError("Exam balance replay outcome is invalid.")


def _combinations(
    values: list[MultiExamCandidate],
    count: int,
) -> Iterator[tuple[MultiExamCandidate, ...]]:
    """Lexicographic exact cardinality search with a proof-safe finite bound."""

    chosen: list[MultiExamCandidate] = []

    def walk(start: int) -> Iterator[tuple[MultiExamCandidate, ...]]:
        remaining = count - len(chosen)
        if remaining == 0:
            yield tuple(chosen)
            return
        last_start = len(values) - remaining
        for index in range(start, last_start + 1):
            chosen.append(values[index])
            yield from walk(index + 1)
            chosen.pop()

    return walk(0)
