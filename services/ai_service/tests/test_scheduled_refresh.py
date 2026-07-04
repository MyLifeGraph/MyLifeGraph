import asyncio
from datetime import date, datetime, timezone

import httpx

from app.api.routes import scheduled
from app.main import create_app
from app.models.recommendations import RecommendationListResponse
from app.models.scheduled import ScheduledRefreshRequest
from app.models.snapshots import SnapshotGenerateRequest, SnapshotGenerateResponse
from app.repositories.scheduled_refresh_repository import SupabaseScheduledRefreshRepository
from app.services.scheduled_refresh import ScheduledRefreshService


TODAY = date(2026, 7, 4)
NOW = datetime(2026, 7, 4, 9, tzinfo=timezone.utc)


class FakeScheduledRefreshRepository:
    def __init__(self, user_ids: list[str]) -> None:
        self.user_ids = user_ids
        self.calls: list[dict[str, object]] = []

    async def list_daily_refresh_user_ids(
        self,
        *,
        limit: int,
        target_date: date,
    ) -> list[str]:
        self.calls.append({"limit": limit, "target_date": target_date})
        return self.user_ids[:limit]


class FakeSnapshotAggregator:
    def __init__(self, failing_user_id: str | None = None) -> None:
        self.failing_user_id = failing_user_id
        self.calls: list[tuple[str, SnapshotGenerateRequest]] = []

    async def generate_snapshot(
        self,
        *,
        user_id: str,
        request: SnapshotGenerateRequest,
    ) -> SnapshotGenerateResponse:
        self.calls.append((user_id, request))
        if user_id == self.failing_user_id:
            raise RuntimeError("snapshot failed")
        return SnapshotGenerateResponse(
            snapshot_id=f"snapshot-{user_id}",
            scope=request.scope,
            period_key=request.target_date.isoformat() if request.target_date else "today",
            generated_at=NOW,
            summary={"user_id": user_id},
            signals={"input_counts": {"daily_logs": 1}},
        )


class FakeRecommendationEngine:
    def __init__(self) -> None:
        self.calls: list[tuple[str, object]] = []

    async def generate_recommendations(self, *, user_id: str, request):
        self.calls.append((user_id, request))
        return RecommendationListResponse(
            items=[],
            needs_generation=False,
            generated_at=NOW,
            period_key="2026-W27",
            stale_reason=None,
        )


class FakeSupabaseClient:
    def __init__(self) -> None:
        self.select_calls = []

    async def select(self, table: str, *, params):
        self.select_calls.append((table, params))
        if table == "profiles":
            if params.get("offset") != "0":
                return []
            return [
                {"id": "missing-daily-1"},
                {"id": "has-daily-1"},
                {"id": ""},
                {"id": None},
                {"id": "missing-daily-2"},
            ]
        if table == "user_state_snapshots" and params.get("user_id"):
            return [{"user_id": "has-daily-1"}]
        if table == "user_state_snapshots":
            return [
                {"user_id": "has-daily-1"},
                {"user_id": "oldest-daily-1"},
                {"user_id": "oldest-daily-2"},
            ]
        return []


def run(coro):
    return asyncio.run(coro)


def test_scheduled_refresh_service_refreshes_each_listed_user() -> None:
    repository = FakeScheduledRefreshRepository(["user-1", "user-2"])
    snapshot_aggregator = FakeSnapshotAggregator()
    service = ScheduledRefreshService(
        repository=repository,
        snapshot_aggregator=snapshot_aggregator,
        today_provider=lambda: TODAY,
    )

    response = run(
        service.refresh_daily(
            ScheduledRefreshRequest(target_date=TODAY, window_days=7, limit=10),
        ),
    )

    assert repository.calls == [{"limit": 10, "target_date": TODAY}]
    assert response.processed == 2
    assert response.succeeded == 2
    assert response.failed == 0
    assert [call[0] for call in snapshot_aggregator.calls] == ["user-1", "user-2"]
    assert all(call[1].scope == "daily" for call in snapshot_aggregator.calls)
    assert all(call[1].target_date == TODAY for call in snapshot_aggregator.calls)


def test_scheduled_refresh_service_uses_resolved_today_for_snapshots() -> None:
    snapshot_aggregator = FakeSnapshotAggregator()
    service = ScheduledRefreshService(
        repository=FakeScheduledRefreshRepository(["user-1"]),
        snapshot_aggregator=snapshot_aggregator,
        today_provider=lambda: TODAY,
    )

    response = run(service.refresh_daily(ScheduledRefreshRequest()))

    assert response.target_date == TODAY
    assert snapshot_aggregator.calls[0][1].target_date == TODAY


