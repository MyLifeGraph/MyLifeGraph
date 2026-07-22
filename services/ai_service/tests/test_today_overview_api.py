import asyncio
from datetime import UTC, date, datetime

import httpx

from app.api.deps.auth import Principal
from app.main import create_app
from app.models.today_overview import (
    TodayCheckIns,
    TodayOverviewResponse,
    TodayOverviewV2Response,
    TodayProgress,
    TodaySourceState,
    TodaySourceStates,
    TodaySourceStatesV2,
    TodayTasks,
    TodayTasksV2,
)


class Verifier:
    async def verify(self, token: str):
        return Principal(user_id="today-user") if token == "today-token" else None


class Service:
    def __init__(self) -> None:
        self.calls = []

    async def get_overview(self, *, user_id):
        self.calls.append(user_id)
        return TodayOverviewResponse(
            contract_version="today-overview-v1",
            origin="authenticated_backend",
            local_date=date(2026, 7, 21),
            timezone="Europe/Berlin",
            generated_at=datetime(2026, 7, 21, 8, tzinfo=UTC),
            check_ins=TodayCheckIns(
                morning_saved=True,
                evening_saved=False,
                completed_days_streak=4,
            ),
            progress=TodayProgress(completed=1, total=2),
            progress_unavailable_sources=[],
            timeline=[],
            tasks=TodayTasks(today=[], all=[]),
            habits=[],
            source_states=TodaySourceStates(
                **{
                    name: TodaySourceState(status="current")
                    for name in (
                        "check_ins",
                        "tasks",
                        "habits",
                        "setup_commitments",
                        "preparation",
                        "calendar_events",
                        "focus_sessions",
                    )
                },
            ),
        )

    async def get_overview_v2(self, *, user_id):
        self.calls.append(user_id)
        return TodayOverviewV2Response(
            contract_version="today-overview-v2",
            origin="authenticated_backend",
            local_date=date(2026, 7, 21),
            timezone="Europe/Berlin",
            generated_at=datetime(2026, 7, 21, 8, tzinfo=UTC),
            check_ins=TodayCheckIns(
                morning_saved=True,
                evening_saved=False,
                completed_days_streak=4,
            ),
            progress=TodayProgress(completed=1, total=2),
            progress_unavailable_sources=[],
            timeline=[],
            tasks=TodayTasksV2(today=[], all=[]),
            habits=[],
            source_states=TodaySourceStatesV2(
                **{
                    name: TodaySourceState(status="current")
                    for name in (
                        "check_ins",
                        "tasks",
                        "habits",
                        "setup_commitments",
                        "preparation",
                        "calendar_events",
                        "focus_sessions",
                        "planner",
                    )
                },
            ),
        )


async def _request(*, authenticated=True, path="/v1/today/overview"):
    app = create_app()
    service = Service()
    app.state.token_verifier = Verifier()
    app.state.today_overview_service = service
    headers = {"Authorization": "Bearer today-token"} if authenticated else {}
    async with httpx.AsyncClient(
        transport=httpx.ASGITransport(app=app),
        base_url="http://test",
    ) as client:
        response = await client.get(path, headers=headers)
    return response, service


def test_today_overview_is_read_only_bearer_scoped_and_exact() -> None:
    response, service = asyncio.run(_request())

    assert response.status_code == 200
    assert response.json()["contract_version"] == "today-overview-v1"
    assert response.json()["check_ins"] == {
        "morning_saved": True,
        "evening_saved": False,
        "completed_days_streak": 4,
    }
    assert service.calls == ["today-user"]

    unauthenticated, blocked_service = asyncio.run(_request(authenticated=False))
    assert unauthenticated.status_code == 401
    assert blocked_service.calls == []


def test_today_overview_v2_is_a_parallel_authenticated_read() -> None:
    response, service = asyncio.run(_request(path="/v1/today/overview-v2"))

    assert response.status_code == 200
    assert response.json()["contract_version"] == "today-overview-v2"
    assert response.json()["source_states"]["planner"] == {
        "status": "current",
        "message": None,
    }
    assert service.calls == ["today-user"]
