import asyncio
import json
from datetime import UTC, datetime
from uuid import UUID

import httpx

from app.api.deps.auth import Principal
from app.main import create_app
from app.models.coach import (
    CoachCapabilitiesResponse,
    CoachHistoryDeleteResponse,
    CoachHistoryResponse,
    CoachLimits,
    CoachMemorySelectionResponse,
    CoachResponse,
)
USER_ID = "coach-owner"
REQUEST_ID = UUID("11111111-1111-4111-8111-111111111111")
MEMORY_ID = UUID("22222222-2222-4222-8222-222222222222")
NOW = datetime(2026, 7, 13, 8, tzinfo=UTC)


class Verifier:
    async def verify(self, token: str):
        return Principal(user_id=USER_ID) if token == "valid-coach-token" else None


class Service:
    def __init__(self) -> None:
        self.calls = []

    async def capabilities(self, *, user_id: str):
        self.calls.append(("capabilities", user_id))
        return CoachCapabilitiesResponse(
            contract_version="coach-capabilities-v1",
            state="ready",
            provider="fake",
            provider_mode="deterministic_test_only",
            model_requested=None,
            model_source="not_applicable",
            reason_code="ready",
            limits=CoachLimits(
                message_codepoints=2_000,
                context_bytes=32_768,
                reply_codepoints=4_000,
                timeout_seconds=45,
                requests_per_local_day=20,
                remaining_requests=20,
            ),
        )

    async def respond(self, *, user_id: str, request):
        self.calls.append(("respond", user_id, request))
        return _response(request.request_id)

    async def history(self, *, user_id: str):
        self.calls.append(("history", user_id))
        return CoachHistoryResponse(contract_version="coach-history-v1", turns=[])

    async def delete_history(self, *, user_id: str):
        self.calls.append(("delete_history", user_id))
        return CoachHistoryDeleteResponse(
            contract_version="coach-history-v1",
            deleted=True,
        )

    async def memories(self, *, user_id: str):
        self.calls.append(("memories", user_id))
        return _memories()

    async def set_memory_selection(self, *, user_id: str, memory_id, selected: bool):
        self.calls.append(("selection", user_id, memory_id, selected))
        return _memories()


async def _request(
    method: str,
    path: str,
    *,
    json_body=None,
    content=None,
    authenticated=True,
):
    app = create_app()
    service = Service()
    app.state.token_verifier = Verifier()
    app.state.coach_service = service
    headers = (
        {"Authorization": "Bearer valid-coach-token"} if authenticated else {}
    )
    request_body = (
        {"content": content}
        if content is not None
        else {"json": json_body}
    )
    if content is not None:
        headers["Content-Type"] = "application/json"
    async with httpx.AsyncClient(
        transport=httpx.ASGITransport(app=app),
        base_url="http://test",
    ) as client:
        response = await client.request(
            method,
            path,
            headers=headers,
            **request_body,
        )
    return response, service


def test_capabilities_and_respond_derive_owner() -> None:
    capability, capability_service = asyncio.run(
        _request("GET", "/v1/coach/capabilities"),
    )
    assert capability.status_code == 200
    assert capability.json()["limits"]["remaining_requests"] == 20
    assert capability_service.calls == [("capabilities", USER_ID)]

    response, service = asyncio.run(
        _request(
            "POST",
            "/v1/coach/respond",
            json_body={
                "contract_version": "coach-request-v1",
                "request_id": str(REQUEST_ID),
                "message": "  Help me plan.  ",
                "context_scope": "today",
            },
        ),
    )
    assert response.status_code == 200
    assert response.json()["request_id"] == str(REQUEST_ID)
    assert service.calls[0][0:2] == ("respond", USER_ID)
    assert service.calls[0][2].message == "Help me plan."


