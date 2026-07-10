import asyncio
from datetime import UTC, datetime

import httpx

from app.api.deps.auth import Principal
from app.main import create_app
from app.models.intake import IntakeResponses, SnapshotSummary
from app.services.intake_service import IntakeRevisionConflict


REQUEST_ID = "00000000-0000-4000-8000-000000000001"
GOAL_KEY = "10000000-0000-4000-8000-000000000001"
ROUTINE_KEY = "20000000-0000-4000-8000-000000000001"
COMMITMENT_KEY = "30000000-0000-4000-8000-000000000001"


class FakeTokenVerifier:
    async def verify(self, token: str) -> Principal | None:
        if token == "valid-test-token":
            return Principal(user_id="user-test-123")
        return None


class FakeIntakeService:
    def __init__(self, *, conflict: bool = False) -> None:
        self.calls: list[tuple[str, object]] = []
        self.conflict = conflict

    async def get_setup(self, *, user_id: str):
        self.calls.append((user_id, "get"))
        return {
            "exists": False,
            "revision": 0,
            "base_revision": 0,
        }

    async def complete_intake(self, *, user_id: str, request):
        self.calls.append((user_id, request))
        if self.conflict:
            raise IntakeRevisionConflict(
                "Setup changed after this draft was loaded.",
                current_revision=2,
            )
        return {
            "exists": True,
            "request_id": request.request_id,
            "revision": 1,
            "base_revision": request.base_revision,
            "status": "applied",
            "intake_response_id": "intake-123",
            "snapshot_id": "snapshot-123",
            "completed_at": datetime(2026, 7, 10, tzinfo=UTC),
            "responses": request.responses,
            "summary": summary(),
            "recommendations": [],
        }


def summary() -> SnapshotSummary:
    return SnapshotSummary(
        primary_focus_areas=["focus", "energy"],
        goals=["Protect focus time"],
        friction_points=[],
        best_energy_window="morning",
        coaching_style="direct",
        reminder_enabled=True,
        fixed_commitment_count=1,
        existing_habit_count=0,
        routine_candidate_count=1,
        active_habit_count=0,
    )


def make_app(*, conflict: bool = False):
    app = create_app()
    app.state.token_verifier = FakeTokenVerifier()
    app.state.intake_service = FakeIntakeService(conflict=conflict)
    return app


async def request(
    method: str,
    url: str,
    *,
    headers: dict[str, str] | None = None,
    json: dict | None = None,
    conflict: bool = False,
) -> httpx.Response:
    app = make_app(conflict=conflict)
    transport = httpx.ASGITransport(app=app)
    async with httpx.AsyncClient(
        transport=transport,
        base_url="http://testserver",
    ) as client:
        response = await client.request(method, url, headers=headers, json=json)
    response.extensions["app"] = app
    return response


def valid_payload() -> dict:
    return {
        "request_id": REQUEST_ID,
        "base_revision": 0,
        "version": "intake-v1",
        "responses": {
            "display_name": "Ada",
            "primary_focus_areas": ["focus", "energy"],
            "goals": [
                {
                    "key": GOAL_KEY,
                    "title": "Protect focus time",
                    "status": "active",
                },
            ],
            "friction_points": [],
            "weekday_shape": "Mornings are school, afternoons are flexible.",
            "best_energy_window": "morning",
            "coaching_style": "direct",
            "reminder_preference": {
                "enabled": True,
                "quiet_hours": {"starts_at": "21:30", "ends_at": "07:00"},
            },
            "routines": [
                {
                    "key": ROUTINE_KEY,
                    "title": "Walk after lunch",
                    "status": "candidate",
                    "cadence_confirmed": False,
                },
            ],
            "fixed_commitments": [
                {
                    "key": COMMITMENT_KEY,
                    "title": "Math",
                    "location": "Room 204",
                    "weekday": 1,
                    "starts_at": "08:15",
                    "ends_at": "09:45",
                    "status": "active",
                },
            ],
        },
        "metadata": {"client": "test"},
    }


def auth_headers() -> dict[str, str]:
    return {"Authorization": "Bearer valid-test-token"}


