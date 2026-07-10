import asyncio
from copy import deepcopy
from uuid import UUID

import httpx
import pytest

from app.repositories.intake_repository import (
    AtomicSetupApply,
    IntakeApplyConflict,
    SetupMaterialization,
    SetupOwnershipConflict,
    SupabaseIntakeRepository,
)


USER_ID = "user-123"
REQUEST_ID = UUID("00000000-0000-4000-8000-000000000001")


class FakeRestClient:
    def __init__(self) -> None:
        self.intakes: list[dict] = []
        self.select_calls: list[tuple[str, dict]] = []
        self.insert_calls: list[tuple[str, list[dict]]] = []
        self.rpc_calls: list[tuple[str, dict]] = []
        self.rpc_result: object = {
            "intake_response_id": "00000000-0000-4000-8000-000000000002",
            "request_id": str(REQUEST_ID),
            "base_revision": 1,
            "revision": 2,
            "state": "applied",
            "snapshot_id": "00000000-0000-4000-8000-000000000003",
        }
        self.rpc_error: httpx.HTTPStatusError | None = None

    async def select(self, table: str, *, params: dict):
        self.select_calls.append((table, deepcopy(params)))
        rows = deepcopy(self.intakes)
        for key, expression in params.items():
            if key in {"select", "order", "limit"}:
                continue
            if isinstance(expression, str) and expression.startswith("eq."):
                expected = expression.removeprefix("eq.")
                rows = [row for row in rows if str(row.get(key)) == expected]
        if str(params.get("order", "")).startswith("revision.desc"):
            rows.sort(key=lambda row: row.get("revision", 0), reverse=True)
        return rows[: int(params.get("limit", len(rows)))]

    async def insert(self, table: str, *, rows: list[dict]):
        self.insert_calls.append((table, deepcopy(rows)))
        self.intakes.extend(deepcopy(rows))
        return deepcopy(rows)

    async def rpc(self, function: str, *, params: dict):
        self.rpc_calls.append((function, deepcopy(params)))
        if self.rpc_error is not None:
            raise self.rpc_error
        return deepcopy(self.rpc_result)


def run(coro):
    return asyncio.run(coro)


def atomic_apply() -> AtomicSetupApply:
    metadata = {
        "source": "intake-v1",
        "managed_by": "setup",
        "setup_item_id": "10000000-0000-4000-8000-000000000001",
        "revision": 2,
        "setup_state": "active",
    }
    return AtomicSetupApply(
        completed_at="2026-07-10T12:00:00+00:00",
        notification_preferences={
            "focus_prompts_enabled": False,
            "recovery_prompts_enabled": False,
            "weekly_summary_enabled": False,
            "quiet_hours_start": None,
            "quiet_hours_end": None,
        },
        materialization=SetupMaterialization(
            goals=[
                {
                    "id": "20000000-0000-4000-8000-000000000001",
                    "title": "Goal",
                    "status": "active",
                    "metadata": metadata,
                },
            ],
            habits=[],
            schedule_items=[],
            memory_entries=[],
        ),
        snapshot={"summary": {}, "signals": {}, "metadata": {}},
        intake_metadata={"source": "onboarding"},
    )


def test_atomic_apply_uses_one_rpc_for_the_complete_projection() -> None:
    client = FakeRestClient()
    repository = SupabaseIntakeRepository(client)
    apply = atomic_apply()

    result = run(
        repository.apply_setup_revision(
            user_id=USER_ID,
            intake_response_id="00000000-0000-4000-8000-000000000002",
            request_id=REQUEST_ID,
            base_revision=1,
            revision=2,
            apply=apply,
        ),
    )

    assert result["state"] == "applied"
    assert len(client.rpc_calls) == 1
    assert client.insert_calls == []
    function, params = client.rpc_calls[0]
    assert function == "apply_intake_v1_setup_revision"
    assert params == {
        "p_user_id": USER_ID,
        "p_intake_response_id": "00000000-0000-4000-8000-000000000002",
        "p_request_id": str(REQUEST_ID),
        "p_base_revision": 1,
        "p_revision": 2,
        "p_completed_at": apply.completed_at,
        "p_notification_preferences": apply.notification_preferences,
        "p_goals": apply.materialization.goals,
        "p_habits": [],
        "p_schedule_items": [],
        "p_memory_entries": [],
        "p_snapshot": apply.snapshot,
        "p_intake_metadata": apply.intake_metadata,
    }
    assert "p_profile_values" not in params


def test_latest_and_latest_applied_reads_are_version_and_user_scoped() -> None:
    client = FakeRestClient()
    client.intakes = [
        {
            "id": "applied",
            "user_id": USER_ID,
            "version": "intake-v1",
            "request_id": str(REQUEST_ID),
            "revision": 1,
            "state": "applied",
        },
        {
            "id": "pending",
            "user_id": USER_ID,
            "version": "intake-v1",
            "request_id": "00000000-0000-4000-8000-000000000004",
            "revision": 2,
            "state": "pending",
        },
        {
            "id": "other-version",
            "user_id": USER_ID,
            "version": "intake-v2",
            "request_id": str(REQUEST_ID),
            "revision": 99,
            "state": "applied",
        },
        {
            "id": "other-user",
            "user_id": "other",
            "version": "intake-v1",
            "request_id": str(REQUEST_ID),
            "revision": 100,
            "state": "applied",
        },
    ]
    repository = SupabaseIntakeRepository(client)

    latest = run(repository.load_latest_intake(user_id=USER_ID))
    latest_applied = run(repository.load_latest_applied_intake(user_id=USER_ID))
    by_request = run(
        repository.load_intake_by_request(
            user_id=USER_ID,
            request_id=REQUEST_ID,
        ),
    )

    assert latest["id"] == "pending"
    assert latest_applied["id"] == "applied"
    assert by_request["id"] == "applied"
    _, applied_params = client.select_calls[1]
    assert applied_params["state"] == "eq.applied"
    assert applied_params["version"] == "eq.intake-v1"
    assert applied_params["user_id"] == f"eq.{USER_ID}"


@pytest.mark.parametrize(
    ("code", "message", "expected"),
    [
        ("40001", "revision is no longer current", IntakeApplyConflict),
        (
            "23505",
            "Setup goal id collides with a non-Setup row",
            SetupOwnershipConflict,
        ),
    ],
)
def test_atomic_rpc_maps_serialization_and_ownership_errors(
    code: str,
    message: str,
    expected: type[RuntimeError],
) -> None:
    client = FakeRestClient()
    request = httpx.Request("POST", "http://local/rest/v1/rpc/apply")
    response = httpx.Response(
        409,
        request=request,
        json={"code": code, "message": message},
    )
    client.rpc_error = httpx.HTTPStatusError(
        message,
        request=request,
        response=response,
    )

    with pytest.raises(expected, match=message):
        run(
            SupabaseIntakeRepository(client).apply_setup_revision(
                user_id=USER_ID,
                intake_response_id="00000000-0000-4000-8000-000000000002",
                request_id=REQUEST_ID,
                base_revision=1,
                revision=2,
                apply=atomic_apply(),
            ),
        )


def test_atomic_rpc_rejects_non_object_response() -> None:
    client = FakeRestClient()
    client.rpc_result = []

    with pytest.raises(ValueError, match="non-object"):
        run(
            SupabaseIntakeRepository(client).apply_setup_revision(
                user_id=USER_ID,
                intake_response_id="00000000-0000-4000-8000-000000000002",
                request_id=REQUEST_ID,
                base_revision=1,
                revision=2,
                apply=atomic_apply(),
            ),
        )
