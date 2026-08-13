import asyncio
from datetime import UTC, date, datetime, timedelta

import httpx

from app.api.deps.auth import Principal, get_token_verifier
from app.api.deps.services import get_today_week_agenda_service
from app.main import create_app
from app.models.today_week_agenda import (
    TodayWeekAgendaDay,
    TodayWeekAgendaResponse,
    TodayWeekAgendaSourceState,
    TodayWeekAgendaSourceStates,
)
from app.services.today_week_agenda_service import TodayWeekAgendaUnavailableError
from tests.api_test_dependencies import override_dependency


class Verifier:
    async def verify(self, token: str):
        return Principal(user_id="week-user") if token == "week-token" else None


class Service:
    def __init__(self, *, unavailable: bool = False) -> None:
        self.calls: list[str] = []
        self.unavailable = unavailable

    async def get_week(self, *, user_id: str) -> TodayWeekAgendaResponse:
        self.calls.append(user_id)
        if self.unavailable:
            raise TodayWeekAgendaUnavailableError("Full week is unavailable.")
        start = date(2026, 8, 10)
        state = TodayWeekAgendaSourceState(status="current")
        return TodayWeekAgendaResponse(
            contract_version="today-week-agenda-v1",
            origin="authenticated_backend",
            generated_at=datetime(2026, 8, 15, 10, tzinfo=UTC),
            timezone="Europe/Berlin",
            local_today=date(2026, 8, 15),
            week_starts_on=start,
            week_ends_on=start + timedelta(days=6),
            days=[
                TodayWeekAgendaDay(local_date=start + timedelta(days=offset))
                for offset in range(7)
            ],
            source_states=TodayWeekAgendaSourceStates(
                setup=state,
                preparation=state,
                calendar=state,
                focus=state,
                tasks=state,
                habits=state,
                fixed_commitments=state,
            ),
        )


async def _request(*, authenticated: bool, unavailable: bool = False):
    app = create_app()
    service = Service(unavailable=unavailable)
    override_dependency(app, get_token_verifier, Verifier())
    override_dependency(app, get_today_week_agenda_service, service)
    headers = {"Authorization": "Bearer week-token"} if authenticated else {}
    async with httpx.AsyncClient(
        transport=httpx.ASGITransport(app=app),
        base_url="http://test",
    ) as client:
        response = await client.get("/v1/today/week-agenda", headers=headers)
    return response, service


def test_week_agenda_route_is_read_only_and_bearer_scoped() -> None:
    response, service = asyncio.run(_request(authenticated=True))
    assert response.status_code == 200
    assert response.json()["contract_version"] == "today-week-agenda-v1"
    assert len(response.json()["days"]) == 7
    assert service.calls == ["week-user"]

    blocked, blocked_service = asyncio.run(_request(authenticated=False))
    assert blocked.status_code == 401
    assert blocked_service.calls == []


def test_week_agenda_route_maps_profile_authority_failure_to_503() -> None:
    response, service = asyncio.run(
        _request(authenticated=True, unavailable=True),
    )

    assert response.status_code == 503
    assert response.json() == {"detail": "Full week is unavailable."}
    assert service.calls == ["week-user"]
