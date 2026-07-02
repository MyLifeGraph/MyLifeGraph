import asyncio
from datetime import UTC, datetime

import httpx

from app.api.deps.auth import Principal
from app.main import create_app
from app.models.intake import SnapshotSummary


class FakeTokenVerifier:
    async def verify(self, token: str) -> Principal | None:
        if token == "valid-test-token":
            return Principal(user_id="user-test-123")
        return None


class FakeIntakeService:
    def __init__(self) -> None:
        self.calls: list[tuple[str, object]] = []

    async def complete_intake(self, user_id: str, request):
        self.calls.append((user_id, request))
        return {
            "intake_response_id": "intake-123",
            "snapshot_id": "snapshot-123",
            "completed_at": datetime(2026, 7, 2, tzinfo=UTC),
            "summary": SnapshotSummary(
                primary_focus_areas=["focus", "energy"],
                goals=["Protect focus time"],
                friction_points=["Too many context switches"],
                best_energy_window="morning",
                coaching_style="direct",
                reminder_enabled=True,
                fixed_commitment_count=1,
                existing_habit_count=1,
            ),
            "recommendations": [],
        }


def make_app():
    app = create_app()
    app.state.token_verifier = FakeTokenVerifier()
    app.state.intake_service = FakeIntakeService()
    return app


async def request(
    method: str,
    url: str,
    *,
    headers: dict[str, str] | None = None,
    json: dict[str, object] | None = None,
) -> httpx.Response:
    app = make_app()
    transport = httpx.ASGITransport(app=app)
    async with httpx.AsyncClient(
        transport=transport,
        base_url="http://testserver",
    ) as client:
        response = await client.request(method, url, headers=headers, json=json)
    response.extensions["app"] = app
    return response


def valid_payload() -> dict[str, object]:
    return {
        "version": "intake-v1",
        "responses": {
            "display_name": "Ada",
            "primary_focus_areas": ["focus", "energy"],
            "goals": ["Protect focus time"],
            "friction_points": ["Too many context switches"],
            "weekday_shape": "Mornings are school, afternoons are flexible.",
            "best_energy_window": "morning",
            "coaching_style": "direct",
            "reminder_preference": {
                "enabled": True,
                "quiet_hours": {"starts_at": "21:30", "ends_at": "07:00"},
            },
            "existing_habits": ["Walk after lunch"],
            "fixed_commitments": [
                {
                    "title": "Math",
                    "location": "Room 204",
                    "weekday": 1,
                    "starts_at": "08:15",
                    "ends_at": "09:45",
                },
            ],
            "context_note": "Prefer concise prompts.",
            "calendar_connection_intent": "not_now",
        },
        "metadata": {"client": "test"},
    }


def test_complete_intake_without_authorization_returns_401() -> None:
    response = asyncio.run(request("POST", "/v1/intake/complete", json=valid_payload()))

    assert response.status_code == 401
    assert response.headers["www-authenticate"] == "Bearer"


def test_complete_intake_malformed_authorization_returns_401() -> None:
    response = asyncio.run(
        request(
            "POST",
            "/v1/intake/complete",
            headers={"Authorization": "Token valid-test-token"},
            json=valid_payload(),
        ),
    )

    assert response.status_code == 401
    assert response.headers["www-authenticate"] == "Bearer"


def test_complete_intake_invalid_bearer_token_returns_401() -> None:
    response = asyncio.run(
        request(
            "POST",
            "/v1/intake/complete",
            headers={"Authorization": "Bearer invalid-test-token"},
            json=valid_payload(),
        ),
    )

    assert response.status_code == 401
    assert response.headers["www-authenticate"] == "Bearer"


def test_complete_intake_with_fake_principal_matches_contract() -> None:
    response = asyncio.run(
        request(
            "POST",
            "/v1/intake/complete",
            headers={"Authorization": "Bearer valid-test-token"},
            json=valid_payload(),
        ),
    )

    assert response.status_code == 200
    assert response.json() == {
        "intake_response_id": "intake-123",
        "snapshot_id": "snapshot-123",
        "completed_at": "2026-07-02T00:00:00Z",
        "summary": {
            "primary_focus_areas": ["focus", "energy"],
            "goals": ["Protect focus time"],
            "friction_points": ["Too many context switches"],
            "best_energy_window": "morning",
            "coaching_style": "direct",
            "reminder_enabled": True,
            "fixed_commitment_count": 1,
            "existing_habit_count": 1,
        },
        "recommendations": [],
    }


def test_complete_intake_rejects_request_user_id() -> None:
    payload = valid_payload()
    payload["user_id"] = "attacker-controlled"

    response = asyncio.run(
        request(
            "POST",
            "/v1/intake/complete",
            headers={"Authorization": "Bearer valid-test-token"},
            json=payload,
        ),
    )

    assert response.status_code == 422


def test_complete_intake_rejects_unknown_focus_area() -> None:
    payload = valid_payload()
    responses = dict(payload["responses"])  # type: ignore[arg-type]
    responses["primary_focus_areas"] = ["focus", "calendar"]
    payload["responses"] = responses

    response = asyncio.run(
        request(
            "POST",
            "/v1/intake/complete",
            headers={"Authorization": "Bearer valid-test-token"},
            json=payload,
        ),
    )

    assert response.status_code == 422
