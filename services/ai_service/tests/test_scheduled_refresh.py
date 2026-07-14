import asyncio
from datetime import UTC, date, datetime
from types import SimpleNamespace
from uuid import UUID

import httpx
import pytest

from app.api.routes import scheduled
from app.main import create_app
from app.models.notifications import NotificationGenerationResult
from app.models.recommendations import RecommendationListResponse
from app.models.scheduled import ScheduledRefreshRequest
from app.repositories.scheduled_refresh_repository import (
    ScheduledRefreshTarget,
    SupabaseScheduledRefreshRepository,
)
from app.services.briefing_service import BriefingPreparationError
from app.services.scheduled_refresh import ScheduledRefreshService


RUN_AT = datetime(2026, 7, 12, 1, 30, tzinfo=UTC)
TODAY = date(2026, 7, 12)
LOS_ANGELES_TODAY = date(2026, 7, 11)
USER_1 = "11111111-1111-4111-8111-111111111111"
USER_2 = "22222222-2222-4222-8222-222222222222"
USER_3 = "33333333-3333-4333-8333-333333333333"
USER_4 = "44444444-4444-4444-8444-444444444444"
USER_5 = "55555555-5555-4555-8555-555555555555"
GUEST_USER = "66666666-6666-4666-8666-666666666666"
INCOMPLETE_USER = "77777777-7777-4777-8777-777777777777"


class FakeScheduledRefreshRepository:
    def __init__(self, targets: list[ScheduledRefreshTarget]) -> None:
        self.targets = targets
        self.calls: list[dict[str, object]] = []

    async def list_daily_refresh_targets(
        self,
        *,
        limit: int,
        run_at: datetime,
        target_date: date | None,
        profile_ids: list[str],
        include_current: bool,
        current_selection_reason: str,
    ) -> list[ScheduledRefreshTarget]:
        self.calls.append(
            {
                "limit": limit,
                "run_at": run_at,
                "target_date": target_date,
                "profile_ids": profile_ids,
                "include_current": include_current,
                "current_selection_reason": current_selection_reason,
            },
        )
        return self.targets[:limit]


class FakeBriefingService:
    def __init__(
        self,
        *,
        outcomes: dict[str, tuple[str, str]] | None = None,
        failures: dict[str, str] | None = None,
    ) -> None:
        self.outcomes = outcomes or {}
        self.failures = failures or {}
        self.calls: list[dict[str, object]] = []

    async def prepare_for_date(
        self,
        *,
        user_id: str,
        briefing_date: date,
        window_days: int,
    ):
        self.calls.append(
            {
                "user_id": user_id,
                "briefing_date": briefing_date,
                "window_days": window_days,
            },
        )
        failure_stage = self.failures.get(user_id)
        if failure_stage in {"snapshot", "briefing"}:
            raise BriefingPreparationError(
                stage=failure_stage,
                cause=RuntimeError(f"{failure_stage} failed"),
            )
        if failure_stage == "generic":
            raise RuntimeError("briefing failed")

        snapshot_status, briefing_status = self.outcomes.get(
            user_id,
            ("generated", "generated"),
        )
        briefing = SimpleNamespace(
            id=f"briefing-{user_id}",
            provenance=SimpleNamespace(source_snapshot_id=f"snapshot-{user_id}"),
        )
        return SimpleNamespace(
            response=SimpleNamespace(briefing=briefing),
            snapshot_status=snapshot_status,
            briefing_status=briefing_status,
        )


class FakeRecommendationEngine:
    def __init__(self, *, failing_users: set[str] | None = None) -> None:
        self.failing_users = failing_users or set()
        self.calls: list[tuple[str, object]] = []

    async def generate_recommendations(self, *, user_id: str, request):
        self.calls.append((user_id, request))
        if user_id in self.failing_users:
            raise RuntimeError("recommendation refresh failed")
        return RecommendationListResponse(
            items=[],
            needs_generation=False,
            generated_at=RUN_AT,
            period_key="2026-W28",
            stale_reason=None,
        )


