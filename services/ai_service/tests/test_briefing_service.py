import asyncio
from datetime import UTC, date, datetime

import pytest
from pydantic import ValidationError

from app.models.briefings import (
    BriefingGenerateRequest,
    BriefingReadResponse,
)
from app.models.snapshots import SnapshotGenerateResponse
from app.repositories.briefing_repository import (
    BriefingContext,
    _daily_briefing,
)
from app.services.briefing_service import (
    BriefingPreparationError,
    BriefingService,
)


NOW = datetime(2026, 7, 12, 8, 0, tzinfo=UTC)
TODAY = date(2026, 7, 12)


class FakeBriefingRepository:
    def __init__(self, context: BriefingContext) -> None:
        self.context = context
        self.briefing = None
        self.persist_calls = []
        self.timezone = "Europe/Berlin"
        self.timezone_calls = 0

    async def get_profile_timezone(self, *, user_id: str) -> str:
        assert user_id == "user-123"
        self.timezone_calls += 1
        return self.timezone

    async def get_daily_snapshot(self, *, user_id: str, briefing_date: date):
        assert user_id == "user-123"
        assert briefing_date == TODAY
        return self.context.snapshot

    async def get_daily_briefing(self, *, user_id: str, briefing_date: date):
        assert user_id == "user-123"
        assert briefing_date == TODAY
        return self.briefing

    async def load_context(self, *, user_id: str, briefing_date: date):
        assert user_id == "user-123"
        assert briefing_date == TODAY
        return self.context

    async def persist_daily_briefing(
        self,
        *,
        user_id: str,
        briefing_date: date,
        row,
    ):
        assert user_id == "user-123"
        assert briefing_date == TODAY
        self.persist_calls.append(row)
        persisted = {
            "id": "briefing-stable-id",
            "created_at": NOW.isoformat(),
            **row,
        }
        self.briefing = _daily_briefing(persisted)
        return self.briefing


class FakeSnapshotAggregator:
    def __init__(self, repository: FakeBriefingRepository) -> None:
        self.repository = repository
        self.calls = []

    async def generate_snapshot(self, *, user_id: str, request):
        self.calls.append((user_id, request))
        return None


class MissingSnapshotRepository(FakeBriefingRepository):
    def __init__(self, context: BriefingContext) -> None:
        super().__init__(context)
        self.snapshot_available = False

    async def get_daily_snapshot(self, *, user_id: str, briefing_date: date):
        assert user_id == "user-123"
        assert briefing_date == TODAY
        return self.context.snapshot if self.snapshot_available else None


class MaterializingSnapshotAggregator(FakeSnapshotAggregator):
    def __init__(self, repository: MissingSnapshotRepository) -> None:
        super().__init__(repository)
        self.repository = repository

    async def generate_snapshot(self, *, user_id: str, request):
        await super().generate_snapshot(user_id=user_id, request=request)
        self.repository.snapshot_available = True
        return SnapshotGenerateResponse(
            snapshot_id=str(self.repository.context.snapshot["id"]),
            scope=request.scope,
            period_key=TODAY.isoformat(),
            generated_at=NOW,
            summary={},
            signals={},
        )


class FailingSnapshotAggregator(FakeSnapshotAggregator):
    async def generate_snapshot(self, *, user_id: str, request):
        self.calls.append((user_id, request))
        raise OSError("snapshot unavailable")


class FailingPersistRepository(FakeBriefingRepository):
    async def persist_daily_briefing(
        self,
        *,
        user_id: str,
        briefing_date: date,
        row,
    ):
        raise LookupError("briefing persistence unavailable")


class ChangingSnapshotRepository(FakeBriefingRepository):
    def __init__(
        self,
        context: BriefingContext,
        *,
        keep_changing: bool = False,
    ) -> None:
        super().__init__(context)
        self.keep_changing = keep_changing
        self.change_count = 0

    async def persist_daily_briefing(
        self,
        *,
        user_id: str,
        briefing_date: date,
        row,
    ):
        briefing = await super().persist_daily_briefing(
            user_id=user_id,
            briefing_date=briefing_date,
            row=row,
        )
        if self.change_count > 0 and not self.keep_changing:
            return briefing
        self.change_count += 1
        self.context = context(
            snapshot_row=snapshot(
                snapshot_id=f"snapshot-concurrent-{self.change_count}",
                generated_at=NOW.replace(hour=8 + self.change_count),
            ),
        )
        return briefing


