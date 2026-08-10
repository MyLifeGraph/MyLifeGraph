import asyncio
import json
from datetime import UTC, datetime
from uuid import UUID

import httpx

from app.api.deps.auth import Principal, get_token_verifier
from app.api.deps.services import get_assignment_series_service
from app.main import create_app
from app.models.assignment_series import (
    AssignmentSeriesListResponse,
    AssignmentSeriesResponse,
)
from app.services.planner_errors import DeadlinePlanConflictError
from tests.api_test_dependencies import override_dependency


USER_ID = "assignment-owner"
SERIES_ID = UUID("22222222-2222-4222-8222-222222222222")
REQUEST_ID = UUID("11111111-1111-4111-8111-111111111111")
NOW = datetime(2026, 8, 10, 8, tzinfo=UTC)


class Verifier:
    async def verify(self, token: str):
        return Principal(user_id=USER_ID) if token == "assignment-token" else None


class Service:
    def __init__(self, *, conflict: bool = False) -> None:
        self.calls: list[tuple] = []
        self.conflict = conflict

    async def list_series(self, *, user_id):
        self.calls.append(("list", user_id))
        return AssignmentSeriesListResponse.model_validate_json(
            json.dumps(
                {
                    "contract_version": "assignment-series-v1",
                    "origin": "authenticated_backend",
                    "assignment_series": [_detail()],
                },
            ),
        )

    async def get_series(self, *, user_id, series_id):
        self.calls.append(("get", user_id, series_id))
        return _response_model()

    async def propose(self, *, user_id, request):
        self.calls.append(("proposal", user_id, request))
        if self.conflict:
            raise DeadlinePlanConflictError("series changed")
        return _response_model()

    async def confirm(self, *, user_id, series_id, request):
        self.calls.append(("confirm", user_id, series_id, request))
        return _response_model(active=True)

    async def cancel_future(self, *, user_id, series_id, request):
        self.calls.append(("cancel-future", user_id, series_id, request))
        return _response_model(cancelled=True)


def _revision(*, active: bool = False):
    return {
        "series_id": str(SERIES_ID),
        "revision": 1,
        "base_revision": 0,
        "state": "active" if active else "proposed",
        "title": "Weekly algorithms sheet",
        "next_deadline_at": "2026-08-17T15:00:00Z",
        "remaining_occurrences": 2,
        "estimated_total_minutes": 90,
        "preferred_session_minutes": 30,
        "max_daily_minutes": 60,
        "buffer_days": 1,
        "use_calendar_availability": False,
        "timezone": "Europe/Berlin",
        "planned_minutes": 180,
        "unscheduled_minutes": 0,
        "created_at": NOW.isoformat(),
        **({"activated_at": NOW.isoformat()} if active else {}),
        "occurrences": [
            {
                "position": position,
                "action": "upsert",
                "plan_id": f"40000000-0000-4000-8000-{position:012d}",
                "plan_revision": 1,
                "deadline_at": f"2026-08-{10 + position * 7:02d}T15:00:00Z",
            }
            for position in (1, 2)
        ],
    }


def _detail(*, active: bool = False, cancelled: bool = False):
    identity = {
        "id": str(SERIES_ID),
        "status": "cancelled" if cancelled else "active" if active else "draft",
        "title": "Weekly algorithms sheet",
        "current_revision": 1 if active or cancelled else 0,
        "latest_revision": 1,
        "created_at": NOW.isoformat(),
        "updated_at": NOW.isoformat(),
    }
    if active or cancelled:
        identity["first_activated_at"] = NOW.isoformat()
    if cancelled:
        identity["cancelled_at"] = NOW.isoformat()
    detail = {"series": identity}
    if active or cancelled:
        detail["active_revision"] = _revision(active=True)
    else:
        detail["pending_revision"] = _revision()
    return detail