class FakeNotificationGenerationService:
    def __init__(self, *, failing_users: set[str] | None = None) -> None:
        self.failing_users = failing_users or set()
        self.calls: list[dict[str, object]] = []

    async def generate_for_user(self, **kwargs):
        self.calls.append(kwargs)
        if kwargs["user_id"] in self.failing_users:
            raise RuntimeError("notification generation failed")
        return NotificationGenerationResult(
            status="created",
            category="focus_prompt",
            delivery_date=kwargs["delivery_date"],
            created_count=1,
            duplicate_count=0,
        )


class FakeSupabaseClient:
    def __init__(
        self,
        *,
        profiles: list[dict[str, object]],
        snapshots: list[dict[str, object]] | None = None,
        briefings: list[dict[str, object]] | None = None,
        notification_preferences: list[dict[str, object]] | None = None,
    ) -> None:
        self.profiles = profiles
        self.snapshots = snapshots or []
        self.briefings = briefings or []
        self.notification_preferences = notification_preferences or []
        self.select_calls: list[tuple[str, object]] = []

    async def select(self, table: str, *, params):
        self.select_calls.append((table, params))
        if table == "profiles":
            rows = [
                row
                for row in self.profiles
                if row.get("onboarding_completed_at") is not None
                and row.get("role") != "guest"
            ]
            if raw_ids := params.get("id"):
                selected_ids = _in_values(raw_ids)
                rows = [row for row in rows if row.get("id") in selected_ids]
            offset = int(params.get("offset", "0"))
            limit = int(params.get("limit", str(len(rows))))
            return [dict(row) for row in rows[offset : offset + limit]]
        if table == "user_state_snapshots":
            user_ids = _in_values(params["user_id"])
            period_keys = _in_values(params["period_key"])
            return [
                dict(row)
                for row in self.snapshots
                if row.get("user_id") in user_ids
                and row.get("period_key") in period_keys
                and row.get("scope", "daily") == "daily"
            ]
        if table == "daily_briefings":
            user_ids = _in_values(params["user_id"])
            briefing_dates = _in_values(params["briefing_date"])
            return [
                dict(row)
                for row in self.briefings
                if row.get("user_id") in user_ids
                and row.get("briefing_date") in briefing_dates
            ]
        if table == "notification_preferences":
            user_ids = _in_values(params["user_id"])
            return [
                {"user_id": row["user_id"]}
                for row in self.notification_preferences
                if row.get("user_id") in user_ids
                and row.get("in_app_delivery_enabled") is True
                and row.get("in_app_delivery_consent_version")
                == "in-app-notification-consent-v1"
            ]
        return []


def _profile(
    user_id: str,
    *,
    timezone_name: str = "UTC",
    role: str = "user",
    onboarded: bool = True,
) -> dict[str, object]:
    return {
        "id": user_id,
        "timezone": timezone_name,
        "role": role,
        "onboarding_completed_at": RUN_AT.isoformat() if onboarded else None,
        "created_at": RUN_AT.isoformat(),
    }


def _snapshot(
    user_id: str,
    target_date: date,
    *,
    snapshot_id: str | None = None,
    generated_at: str = "2026-07-12T00:15:00Z",
) -> dict[str, object]:
    return {
        "id": snapshot_id or f"snapshot-{user_id}",
        "user_id": user_id,
        "scope": "daily",
        "period_key": target_date.isoformat(),
        "generated_at": generated_at,
    }


def _briefing(
    user_id: str,
    briefing_date: date,
    *,
    source_snapshot_id: str | None = None,
    source_snapshot_generated_at: str = "2026-07-12T00:15:00+00:00",
) -> dict[str, object]:
    return {
        "id": f"briefing-{user_id}",
        "user_id": user_id,
        "briefing_date": briefing_date.isoformat(),
        "generated_at": "2026-07-12T00:20:00Z",
        "provenance": {
            "source_snapshot_id": source_snapshot_id or f"snapshot-{user_id}",
            "source_snapshot_generated_at": source_snapshot_generated_at,
        },
    }


def _in_values(value: str) -> set[str]:
    assert value.startswith("in.(") and value.endswith(")")
    contents = value[4:-1]
    return set(contents.split(",")) if contents else set()


def run(coro):
    return asyncio.run(coro)


