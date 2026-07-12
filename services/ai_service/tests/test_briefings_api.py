import asyncio
from datetime import date

import httpx

from app.api.deps.auth import Principal
from app.main import create_app


class FakeTokenVerifier:
    async def verify(self, token: str) -> Principal | None:
        if token == "valid-briefing-token":
            return Principal(user_id="principal-briefing-user")
        return None


class FakeBriefingService:
    def __init__(self) -> None:
        self.get_user_ids = []
        self.generate_calls = []

    async def get_today(self, *, user_id: str):
        self.get_user_ids.append(user_id)
        return empty_response()

    async def generate_today(self, *, user_id: str, request):
        self.generate_calls.append((user_id, request))
        return empty_response()


def empty_response() -> dict:
    return {
        "contract_version": "daily-briefing-v1",
        "briefing_date": date.today(),
        "freshness": "missing",
        "needs_generation": True,
        "stale_reasons": [],
        "briefing": None,
    }


async def request(method: str, path: str, *, json=None):
    app = create_app()
    service = FakeBriefingService()
    app.state.token_verifier = FakeTokenVerifier()
    app.state.briefing_service = service
    transport = httpx.ASGITransport(app=app)
    async with httpx.AsyncClient(
        transport=transport,
        base_url="http://testserver",
    ) as client:
        response = await client.request(
            method,
            path,
            headers={"Authorization": "Bearer valid-briefing-token"},
            json=json,
        )
    return response, service


def test_get_today_derives_user_from_principal() -> None:
    response, service = asyncio.run(request("GET", "/v1/briefings/today"))

    assert response.status_code == 200
    assert response.json() == {
        **empty_response(),
        "briefing_date": date.today().isoformat(),
    }
    assert service.get_user_ids == ["principal-briefing-user"]


def test_generate_derives_user_from_principal() -> None:
    response, service = asyncio.run(
        request("POST", "/v1/briefings/generate", json={"force": False}),
    )

    assert response.status_code == 200
    assert service.generate_calls[0][0] == "principal-briefing-user"
    assert service.generate_calls[0][1].force is False


def test_generate_rejects_request_user_id() -> None:
    response, service = asyncio.run(
        request(
            "POST",
            "/v1/briefings/generate",
            json={"force": False, "user_id": "attacker-controlled"},
        ),
    )

    assert response.status_code == 422
    assert service.generate_calls == []


def test_briefing_routes_require_authentication() -> None:
    app = create_app()
    app.state.token_verifier = FakeTokenVerifier()
    app.state.briefing_service = FakeBriefingService()

    async def unauthorized_requests():
        transport = httpx.ASGITransport(app=app)
        async with httpx.AsyncClient(
            transport=transport,
            base_url="http://testserver",
        ) as client:
            get_response = await client.get("/v1/briefings/today")
            post_response = await client.post("/v1/briefings/generate", json={})
        return get_response, post_response

    get_response, post_response = asyncio.run(unauthorized_requests())
    assert get_response.status_code == 401
    assert post_response.status_code == 401