def snapshot(
    *,
    mode: str = "steady",
    data_quality: str = "current",
    snapshot_id: str = "snapshot-1",
    generated_at: datetime = NOW,
) -> dict:
    return {
        "id": snapshot_id,
        "period_key": TODAY.isoformat(),
        "generated_at": generated_at.isoformat(),
        "metadata": {"target_date": TODAY.isoformat()},
        "signals": {},
        "summary": {
            "daily_state": {
                "contract_version": "explainable-daily-state-v1",
                "target_date": TODAY.isoformat(),
                "mode": mode,
                "data_quality": data_quality,
                "freshness": {},
                "context": {},
                "risk_flags": [],
                "reason_codes": [],
                "reasons": [],
                "load_guidance": "maintain",
                "provenance": {
                    "kind": "deterministic",
                    "basis": "explicit_capture_v2",
                    "baseline": "none",
                    "history_claim": "current_state_only",
                },
            },
        },
    }


def context(
    *,
    snapshot_row: dict | None = None,
    tasks: list[dict] | None = None,
    goals: list[dict] | None = None,
    habits: list[dict] | None = None,
    habit_logs: list[dict] | None = None,
    recommendations: list[dict] | None = None,
) -> BriefingContext:
    return BriefingContext(
        snapshot=snapshot_row or snapshot(),
        tasks=tasks or [],
        goals=goals or [],
        habits=habits or [],
        habit_logs=habit_logs or [],
        recommendations=recommendations or [],
    )


def service_for(context_value: BriefingContext):
    repository = FakeBriefingRepository(context_value)
    aggregator = FakeSnapshotAggregator(repository)
    return (
        BriefingService(
            repository=repository,
            snapshot_aggregator=aggregator,
            now_provider=lambda: NOW,
        ),
        repository,
        aggregator,
    )


def run(coro):
    return asyncio.run(coro)


def test_get_today_is_read_only_and_reports_missing() -> None:
    service, repository, aggregator = service_for(context())

    response = run(service.get_today(user_id="user-123"))

    assert response.freshness == "missing"
    assert response.needs_generation is True
    assert response.briefing is None
    assert aggregator.calls == []
    assert repository.persist_calls == []


def test_prepare_for_date_leaves_a_current_briefing_unchanged() -> None:
    service, repository, aggregator = service_for(context())
    initial = run(
        service.generate_today(
            user_id="user-123",
            request=BriefingGenerateRequest(),
        ),
    )
    repository.persist_calls.clear()
    aggregator.calls.clear()
    repository.timezone_calls = 0

    prepared = run(
        service.prepare_for_date(
            user_id="user-123",
            briefing_date=TODAY,
        ),
    )

    assert prepared.response.freshness == "current"
    assert prepared.response.briefing is not None
    assert initial.briefing is not None
    assert prepared.response.briefing.id == initial.briefing.id
    assert prepared.snapshot_status == "reused"
    assert prepared.briefing_status == "unchanged"
    assert aggregator.calls == []
    assert repository.persist_calls == []
    assert repository.timezone_calls == 0


def test_prepare_for_date_generates_one_missing_snapshot() -> None:
    repository = MissingSnapshotRepository(context())
    aggregator = MaterializingSnapshotAggregator(repository)
    service = BriefingService(
        repository=repository,
        snapshot_aggregator=aggregator,
        now_provider=lambda: NOW,
    )

    prepared = run(
        service.prepare_for_date(
            user_id="user-123",
            briefing_date=TODAY,
            window_days=14,
        ),
    )

    assert prepared.snapshot_status == "generated"
    assert prepared.briefing_status == "generated"
    assert prepared.response.freshness == "current"
    assert len(aggregator.calls) == 1
    user_id, request = aggregator.calls[0]
    assert user_id == "user-123"
    assert request.scope == "daily"
    assert request.target_date == TODAY
    assert request.window_days == 14
    assert len(repository.persist_calls) == 1