def test_scheduled_service_uses_pinned_local_dates_and_reports_stage_results() -> None:
    targets = [
        ScheduledRefreshTarget(
            user_id=USER_1,
            briefing_date=TODAY,
            selection_reason="missing_snapshot",
        ),
        ScheduledRefreshTarget(
            user_id=USER_2,
            briefing_date=LOS_ANGELES_TODAY,
            selection_reason="stale_briefing",
        ),
    ]
    repository = FakeScheduledRefreshRepository(targets)
    briefing_service = FakeBriefingService(
        outcomes={USER_2: ("reused", "refreshed")},
    )
    recommendation_engine = FakeRecommendationEngine()
    service = ScheduledRefreshService(
        repository=repository,
        briefing_service=briefing_service,
        recommendation_engine=recommendation_engine,
        now_provider=lambda: RUN_AT,
    )

    response = run(
        service.refresh_daily(
            ScheduledRefreshRequest(
                window_days=9,
                limit=10,
                profile_ids=[UUID(USER_1), UUID(USER_2)],
            ),
        ),
    )

    assert repository.calls == [
        {
            "limit": 10,
            "run_at": RUN_AT,
            "target_date": None,
            "profile_ids": [USER_1, USER_2],
            "include_current": False,
            "current_selection_reason": "recommendation_refresh",
        },
    ]
    assert response.run_at == RUN_AT
    assert response.target_date is None
    assert response.processed == 2
    assert response.succeeded == 2
    assert response.failed == 0
    assert {
        call["user_id"]: (call["briefing_date"], call["window_days"])
        for call in briefing_service.calls
    } == {
        USER_1: (TODAY, 9),
        USER_2: (LOS_ANGELES_TODAY, 9),
    }
    results = {result.user_id: result for result in response.results}
    assert results[USER_1].briefing_date == TODAY
    assert results[USER_1].snapshot_id == f"snapshot-{USER_1}"
    assert results[USER_1].snapshot_status == "generated"
    assert results[USER_1].briefing_id == f"briefing-{USER_1}"
    assert results[USER_1].briefing_status == "generated"
    assert results[USER_1].period_key == TODAY.isoformat()
    assert results[USER_2].briefing_date == LOS_ANGELES_TODAY
    assert results[USER_2].snapshot_status == "reused"
    assert results[USER_2].briefing_status == "refreshed"
    assert recommendation_engine.calls == []


def test_scheduled_service_isolates_profile_snapshot_and_briefing_failures() -> None:
    targets = [
        ScheduledRefreshTarget(
            user_id=USER_1,
            briefing_date=None,
            selection_reason="invalid_timezone",
            error="ZoneInfoNotFoundError",
        ),
        ScheduledRefreshTarget(
            user_id=USER_2,
            briefing_date=TODAY,
            selection_reason="missing_snapshot",
        ),
        ScheduledRefreshTarget(
            user_id=USER_3,
            briefing_date=TODAY,
            selection_reason="missing_briefing",
        ),
        ScheduledRefreshTarget(
            user_id=USER_4,
            briefing_date=TODAY,
            selection_reason="stale_briefing",
        ),
    ]
    briefing_service = FakeBriefingService(
        failures={USER_2: "snapshot", USER_3: "briefing"},
        outcomes={USER_4: ("reused", "refreshed")},
    )
    service = ScheduledRefreshService(
        repository=FakeScheduledRefreshRepository(targets),
        briefing_service=briefing_service,
        now_provider=lambda: RUN_AT,
    )

    response = run(service.refresh_daily(ScheduledRefreshRequest()))

    assert response.processed == 4
    assert response.succeeded == 1
    assert response.failed == 3
    results = {result.user_id: result for result in response.results}
    assert results[USER_1].failed_stage == "profile_date"
    assert results[USER_1].error == "ZoneInfoNotFoundError"
    assert results[USER_1].briefing_date is None
    assert results[USER_2].failed_stage == "snapshot"
    assert results[USER_2].error == "RuntimeError"
    assert results[USER_3].failed_stage == "briefing"
    assert results[USER_3].error == "RuntimeError"
    assert results[USER_4].status == "succeeded"
    assert {call["user_id"] for call in briefing_service.calls} == {
        USER_2,
        USER_3,
        USER_4,
    }


