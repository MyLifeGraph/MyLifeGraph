import asyncio
from datetime import UTC, datetime
from uuid import UUID

import httpx

from app.api.deps.auth import Principal, get_token_verifier
from app.api.deps.services import get_learning_service
from app.main import create_app
from app.models.learning import (
    FocusReflectionHistoryClearResponse,
    LearningPreferencesState,
    LearningPreferencesUpdateResponse,
)
from app.repositories.learning_repository import (
    LearningPersistenceConflict,
    LearningPersistenceError,
    LearningPersistenceNotFound,
    LearningPersistenceOutcomeUnknown,
)
from app.services.learning_service import LearningContractError
from tests.api_test_dependencies import override_dependency


USER_ID = "learning-owner"
REQUEST_ID = "a2000000-0000-4000-8000-000000000001"
NOW = datetime(2026, 7, 26, 8, tzinfo=UTC)


class Verifier:
    async def verify(self, token: str):
        if token != "valid-learning-token":
            return None
        return Principal(user_id=USER_ID, authenticated_at=NOW)


class Service:
    def __init__(self) -> None:
        self.calls: list[tuple] = []
        self.error: Exception | None = None

    async def get_preferences(self, *, user_id: str):
        self.calls.append(("get", user_id))
        if self.error is not None:
            raise self.error
        return LearningPreferencesState(
            contract_version="learning-preferences-v1",
            revision=2,
            focus_reflection_prompt_enabled=True,
            personal_pattern_analysis_enabled=True,
            learned_focus_planning_enabled=False,
            updated_at=NOW,
        )

    async def update_preferences(self, *, user_id: str, request):
        self.calls.append(("update", user_id, request))
        if self.error is not None:
            raise self.error
        return LearningPreferencesUpdateResponse(
            contract_version="learning-preferences-v1",
            revision=request.expected_revision + 1,
            focus_reflection_prompt_enabled=(request.focus_reflection_prompt_enabled),
            personal_pattern_analysis_enabled=(
                request.personal_pattern_analysis_enabled
            ),
            learned_focus_planning_enabled=(request.learned_focus_planning_enabled),
            updated_at=NOW,
            replayed=False,
        )

    async def clear_focus_reflections(self, *, user_id: str, request):
        self.calls.append(("clear", user_id, request))
        if self.error is not None:
            raise self.error
        return FocusReflectionHistoryClearResponse(
            contract_version="focus-reflection-v1",
            revision=request.expected_revision,
            deleted_count=4,
            cleared_at=NOW,
            replayed=False,
        )


async def _request(
    method: str,
    path: str,
    *,
    body=None,
    authenticated: bool = True,
    service: Service | None = None,
):
    app = create_app()
    learning_service = service or Service()
    override_dependency(app, get_token_verifier, Verifier())
    override_dependency(app, get_learning_service, learning_service)
    headers = {"Authorization": "Bearer valid-learning-token"} if authenticated else {}
    async with httpx.AsyncClient(
        transport=httpx.ASGITransport(app=app),
        base_url="http://test",
    ) as client:
        response = await client.request(
            method,
            path,
            headers=headers,
            json=body,
        )
    return response, learning_service


def test_preferences_get_is_authenticated_and_owner_derived() -> None:
    response, service = asyncio.run(
        _request("GET", "/v1/learning/preferences"),
    )
    assert response.status_code == 200
    assert response.json() == {
        "contract_version": "learning-preferences-v1",
        "revision": 2,
        "focus_reflection_prompt_enabled": True,
        "personal_pattern_analysis_enabled": True,
        "learned_focus_planning_enabled": False,
        "updated_at": "2026-07-26T08:00:00Z",
    }
    assert service.calls == [("get", USER_ID)]

    unauthenticated, unauthenticated_service = asyncio.run(
        _request(
            "GET",
            "/v1/learning/preferences",
            authenticated=False,
        ),
    )
    assert unauthenticated.status_code == 401
    assert unauthenticated_service.calls == []


def test_preferences_patch_requires_complete_consistent_state() -> None:
    body = {
        "request_id": REQUEST_ID,
        "expected_revision": 2,
        "focus_reflection_prompt_enabled": False,
        "personal_pattern_analysis_enabled": True,
        "learned_focus_planning_enabled": True,
    }
    response, service = asyncio.run(
        _request("PATCH", "/v1/learning/preferences", body=body),
    )
    assert response.status_code == 200
    assert response.json()["revision"] == 3
    assert response.json()["learned_focus_planning_enabled"] is True
    call = service.calls[0]
    assert call[0:2] == ("update", USER_ID)
    assert call[2].request_id == UUID(REQUEST_ID)

    for invalid in (
        {**body, "user_id": "another-owner"},
        {**body, "personal_pattern_analysis_enabled": False},
        {key: value for key, value in body.items() if key != "expected_revision"},
        {**body, "expected_revision": True},
    ):
        invalid_response, invalid_service = asyncio.run(
            _request("PATCH", "/v1/learning/preferences", body=invalid),
        )
        assert invalid_response.status_code == 422
        assert invalid_service.calls == []


def test_clear_requires_exact_confirmation_and_expected_revision() -> None:
    body = {
        "request_id": REQUEST_ID,
        "expected_revision": 2,
        "confirmation": "CLEAR",
    }
    response, service = asyncio.run(
        _request(
            "POST",
            "/v1/learning/focus-reflections/clear",
            body=body,
        ),
    )
    assert response.status_code == 200
    assert response.json()["deleted_count"] == 4
    assert service.calls[0][0:2] == ("clear", USER_ID)

    invalid, invalid_service = asyncio.run(
        _request(
            "POST",
            "/v1/learning/focus-reflections/clear",
            body={**body, "confirmation": "clear"},
        ),
    )
    assert invalid.status_code == 422
    assert invalid_service.calls == []


def test_learning_routes_map_conflict_ambiguous_and_safe_failures() -> None:
    patch_body = {
        "request_id": REQUEST_ID,
        "expected_revision": 2,
        "focus_reflection_prompt_enabled": True,
        "personal_pattern_analysis_enabled": True,
        "learned_focus_planning_enabled": False,
    }
    cases = (
        (LearningPersistenceConflict("safe conflict"), 409),
        (LearningPersistenceNotFound("private owner"), 404),
        (LearningPersistenceOutcomeUnknown("private outcome"), 502),
        (LearningContractError("private contract"), 502),
        (LearningPersistenceError("private upstream"), 503),
    )
    for error, expected_status in cases:
        service = Service()
        service.error = error
        response, _ = asyncio.run(
            _request(
                "PATCH",
                "/v1/learning/preferences",
                body=patch_body,
                service=service,
            ),
        )
        assert response.status_code == expected_status
        assert "private" not in response.text
