import asyncio
from datetime import UTC, date, datetime, timedelta

import httpx

from app.api.deps.auth import Principal
from app.main import create_app
from app.models.personal_patterns import (
    LearnedFocusPlannerPreference,
    PersonalPatternsResponse,
    PersonalPatternsSample,
    PersonalPatternsWindow,
)


NOW = datetime(2026, 7, 26, 12, tzinfo=UTC)


class Verifier:
    async def verify(self, token: str):
        if token != "patterns-token":
            return None
        return Principal(user_id="patterns-owner", authenticated_at=NOW)


class Service:
    def __init__(self) -> None:
        self.calls: list[str] = []

    async def get_patterns(self, *, user_id: str) -> PersonalPatternsResponse:
        self.calls.append(user_id)
        return PersonalPatternsResponse(
            contract_version="personal-patterns-v1",
            status="disabled",
            generated_at=NOW,
            timezone="Europe/Berlin",
            window=PersonalPatternsWindow(
                rolling_days=90,
                starts_at=NOW - timedelta(days=90),
                ends_at=NOW,
                local_starts_on=date(2026, 4, 27),
                local_ends_on=date(2026, 7, 26),
            ),
            summary="Personal pattern analysis is turned off.",
            sample=PersonalPatternsSample(
                terminal_sessions=0,
                rated_sessions=0,
                rated_local_days=0,
                rating_coverage=0,
                first_rated_local_date=None,
                last_rated_local_date=None,
            ),
            baseline=None,
            patterns=[],
            planner_preference=LearnedFocusPlannerPreference(
                eligible=False,
                reason="analysis_disabled",
                window=None,
                window_label=None,
                evidence_count=0,
                evidence_starts_on=None,
                evidence_ends_on=None,
                evidence_fingerprint=None,
            ),
            limitations=["No behavioral history was read."],
            correlation_points=[],
            evidence_fingerprint=None,
        )


async def _get(*, authenticated: bool):
    app = create_app()
    service = Service()
    app.state.token_verifier = Verifier()
    app.state.personal_patterns_service = service
    headers = (
        {"Authorization": "Bearer patterns-token"} if authenticated else {}
    )
    async with httpx.AsyncClient(
        transport=httpx.ASGITransport(app=app),
        base_url="http://test",
    ) as client:
        response = await client.get(
            "/v1/insights/personal-patterns",
            headers=headers,
        )
    return response, service


def test_personal_patterns_route_is_authenticated_and_read_only() -> None:
    response, service = asyncio.run(_get(authenticated=True))

    assert response.status_code == 200
    assert response.json()["contract_version"] == "personal-patterns-v1"
    assert response.json()["status"] == "disabled"
    assert service.calls == ["patterns-owner"]

    unauthorized, unauthorized_service = asyncio.run(
        _get(authenticated=False),
    )
    assert unauthorized.status_code == 401
    assert unauthorized_service.calls == []
