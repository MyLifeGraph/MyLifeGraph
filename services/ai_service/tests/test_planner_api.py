import asyncio
from datetime import UTC, date, datetime, timedelta

import httpx

from app.api.deps.auth import Principal
from app.main import create_app
from app.models.planner import (
    PlannerDay,
    PlannerOverviewResponse,
    PlannerPreferencesResponse,
)
from app.services.planner_service import PlannerConflictError


class Verifier:
    async def verify(self, token: str):
        return Principal(user_id="planner-user") if token == "planner-token" else None


class Service:
    def __init__(self) -> None:
        self.calls: list[tuple[str, str]] = []

    async def get_overview(self, *, user_id):
        self.calls.append(("overview", user_id))
        local_date = date(2026, 7, 21)
        return PlannerOverviewResponse(
            contract_version="planner-v1",
            origin="authenticated_backend",
            generated_at=datetime(2026, 7, 21, 8, tzinfo=UTC),
            timezone="Europe/Berlin",
            local_date=local_date,
            preferences=PlannerPreferencesResponse(
                contract_version="planner-preferences-v1",
                origin="authenticated_backend",
                use_calendar_busy_time=False,
                updated_at=None,
                current_calendar_import_id=None,
                calendar_available=False,
            ),
            action_plans=[],
            commitments=[],
            needs_attention=[],
            days=[
                PlannerDay(
                    local_date=local_date + timedelta(days=offset),
                    items=[],
                )
                for offset in range(7)
            ],
            ongoing_preparation=[],
            unscheduled=[],
            history=[],
        )

    async def update_preferences(self, *, user_id, request):
        self.calls.append(("preferences", user_id))
        raise PlannerConflictError("Planner preferences changed.")

    async def propose(self, *, user_id, request):
        self.calls.append(("proposal", user_id))
        raise PlannerConflictError("Preview conflict.")


async def _request(method, path, *, body=None, authenticated=True):
    app = create_app()
    service = Service()
    app.state.token_verifier = Verifier()
    app.state.planner_service = service
    headers = {"Authorization": "Bearer planner-token"} if authenticated else {}
    async with httpx.AsyncClient(
        transport=httpx.ASGITransport(app=app),
        base_url="http://test",
    ) as client:
        response = await client.request(method, path, headers=headers, json=body)
    return response, service


def test_planner_overview_is_bearer_scoped_read_only_and_exact() -> None:
    response, service = asyncio.run(_request("GET", "/v1/planner/overview"))

    assert response.status_code == 200
    assert response.json()["contract_version"] == "planner-v1"
    assert len(response.json()["days"]) == 7
    assert service.calls == [("overview", "planner-user")]

    blocked, blocked_service = asyncio.run(
        _request("GET", "/v1/planner/overview", authenticated=False),
    )
    assert blocked.status_code == 401
    assert blocked_service.calls == []


def test_planner_contract_rejects_unknown_fields_before_service_call() -> None:
    response, service = asyncio.run(
        _request(
            "POST",
            "/v1/planner/action-plans/proposals",
            body={"unexpected": True},
        ),
    )

    assert response.status_code == 422
    assert service.calls == []


def test_planner_contract_accepts_canonical_json_transport_values() -> None:
    response, service = asyncio.run(
        _request(
            "POST",
            "/v1/planner/action-plans/proposals",
            body={
                "request_id": "10000000-0000-4000-8000-000000000001",
                "plan_id": "20000000-0000-4000-8000-000000000001",
                "base_revision": 0,
                "planning_start_on": "2026-07-21",
                "target": {
                    "kind": "task",
                    "operation": "create",
                    "target_id": "30000000-0000-4000-8000-000000000001",
                    "expected_updated_at": None,
                    "title": "Prepare slides",
                    "description": None,
                    "priority": "medium",
                    "estimated_minutes": 90,
                    "deadline_at": "2026-07-24T12:00:00+00:00",
                    "preferred_session_minutes": 30,
                },
            },
        ),
    )

    assert response.status_code == 409
    assert service.calls == [("proposal", "planner-user")]


def test_planner_conflicts_are_public_409_without_mutation_fallback() -> None:
    response, service = asyncio.run(
        _request(
            "PATCH",
            "/v1/planner/preferences",
            body={
                "request_id": "10000000-0000-4000-8000-000000000001",
                "expected_updated_at": None,
                "use_calendar_busy_time": True,
            },
        ),
    )

    assert response.status_code == 409
    assert response.json() == {"detail": "Planner preferences changed."}
    assert service.calls == [("preferences", "planner-user")]