def test_scheduled_refresh_service_continues_after_user_failure() -> None:
    service = ScheduledRefreshService(
        repository=FakeScheduledRefreshRepository(["user-1", "user-2"]),
        snapshot_aggregator=FakeSnapshotAggregator(failing_user_id="user-1"),
        today_provider=lambda: TODAY,
    )

    response = run(service.refresh_daily(ScheduledRefreshRequest()))

    assert response.processed == 2
    assert response.succeeded == 1
    assert response.failed == 1
    failed = next(result for result in response.results if result.status == "failed")
    assert failed.user_id == "user-1"
    assert failed.error == "RuntimeError"


def test_scheduled_refresh_service_can_refresh_recommendations_without_llm_wording() -> None:
    recommendation_engine = FakeRecommendationEngine()
    service = ScheduledRefreshService(
        repository=FakeScheduledRefreshRepository(["user-1"]),
        snapshot_aggregator=FakeSnapshotAggregator(),
        recommendation_engine=recommendation_engine,
        today_provider=lambda: TODAY,
    )

    response = run(
        service.refresh_daily(
            ScheduledRefreshRequest(
                include_recommendations=True,
                recommendation_window_days=21,
            ),
        ),
    )

    assert response.succeeded == 1
    assert response.results[0].recommendation_count == 0
    assert recommendation_engine.calls[0][0] == "user-1"
    recommendation_request = recommendation_engine.calls[0][1]
    assert recommendation_request.window_days == 21
    assert recommendation_request.force is False
    assert recommendation_request.allow_llm_wording is False


def test_scheduled_refresh_repository_prioritizes_missing_then_oldest_daily_snapshots() -> None:
    client = FakeSupabaseClient()
    repository = SupabaseScheduledRefreshRepository(client)

    user_ids = run(repository.list_daily_refresh_user_ids(limit=4, target_date=TODAY))

    assert user_ids == [
        "missing-daily-1",
        "missing-daily-2",
        "has-daily-1",
        "oldest-daily-1",
    ]
    assert client.select_calls == [
        (
            "profiles",
            {
                "select": "id",
                "onboarding_completed_at": "not.is.null",
                "role": "neq.guest",
                "order": "created_at.asc,id.asc",
                "limit": "100",
                "offset": "0",
            },
        ),
        (
            "user_state_snapshots",
            {
                "select": "user_id",
                "user_id": "in.(missing-daily-1,has-daily-1,missing-daily-2)",
                "scope": "eq.daily",
                "period_key": "eq.2026-07-04",
                "limit": "3",
            },
        ),
        (
            "user_state_snapshots",
            {
                "select": "user_id",
                "scope": "eq.daily",
                "order": "generated_at.asc",
                "limit": "4",
            },
        ),
    ]


async def request(
    method: str,
    url: str,
    *,
    headers: dict[str, str] | None = None,
    json: dict[str, object] | None = None,
    service: ScheduledRefreshService | None = None,
) -> httpx.Response:
    app = create_app()
    if service is not None:
        app.state.scheduled_refresh_service = service
    transport = httpx.ASGITransport(app=app)
    async with httpx.AsyncClient(
        transport=transport,
        base_url="http://testserver",
    ) as client:
        return await client.request(method, url, headers=headers, json=json)


def test_scheduled_refresh_endpoint_requires_configured_token() -> None:
    original_token = scheduled.settings.scheduled_refresh_token
    scheduled.settings.scheduled_refresh_token = ""
    try:
        response = run(request("POST", "/v1/scheduled/daily-refresh", json={}))
    finally:
        scheduled.settings.scheduled_refresh_token = original_token

    assert response.status_code == 503


def test_scheduled_refresh_endpoint_rejects_wrong_token() -> None:
    original_token = scheduled.settings.scheduled_refresh_token
    scheduled.settings.scheduled_refresh_token = "test-scheduled-token"
    try:
        response = run(
            request(
                "POST",
                "/v1/scheduled/daily-refresh",
                headers={"X-Scheduled-Refresh-Token": "wrong"},
                json={},
            ),
        )
    finally:
        scheduled.settings.scheduled_refresh_token = original_token

    assert response.status_code == 401


def test_scheduled_refresh_endpoint_runs_injected_service() -> None:
    original_token = scheduled.settings.scheduled_refresh_token
    scheduled.settings.scheduled_refresh_token = "test-scheduled-token"
    service = ScheduledRefreshService(
        repository=FakeScheduledRefreshRepository(["user-1"]),
        snapshot_aggregator=FakeSnapshotAggregator(),
        today_provider=lambda: TODAY,
    )
    try:
        response = run(
            request(
                "POST",
                "/v1/scheduled/daily-refresh",
                headers={"X-Scheduled-Refresh-Token": "test-scheduled-token"},
                json={"target_date": "2026-07-04", "limit": 5},
                service=service,
            ),
        )
    finally:
        scheduled.settings.scheduled_refresh_token = original_token

    assert response.status_code == 200
    body = response.json()
    assert body["target_date"] == "2026-07-04"
    assert body["processed"] == 1
    assert body["succeeded"] == 1
    assert body["failed"] == 0