def test_prepare_for_date_reuses_snapshot_when_briefing_is_missing() -> None:
    service, repository, aggregator = service_for(context())

    prepared = run(
        service.prepare_for_date(
            user_id="user-123",
            briefing_date=TODAY,
        ),
    )

    assert prepared.snapshot_status == "reused"
    assert prepared.briefing_status == "generated"
    assert prepared.response.freshness == "current"
    assert aggregator.calls == []
    assert len(repository.persist_calls) == 1


def test_prepare_for_date_reuses_snapshot_when_briefing_is_stale() -> None:
    service, repository, aggregator = service_for(context())
    run(
        service.generate_today(
            user_id="user-123",
            request=BriefingGenerateRequest(),
        ),
    )
    repository.context = context(
        snapshot_row=snapshot(
            snapshot_id="snapshot-refreshed",
            generated_at=NOW.replace(hour=9),
        ),
    )
    repository.persist_calls.clear()
    aggregator.calls.clear()

    prepared = run(
        service.prepare_for_date(
            user_id="user-123",
            briefing_date=TODAY,
        ),
    )

    assert prepared.snapshot_status == "reused"
    assert prepared.briefing_status == "refreshed"
    assert prepared.response.freshness == "current"
    assert prepared.response.briefing is not None
    assert (
        prepared.response.briefing.provenance.source_snapshot_id
        == "snapshot-refreshed"
    )
    assert aggregator.calls == []
    assert len(repository.persist_calls) == 1


def test_prepare_for_date_retries_one_post_persist_snapshot_race() -> None:
    repository = ChangingSnapshotRepository(context())
    aggregator = FakeSnapshotAggregator(repository)
    service = BriefingService(
        repository=repository,
        snapshot_aggregator=aggregator,
        now_provider=lambda: NOW,
    )

    prepared = run(
        service.prepare_for_date(
            user_id="user-123",
            briefing_date=TODAY,
        ),
    )

    assert prepared.response.freshness == "current"
    assert prepared.response.briefing is not None
    assert (
        prepared.response.briefing.provenance.source_snapshot_id
        == "snapshot-concurrent-1"
    )
    assert len(repository.persist_calls) == 2
    assert repository.change_count == 1
    assert aggregator.calls == []


def test_prepare_for_date_bounds_post_persist_convergence() -> None:
    repository = ChangingSnapshotRepository(context(), keep_changing=True)
    aggregator = FakeSnapshotAggregator(repository)
    service = BriefingService(
        repository=repository,
        snapshot_aggregator=aggregator,
        now_provider=lambda: NOW,
    )

    with pytest.raises(BriefingPreparationError) as error:
        run(
            service.prepare_for_date(
                user_id="user-123",
                briefing_date=TODAY,
            ),
        )

    assert error.value.stage == "briefing"
    assert error.value.error_type == "RuntimeError"
    assert len(repository.persist_calls) == 2
    assert repository.change_count == 2
    assert aggregator.calls == []


def test_prepare_for_date_reports_snapshot_stage_errors() -> None:
    repository = MissingSnapshotRepository(context())
    aggregator = FailingSnapshotAggregator(repository)
    service = BriefingService(
        repository=repository,
        snapshot_aggregator=aggregator,
        now_provider=lambda: NOW,
    )

    with pytest.raises(BriefingPreparationError) as error:
        run(
            service.prepare_for_date(
                user_id="user-123",
                briefing_date=TODAY,
            ),
        )

    assert error.value.stage == "snapshot"
    assert error.value.error_type == "OSError"
    assert error.value.snapshot_status is None
    assert error.value.snapshot_id is None
    assert isinstance(error.value.__cause__, OSError)
    assert len(aggregator.calls) == 1
    assert repository.persist_calls == []


