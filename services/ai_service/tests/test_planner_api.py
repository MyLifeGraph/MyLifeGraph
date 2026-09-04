import asyncio
from datetime import UTC, date, datetime, timedelta
from types import SimpleNamespace
from unittest.mock import AsyncMock

import httpx
import pytest

from app.api.deps.auth import Principal, get_token_verifier
from app.api.deps.services import get_planner_service
from app.main import create_app
from app.models.planner import (
    PlannerDay,
    PlannerOverviewResponse,
    PlannerPreferencesResponse,
)
from app.services.planner_service import PlannerConflictError, PlannerService
from app.services.planner_errors import DeadlinePlanConflictError
from app.services.today_planner_read_context import TodayPlannerReadContextFactory
from tests.api_test_dependencies import override_dependency


class Verifier:
    async def verify(self, token: str):
        return Principal(user_id="planner-user") if token == "planner-token" else None


@pytest.mark.parametrize("shared_context", [False, True])
def test_deadline_read_conflict_uses_the_existing_planner_http_problem(
    shared_context: bool,
) -> None:
    detail = "Deadline plan count exceeds the V1 response bound."
    deadlines = SimpleNamespace(
        list_plans=AsyncMock(side_effect=DeadlinePlanConflictError(detail)),
    )
    repository = SimpleNamespace(
        load_overview_context=AsyncMock(return_value=None),
    )
    contexts = (
        TodayPlannerReadContextFactory(repository=repository, deadline_plans=deadlines)
        if shared_context
        else None
    )
    service = PlannerService(
        repository=repository,
        deadline_plans=deadlines,
        read_context_factory=contexts,
    )

    async def request():
        app = create_app()
        override_dependency(app, get_token_verifier, Verifier())
        override_dependency(app, get_planner_service, service)
        async with httpx.AsyncClient(
            transport=httpx.ASGITransport(app=app, raise_app_exceptions=False),
            base_url="http://test",
        ) as client:
            return await client.get(
                "/v1/planner/overview",
                headers={"Authorization": "Bearer planner-token"},
            )

    response = asyncio.run(request())
    assert response.status_code == 409
    assert response.json() == {"detail": detail}
    deadlines.list_plans.assert_awaited_once_with(user_id="planner-user")


class Service:
    def __init__(self) -> None:
        self.calls: list[tuple[str, str]] = []

    async def get_overview(self, *, user_id):
        self.calls.append(("overview", user_id))
        local_date = date(2026, 7, 21)
        return PlannerOverviewResponse(
            contract_version="planner-overview-v2",
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
            habits=[],
            task_targets=[],
            unscheduled_tasks=[],
            history=[],
        )

    async def update_preferences(self, *, user_id, request):
        self.calls.append(("preferences", user_id))
        raise PlannerConflictError("Planner preferences changed.")

    async def propose(self, *, user_id, request):
        self.calls.append(("proposal", user_id))
        raise PlannerConflictError("Preview conflict.")

    async def confirm(self, *, user_id, plan_id, request):
        self.calls.append(("confirm", user_id))
        raise PlannerConflictError("Preview conflict.")

    async def cancel(self, *, user_id, plan_id, request):
        self.calls.append(("cancel", user_id))
        raise PlannerConflictError("Preview conflict.")


async def _request(method, path, *, body=None, authenticated=True):
    app = create_app()
    service = Service()
    override_dependency(app, get_token_verifier, Verifier())
    override_dependency(app, get_planner_service, service)
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
    assert response.json()["contract_version"] == "planner-overview-v2"
    assert set(response.json()) == {
        "contract_version",
        "origin",
        "generated_at",
        "timezone",
        "local_date",
        "preferences",
        "action_plans",
        "commitments",
        "needs_attention",
        "days",
        "ongoing_preparation",
        "habits",
        "task_targets",
        "unscheduled_tasks",
        "history",
    }
    assert "unscheduled" not in response.json()
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


def test_planner_mutations_reject_revision_numbers_above_sql_bounds() -> None:
    proposal = {
        "request_id": "10000000-0000-4000-8000-000000000001",
        "plan_id": "20000000-0000-4000-8000-000000000001",
        "base_revision": 500,
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
    }
    cases = [
        ("/v1/planner/action-plans/proposals", proposal),
        (
            "/v1/planner/action-plans/20000000-0000-4000-8000-000000000001/confirm",
            {
                "request_id": "10000000-0000-4000-8000-000000000002",
                "expected_revision": 501,
            },
        ),
        (
            "/v1/planner/action-plans/20000000-0000-4000-8000-000000000001/cancel",
            {
                "request_id": "10000000-0000-4000-8000-000000000003",
                "expected_revision": 501,
            },
        ),
    ]

    for path, body in cases:
        response, service = asyncio.run(_request("POST", path, body=body))

        assert response.status_code == 422
        assert service.calls == []


def test_planner_mutations_accept_inclusive_sql_revision_boundaries() -> None:
    proposal = {
        "request_id": "10000000-0000-4000-8000-000000000011",
        "plan_id": "20000000-0000-4000-8000-000000000011",
        "base_revision": 499,
        "planning_start_on": "2026-07-21",
        "target": {
            "kind": "task",
            "operation": "create",
            "target_id": "30000000-0000-4000-8000-000000000011",
            "expected_updated_at": None,
            "title": "Prepare slides",
            "description": None,
            "priority": "medium",
            "estimated_minutes": 90,
            "deadline_at": "2026-07-24T12:00:00+00:00",
            "preferred_session_minutes": 30,
        },
    }
    cases = [
        (
            "/v1/planner/action-plans/proposals",
            proposal,
            ("proposal", "planner-user"),
        ),
        (
            "/v1/planner/action-plans/20000000-0000-4000-8000-000000000011/confirm",
            {
                "request_id": "10000000-0000-4000-8000-000000000012",
                "expected_revision": 500,
            },
            ("confirm", "planner-user"),
        ),
        (
            "/v1/planner/action-plans/20000000-0000-4000-8000-000000000011/cancel",
            {
                "request_id": "10000000-0000-4000-8000-000000000013",
                "expected_revision": 500,
            },
            ("cancel", "planner-user"),
        ),
    ]

    for path, body, expected_call in cases:
        response, service = asyncio.run(_request("POST", path, body=body))

        assert response.status_code == 409
        assert service.calls == [expected_call]


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