def test_respond_validation_always_uses_exact_error_detail() -> None:
    base = {
        "contract_version": "coach-request-v1",
        "request_id": str(REQUEST_ID),
        "message": "Help me plan.",
        "context_scope": "today",
    }
    expected = {
        "detail": {
            "code": "invalid_request",
            "message": "The Coach request body does not match its strict contract.",
            "retryable": False,
        },
    }
    for invalid in [
        {**base, "user_id": "attacker"},
        {**base, "unknown": True},
        {**base, "message": None},
        {**base, "message": 9},
    ]:
        response, service = asyncio.run(
            _request("POST", "/v1/coach/respond", json_body=invalid),
        )
        assert response.status_code == 422
        assert response.json() == expected
        assert service.calls == []


def test_respond_rejects_raw_body_over_32_kib_before_model_validation() -> None:
    payload = {
        "contract_version": "coach-request-v1",
        "request_id": str(REQUEST_ID),
        "message": "Help me plan.",
        "context_scope": "today",
    }
    encoded = json.dumps(payload, separators=(",", ":")).encode()
    oversized = encoded + b" " * ((32 * 1024) - len(encoded) + 1)

    response, service = asyncio.run(
        _request("POST", "/v1/coach/respond", content=oversized),
    )

    assert response.status_code == 422
    assert response.json() == {
        "detail": {
            "code": "invalid_request",
            "message": "The Coach request body does not match its strict contract.",
            "retryable": False,
        },
    }
    assert service.calls == []


def test_memory_selection_is_strict_and_delete_uses_no_body() -> None:
    selected, selected_service = asyncio.run(
        _request(
            "POST",
            f"/v1/coach/memories/{MEMORY_ID}/selection",
            json_body={"selected": True},
        ),
    )
    assert selected.status_code == 200
    assert selected_service.calls == [("selection", USER_ID, MEMORY_ID, True)]

    coerced, coerced_service = asyncio.run(
        _request(
            "POST",
            f"/v1/coach/memories/{MEMORY_ID}/selection",
            json_body={"selected": 1},
        ),
    )
    assert coerced.status_code == 422
    assert coerced.json()["detail"]["code"] == "invalid_request"
    assert coerced_service.calls == []

    deleted, deleted_service = asyncio.run(
        _request("DELETE", f"/v1/coach/memories/{MEMORY_ID}/selection"),
    )
    assert deleted.status_code == 200
    assert deleted_service.calls == [("selection", USER_ID, MEMORY_ID, False)]


def test_body_free_deletes_reject_the_first_nonempty_chunk() -> None:
    oversized = b"x" * (64 * 1024)
    for path in [
        "/v1/coach/history",
        f"/v1/coach/memories/{MEMORY_ID}/selection",
    ]:
        response, service = asyncio.run(
            _request("DELETE", path, content=oversized),
        )

        assert response.status_code == 422
        assert response.json() == {
            "detail": {
                "code": "invalid_request",
                "message": "This Coach operation does not accept a request body.",
                "retryable": False,
            },
        }
        assert service.calls == []


def test_coach_routes_require_authentication_before_service_calls() -> None:
    response, service = asyncio.run(
        _request("GET", "/v1/coach/history", authenticated=False),
    )
    assert response.status_code == 401
    assert service.calls == []


def _response(request_id: UUID) -> CoachResponse:
    return CoachResponse(
        contract_version="coach-response-v1",
        request_id=request_id,
        reply="Protect one small next step.",
        uncertainty={"level": "medium", "reason": "Bounded current context."},
        staged_suggestion={
            "title": "Protect one small next step",
            "rationale": "Review whether it fits today's capacity.",
        },
        safety={"classification": "normal"},
        used_context=[],
        provenance={
            "source": "model",
            "provider": "fake",
            "provider_mode": "deterministic_test_only",
            "model_requested": None,
            "model_reported": None,
            "model_source": "not_applicable",
            "prompt_version": "controlled-coach-prompt-v1",
            "context_version": "coach-context-v1",
            "generated_at": NOW,
            "provider_called": True,
        },
    )


def _memories() -> CoachMemorySelectionResponse:
    return CoachMemorySelectionResponse(
        contract_version="coach-memory-selection-v1",
        max_selected=8,
        available_count=0,
        memories=[],
    )