def test_prepare_for_date_reports_briefing_stage_errors() -> None:
    repository = FailingPersistRepository(context())
    aggregator = FakeSnapshotAggregator(repository)
    service = BriefingService(
        repository=repository,
        snapshot_aggregator=aggregator,
        now_provider=lambda: NOW,
    )

    with pytest.raises(BriefingPreparationError) as error:
        run(
            service.prepare_for_date(
                user_id="user-123",
                briefing_date=TODAY,
            ),
        )

    assert error.value.stage == "briefing"
    assert error.value.error_type == "LookupError"
    assert error.value.snapshot_status == "reused"
    assert error.value.snapshot_id == "snapshot-1"
    assert isinstance(error.value.__cause__, LookupError)
    assert aggregator.calls == []


def test_generate_refreshes_snapshot_and_persists_one_strict_action() -> None:
    tasks = [
        {
            "id": "11111111-1111-4111-8111-111111111111",
            "title": "Submit the report",
            "status": "todo",
            "priority": "high",
            "deadline": "2026-07-12T17:00:00+00:00",
            "estimated_minutes": 45,
            "metadata": {},
        },
    ]
    service, repository, aggregator = service_for(context(tasks=tasks))

    response = run(
        service.generate_today(
            user_id="user-123",
            request=BriefingGenerateRequest(),
        ),
    )

    assert len(aggregator.calls) == 1
    user_id, request = aggregator.calls[0]
    assert user_id == "user-123"
    assert request.scope == "daily"
    assert request.target_date == TODAY
    assert request.window_days == 7
    assert response.freshness == "current"
    assert response.needs_generation is False
    assert response.briefing is not None
    assert response.briefing.id == "briefing-stable-id"
    assert response.briefing.primary_action.target.command == "open_task"
    assert response.briefing.primary_action.target.target_id == tasks[0]["id"]
    assert response.briefing.provenance.llm_used is False
    assert response.briefing.capacity_minutes is None
    assert len(response.briefing.support_actions) <= 2
    assert len(repository.persist_calls) == 1
    serialized = response.model_dump(mode="json")
    serialized_action = serialized["briefing"]["primary_action"]
    assert "recommendation_id" not in serialized_action
    assert None not in serialized_action["target"]["metadata"].values()
    assert serialized["briefing"]["capacity_minutes"] is None

    repeated = run(
        service.generate_today(
            user_id="user-123",
            request=BriefingGenerateRequest(),
        ),
    )
    assert repeated.briefing is not None
    assert repeated.briefing.id == "briefing-stable-id"
    assert len(aggregator.calls) == 1
    assert len(repository.persist_calls) == 1


def test_force_regenerates_a_current_briefing() -> None:
    service, repository, aggregator = service_for(context())
    run(
        service.generate_today(
            user_id="user-123",
            request=BriefingGenerateRequest(),
        ),
    )

    response = run(
        service.generate_today(
            user_id="user-123",
            request=BriefingGenerateRequest(force=True),
        ),
    )

    assert response.freshness == "current"
    assert len(aggregator.calls) == 2
    assert len(repository.persist_calls) == 2


@pytest.mark.parametrize("mode", ["push", "steady", "recover", "plan"])
def test_generation_preserves_each_daily_mode(mode: str) -> None:
    service, _, _ = service_for(context(snapshot_row=snapshot(mode=mode)))

    response = run(
        service.generate_today(
            user_id="user-123",
            request=BriefingGenerateRequest(),
        ),
    )

    assert response.briefing is not None
    assert response.briefing.mode == mode
    assert response.briefing.capacity_note


@pytest.mark.parametrize("data_quality", ["missing", "partial", "stale"])
def test_limited_data_quality_returns_a_conservative_capture(
    data_quality: str,
) -> None:
    service, _, _ = service_for(
        context(snapshot_row=snapshot(data_quality=data_quality)),
    )

    response = run(
        service.generate_today(
            user_id="user-123",
            request=BriefingGenerateRequest(),
        ),
    )

    assert response.briefing is not None
    assert response.briefing.data_quality == data_quality
    assert response.briefing.primary_action.target.command == "open_capture"