def _response(*, active: bool = False, cancelled: bool = False):
    return {
        "contract_version": "assignment-series-v1",
        "origin": "authenticated_backend",
        "assignment_series": _detail(active=active, cancelled=cancelled),
    }


def _response_model(*, active: bool = False, cancelled: bool = False):
    return AssignmentSeriesResponse.model_validate_json(
        json.dumps(_response(active=active, cancelled=cancelled)),
    )


def _proposal():
    return {
        "contract_version": "assignment-series-v1",
        "request_id": str(REQUEST_ID),
        "series_id": str(SERIES_ID),
        "base_revision": 0,
        "title": "Weekly algorithms sheet",
        "next_deadline_at": "2026-08-17T17:00:00+02:00",
        "remaining_occurrences": 2,
        "estimated_total_minutes": 90,
        "preferred_session_minutes": 30,
        "max_daily_minutes": 60,
        "buffer_days": 1,
        "use_calendar_availability": False,
    }


async def _request(method, path, *, json=None, authenticated=True, conflict=False):
    app = create_app()
    service = Service(conflict=conflict)
    override_dependency(app, get_token_verifier, Verifier())
    override_dependency(app, get_assignment_series_service, service)
    headers = {"Authorization": "Bearer assignment-token"} if authenticated else {}
    async with httpx.AsyncClient(
        transport=httpx.ASGITransport(app=app),
        base_url="http://test",
    ) as client:
        response = await client.request(method, path, headers=headers, json=json)
    return response, service


def test_assignment_series_routes_derive_owner_and_do_not_collide() -> None:
    listed, list_service = asyncio.run(
        _request("GET", "/v1/deadline-plans/assignment-series"),
    )
    assert listed.status_code == 200
    assert list_service.calls == [("list", USER_ID)]

    proposed, proposal_service = asyncio.run(
        _request(
            "POST",
            "/v1/deadline-plans/assignment-series/proposals",
            json=_proposal(),
        ),
    )
    assert proposed.status_code == 200
    assert proposal_service.calls[0][0:2] == ("proposal", USER_ID)

    detail, detail_service = asyncio.run(
        _request("GET", f"/v1/deadline-plans/assignment-series/{SERIES_ID}"),
    )
    assert detail.status_code == 200
    assert detail_service.calls == [("get", USER_ID, SERIES_ID)]


def test_series_mutations_are_strict_and_map_conflicts() -> None:
    mutation = {
        "contract_version": "assignment-series-v1",
        "request_id": str(REQUEST_ID),
        "expected_revision": 1,
    }
    confirmed, service = asyncio.run(
        _request(
            "POST",
            f"/v1/deadline-plans/assignment-series/{SERIES_ID}/confirm",
            json=mutation,
        ),
    )
    assert confirmed.status_code == 200
    assert service.calls[0][0:3] == ("confirm", USER_ID, SERIES_ID)

    cancelled, cancel_service = asyncio.run(
        _request(
            "POST",
            f"/v1/deadline-plans/assignment-series/{SERIES_ID}/cancel-future",
            json=mutation,
        ),
    )
    assert cancelled.status_code == 200
    assert cancel_service.calls[0][0:3] == ("cancel-future", USER_ID, SERIES_ID)

    invalid = {**mutation, "expected_revision": "1"}
    rejected, rejected_service = asyncio.run(
        _request(
            "POST",
            f"/v1/deadline-plans/assignment-series/{SERIES_ID}/confirm",
            json=invalid,
        ),
    )
    assert rejected.status_code == 422
    assert rejected_service.calls == []

    conflict, _ = asyncio.run(
        _request(
            "POST",
            "/v1/deadline-plans/assignment-series/proposals",
            json=_proposal(),
            conflict=True,
        ),
    )
    assert conflict.status_code == 409


def test_assignment_series_requires_authentication() -> None:
    response, service = asyncio.run(
        _request(
            "GET",
            "/v1/deadline-plans/assignment-series",
            authenticated=False,
        ),
    )
    assert response.status_code == 401
    assert service.calls == []
