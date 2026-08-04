import asyncio
from datetime import UTC, date, datetime, timedelta

import httpx
import pytest

from app.api.deps.auth import Principal, get_token_verifier
from app.api.deps.services import get_sleep_recommendation_service
from app.main import create_app
from app.models.sleep_recommendation import (
    SleepRecommendationResponse,
    SleepRecommendationSample,
    SleepRecommendationWindow,
)
from app.services.sleep_recommendation_service import (
    SleepRecommendationDataError,
    SleepRecommendationNotFoundError,
    SleepRecommendationUnavailableError,
)
from tests.api_test_dependencies import override_dependency


NOW = datetime(2026, 7, 30, 12, tzinfo=UTC)


class Verifier:
    async def verify(self, token: str):
        if token != "sleep-token":
            return None
        return Principal(user_id="sleep-owner", authenticated_at=NOW)


class Service:
    def __init__(self) -> None:
        self.calls: list[str] = []
        self.error: Exception | None = None

    async def get_recommendation(self, *, user_id: str):
        self.calls.append(user_id)
        if self.error is not None:
            raise self.error
        return SleepRecommendationResponse(
            contract_version="sleep-recommendation-v1",
            status="disabled",
            reason="analysis_disabled",
            generated_at=NOW,
            timezone="Europe/Berlin",
            window=SleepRecommendationWindow(
                rolling_days=90,
                starts_at=NOW - timedelta(days=90),
                ends_at=NOW,
                local_starts_on=date(2026, 5, 1),
                local_ends_on=date(2026, 7, 30),
            ),
            sample=SleepRecommendationSample(
                valid_nights=0,
                eligible_focus_days=0,
                rated_sessions=0,
                required_eligible_days=30,
                progress="0/30",
            ),
            recommendation=None,
            summary="Sleep recommendation analysis is turned off.",
            limitations=["No sleep or Focus history was read."],
        )


async def _get(*, authenticated: bool, error: Exception | None = None):
    app = create_app()
    service = Service()
    service.error = error
    override_dependency(app, get_token_verifier, Verifier())
    override_dependency(app, get_sleep_recommendation_service, service)
    headers = {"Authorization": "Bearer sleep-token"} if authenticated else {}
    async with httpx.AsyncClient(
        transport=httpx.ASGITransport(app=app),
        base_url="http://test",
    ) as client:
        response = await client.get(
            "/v1/insights/sleep-recommendation",
            headers=headers,
        )
    return response, service


def test_sleep_recommendation_route_is_authenticated_and_read_only() -> None:
    response, service = asyncio.run(_get(authenticated=True))

    assert response.status_code == 200
    assert response.json()["contract_version"] == "sleep-recommendation-v1"
    assert service.calls == ["sleep-owner"]

    unauthorized, unauthorized_service = asyncio.run(_get(authenticated=False))
    assert unauthorized.status_code == 401
    assert unauthorized_service.calls == []


@pytest.mark.parametrize(
    ("error", "expected_status"),
    [
        (SleepRecommendationNotFoundError("missing"), 404),
        (SleepRecommendationUnavailableError("unavailable"), 503),
        (SleepRecommendationDataError("invalid"), 503),
    ],
)
def test_sleep_recommendation_route_maps_bounded_failures(
    error: Exception,
    expected_status: int,
) -> None:
    response, service = asyncio.run(_get(authenticated=True, error=error))

    assert response.status_code == expected_status
    assert service.calls == ["sleep-owner"]