def test_briefing_models_reject_unknown_request_and_response_fields() -> None:
    with pytest.raises(ValidationError):
        BriefingGenerateRequest.model_validate(
            {"force": False, "user_id": "attacker-controlled"},
            strict=True,
        )

    with pytest.raises(ValidationError):
        BriefingReadResponse.model_validate(
            {
                "contract_version": "daily-briefing-v1",
                "briefing_date": TODAY,
                "freshness": "missing",
                "needs_generation": True,
                "stale_reasons": [],
                "briefing": None,
                "unexpected": True,
            },
            strict=True,
        )


def test_missing_state_prioritizes_capture_over_overdue_task() -> None:
    tasks = [
        {
            "id": "22222222-2222-4222-8222-222222222222",
            "title": "Old deadline",
            "status": "todo",
            "priority": "critical",
            "deadline": "2026-07-01T17:00:00+00:00",
            "estimated_minutes": 60,
            "metadata": {},
        },
    ]
    service, _, _ = service_for(
        context(
            snapshot_row=snapshot(mode="recover", data_quality="missing"),
            tasks=tasks,
        ),
    )

    response = run(
        service.generate_today(
            user_id="user-123",
            request=BriefingGenerateRequest(),
        ),
    )

    assert response.briefing is not None
    assert response.briefing.mode == "recover"
    assert response.briefing.primary_action.target.command == "open_capture"
    assert response.briefing.primary_action.target.metadata.route == (
        "/morning-calibration"
    )
    assert response.briefing.support_actions[0].target.command == "open_task"


def test_recover_mode_prefers_bounded_habit_to_large_noncritical_task() -> None:
    task_id = "33333333-3333-4333-8333-333333333333"
    habit_id = "44444444-4444-4444-8444-444444444444"
    service, _, _ = service_for(
        context(
            snapshot_row=snapshot(mode="recover", data_quality="current"),
            tasks=[
                {
                    "id": task_id,
                    "title": "Large backlog item",
                    "status": "todo",
                    "priority": "medium",
                    "deadline": None,
                    "estimated_minutes": 180,
                    "metadata": {},
                },
            ],
            habits=[
                {
                    "id": habit_id,
                    "title": "Take a short walk",
                    "frequency": "daily",
                    "target": 1,
                    "active": True,
                    "metadata": {
                        "contract_version": "habit-v1",
                        "cadence": "daily",
                        "lifecycle": "active",
                    },
                },
            ],
        ),
    )

    response = run(
        service.generate_today(
            user_id="user-123",
            request=BriefingGenerateRequest(),
        ),
    )

    assert response.briefing is not None
    assert response.briefing.primary_action.target.command == "log_habit"
    assert response.briefing.primary_action.target.target_id == habit_id


def test_completed_or_unscheduled_habits_are_not_candidates() -> None:
    completed_id = "55555555-5555-4555-8555-555555555555"
    unscheduled_id = "66666666-6666-4666-8666-666666666666"
    service, _, _ = service_for(
        context(
            habits=[
                {
                    "id": completed_id,
                    "title": "Already done",
                    "frequency": "daily",
                    "target": 1,
                    "active": True,
                    "metadata": {"cadence": "daily", "lifecycle": "active"},
                },
                {
                    "id": unscheduled_id,
                    "title": "Monday only",
                    "frequency": "daily",
                    "target": 1,
                    "active": True,
                    "metadata": {
                        "cadence": "weekdays",
                        "scheduled_weekdays": [1],
                        "lifecycle": "active",
                    },
                },
            ],
            habit_logs=[
                {
                    "id": "log-1",
                    "habit_id": completed_id,
                    "entry_date": TODAY.isoformat(),
                    "status": "completed",
                },
            ],
        ),
    )

    response = run(
        service.generate_today(
            user_id="user-123",
            request=BriefingGenerateRequest(),
        ),
    )

    assert response.briefing is not None
    assert response.briefing.primary_action.target.command == "open_capture"
    returned_ids = {
        response.briefing.primary_action.target.target_id,
        *(action.target.target_id for action in response.briefing.support_actions),
    }
    assert completed_id not in returned_ids
    assert unscheduled_id not in returned_ids


