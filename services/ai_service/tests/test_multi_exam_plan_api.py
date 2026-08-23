import asyncio
import json
from datetime import UTC, datetime, timedelta
from uuid import UUID

import httpx
import pytest
from pydantic import ValidationError

from app.api.deps.auth import Principal, get_token_verifier
from app.api.deps.services import get_multi_exam_plan_service
from app.main import create_app
from app.models.multi_exam_plans import (
    MultiExamPlanBatchProposalResponse,
    MultiExamPlanBatchResponse,
    MultiExamPlanListResponse,
    MultiExamPlanNoChangeResponse,
)
from app.services.deadline_plan_service import DeadlinePlanConflictError
from tests.api_test_dependencies import override_dependency


USER_ID = "exam-balance-owner"
TARGET_ID = UUID("11111111-1111-4111-8111-111111111111")
OTHER_ID = UUID("22222222-2222-4222-8222-222222222222")
BALANCE_ID = UUID("33333333-3333-4333-8333-333333333333")
REQUEST_ID = UUID("44444444-4444-4444-8444-444444444444")
NOW = datetime(2026, 8, 13, 9, tzinfo=UTC)


class Verifier:
    async def verify(self, token: str):
        return Principal(user_id=USER_ID) if token == "balance-token" else None


def _block(plan_id: UUID, offset: int, identifier: str) -> dict[str, object]:
    starts_at = NOW + timedelta(days=offset, hours=2)
    ends_at = starts_at + timedelta(minutes=30)
    return {
        "id": identifier,
        "sequence": 1,
        "starts_at": starts_at.isoformat(),
        "ends_at": ends_at.isoformat(),
        "reserved_ends_at": ends_at.isoformat(),
        "local_date": starts_at.date().isoformat(),
        "planned_minutes": 30,
        "recovery_minutes": 0,
        "credited_minutes": 0,
    }


def _item(
    plan_id: UUID,
    *,
    position: int,
    deadline_offset: int,
) -> dict[str, object]:
    current = _block(
        plan_id,
        deadline_offset,
        f"{position}1111111-1111-4111-8111-111111111111",
    )
    proposed = _block(
        plan_id,
        deadline_offset + 1,
        f"{position}2222222-2222-4222-8222-222222222222",
    )
    proposed["starts_at"] = (
        datetime.fromisoformat(str(proposed["starts_at"])) + timedelta(hours=1)
    ).isoformat()
    proposed["ends_at"] = (
        datetime.fromisoformat(str(proposed["ends_at"])) + timedelta(hours=1)
    ).isoformat()
    proposed["reserved_ends_at"] = proposed["ends_at"]
    return {
        "position": position,
        "plan_id": str(plan_id),
        "title": "Algorithms" if position == 1 else "Physics",
        "deadline_at": (NOW + timedelta(days=deadline_offset + 20)).isoformat(),
        "remaining_minutes": 120,
        "active_revision": 1,
        "base_revision": 1,
        "proposed_revision": 2,
        "current_blocks": [current],
        "proposed_blocks": [proposed],
        "retained_minutes": 0,
        "added_minutes": 0,
        "shifted_minutes": 30,
        "removed_minutes": 0,
        "retained_block_count": 0,
        "added_block_count": 0,
        "shifted_block_count": 1,
        "removed_block_count": 0,
    }


