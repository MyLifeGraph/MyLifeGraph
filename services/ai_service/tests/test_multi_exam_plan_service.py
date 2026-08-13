import asyncio
from datetime import UTC, date, datetime, timedelta
from types import MethodType, SimpleNamespace
from uuid import UUID

import pytest

from app.models.multi_exam_plans import MultiExamPlanProposalRequest
from app.repositories.deadline_plan_repository import ExamPlanHealthSnapshot
from app.repositories.multi_exam_plan_repository import MultiExamPlanSnapshot
from app.services.deadline_plan_service import DeadlinePlanConflictError
from app.services.multi_exam_plan_builder import (
    MultiExamCandidate,
    colliding_candidates,
    current_review_blocks,
    retained_blocks,
    subset_tie_key,
)
from app.services.multi_exam_plan_service import (
    MultiExamPlanService,
    _combinations,
)


NOW = datetime(2026, 8, 13, 8, tzinfo=UTC)
TARGET_ID = UUID("11111111-1111-4111-8111-111111111111")
OTHER_ID = UUID("22222222-2222-4222-8222-222222222222")
THIRD_ID = UUID("33333333-3333-4333-8333-333333333333")
FOURTH_ID = UUID("44444444-4444-4444-8444-444444444444")


def _candidate(plan_id: UUID, offset: int, remaining: int = 120) -> MultiExamCandidate:
    deadline = NOW + timedelta(days=offset)
    return MultiExamCandidate(
        plan_id=plan_id,
        row={"id": str(plan_id)},
        deadline_at=deadline,
        remaining_minutes=remaining,
    )


def _health(
    *,
    blocks: list[dict[str, object]] | None = None,
    focus_facts: list[dict[str, object]] | None = None,
) -> ExamPlanHealthSnapshot:
    return ExamPlanHealthSnapshot(
        generated_at=NOW,
        local_today=date(2026, 8, 13),
        horizon_ends_before=date(2027, 8, 15),
        profile={
            "timezone": "UTC",
            "timezone_revision": 1,
            "daily_preparation_budget_minutes": 120,
        },
        best_energy_window="morning",
        study_setup=None,
        planner_preference={"use_calendar_busy_time": False},
        exams=[],
        focus_totals=[],
        focus_facts=focus_facts or [],
        deadline_blocks=blocks or [],
        schedule_items=[],
        planner_task_blocks=[],
        planner_habit_slots=[],
        planner_commitments=[],
        calendar_import=None,
        calendar_timed_events=[],
        calendar_all_day_events=[],
    )


def _plan(plan_id: UUID, *, deadline_offset: int) -> dict[str, object]:
    return {
        "id": str(plan_id),
        "kind": "exam",
        "title": str(plan_id),
        "status": "active",
        "current_revision": 1,
        "latest_revision": 1,
        "pending_revision": None,
        "deadline_at": (NOW + timedelta(days=deadline_offset)).isoformat(),
        "planning_start_on": NOW.date().isoformat(),
        "buffer_days": 0,
        "estimated_total_minutes": 120,
        "credited_prior_minutes": 0,
        "tracked_focus_minutes_at_proposal": 0,
    }


def _snapshot(
    plans: list[dict[str, object]],
    *,
    blocks: list[dict[str, object]] | None = None,
    focus_facts: list[dict[str, object]] | None = None,
) -> MultiExamPlanSnapshot:
    health = _health(blocks=blocks, focus_facts=focus_facts)
    health.focus_totals.extend(
        {
            "plan_id": str(plan["id"]),
            "actual_minutes": 0,
            "focus_count": 0,
        }
        for plan in plans
        if plan.get("kind") == "exam"
    )
    return MultiExamPlanSnapshot(
        health=health,
        context_fingerprint="a" * 64,
        active_plans=plans,
    )


