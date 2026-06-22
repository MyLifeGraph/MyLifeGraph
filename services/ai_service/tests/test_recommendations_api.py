import asyncio
from datetime import date

import httpx

from app.api.deps.auth import Principal
from app.main import create_app
from app.services.recommendation_engine import current_period_key


class FakeTokenVerifier:
    async def verify(self, token: str) -> Principal | None:
        if token == "valid-test-token":
            return Principal(user_id="user-test-123")
        return None


class FakeRecommendationEngine:
    async def list_recommendations(self, user_id: str):
        return expected_empty_response()

    async def generate_recommendations(self, user_id: str, request):
        return expected_empty_response()


def make_app():
    app = create_app()
    app.state.token_verifier = FakeTokenVerifier()
    app.state.recommendation_engine = FakeRecommendationEngine()
    return app


async def request(
    method: str,
    url: str,
    *,
    headers: dict[str, str] | None = None,
    json: dict[str, object] | None = None,
) -> httpx.Response:
    transport = httpx.ASGITransport(app=make_app())
    async with httpx.AsyncClient(
        transport=transport,
        base_url="http://testserver",
    ) as client:
        return await client.request(method, url, headers=headers, json=json)


def expected_empty_response() -> dict[str, object]:
    return {
        "items": [],
        "needs_generation": True,
        "generated_at": None,
        "period_key": current_period_key(date.today()),
        "stale_reason": "missing",
    }


def test_get_recommendations_without_authorization_returns_401() -> None:
    response = asyncio.run(request("GET", "/v1/recommendations"))

    assert response.status_code == 401
    assert response.headers["www-authenticate"] == "Bearer"


def test_generate_recommendations_without_authorization_returns_401() -> None:
    response = asyncio.run(request("POST", "/v1/recommendations/generate", json={}))

    assert response.status_code == 401
    assert response.headers["www-authenticate"] == "Bearer"


def test_malformed_authorization_returns_401() -> None:
    response = asyncio.run(
        request(
            "GET",
            "/v1/recommendations",
            headers={"Authorization": "Token valid-test-token"},
        ),
    )

    assert response.status_code == 401
    assert response.headers["www-authenticate"] == "Bearer"


def test_invalid_bearer_token_returns_401() -> None:
    response = asyncio.run(
        request(
            "GET",
            "/v1/recommendations",
            headers={"Authorization": "Bearer invalid-test-token"},
        ),
    )

    assert response.status_code == 401
    assert response.headers["www-authenticate"] == "Bearer"


def test_get_recommendations_with_fake_principal_matches_contract() -> None:
    response = asyncio.run(
        request(
            "GET",
            "/v1/recommendations",
            headers={"Authorization": "Bearer valid-test-token"},
        ),
    )

    assert response.status_code == 200
    assert response.json() == expected_empty_response()


def test_generate_recommendations_with_fake_principal_matches_contract() -> None:
    response = asyncio.run(
        request(
            "POST",
            "/v1/recommendations/generate",
            headers={"Authorization": "Bearer valid-test-token"},
            json={
                "window_days": 28,
                "force": False,
                "allow_llm_wording": False,
            },
        ),
    )

    assert response.status_code == 200
    assert response.json() == expected_empty_response()


def test_generate_recommendations_rejects_request_user_id() -> None:
    response = asyncio.run(
        request(
            "POST",
            "/v1/recommendations/generate",
            headers={"Authorization": "Bearer valid-test-token"},
            json={
                "window_days": 28,
                "force": False,
                "allow_llm_wording": False,
                "user_id": "attacker-controlled",
            },
        ),
    )

    assert response.status_code == 422