def _batch(status: str = "proposed") -> MultiExamPlanBatchResponse:
    items = [
        _item(TARGET_ID, position=1, deadline_offset=1),
        _item(OTHER_ID, position=2, deadline_offset=2),
    ]
    payload = {
        "contract_version": "multi-exam-plan-v1",
        "origin": "authenticated_backend",
        "balance": {
            "id": str(BALANCE_ID),
            "status": status,
            "revision": 1,
            "target_plan_id": str(TARGET_ID),
            "context_fingerprint": "a" * 64,
            "confirmation_fingerprint": "b" * 64,
            "timezone": "UTC",
            "created_at": NOW.isoformat(),
            "updated_at": NOW.isoformat(),
            "confirmed_at": NOW.isoformat() if status == "confirmed" else None,
            "cancelled_at": NOW.isoformat() if status == "cancelled" else None,
            "retained_minutes": 0,
            "added_minutes": 0,
            "shifted_minutes": 60,
            "removed_minutes": 0,
            "items": items,
            "child_links": [
                {
                    "plan_id": str(item["plan_id"]),
                    "proposed_revision": 2,
                    "balance_id": str(BALANCE_ID),
                    "balance_revision": 1,
                    "status": status,
                }
                for item in items
            ],
        },
    }
    return MultiExamPlanBatchResponse.model_validate_json(json.dumps(payload))


class Service:
    def __init__(self, *, stale: bool = False, stale_read: bool = False) -> None:
        self.calls: list[tuple[object, ...]] = []
        self.stale = stale
        self.stale_read = stale_read

    async def list_balances(self, *, user_id):
        self.calls.append(("list", user_id))
        detail = _batch().balance
        return MultiExamPlanListResponse(
            contract_version="multi-exam-plan-v1",
            origin="authenticated_backend",
            balances=[
                {
                    "id": detail.id,
                    "status": detail.status,
                    "revision": detail.revision,
                    "target_plan_id": detail.target_plan_id,
                    "affected_plan_count": len(detail.items),
                    "shifted_minutes": detail.shifted_minutes,
                    "created_at": detail.created_at,
                    "updated_at": detail.updated_at,
                },
            ],
        )

    async def get_balance(self, *, user_id, balance_id):
        self.calls.append(("get", user_id, balance_id))
        if self.stale_read:
            raise DeadlinePlanConflictError(
                "Exam balance projection is inconsistent.",
            )
        return _batch()

    async def propose(self, *, user_id, request):
        self.calls.append(("propose", user_id, request))
        if self.stale:
            raise DeadlinePlanConflictError(
                "Selected Exam changed. Reload before balancing.",
            )
        return MultiExamPlanNoChangeResponse(
            contract_version="multi-exam-plan-v1",
            origin="authenticated_backend",
            outcome="no_change",
            target_plan_id=request.target_plan_id,
            reason="already_balanced",
        )

    async def confirm(self, *, user_id, balance_id, request):
        self.calls.append(("confirm", user_id, balance_id, request))
        return _batch("confirmed")

    async def cancel(self, *, user_id, balance_id, request):
        self.calls.append(("cancel", user_id, balance_id, request))
        return _batch("cancelled")


async def _request(
    method: str,
    path: str,
    *,
    body=None,
    authenticated=True,
    stale=False,
    stale_read=False,
):
    app = create_app()
    service = Service(stale=stale, stale_read=stale_read)
    override_dependency(app, get_token_verifier, Verifier())
    override_dependency(app, get_multi_exam_plan_service, service)
    headers = {"Authorization": "Bearer balance-token"} if authenticated else {}
    async with httpx.AsyncClient(
        transport=httpx.ASGITransport(app=app),
        base_url="http://test",
    ) as client:
        response = await client.request(method, path, headers=headers, json=body)
    return response, service