def test_current_preparation_retries_recommendations_without_rewriting_briefing(
) -> None:
    target = ScheduledRefreshTarget(
        user_id=USER_1,
        briefing_date=TODAY,
        selection_reason="recommendation_refresh",
    )
    repository = FakeScheduledRefreshRepository([target])
    briefing_service = FakeBriefingService(
        outcomes={USER_1: ("reused", "unchanged")},
    )
    recommendation_engine = FakeRecommendationEngine(failing_users={USER_1})
    service = ScheduledRefreshService(
        repository=repository,
        briefing_service=briefing_service,
        recommendation_engine=recommendation_engine,
        now_provider=lambda: RUN_AT,
    )
    request = ScheduledRefreshRequest(
        include_recommendations=True,
        recommendation_window_days=21,
    )

    failed = run(service.refresh_daily(request))

    assert failed.failed == 1
    assert failed.results[0].failed_stage == "recommendations"
    assert failed.results[0].error == "RuntimeError"
    assert repository.calls[0]["include_current"] is True
    assert repository.calls[0]["current_selection_reason"] == (
        "recommendation_refresh"
    )
    assert briefing_service.calls[0]["briefing_date"] == TODAY
    recommendation_request = recommendation_engine.calls[0][1]
    assert recommendation_request.window_days == 21
    assert recommendation_request.force is False
    assert recommendation_request.allow_llm_wording is False

    recommendation_engine.failing_users.clear()
    retried = run(service.refresh_daily(request))

    assert retried.succeeded == 1
    assert retried.results[0].selection_reason == "recommendation_refresh"
    assert retried.results[0].snapshot_status == "reused"
    assert retried.results[0].briefing_status == "unchanged"
    assert retried.results[0].recommendation_count == 0
    assert len(briefing_service.calls) == 2
    assert len(recommendation_engine.calls) == 2
    assert repository.calls[1]["include_current"] is True


def test_current_preparation_generates_notifications_with_one_pinned_run_time() -> None:
    target = ScheduledRefreshTarget(
        user_id=USER_1,
        briefing_date=TODAY,
        selection_reason="notification_delivery",
    )
    repository = FakeScheduledRefreshRepository([target])
    notifications = FakeNotificationGenerationService()
    service = ScheduledRefreshService(
        repository=repository,
        briefing_service=FakeBriefingService(
            outcomes={USER_1: ("reused", "unchanged")},
        ),
        notification_generation_service=notifications,
        now_provider=lambda: RUN_AT,
    )

    response = run(
        service.refresh_daily(
            ScheduledRefreshRequest(include_notifications=True),
        ),
    )

    assert repository.calls[0]["include_current"] is True
    assert repository.calls[0]["current_selection_reason"] == (
        "notification_delivery"
    )
    assert notifications.calls == [
        {
            "user_id": USER_1,
            "delivery_date": TODAY,
            "run_at": RUN_AT,
        },
    ]
    result = response.results[0]
    assert result.notification_status == "created"
    assert result.notification_created_count == 1
    assert result.notification_duplicate_count == 0


def test_scheduled_service_rejects_naive_run_time() -> None:
    service = ScheduledRefreshService(
        repository=FakeScheduledRefreshRepository([]),
        briefing_service=FakeBriefingService(),
        now_provider=lambda: datetime(2026, 7, 12, 1, 30),
    )

    with pytest.raises(ValueError, match="include a timezone"):
        run(service.refresh_daily(ScheduledRefreshRequest()))


def test_scheduled_service_normalizes_run_time_to_utc() -> None:
    repository = FakeScheduledRefreshRepository([])
    service = ScheduledRefreshService(
        repository=repository,
        briefing_service=FakeBriefingService(),
        now_provider=lambda: datetime.fromisoformat("2026-07-12T03:30:00+02:00"),
    )

    response = run(service.refresh_daily(ScheduledRefreshRequest()))

    assert response.run_at == RUN_AT
    assert repository.calls[0]["run_at"] == RUN_AT


