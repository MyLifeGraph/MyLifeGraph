import asyncio
from datetime import date

import httpx

from app.api.deps.auth import Principal
from app.main import create_app
from app.services.weekly_review_service import WeeklyReviewPeriodError


class FakeTokenVerifier:
    async def verify(self, token: str) -> Principal | None:
        if token == "valid-weekly-review-token":
            return Principal(user_id="principal-weekly-review-user")
        return None


class FakeWeeklyReviewService:
    def __init__(self) -> None:
        self.latest_user_ids = []
        self.period_calls = []
        self.generate_calls = []

    async def get_latest(self, *, user_id: str):
        self.latest_user_ids.append(user_id)
        return not_ready_response()

    async def get_period(self, *, user_id: str, period_key: str):
        self.period_calls.append((user_id, period_key))
        if period_key != "2026-W28":
            raise WeeklyReviewPeriodError("Only the latest week is available.")
        return not_ready_response()

    async def generate(self, *, user_id: str, request):
        self.generate_calls.append((user_id, request))
        if request.period_key != "2026-W28":
            raise WeeklyReviewPeriodError("Only the latest week is available.")
        return not_ready_response()


def not_ready_response() -> dict:
    return {
        "contract_version": "weekly-review-v1",
        "period_key": "2026-W28",
        "starts_on": date(2026, 7, 6),
        "ends_on": date(2026, 7, 12),
        "timezone": "Europe/Berlin",
        "freshness": "not_ready",
        "needs_generation": False,
        "stale_reasons": [],
        "review": None,
    }


async def request(method: str, path: str, *, json=None, authenticated: bool = True):
    app = create_app()
    service = FakeWeeklyReviewService()
    app.state.token_verifier = FakeTokenVerifier()
    app.state.weekly_review_service = service
    transport = httpx.ASGITransport(app=app)
    headers = (
        {"Authorization": "Bearer valid-weekly-review-token"}
        if authenticated
        else {}
    )
    async with httpx.AsyncClient(
        transport=transport,
        base_url="http://testserver",
    ) as client:
        response = await client.request(
            method,
            path,
            headers=headers,
            json=json,
        )
    return response, service


def test_latest_and_period_reads_derive_user_from_principal() -> None:
    latest, latest_service = asyncio.run(
        request("GET", "/v1/weekly-reviews/latest"),
    )
    period, period_service = asyncio.run(
        request("GET", "/v1/weekly-reviews/2026-W28"),
    )

    assert latest.status_code == 200
    assert latest.json()["starts_on"] == "2026-07-06"
    assert latest_service.latest_user_ids == ["principal-weekly-review-user"]
    assert period.status_code == 200
    assert period_service.period_calls == [
        ("principal-weekly-review-user", "2026-W28"),
    ]


def test_generate_is_strict_and_derives_user_from_principal() -> None:
    response, service = asyncio.run(
        request(
            "POST",
            "/v1/weekly-reviews/generate",
            json={"period_key": "2026-W28", "force": False},
        ),
    )

    assert response.status_code == 200
    user_id, generated = service.generate_calls[0]
    assert user_id == "principal-weekly-review-user"
    assert generated.period_key == "2026-W28"
    assert generated.force is False

    invalid, invalid_service = asyncio.run(
        request(
            "POST",
            "/v1/weekly-reviews/generate",
            json={
                "period_key": "2026-W28",
                "force": False,
                "user_id": "attacker-controlled",
            },
        ),
    )
    assert invalid.status_code == 422
    assert invalid_service.generate_calls == []


def test_only_latest_period_is_accepted() -> None:
    get_response, _ = asyncio.run(
        request("GET", "/v1/weekly-reviews/2026-W27"),
    )
    post_response, _ = asyncio.run(
        request(
            "POST",
            "/v1/weekly-reviews/generate",
            json={"period_key": "2026-W27", "force": False},
        ),
    )

    assert get_response.status_code == 422
    assert post_response.status_code == 422


def test_weekly_review_routes_require_authentication() -> None:
    latest, _ = asyncio.run(
        request("GET", "/v1/weekly-reviews/latest", authenticated=False),
    )
    period, _ = asyncio.run(
        request("GET", "/v1/weekly-reviews/2026-W28", authenticated=False),
    )
    generate, _ = asyncio.run(
        request(
            "POST",
            "/v1/weekly-reviews/generate",
            json={"period_key": "2026-W28", "force": False},
            authenticated=False,
        ),
    )

    assert latest.status_code == 401
    assert period.status_code == 401
    assert generate.status_code == 401
