import asyncio
from datetime import UTC, date, datetime, timedelta
from uuid import UUID

import httpx

from app.api.deps.auth import Principal
from app.main import create_app
from app.models.deadline_plans import (
    DeadlinePlanIdentity,
    DeadlinePlanProgress,
    DeadlinePlanResponse,
    DeadlinePlansResponse,
    PreparationWorkloadDay,
    PreparationWorkloadResponse,
)
from app.services.deadline_plan_service import DeadlinePlanConflictError


USER_ID = "deadline-owner"
PLAN_ID = UUID("bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb")
REQUEST_ID = UUID("cccccccc-cccc-4ccc-8ccc-cccccccccccc")
NOW = datetime(2026, 7, 20, 8, tzinfo=UTC)


class Verifier:
    async def verify(self, token: str):
        return Principal(user_id=USER_ID) if token == "deadline-token" else None


class Service:
    def __init__(self, *, conflict: bool = False) -> None:
        self.calls = []
        self.conflict = conflict

    async def list_plans(self, *, user_id):
        self.calls.append(("list", user_id))
        response = _response()
        return DeadlinePlansResponse(
            contract_version="deadline-plan-v1",
            origin="authenticated_backend",
            plans=[response],
        )

    async def get_plan(self, *, user_id, plan_id):
        self.calls.append(("get", user_id, plan_id))
        return _response_envelope()

    async def get_workload(self, *, user_id):
        self.calls.append(("workload", user_id))
        return PreparationWorkloadResponse(
            contract_version="preparation-workload-v1",
            origin="authenticated_backend",
            generated_at=NOW,
            timezone="UTC",
            daily_preparation_budget_minutes=120,
            days=[
                PreparationWorkloadDay(
                    local_date=date(2026, 7, 20) + timedelta(days=offset),
                    reserved_preparation_minutes=0,
                    remaining_budget_minutes=120,
                    over_budget_minutes=0,
                    active_plan_count=0,
                    fixed_commitment_minutes=0,
                )
                for offset in range(7)
            ],
        )

    async def propose(self, *, user_id, request):
        self.calls.append(("proposal", user_id, request))
        if self.conflict:
            raise DeadlinePlanConflictError("stale revision")
        return _response_envelope()

    async def confirm(self, **kwargs):
        self.calls.append(("confirm", kwargs))
        return _response_envelope()

    async def complete(self, **kwargs):
        self.calls.append(("complete", kwargs))
        return _response_envelope()

    async def cancel(self, **kwargs):
        self.calls.append(("cancel", kwargs))
        return _response_envelope()


def _response():
    return {
        "plan": DeadlinePlanIdentity(
            id=PLAN_ID,
            status="cancelled",
            kind="exam",
            title="Mathematics",
            original_estimated_total_minutes=600,
            original_credited_prior_minutes=30,
            current_revision=0,
            latest_revision=1,
            created_at=NOW,
            updated_at=NOW,
            cancelled_at=NOW,
        ),
        "progress": DeadlinePlanProgress(
            estimated_total_minutes=600,
            credited_prior_minutes=30,
            tracked_focus_minutes=0,
            accounted_minutes=30,
            remaining_minutes=570,
            completion_suggested=False,
        ),
    }


def _response_envelope() -> DeadlinePlanResponse:
    return DeadlinePlanResponse(
        contract_version="deadline-plan-v1",
        origin="authenticated_backend",
        **_response(),
    )


def _proposal() -> dict[str, object]:
    return {
        "request_id": str(REQUEST_ID),
        "plan_id": str(PLAN_ID),
        "base_revision": 0,
        "kind": "exam",
        "title": "Mathematics",
        "deadline_at": "2026-08-01T12:00:00+02:00",
        "estimated_total_minutes": 600,
        "credited_prior_minutes": 30,
        "preferred_session_minutes": 50,
        "max_daily_minutes": 100,
        "planning_start_on": "2026-07-20",
        "buffer_days": 2,
        "source_kind": "manual",
        "use_calendar_availability": False,
    }


async def _request(method, path, *, json=None, authenticated=True, conflict=False):
    app = create_app()
    service = Service(conflict=conflict)
    app.state.token_verifier = Verifier()
    app.state.deadline_plan_service = service
    headers = {"Authorization": "Bearer deadline-token"} if authenticated else {}
    async with httpx.AsyncClient(
        transport=httpx.ASGITransport(app=app),
        base_url="http://test",
    ) as client:
        response = await client.request(method, path, headers=headers, json=json)
    return response, service


def test_deadline_routes_derive_owner_and_keep_exact_envelopes() -> None:
    response, service = asyncio.run(_request("GET", "/v1/deadline-plans"))
    assert response.status_code == 200
    assert response.json()["contract_version"] == "deadline-plan-v1"
    assert response.json()["plans"][0]["plan"]["id"] == str(PLAN_ID)
    assert service.calls == [("list", USER_ID)]

    detail, detail_service = asyncio.run(
        _request("GET", f"/v1/deadline-plans/{PLAN_ID}"),
    )
    assert detail.status_code == 200
    assert detail.json()["plan"]["status"] == "cancelled"
    assert detail_service.calls == [("get", USER_ID, PLAN_ID)]

    workload, workload_service = asyncio.run(
        _request("GET", "/v1/deadline-plans/workload"),
    )
    assert workload.status_code == 200
    assert workload.json()["contract_version"] == "preparation-workload-v1"
    assert len(workload.json()["days"]) == 7
    assert workload_service.calls == [("workload", USER_ID)]


def test_proposal_route_is_strict_and_maps_conflict() -> None:
    response, service = asyncio.run(
        _request("POST", "/v1/deadline-plans/proposals", json=_proposal()),
    )
    assert response.status_code == 200
    assert service.calls[0][0:2] == ("proposal", USER_ID)

    invalid = {**_proposal(), "user_id": USER_ID}
    rejected, rejected_service = asyncio.run(
        _request("POST", "/v1/deadline-plans/proposals", json=invalid),
    )
    assert rejected.status_code == 422
    assert rejected_service.calls == []

    numeric_timestamp = {**_proposal(), "deadline_at": 1_785_583_200}
    numeric_response, numeric_service = asyncio.run(
        _request(
            "POST",
            "/v1/deadline-plans/proposals",
            json=numeric_timestamp,
        ),
    )
    assert numeric_response.status_code == 422
    assert numeric_service.calls == []

    conflict, _ = asyncio.run(
        _request(
            "POST",
            "/v1/deadline-plans/proposals",
            json=_proposal(),
            conflict=True,
        ),
    )
    assert conflict.status_code == 409


def test_mutation_shape_and_authentication_are_enforced() -> None:
    mutation = {"request_id": str(REQUEST_ID), "expected_revision": 1}
    response, service = asyncio.run(
        _request("POST", f"/v1/deadline-plans/{PLAN_ID}/cancel", json=mutation),
    )
    assert response.status_code == 200
    assert service.calls[0][0] == "cancel"

    invalid, invalid_service = asyncio.run(
        _request(
            "POST",
            f"/v1/deadline-plans/{PLAN_ID}/confirm",
            json={**mutation, "expected_revision": "1"},
        ),
    )
    assert invalid.status_code == 422
    assert invalid_service.calls == []

    unauthenticated, _ = asyncio.run(
        _request("GET", "/v1/deadline-plans", authenticated=False),
    )
    assert unauthenticated.status_code == 401
