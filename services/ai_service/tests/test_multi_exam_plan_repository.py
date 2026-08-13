import asyncio
from datetime import UTC, datetime
from uuid import UUID

import httpx
import pytest

from app.repositories.deadline_plan_repository import (
    DeadlinePlanPersistenceConflict,
    DeadlinePlanPersistenceNotFound,
)
from app.repositories.multi_exam_plan_repository import (
    SupabaseMultiExamPlanRepository,
)


USER_ID = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
TARGET_ID = UUID("bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb")
BALANCE_ID = UUID("cccccccc-cccc-4ccc-8ccc-cccccccccccc")
REQUEST_ID = UUID("dddddddd-dddd-4ddd-8ddd-dddddddddddd")
NOW = datetime(2026, 8, 13, 8, tzinfo=UTC)


def _health(generated_at: str) -> dict[str, object]:
    return {
        "contract_version": "exam-plan-health-snapshot-v1",
        "generated_at": generated_at,
        "local_today": "2026-08-13",
        "horizon_ends_before": "2027-08-15",
        "profile": {
            "timezone": "UTC",
            "timezone_revision": 2,
            "daily_preparation_budget_minutes": 120,
        },
        "best_energy_window": "variable",
        "study_setup": None,
        "planner_preference": {"use_calendar_busy_time": False},
        "exams": [{"id": str(TARGET_ID)}],
        "focus_totals": [
            {"plan_id": str(TARGET_ID), "actual_minutes": 0, "focus_count": 0},
        ],
        "focus_facts": [],
        "deadline_blocks": [],
        "schedule_items": [],
        "planner_task_blocks": [],
        "planner_habit_slots": [],
        "planner_commitments": [],
        "calendar_import": None,
        "calendar_timed_events": [],
        "calendar_all_day_events": [],
    }


class Client:
    def __init__(self) -> None:
        self.calls: list[tuple[str, dict[str, object]]] = []

    async def rpc(self, function, *, params):
        self.calls.append((function, params))
        if function == "get_multi_exam_plan_snapshot_v1":
            return {
                "contract_version": "multi-exam-plan-snapshot-v1",
                "context_fingerprint": "a" * 64,
                "active_plans": [
                    {
                        "id": str(TARGET_ID),
                        "kind": "exam",
                        "latest_revision": 1,
                    },
                ],
                "health_snapshot": _health(params["p_generated_at"]),
            }
        if function == "get_multi_exam_plan_request_v1":
            return {"found": False}
        if function == "get_multi_exam_plan_projection_v1":
            return {
                "contract_version": "multi-exam-plan-v1",
                "origin": "authenticated_backend",
                "balances": [],
            }
        return {
            "outcome": "no_change",
            "balance_id": None,
            "result_plan_id": None,
            "result_revision": None,
            "result_status": "unchanged",
        }


def test_snapshot_and_reads_use_exact_owner_scoped_rpcs() -> None:
    client = Client()
    repository = SupabaseMultiExamPlanRepository(client)

    snapshot = asyncio.run(
        repository.load_snapshot(user_id=USER_ID, generated_at=NOW),
    )
    assert snapshot.context_fingerprint == "a" * 64
    assert snapshot.health.horizon_ends_before.isoformat() == "2027-08-15"
    assert (
        asyncio.run(
            repository.get_request_identity(user_id=USER_ID, request_id=REQUEST_ID),
        )
        is None
    )
    asyncio.run(repository.list_balances(user_id=USER_ID))
    asyncio.run(repository.get_balance(user_id=USER_ID, balance_id=BALANCE_ID))

    assert client.calls == [
        (
            "get_multi_exam_plan_snapshot_v1",
            {"p_user_id": USER_ID, "p_generated_at": NOW.isoformat()},
        ),
        (
            "get_multi_exam_plan_request_v1",
            {"p_user_id": USER_ID, "p_request_id": str(REQUEST_ID)},
        ),
        ("get_multi_exam_plan_projection_v1", {"p_user_id": USER_ID}),
        (
            "get_multi_exam_plan_projection_v1",
            {"p_user_id": USER_ID, "p_balance_id": str(BALANCE_ID)},
        ),
    ]