def test_all_five_routes_derive_owner_and_preserve_strict_contract() -> None:
    listing, list_service = asyncio.run(
        _request("GET", "/v1/deadline-plans/exam-balances"),
    )
    assert listing.status_code == 200
    assert listing.json()["balances"][0]["affected_plan_count"] == 2
    assert list_service.calls == [("list", USER_ID)]

    detail, detail_service = asyncio.run(
        _request("GET", f"/v1/deadline-plans/exam-balances/{BALANCE_ID}"),
    )
    assert detail.status_code == 200
    assert detail.json()["balance"]["items"][0]["plan_id"] == str(TARGET_ID)
    assert detail_service.calls == [("get", USER_ID, BALANCE_ID)]

    proposal = {
        "contract_version": "multi-exam-plan-v1",
        "request_id": str(REQUEST_ID),
        "target_plan_id": str(TARGET_ID),
        "expected_plan_revision": 1,
    }
    proposed, proposed_service = asyncio.run(
        _request(
            "POST",
            "/v1/deadline-plans/exam-balances/proposals",
            body=proposal,
        ),
    )
    assert proposed.status_code == 200
    assert proposed.json()["outcome"] == "no_change"
    assert proposed_service.calls[0][0:2] == ("propose", USER_ID)

    mutation = {
        "contract_version": "multi-exam-plan-v1",
        "request_id": str(REQUEST_ID),
        "expected_revision": 1,
    }
    confirmed, confirmed_service = asyncio.run(
        _request(
            "POST",
            f"/v1/deadline-plans/exam-balances/{BALANCE_ID}/confirm",
            body=mutation,
        ),
    )
    assert confirmed.status_code == 200
    assert confirmed.json()["balance"]["status"] == "confirmed"
    assert confirmed_service.calls[0][0] == "confirm"

    cancelled, cancelled_service = asyncio.run(
        _request(
            "POST",
            f"/v1/deadline-plans/exam-balances/{BALANCE_ID}/cancel",
            body=mutation,
        ),
    )
    assert cancelled.status_code == 200
    assert cancelled.json()["balance"]["status"] == "cancelled"
    assert cancelled_service.calls[0][0] == "cancel"


def test_proposal_revision_is_required_strict_and_stale_is_stable_409() -> None:
    body = {
        "contract_version": "multi-exam-plan-v1",
        "request_id": str(REQUEST_ID),
        "target_plan_id": str(TARGET_ID),
        "expected_plan_revision": "1",
    }
    invalid, invalid_service = asyncio.run(
        _request(
            "POST",
            "/v1/deadline-plans/exam-balances/proposals",
            body=body,
        ),
    )
    assert invalid.status_code == 422
    assert invalid_service.calls == []

    body["expected_plan_revision"] = 1
    stale, stale_service = asyncio.run(
        _request(
            "POST",
            "/v1/deadline-plans/exam-balances/proposals",
            body=body,
            stale=True,
        ),
    )
    assert stale.status_code == 409
    assert stale.json() == {
        "detail": "Selected Exam changed. Reload before balancing.",
    }
    assert stale_service.calls[0][0] == "propose"


def test_inconsistent_targeted_projection_is_a_stable_conflict() -> None:
    response, service = asyncio.run(
        _request(
            "GET",
            f"/v1/deadline-plans/exam-balances/{BALANCE_ID}",
            stale_read=True,
        ),
    )

    assert response.status_code == 409
    assert response.json() == {
        "detail": "Exam balance projection is inconsistent.",
    }
    assert service.calls == [("get", USER_ID, BALANCE_ID)]


def test_exam_balance_routes_require_bearer_authentication() -> None:
    response, service = asyncio.run(
        _request(
            "GET",
            "/v1/deadline-plans/exam-balances",
            authenticated=False,
        ),
    )
    assert response.status_code == 401
    assert service.calls == []


def test_batch_contract_rejects_forged_target_timezone_and_terminal_proposal() -> None:
    forged_target = _batch().model_dump(mode="python")
    forged_target["balance"]["target_plan_id"] = UUID(
        "99999999-9999-4999-8999-999999999999",
    )
    with pytest.raises(ValidationError, match="target must be a changed plan"):
        MultiExamPlanBatchResponse.model_validate(forged_target)

    invalid_timezone = _batch().model_dump(mode="python")
    invalid_timezone["balance"]["timezone"] = "Not/A_Timezone"
    with pytest.raises(ValidationError, match="timezone is invalid"):
        MultiExamPlanBatchResponse.model_validate(invalid_timezone)

    confirmed = _batch("confirmed").balance
    with pytest.raises(ValidationError, match="proposal must be staged"):
        MultiExamPlanBatchProposalResponse(
            contract_version="multi-exam-plan-v1",
            origin="authenticated_backend",
            outcome="multi_exam_batch",
            balance=confirmed,
        )