def test_exact_combination_order_is_stable_and_complete() -> None:
    values = [
        _candidate(TARGET_ID, 1),
        _candidate(OTHER_ID, 2),
        _candidate(THIRD_ID, 3),
        _candidate(FOURTH_ID, 4),
    ]
    assert [
        tuple(item.plan_id for item in subset) for subset in _combinations(values, 2)
    ] == [
        (TARGET_ID, OTHER_ID),
        (TARGET_ID, THIRD_ID),
        (TARGET_ID, FOURTH_ID),
        (OTHER_ID, THIRD_ID),
        (OTHER_ID, FOURTH_ID),
        (THIRD_ID, FOURTH_ID),
    ]


def test_exam_priority_is_deadline_then_larger_remaining_then_stable_id() -> None:
    same_deadline = NOW + timedelta(days=10)
    candidates = [
        MultiExamCandidate(OTHER_ID, {}, same_deadline, 120),
        MultiExamCandidate(THIRD_ID, {}, NOW + timedelta(days=9), 30),
        MultiExamCandidate(TARGET_ID, {}, same_deadline, 180),
        MultiExamCandidate(FOURTH_ID, {}, same_deadline, 120),
    ]
    assert [
        candidate.plan_id
        for candidate in sorted(candidates, key=lambda item: item.priority)
    ] == [
        THIRD_ID,
        TARGET_ID,
        OTHER_ID,
        FOURTH_ID,
    ]


def test_subset_tie_prefers_later_deadlines_then_stable_ids(monkeypatch) -> None:
    monkeypatch.setattr(
        "app.services.multi_exam_plan_builder.shifted_minutes",
        lambda prepared: 60,
    )
    target = SimpleNamespace(candidate=_candidate(TARGET_ID, 5))
    early = SimpleNamespace(candidate=_candidate(OTHER_ID, 10, remaining=300))
    late_low_id = SimpleNamespace(candidate=_candidate(THIRD_ID, 20, remaining=30))
    late_high_id = SimpleNamespace(candidate=_candidate(FOURTH_ID, 20, remaining=500))

    early_key = subset_tie_key(
        [target, early],
        target_plan_id=TARGET_ID,
    )
    late_low_key = subset_tie_key(
        [target, late_low_id],
        target_plan_id=TARGET_ID,
    )
    late_high_key = subset_tie_key(
        [target, late_high_id],
        target_plan_id=TARGET_ID,
    )
    assert late_low_key < early_key
    assert late_low_key < late_high_key


def test_all_active_exam_consumers_remain_search_candidates_beyond_old_target_window() -> (
    None
):
    target = _plan(TARGET_ID, deadline_offset=10)
    other = _plan(OTHER_ID, deadline_offset=30)
    far_block_start = NOW + timedelta(days=25)
    blocks = [
        {
            "id": "55555555-5555-4555-8555-555555555555",
            "plan_id": str(OTHER_ID),
            "revision": 1,
            "sequence": 1,
            "starts_at": far_block_start.isoformat(),
            "ends_at": (far_block_start + timedelta(minutes=30)).isoformat(),
            "reserved_ends_at": (far_block_start + timedelta(minutes=30)).isoformat(),
            "local_date": far_block_start.date().isoformat(),
            "planned_minutes": 30,
            "recovery_minutes": 0,
        },
    ]
    snapshot = _snapshot([target, other], blocks=blocks)
    selected = colliding_candidates(
        snapshot,
        target=_candidate(TARGET_ID, 10),
    )
    assert [candidate.plan_id for candidate in selected] == [OTHER_ID]


def test_active_exam_without_future_blocks_remains_an_exact_search_candidate() -> None:
    target = _plan(TARGET_ID, deadline_offset=10)
    other = _plan(OTHER_ID, deadline_offset=30)
    selected = colliding_candidates(
        _snapshot([target, other]),
        target=_candidate(TARGET_ID, 10),
    )
    assert [candidate.plan_id for candidate in selected] == [OTHER_ID]