def test_repository_selects_local_missing_and_stale_targets_only() -> None:
    client = FakeSupabaseClient(
        profiles=[
            _profile(USER_1, timezone_name="Europe/Berlin"),
            _profile(USER_2, timezone_name="America/Los_Angeles"),
            _profile(USER_3),
            _profile(USER_4),
            _profile(USER_5, timezone_name="Not/A_Timezone"),
            _profile(GUEST_USER, role="guest"),
            _profile(INCOMPLETE_USER, onboarded=False),
        ],
        snapshots=[
            _snapshot(USER_2, LOS_ANGELES_TODAY),
            _snapshot(USER_3, TODAY),
            _snapshot(USER_4, TODAY),
        ],
        briefings=[
            _briefing(USER_3, TODAY, source_snapshot_id="different-snapshot"),
            _briefing(USER_4, TODAY),
        ],
    )
    repository = SupabaseScheduledRefreshRepository(client)

    targets = run(
        repository.list_daily_refresh_targets(
            limit=10,
            run_at=RUN_AT,
            target_date=None,
            profile_ids=[],
            include_current=False,
            current_selection_reason="recommendation_refresh",
        ),
    )

    assert [target.user_id for target in targets] == [
        USER_1,
        USER_2,
        USER_3,
        USER_5,
    ]
    by_user = {target.user_id: target for target in targets}
    assert by_user[USER_1].briefing_date == TODAY
    assert by_user[USER_1].selection_reason == "missing_snapshot"
    assert by_user[USER_2].briefing_date == LOS_ANGELES_TODAY
    assert by_user[USER_2].selection_reason == "missing_briefing"
    assert by_user[USER_3].selection_reason == "stale_briefing"
    assert by_user[USER_5].briefing_date is None
    assert by_user[USER_5].selection_reason == "invalid_timezone"
    assert by_user[USER_5].error == "ZoneInfoNotFoundError"
    assert USER_4 not in by_user
    assert GUEST_USER not in by_user
    assert INCOMPLETE_USER not in by_user
    assert client.select_calls[0] == (
        "profiles",
        {
            "select": "id,timezone",
            "onboarding_completed_at": "not.is.null",
            "role": "neq.guest",
            "order": "created_at.asc,id.asc",
            "limit": "100",
            "offset": "0",
        },
    )


def test_repository_selects_current_target_for_recommendation_retry() -> None:
    client = FakeSupabaseClient(
        profiles=[_profile(USER_4)],
        snapshots=[_snapshot(USER_4, TODAY)],
        briefings=[_briefing(USER_4, TODAY)],
    )
    repository = SupabaseScheduledRefreshRepository(client)

    normal_targets = run(
        repository.list_daily_refresh_targets(
            limit=10,
            run_at=RUN_AT,
            target_date=None,
            profile_ids=[],
            include_current=False,
            current_selection_reason="recommendation_refresh",
        ),
    )
    retry_targets = run(
        repository.list_daily_refresh_targets(
            limit=10,
            run_at=RUN_AT,
            target_date=None,
            profile_ids=[],
            include_current=True,
            current_selection_reason="recommendation_refresh",
        ),
    )

    assert normal_targets == []
    assert retry_targets == [
        ScheduledRefreshTarget(
            user_id=USER_4,
            briefing_date=TODAY,
            selection_reason="recommendation_refresh",
        ),
    ]


def test_repository_selects_only_consented_current_notification_targets() -> None:
    client = FakeSupabaseClient(
        profiles=[_profile(USER_1), _profile(USER_2), _profile(USER_3)],
        snapshots=[_snapshot(USER_1, TODAY), _snapshot(USER_2, TODAY)],
        briefings=[_briefing(USER_1, TODAY), _briefing(USER_2, TODAY)],
        notification_preferences=[
            {
                "user_id": USER_1,
                "in_app_delivery_enabled": True,
                "in_app_delivery_consent_version": (
                    "in-app-notification-consent-v1"
                ),
            },
            {
                "user_id": USER_2,
                "in_app_delivery_enabled": False,
                "in_app_delivery_consent_version": None,
            },
        ],
    )
    repository = SupabaseScheduledRefreshRepository(client)

    targets = run(
        repository.list_daily_refresh_targets(
            limit=10,
            run_at=RUN_AT,
            target_date=None,
            profile_ids=[],
            include_current=True,
            current_selection_reason="notification_delivery",
        ),
    )

    assert targets == [
        ScheduledRefreshTarget(
            user_id=USER_1,
            briefing_date=TODAY,
            selection_reason="notification_delivery",
        ),
        ScheduledRefreshTarget(
            user_id=USER_3,
            briefing_date=TODAY,
            selection_reason="missing_snapshot",
        ),
    ]
    preference_calls = [
        params
        for table, params in client.select_calls
        if table == "notification_preferences"
    ]
    assert preference_calls == [
        {
            "select": "user_id",
            "user_id": f"in.({USER_1},{USER_2},{USER_3})",
            "in_app_delivery_enabled": "eq.true",
            "in_app_delivery_consent_version": (
                "eq.in-app-notification-consent-v1"
            ),
            "limit": "3",
        },
    ]