def test_get_setup_without_authorization_returns_401() -> None:
    response = asyncio.run(request("GET", "/v1/intake/setup"))

    assert response.status_code == 401
    assert response.headers["www-authenticate"] == "Bearer"


def test_get_setup_uses_principal_and_returns_explicit_empty_state() -> None:
    response = asyncio.run(
        request("GET", "/v1/intake/setup", headers=auth_headers()),
    )

    assert response.status_code == 200
    assert response.json() == {
        "exists": False,
        "revision": 0,
        "base_revision": 0,
    }
    service = response.extensions["app"].state.intake_service
    assert service.calls == [("user-test-123", "get")]


def test_complete_intake_without_authorization_returns_401() -> None:
    response = asyncio.run(
        request("POST", "/v1/intake/complete", json=valid_payload()),
    )

    assert response.status_code == 401


def test_complete_intake_with_principal_returns_canonical_setup_envelope() -> None:
    response = asyncio.run(
        request(
            "POST",
            "/v1/intake/complete",
            headers=auth_headers(),
            json=valid_payload(),
        ),
    )

    assert response.status_code == 200
    body = response.json()
    assert body["exists"] is True
    assert body["request_id"] == REQUEST_ID
    assert body["revision"] == 1
    assert body["base_revision"] == 0
    assert body["status"] == "applied"
    assert body["intake_response_id"] == "intake-123"
    assert body["snapshot_id"] == "snapshot-123"
    assert body["responses"]["goals"][0]["key"] == GOAL_KEY
    assert body["responses"]["routines"][0]["status"] == "candidate"
    assert body["summary"]["routine_candidate_count"] == 1
    service = response.extensions["app"].state.intake_service
    assert service.calls[0][0] == "user-test-123"


def test_complete_intake_maps_revision_conflict_to_409() -> None:
    response = asyncio.run(
        request(
            "POST",
            "/v1/intake/complete",
            headers=auth_headers(),
            json=valid_payload(),
            conflict=True,
        ),
    )

    assert response.status_code == 409
    assert response.json()["detail"] == {
        "code": "intake_revision_conflict",
        "message": "Setup changed after this draft was loaded.",
        "current_revision": 2,
    }


def test_complete_intake_rejects_request_user_id() -> None:
    payload = valid_payload()
    payload["user_id"] = "attacker-controlled"

    response = asyncio.run(
        request(
            "POST",
            "/v1/intake/complete",
            headers=auth_headers(),
            json=payload,
        ),
    )

    assert response.status_code == 422


def test_complete_intake_rejects_unconfirmed_cadence() -> None:
    payload = valid_payload()
    payload["responses"]["routines"][0].update(  # type: ignore[index]
        {"frequency": "weekly", "target": 3},
    )

    response = asyncio.run(
        request(
            "POST",
            "/v1/intake/complete",
            headers=auth_headers(),
            json=payload,
        ),
    )

    assert response.status_code == 422


def test_complete_intake_rejects_invalid_commitment_time_range() -> None:
    payload = valid_payload()
    payload["responses"]["fixed_commitments"][0]["ends_at"] = "07:00"  # type: ignore[index]

    response = asyncio.run(
        request(
            "POST",
            "/v1/intake/complete",
            headers=auth_headers(),
            json=payload,
        ),
    )

    assert response.status_code == 422


def test_complete_intake_rejects_duplicate_keys_across_kinds() -> None:
    payload = valid_payload()
    payload["responses"]["routines"][0]["key"] = GOAL_KEY  # type: ignore[index]

    response = asyncio.run(
        request(
            "POST",
            "/v1/intake/complete",
            headers=auth_headers(),
            json=payload,
        ),
    )

    assert response.status_code == 422


def test_disabled_reminders_may_omit_quiet_hours() -> None:
    payload = valid_payload()
    payload["responses"]["reminder_preference"] = {"enabled": False}  # type: ignore[index]
    parsed = IntakeResponses.model_validate(payload["responses"])

    assert parsed.reminder_preference.enabled is False
    assert parsed.reminder_preference.quiet_hours is None