def test_partial_block_credit_is_preserved_as_effective_old_minutes() -> None:
    plan = _plan(TARGET_ID, deadline_offset=10)
    starts_at = NOW + timedelta(days=2)
    block_id = "66666666-6666-4666-8666-666666666666"
    block = {
        "id": block_id,
        "plan_id": str(TARGET_ID),
        "revision": 1,
        "sequence": 1,
        "starts_at": starts_at.isoformat(),
        "ends_at": (starts_at + timedelta(minutes=60)).isoformat(),
        "reserved_ends_at": (starts_at + timedelta(minutes=60)).isoformat(),
        "local_date": starts_at.date().isoformat(),
        "planned_minutes": 60,
        "recovery_minutes": 0,
    }
    focus = {
        "id": "77777777-7777-4777-8777-777777777777",
        "plan_id": str(TARGET_ID),
        "started_at": (NOW - timedelta(hours=1)).isoformat(),
        "actual_minutes": 17,
        "deadline_plan_block_id": block_id,
    }
    snapshot = _snapshot([plan], blocks=[block], focus_facts=[focus])
    candidate = MultiExamCandidate(
        plan_id=TARGET_ID,
        row=plan,
        deadline_at=NOW + timedelta(days=10),
        remaining_minutes=103,
    )
    review = current_review_blocks(snapshot, candidate)
    assert len(review) == 1
    assert review[0].credited_minutes == 17
    assert review[0].effective_minutes == 43


def test_retain_and_supplement_never_retains_past_remaining_work() -> None:
    plan = {
        **_plan(TARGET_ID, deadline_offset=10),
        "timezone": "UTC",
        "preferred_session_minutes": 60,
        "max_daily_minutes": 120,
        "recovery_minutes": 0,
        "study_setup_revision": None,
        "use_calendar_availability": False,
    }
    starts_at = NOW + timedelta(days=2)
    blocks = [
        {
            "id": str(UUID(int=index + 10)),
            "plan_id": str(TARGET_ID),
            "revision": 1,
            "sequence": index,
            "starts_at": (starts_at + timedelta(hours=index - 1)).isoformat(),
            "ends_at": (
                starts_at + timedelta(hours=index - 1, minutes=60)
            ).isoformat(),
            "reserved_ends_at": (
                starts_at + timedelta(hours=index - 1, minutes=60)
            ).isoformat(),
            "local_date": starts_at.date().isoformat(),
            "planned_minutes": 60,
            "recovery_minutes": 0,
        }
        for index in (1, 2)
    ]
    snapshot = _snapshot([plan], blocks=blocks)
    candidate = MultiExamCandidate(
        plan_id=TARGET_ID,
        row=plan,
        deadline_at=NOW + timedelta(days=10),
        remaining_minutes=60,
    )

    retained = retained_blocks(
        snapshot,
        candidate=candidate,
        outer_request_id=UUID("88888888-8888-4888-8888-888888888887"),
    )

    assert len(retained) == 1
    assert sum(block.planned_minutes for block in retained) == 60


def test_search_proves_cardinality_then_tie_breaks_after_enumerating_whole_level(
    monkeypatch,
) -> None:
    target = _candidate(TARGET_ID, 10)
    colliders = [
        _candidate(OTHER_ID, 12),
        _candidate(THIRD_ID, 13),
        _candidate(FOURTH_ID, 14),
    ]
    service = MultiExamPlanService(repository=object(), deadline_plans=object())
    calls: list[tuple[tuple[UUID, ...], bool]] = []

    async def evaluate(self, **kwargs):
        selected = kwargs["selected"]
        retain = kwargs["retain_target"]
        calls.append((tuple(item.plan_id for item in selected), retain))
        if len(selected) == 2 and selected[1].plan_id in {OTHER_ID, FOURTH_ID}:
            return [
                SimpleNamespace(candidate=target, tie=2),
                SimpleNamespace(
                    candidate=selected[1],
                    tie=(1 if selected[1].plan_id == FOURTH_ID else 2),
                ),
            ]
        return None

    service._evaluate = MethodType(evaluate, service)
    monkeypatch.setattr(
        "app.services.multi_exam_plan_service.colliding_candidates",
        lambda snapshot, target: colliders,
    )
    monkeypatch.setattr(
        "app.services.multi_exam_plan_service.subset_tie_key",
        lambda result, target_plan_id: result[1].tie,
    )
    result = asyncio.run(
        service._choose_minimal_balance(
            user_id="owner",
            outer_request_id=UUID("88888888-8888-4888-8888-888888888888"),
            snapshot=object(),
            target=target,
        ),
    )
    assert result[1].candidate.plan_id == FOURTH_ID
    assert calls[:2] == [((TARGET_ID,), True), ((TARGET_ID,), False)]
    assert [selected for selected, _ in calls[2:]] == [
        (TARGET_ID, OTHER_ID),
        (TARGET_ID, THIRD_ID),
        (TARGET_ID, FOURTH_ID),
    ]


