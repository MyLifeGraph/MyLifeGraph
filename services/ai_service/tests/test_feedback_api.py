import asyncio
from datetime import UTC, datetime
from uuid import UUID

import httpx

from app.api.deps.auth import Principal
from app.models.feedback import (
    DecisionFeedback,
    DecisionFeedbackDeleteResponse,
    DecisionFeedbackListResponse,
    DecisionFeedbackResponse,
)
from app.main import create_app


FEEDBACK_ID = UUID("33333333-3333-4333-8333-333333333333")


class Verifier:
    async def verify(self, token):
        return Principal(user_id="feedback-user") if token == "valid" else None


class Service:
    def __init__(self):
        self.calls = []

    async def create(self, *, user_id, request):
        self.calls.append(("create", user_id, request))
        return DecisionFeedbackResponse(
            contract_version="decision-feedback-v1",
            feedback=_feedback(),
        )

    async def list_recent(self, *, user_id):
        self.calls.append(("list", user_id))
        return DecisionFeedbackListResponse(
            contract_version="decision-feedback-v1",
            feedback=[_feedback()],
        )

    async def delete(self, *, user_id, feedback_id):
        self.calls.append(("delete", user_id, feedback_id))
        return DecisionFeedbackDeleteResponse(
            contract_version="decision-feedback-v1",
            deleted_id=feedback_id,
        )


def _feedback():
    return DecisionFeedback(
        id=FEEDBACK_ID,
        request_id=UUID("22222222-2222-4222-8222-222222222222"),
        briefing_id=UUID("11111111-1111-4111-8111-111111111111"),
        recommendation_id=None,
        action_id="open_task:target",
        action_kind="task",
        feedback_type="later",
        context_mode="steady",
        estimated_minutes=30,
        rule_key="open_task",
        created_at=datetime(2026, 7, 12, 8, tzinfo=UTC),
    )


async def _request(method, path, *, json=None, authenticated=True):
    app = create_app()
    service = Service()
    app.state.token_verifier = Verifier()
    app.state.feedback_service = service
    transport = httpx.ASGITransport(app=app)
    headers = {"Authorization": "Bearer valid"} if authenticated else {}
    async with httpx.AsyncClient(transport=transport, base_url="http://test") as client:
        response = await client.request(method, path, headers=headers, json=json)
    return response, service


def test_feedback_routes_derive_owner_and_accept_exact_contract() -> None:
    response, service = asyncio.run(
        _request(
            "POST",
            "/v1/feedback",
            json={
                "request_id": "22222222-2222-4222-8222-222222222222",
                "briefing_id": "11111111-1111-4111-8111-111111111111",
                "action_id": "open_task:target",
                "feedback_type": "later",
            },
        ),
    )
    assert response.status_code == 200
    assert service.calls[0][1] == "feedback-user"

    listed, _ = asyncio.run(_request("GET", "/v1/feedback"))
    deleted, _ = asyncio.run(_request("DELETE", f"/v1/feedback/{FEEDBACK_ID}"))
    assert listed.status_code == 200
    assert deleted.status_code == 200


def test_feedback_rejects_unknown_fields_and_requires_authentication() -> None:
    invalid, service = asyncio.run(
        _request(
            "POST",
            "/v1/feedback",
            json={
                "request_id": "22222222-2222-4222-8222-222222222222",
                "briefing_id": "11111111-1111-4111-8111-111111111111",
                "action_id": "open_task:target",
                "feedback_type": "later",
                "user_id": "attacker",
            },
        ),
    )
    unauthorized, _ = asyncio.run(_request("GET", "/v1/feedback", authenticated=False))
    assert invalid.status_code == 422
    assert service.calls == []
    assert unauthorized.status_code == 401
