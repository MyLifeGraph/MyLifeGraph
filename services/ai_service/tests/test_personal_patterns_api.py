import asyncio
from datetime import UTC, date, datetime, timedelta

import httpx
import pytest

from app.api.deps.auth import Principal, get_token_verifier
from app.api.deps.services import get_personal_patterns_service
from app.main import create_app
from app.models.personal_patterns import (
    LearnedFocusPlannerPreference,
    PersonalPatternsResponse,
    PersonalPatternsSample,
    PersonalPatternsWindow,
)
from app.services.personal_patterns_service import (
    PersonalPatternsDataError,
    PersonalPatternsNotFoundError,
    PersonalPatternsUnavailableError,
)
from tests.api_test_dependencies import override_dependency


NOW = datetime(2026, 7, 26, 12, tzinfo=UTC)


class Verifier:
    async def verify(self, token: str):
        if token != "patterns-token":
            return None
        return Principal(user_id="patterns-owner", authenticated_at=NOW)


class Service:
    def __init__(self) -> None:
        self.calls: list[str] = []
        self.error: Exception | None = None

    async def get_patterns(self, *, user_id: str) -> PersonalPatternsResponse:
        self.calls.append(user_id)
        if self.error is not None:
            raise self.error
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


async def _get(*, authenticated: bool, error: Exception | None = None):
    app = create_app()
    service = Service()
    service.error = error
    override_dependency(app, get_token_verifier, Verifier())
    override_dependency(app, get_personal_patterns_service, service)
    headers = {"Authorization": "Bearer patterns-token"} if authenticated else {}
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


@pytest.mark.parametrize(
    ("error", "expected_status"),
    [
        (PersonalPatternsNotFoundError("missing"), 404),
        (PersonalPatternsUnavailableError("unavailable"), 503),
        (PersonalPatternsDataError("invalid"), 503),
    ],
)
def test_personal_patterns_route_maps_service_failures(
    error: Exception,
    expected_status: int,
) -> None:
    response, service = asyncio.run(_get(authenticated=True, error=error))

    assert response.status_code == expected_status
    assert service.calls == ["patterns-owner"]