def test_search_bound_fails_closed_before_an_unproved_cardinality(monkeypatch) -> None:
    target = _candidate(TARGET_ID, 10)
    colliders = [
        _candidate(OTHER_ID, 12),
        _candidate(THIRD_ID, 13),
        _candidate(FOURTH_ID, 14),
    ]
    service = MultiExamPlanService(repository=object(), deadline_plans=object())
    calls = 0

    async def evaluate(self, **kwargs):
        nonlocal calls
        calls += 1
        return None

    service._evaluate = MethodType(evaluate, service)
    monkeypatch.setattr(
        "app.services.multi_exam_plan_service.colliding_candidates",
        lambda snapshot, target: colliders,
    )
    monkeypatch.setattr(
        "app.services.multi_exam_plan_service.MAX_MULTI_EXAM_SEARCH_NODES",
        2,
    )
    with pytest.raises(DeadlinePlanConflictError, match="balance_search_limit"):
        asyncio.run(
            service._choose_minimal_balance(
                user_id="owner",
                outer_request_id=UUID("99999999-9999-4999-8999-999999999999"),
                snapshot=object(),
                target=target,
            ),
        )
    assert calls == 2


def test_search_bound_counts_the_initial_retained_probe(monkeypatch) -> None:
    target = _candidate(TARGET_ID, 10)
    service = MultiExamPlanService(repository=object(), deadline_plans=object())
    calls = 0

    async def evaluate(self, **kwargs):
        nonlocal calls
        calls += 1
        return None

    service._evaluate = MethodType(evaluate, service)
    monkeypatch.setattr(
        "app.services.multi_exam_plan_service.MAX_MULTI_EXAM_SEARCH_NODES",
        1,
    )
    with pytest.raises(DeadlinePlanConflictError, match="balance_search_limit"):
        asyncio.run(
            service._choose_minimal_balance(
                user_id="owner",
                outer_request_id=UUID("99999999-9999-4999-8999-999999999996"),
                snapshot=object(),
                target=target,
            ),
        )
    assert calls == 1


def test_changed_plan_bound_fails_closed_instead_of_claiming_no_capacity(
    monkeypatch,
) -> None:
    target = _candidate(TARGET_ID, 10)
    colliders = [_candidate(OTHER_ID, 12), _candidate(THIRD_ID, 13)]
    service = MultiExamPlanService(repository=object(), deadline_plans=object())

    async def evaluate(self, **kwargs):
        return None

    service._evaluate = MethodType(evaluate, service)
    monkeypatch.setattr(
        "app.services.multi_exam_plan_service.colliding_candidates",
        lambda snapshot, target: colliders,
    )
    monkeypatch.setattr(
        "app.services.multi_exam_plan_service.MAX_MULTI_EXAM_CHANGED_PLANS",
        2,
    )
    with pytest.raises(DeadlinePlanConflictError, match="balance_search_limit"):
        asyncio.run(
            service._choose_minimal_balance(
                user_id="owner",
                outer_request_id=UUID("99999999-9999-4999-8999-999999999997"),
                snapshot=object(),
                target=target,
            ),
        )