def test_repository_profile_ids_are_bounded_to_eligible_requested_profiles() -> None:
    client = FakeSupabaseClient(
        profiles=[
            _profile(USER_1),
            _profile(USER_2),
            _profile(GUEST_USER, role="guest"),
            _profile(INCOMPLETE_USER, onboarded=False),
        ],
    )
    repository = SupabaseScheduledRefreshRepository(client)

    targets = run(
        repository.list_daily_refresh_targets(
            limit=10,
            run_at=RUN_AT,
            target_date=TODAY,
            profile_ids=[USER_2, GUEST_USER, INCOMPLETE_USER, USER_2],
            include_current=False,
            current_selection_reason="recommendation_refresh",
        ),
    )

    assert targets == [
        ScheduledRefreshTarget(
            user_id=USER_2,
            briefing_date=TODAY,
            selection_reason="missing_snapshot",
        ),
    ]
    assert client.select_calls[0][1]["id"] == (
        f"in.({USER_2},{GUEST_USER},{INCOMPLETE_USER})"
    )


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


@pytest.mark.parametrize(
    "body",
    [
        {"user_id": USER_1},
        {"profile_ids": ["not-a-uuid"]},
        {"profile_ids": [USER_1] * 21},
        {"target_date": TODAY.isoformat(), "include_notifications": True},
        {"unexpected": True},
    ],
)
def test_scheduled_refresh_endpoint_rejects_invalid_or_unbounded_body(body) -> None:
    original_token = scheduled.settings.scheduled_refresh_token
    scheduled.settings.scheduled_refresh_token = "test-scheduled-token"
    service = ScheduledRefreshService(
        repository=FakeScheduledRefreshRepository([]),
        briefing_service=FakeBriefingService(),
        now_provider=lambda: RUN_AT,
    )
    try:
        response = run(
            request(
                "POST",
                "/v1/scheduled/daily-refresh",
                headers={"X-Scheduled-Refresh-Token": "test-scheduled-token"},
                json=body,
                service=service,
            ),
        )
    finally:
        scheduled.settings.scheduled_refresh_token = original_token

    assert response.status_code == 422


def test_scheduled_refresh_endpoint_runs_injected_service_with_strict_response(
) -> None:
    original_token = scheduled.settings.scheduled_refresh_token
    scheduled.settings.scheduled_refresh_token = "test-scheduled-token"
    repository = FakeScheduledRefreshRepository(
        [
            ScheduledRefreshTarget(
                user_id=USER_1,
                briefing_date=TODAY,
                selection_reason="missing_snapshot",
            ),
        ],
    )
    service = ScheduledRefreshService(
        repository=repository,
        briefing_service=FakeBriefingService(),
        now_provider=lambda: RUN_AT,
    )
    try:
        response = run(
            request(
                "POST",
                "/v1/scheduled/daily-refresh",
                headers={"X-Scheduled-Refresh-Token": "test-scheduled-token"},
                json={
                    "target_date": TODAY.isoformat(),
                    "limit": 5,
                    "profile_ids": [USER_1],
                },
                service=service,
            ),
        )
    finally:
        scheduled.settings.scheduled_refresh_token = original_token

    assert response.status_code == 200
    body = response.json()
    assert body["run_at"] == RUN_AT.isoformat().replace("+00:00", "Z")
    assert body["target_date"] == TODAY.isoformat()
    assert body["processed"] == 1
    assert body["succeeded"] == 1
    assert body["failed"] == 0
    assert body["results"][0]["briefing_date"] == TODAY.isoformat()
    assert body["results"][0]["snapshot_status"] == "generated"
    assert body["results"][0]["briefing_status"] == "generated"
    assert repository.calls[0]["profile_ids"] == [USER_1]