def test_proposal_binds_expected_plan_revision_and_full_immutable_request() -> None:
    client = Client()
    repository = SupabaseMultiExamPlanRepository(client)
    children = [{"plan_id": str(TARGET_ID)}]
    asyncio.run(
        repository.persist_proposal(
            user_id=USER_ID,
            outcome="single_plan",
            balance_id=None,
            request_id=REQUEST_ID,
            request_fingerprint="a" * 64,
            target_plan_id=TARGET_ID,
            expected_plan_revision=4,
            context_generated_at=NOW,
            context_fingerprint="b" * 64,
            timezone="UTC",
            learned_timing_pilot_enabled=True,
            children=children,
            now=NOW,
        ),
    )
    function, params = client.calls[-1]
    assert function == "propose_multi_exam_plan_v1"
    assert params == {
        "p_user_id": USER_ID,
        "p_outcome": "single_plan",
        "p_balance_id": None,
        "p_request_id": str(REQUEST_ID),
        "p_request_fingerprint": "a" * 64,
        "p_target_plan_id": str(TARGET_ID),
        "p_expected_plan_revision": 4,
        "p_context_generated_at": NOW.isoformat(),
        "p_context_fingerprint": "b" * 64,
        "p_timezone": "UTC",
        "p_learned_timing_pilot_enabled": True,
        "p_children": children,
        "p_now": NOW.isoformat(),
    }


def test_confirm_and_cancel_use_distinct_exact_mutation_rpcs() -> None:
    client = Client()
    repository = SupabaseMultiExamPlanRepository(client)
    for operation in ("confirm", "cancel"):
        asyncio.run(
            getattr(repository, operation)(
                user_id=USER_ID,
                balance_id=BALANCE_ID,
                request_id=REQUEST_ID,
                request_fingerprint="f" * 64,
                expected_revision=1,
                **(
                    {"learned_timing_pilot_enabled": True}
                    if operation == "confirm"
                    else {}
                ),
                now=NOW,
            ),
        )
    assert [call[0] for call in client.calls] == [
        "confirm_multi_exam_plan_v1",
        "cancel_multi_exam_plan_v1",
    ]
    assert all(call[1]["p_expected_revision"] == 1 for call in client.calls)
    assert client.calls[0][1]["p_learned_timing_pilot_enabled"] is True
    assert "p_learned_timing_pilot_enabled" not in client.calls[1][1]


class ErrorClient:
    def __init__(self, code: str, message: str) -> None:
        self.code = code
        self.message = message

    async def rpc(self, function, *, params):
        request = httpx.Request("POST", f"http://supabase.test/rpc/{function}")
        response = httpx.Response(
            409 if self.code == "PT409" else 404,
            request=request,
            json={"code": self.code, "message": self.message},
        )
        raise httpx.HTTPStatusError(self.message, request=request, response=response)


@pytest.mark.parametrize(
    ("code", "error_type"),
    [
        ("23505", DeadlinePlanPersistenceConflict),
        ("40001", DeadlinePlanPersistenceConflict),
        ("40P01", DeadlinePlanPersistenceConflict),
        ("55P03", DeadlinePlanPersistenceConflict),
        ("PT409", DeadlinePlanPersistenceConflict),
        ("PT404", DeadlinePlanPersistenceNotFound),
    ],
)
def test_stable_postgres_problems_map_to_repository_errors(code, error_type) -> None:
    repository = SupabaseMultiExamPlanRepository(ErrorClient(code, "stable problem"))
    with pytest.raises(error_type, match="stable problem"):
        asyncio.run(repository.get_balance(user_id=USER_ID, balance_id=BALANCE_ID))


def test_snapshot_rejects_duplicate_or_unrecognized_authorities() -> None:
    class InvalidClient(Client):
        async def rpc(self, function, *, params):
            result = await super().rpc(function, params=params)
            if function == "get_multi_exam_plan_snapshot_v1":
                result["active_plans"] = [
                    {"id": str(TARGET_ID)},
                    {"id": str(TARGET_ID)},
                ]
            return result

    repository = SupabaseMultiExamPlanRepository(InvalidClient())
    with pytest.raises(ValueError, match="duplicate plans"):
        asyncio.run(repository.load_snapshot(user_id=USER_ID, generated_at=NOW))
