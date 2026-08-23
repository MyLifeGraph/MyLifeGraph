import asyncio
from datetime import UTC, date, datetime
from uuid import UUID

import httpx

from app.api.deps.auth import Principal, get_token_verifier
from app.api.deps.services import get_focus_service
from app.main import create_app
from app.models.focus import (
    FocusScheduleSource,
    FocusSessionResponse,
    FocusStartContextResponse,
    FocusStartTarget,
)
from app.services.focus_service import FocusConflictError, FocusNotFoundError
from tests.api_test_dependencies import override_dependency


USER_ID = "focus-owner"
SESSION_ID = UUID("f3000000-0000-4000-8000-000000000001")
BLOCK_ID = UUID("f3000000-0000-4000-8000-000000000002")
TASK_ID = UUID("f3000000-0000-4000-8000-000000000003")
NOW = datetime(2026, 8, 2, 10, tzinfo=UTC)


class Verifier:
    async def verify(self, token: str):
        return Principal(user_id=USER_ID) if token == "focus-token" else None


class Service:
    def __init__(self, *, error: Exception | None = None) -> None:
        self.error = error
        self.calls = []

    async def get_start_context(self, **kwargs):
        self.calls.append(("context", kwargs))
        if self.error:
            raise self.error
        return FocusStartContextResponse(
            contract_version="focus-start-context-v2",
            origin="authenticated_backend",
            source_kind="planner_task_block",
            block_id=BLOCK_ID,
            target=FocusStartTarget(kind="task", id=TASK_ID, title="Read"),
            original_starts_at=NOW,
            original_ends_at=NOW.replace(minute=30),
            recovery_minutes=10,
            remaining_minutes=20,
            source_state="partial",
            can_start=True,
            blocking_reason=None,
        )

    async def start(self, **kwargs):
        self.calls.append(("start", kwargs))
        if self.error:
            raise self.error
        return _session(status="active")

    async def finish(self, **kwargs):
        self.calls.append(("finish", kwargs))
        if self.error:
            raise self.error
        return _session(status=kwargs["terminal_status"])


def _session(*, status: str) -> FocusSessionResponse:
    terminal = status != "active"
    return FocusSessionResponse(
        contract_version="focus-session-v2",
        origin="authenticated_backend",
        replayed=False,
        id=SESSION_ID,
        status=status,
        started_at=NOW,
        ended_at=NOW.replace(minute=17) if terminal else None,
        planned_minutes=20,
        actual_minutes=17 if terminal else None,
        label="Read",
        task_id=TASK_ID,
        habit_id=None,
        entry_date=date(2026, 8, 2),
        recovery_minutes=10,
        updated_at=NOW.replace(minute=17) if terminal else NOW,
        schedule_source=FocusScheduleSource(
            source_kind="planner_task_block",
            block_id=BLOCK_ID,
            original_starts_at=NOW,
            original_ends_at=NOW.replace(minute=30),
            original_recovery_minutes=10,
        ),
    )


async def _request(method, path, *, json=None, error=None, authenticated=True):
    app = create_app()
    service = Service(error=error)
    override_dependency(app, get_token_verifier, Verifier())
    override_dependency(app, get_focus_service, service)
    headers = {"Authorization": "Bearer focus-token"} if authenticated else {}
    async with httpx.AsyncClient(
        transport=httpx.ASGITransport(app=app),
        base_url="http://test",
    ) as client:
        response = await client.request(method, path, headers=headers, json=json)
    return response, service


def test_focus_context_and_start_derive_the_authenticated_owner() -> None:
    response, service = asyncio.run(
        _request(
            "GET",
            f"/v1/focus/start-context/planner_task_block/{BLOCK_ID}",
        ),
    )
    assert response.status_code == 200
    assert response.json()["remaining_minutes"] == 20
    assert service.calls == [
        (
            "context",
            {
                "user_id": USER_ID,
                "source_kind": "planner_task_block",
                "block_id": BLOCK_ID,
            },
        ),
    ]

    started, start_service = asyncio.run(
        _request(
            "POST",
            "/v1/focus/sessions/start",
            json={
                "contract_version": "focus-start-v2",
                "request_id": str(SESSION_ID),
                "source_kind": "planner_task_block",
                "source_block_id": str(BLOCK_ID),
                "planned_minutes": 20,
            },
        ),
    )
    assert started.status_code == 200
    assert started.json()["schedule_source"]["block_id"] == str(BLOCK_ID)
    request = start_service.calls[0][1]["request"]
    assert request.request_id == SESSION_ID
    assert start_service.calls[0][1]["user_id"] == USER_ID


def test_focus_capability_is_authenticated_and_strict() -> None:
    response, service = asyncio.run(_request("GET", "/v1/focus/capabilities"))
    assert response.status_code == 200
    assert response.json() == {
        "contract_version": "focus-capabilities-v1",
        "origin": "authenticated_backend",
        "focus_session_v2": True,
    }
    assert service.calls == []

    unauthenticated, unauthenticated_service = asyncio.run(
        _request("GET", "/v1/focus/capabilities", authenticated=False),
    )
    assert unauthenticated.status_code == 401
    assert unauthenticated_service.calls == []


def test_focus_start_contract_is_strict_and_auth_required() -> None:
    payload = {
        "contract_version": "focus-start-v2",
        "request_id": str(SESSION_ID),
        "source_kind": "manual",
        "planned_minutes": 25,
        "recovery_minutes": 0,
        "target_kind": None,
        "target_id": None,
        "label": None,
        "unexpected": True,
    }
    invalid, service = asyncio.run(
        _request("POST", "/v1/focus/sessions/start", json=payload),
    )
    assert invalid.status_code == 422
    assert service.calls == []

    unauthenticated, unauthenticated_service = asyncio.run(
        _request(
            "GET",
            f"/v1/focus/start-context/planner_task_block/{BLOCK_ID}",
            authenticated=False,
        ),
    )
    assert unauthenticated.status_code == 401
    assert unauthenticated_service.calls == []


def test_focus_routes_map_owned_not_found_and_expected_conflicts() -> None:
    missing, _ = asyncio.run(
        _request(
            "GET",
            f"/v1/focus/start-context/planner_task_block/{BLOCK_ID}",
            error=FocusNotFoundError("source unavailable"),
        ),
    )
    assert missing.status_code == 404
    assert missing.json() == {"detail": "source unavailable"}

    conflict, _ = asyncio.run(
        _request(
            "POST",
            f"/v1/focus/sessions/{SESSION_ID}/finish",
            error=FocusConflictError("already ended differently"),
        ),
    )
    assert conflict.status_code == 409
    assert conflict.json() == {"detail": "already ended differently"}


def test_finish_and_abandon_send_only_server_derived_terminal_intent() -> None:
    for operation, terminal_status in (
        ("finish", "completed"),
        ("abandon", "abandoned"),
    ):
        response, service = asyncio.run(
            _request(
                "POST",
                f"/v1/focus/sessions/{SESSION_ID}/{operation}",
            ),
        )
        assert response.status_code == 200
        assert response.json()["status"] == terminal_status
        assert response.json()["actual_minutes"] == 17
        assert service.calls == [
            (
                "finish",
                {
                    "user_id": USER_ID,
                    "session_id": SESSION_ID,
                    "terminal_status": terminal_status,
                },
            ),
        ]