def test_get_reports_stale_when_source_snapshot_changes() -> None:
    service, repository, _ = service_for(context())
    run(
        service.generate_today(
            user_id="user-123",
            request=BriefingGenerateRequest(),
        ),
    )
    repository.context = context(
        snapshot_row=snapshot(
            snapshot_id="snapshot-2",
            generated_at=datetime(2026, 7, 12, 9, 0, tzinfo=UTC),
        ),
    )

    response = run(service.get_today(user_id="user-123"))

    assert response.freshness == "stale"
    assert response.needs_generation is True
    assert response.stale_reasons == [
        "daily_snapshot_changed",
        "daily_snapshot_refreshed",
    ]


def test_profile_timezone_determines_briefing_date() -> None:
    near_midnight = datetime(2026, 7, 11, 22, 30, tzinfo=UTC)
    repository = FakeBriefingRepository(context())
    aggregator = FakeSnapshotAggregator(repository)
    service = BriefingService(
        repository=repository,
        snapshot_aggregator=aggregator,
        now_provider=lambda: near_midnight,
    )

    response = run(service.get_today(user_id="user-123"))

    assert response.briefing_date == TODAY


def test_generate_today_resolves_the_briefing_date_once() -> None:
    before_local_midnight = datetime(2026, 7, 12, 21, 59, tzinfo=UTC)
    after_local_midnight = datetime(2026, 7, 12, 22, 1, tzinfo=UTC)
    now_calls = []

    def advancing_now() -> datetime:
        value = before_local_midnight if not now_calls else after_local_midnight
        now_calls.append(value)
        return value

    repository = FakeBriefingRepository(context())
    aggregator = FakeSnapshotAggregator(repository)
    service = BriefingService(
        repository=repository,
        snapshot_aggregator=aggregator,
        now_provider=advancing_now,
    )

    response = run(
        service.generate_today(
            user_id="user-123",
            request=BriefingGenerateRequest(),
        ),
    )

    assert response.briefing_date == TODAY
    assert response.briefing is not None
    assert response.briefing.briefing_date == TODAY
    assert repository.timezone_calls == 1
    assert len(now_calls) == 2
    assert len(aggregator.calls) == 1
    assert aggregator.calls[0][1].target_date == TODAY
    assert repository.persist_calls[0]["briefing_date"] == TODAY.isoformat()


def test_repeated_recent_feedback_changes_ranking_with_bounded_provenance() -> None:
    first_id = "77777777-7777-4777-8777-777777777777"
    second_id = "88888888-8888-4888-8888-888888888888"
    feedback_rows = [
        {
            "action_id": f"open_task:{first_id}",
            "action_kind": "task",
            "feedback_type": "not_helpful",
            "context_mode": "steady",
            "rule_key": "open_task",
            "created_at": NOW.isoformat(),
        }
        for _ in range(3)
    ]
    service, _, _ = service_for(
        BriefingContext(
            snapshot=snapshot(),
            tasks=[
                {
                    "id": first_id,
                    "title": "First task",
                    "status": "todo",
                    "priority": "high",
                    "deadline": None,
                    "estimated_minutes": 30,
                    "metadata": {},
                },
                {
                    "id": second_id,
                    "title": "Second task",
                    "status": "todo",
                    "priority": "medium",
                    "deadline": None,
                    "estimated_minutes": 30,
                    "metadata": {},
                },
            ],
            goals=[],
            habits=[],
            habit_logs=[],
            recommendations=[],
            feedback=feedback_rows,
        ),
    )

    response = run(
        service.generate_today(
            user_id="user-123",
            request=BriefingGenerateRequest(),
        ),
    )

    assert response.briefing is not None
    assert response.briefing.primary_action.target.target_id == second_id
    ranking = response.briefing.provenance.feedback_ranking
    assert ranking.contract_version == "feedback-ranking-v1"
    assert ranking.event_count == 3
    assert ranking.applied_count == 3
    assert ranking.primary_contribution == -135
    assert ranking.reasons == ["recent_not_helpful_feedback"]
    assert response.briefing.primary_action.reason == (
        "This open task is the strongest remaining executable option."
    )