def test_search_rejects_a_result_that_does_not_change_the_explicit_target(
    monkeypatch,
) -> None:
    target = _candidate(TARGET_ID, 10)
    colliders = [_candidate(OTHER_ID, 12), _candidate(THIRD_ID, 13)]
    service = MultiExamPlanService(repository=object(), deadline_plans=object())

    async def evaluate(self, **kwargs):
        selected = kwargs["selected"]
        if len(selected) == 1:
            return None
        return [
            SimpleNamespace(candidate=colliders[0]),
            SimpleNamespace(candidate=colliders[1]),
        ]

    service._evaluate = MethodType(evaluate, service)
    monkeypatch.setattr(
        "app.services.multi_exam_plan_service.colliding_candidates",
        lambda snapshot, target: colliders,
    )
    with pytest.raises(
        DeadlinePlanConflictError,
        match="No complete Exam balance fits current capacity",
    ):
        asyncio.run(
            service._choose_minimal_balance(
                user_id="owner",
                outer_request_id=UUID("99999999-9999-4999-8999-999999999998"),
                snapshot=object(),
                target=target,
            ),
        )


def test_confirm_delegates_to_atomic_rpc_before_any_projection_read() -> None:
    class Repository:
        def __init__(self) -> None:
            self.calls: list[str] = []

        async def confirm(self, **kwargs):
            self.calls.append("confirm")

        async def get_balance(self, **kwargs):
            self.calls.append("get")
            raise ValueError("projection intentionally unavailable")

    repository = Repository()
    service = MultiExamPlanService(repository=repository, deadline_plans=object())
    request = SimpleNamespace(
        request_id=UUID("aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaab"),
        expected_revision=1,
    )
    with pytest.raises(DeadlinePlanConflictError, match="projection is inconsistent"):
        asyncio.run(
            service.confirm(
                user_id="owner",
                balance_id=UUID("aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaac"),
                request=request,
            ),
        )
    assert repository.calls == ["confirm", "get"]


def test_terminal_single_proposal_replay_is_a_stable_conflict() -> None:
    class DeadlinePlans:
        async def get_plan(self, **kwargs):
            return SimpleNamespace(
                plan=SimpleNamespace(id=TARGET_ID, kind="exam"),
                pending_revision=None,
            )

    service = MultiExamPlanService(
        repository=object(),
        deadline_plans=DeadlinePlans(),
    )
    request = MultiExamPlanProposalRequest(
        contract_version="multi-exam-plan-v1",
        request_id=UUID("aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1"),
        target_plan_id=TARGET_ID,
        expected_plan_revision=1,
    )
    replay = {
        "operation": "proposal",
        "request_fingerprint": "f" * 64,
        "target_plan_id": str(TARGET_ID),
        "outcome": "single_plan",
        "result_plan_id": str(TARGET_ID),
        "result_revision": 2,
        "result_status": "proposed",
    }
    with pytest.raises(
        DeadlinePlanConflictError,
        match="Original Exam balance proposal is no longer pending",
    ):
        asyncio.run(
            service._proposal_replay(
                user_id="owner",
                request=request,
                request_fingerprint="f" * 64,
                replay=replay,
            ),
        )


def test_terminal_batch_proposal_replay_is_a_stable_conflict() -> None:
    balance_id = UUID("aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa2")

    class Repository:
        async def get_balance(self, **kwargs):
            return {
                "contract_version": "multi-exam-plan-v1",
                "origin": "authenticated_backend",
                "balance": {},
            }

    class Service(MultiExamPlanService):
        async def get_balance(self, **kwargs):
            return SimpleNamespace(
                balance=SimpleNamespace(
                    id=balance_id,
                    target_plan_id=TARGET_ID,
                    revision=1,
                    status="cancelled",
                ),
            )

    service = Service(repository=Repository(), deadline_plans=object())
    request = MultiExamPlanProposalRequest(
        contract_version="multi-exam-plan-v1",
        request_id=UUID("aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa3"),
        target_plan_id=TARGET_ID,
        expected_plan_revision=1,
    )
    replay = {
        "operation": "proposal",
        "request_fingerprint": "e" * 64,
        "target_plan_id": str(TARGET_ID),
        "outcome": "multi_exam_batch",
        "balance_id": str(balance_id),
        "result_revision": 1,
        "result_status": "proposed",
    }
    with pytest.raises(
        DeadlinePlanConflictError,
        match="Original Exam balance proposal is no longer pending",
    ):
        asyncio.run(
            service._proposal_replay(
                user_id="owner",
                request=request,
                request_fingerprint="e" * 64,
                replay=replay,
            ),
        )
