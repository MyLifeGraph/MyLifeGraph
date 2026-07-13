import asyncio
from copy import deepcopy
from datetime import UTC, date, datetime
from typing import Any

import pytest

from app.models.snapshots import SnapshotGenerateResponse
from app.models.weekly_reviews import WeeklyReviewGenerateRequest
from app.repositories.weekly_review_repository import (
    WeeklyReviewContext,
    WeeklyReviewProfile,
    _weekly_review,
)
from app.services.weekly_review_service import (
    WeeklyReviewPeriodError,
    WeeklyReviewService,
)


NOW = datetime(2026, 7, 13, 8, tzinfo=UTC)
PERIOD = "2026-W28"


class FakeRepository:
    def __init__(self, *, context: WeeklyReviewContext | None = None) -> None:
        self.profile = WeeklyReviewProfile(timezone="Europe/Berlin", onboarded=True)
        self.context = context or weekly_context()
        self.review = None
        self.snapshot: dict[str, Any] | None = None
        self.persist_rows: list[dict[str, Any]] = []
        self.load_calls = []

    async def get_profile(self, *, user_id: str) -> WeeklyReviewProfile:
        assert user_id == "user-1"
        return self.profile

    async def get_weekly_review(self, *, user_id: str, period_key: str):
        assert user_id == "user-1"
        return self.review

    async def get_weekly_snapshot(self, *, user_id: str, period_key: str):
        assert user_id == "user-1"
        return self.snapshot

    async def load_context(self, **kwargs):
        self.load_calls.append(kwargs)
        return deepcopy(self.context)

    async def persist_weekly_review(self, *, user_id: str, period_key: str, row):
        assert user_id == "user-1"
        assert period_key == PERIOD
        self.persist_rows.append(deepcopy(row))
        self.review = _weekly_review({"id": "review-1", **row})
        return self.review


class FakeSnapshotAggregator:
    def __init__(self, repository: FakeRepository) -> None:
        self.repository = repository
        self.calls = []

    async def generate_snapshot(self, *, user_id: str, request):
        assert user_id == "user-1"
        self.calls.append(request)
        generated_at = datetime(2026, 7, 13, 8, 5, tzinfo=UTC)
        self.repository.snapshot = {
            "id": "snapshot-1",
            "period_key": PERIOD,
            "generated_at": generated_at.isoformat(),
            "metadata": {},
        }
        return SnapshotGenerateResponse(
            snapshot_id="snapshot-1",
            scope="weekly",
            period_key=PERIOD,
            generated_at=generated_at,
            summary={},
            signals={},
        )


def service(repository: FakeRepository) -> tuple[WeeklyReviewService, FakeSnapshotAggregator]:
    aggregator = FakeSnapshotAggregator(repository)
    return (
        WeeklyReviewService(
            repository=repository,
            snapshot_aggregator=aggregator,
            now_provider=lambda: NOW,
        ),
        aggregator,
    )


def weekly_context() -> WeeklyReviewContext:
    daily_snapshots = [daily_snapshot(day) for day in range(6, 13)]
    return WeeklyReviewContext(
        tasks=[
            {
                "id": "task-done",
                "title": "Finished task",
                "status": "done",
                "deadline": None,
                "completed_at": "2026-07-08T12:00:00+00:00",
                "cancelled_at": None,
                "metadata": {"goal_id": "goal-1"},
                "created_at": "2026-07-01T08:00:00+00:00",
                "updated_at": "2026-07-08T12:00:00+00:00",
            },
            {
                "id": "task-open",
                "title": "Still open",
                "status": "todo",
                "deadline": "2026-07-10T12:00:00+00:00",
                "completed_at": None,
                "cancelled_at": None,
                "metadata": {},
                "created_at": "2026-07-02T08:00:00+00:00",
                "updated_at": "2026-07-02T08:00:00+00:00",
            },
        ],
        goals=[
            {
                "id": "goal-1",
                "title": "Goal",
                "status": "active",
                "metadata": {},
                "created_at": "2026-06-01T08:00:00+00:00",
                "updated_at": "2026-06-01T08:00:00+00:00",
            },
        ],
        habits=[weekly_habit()],
        habit_logs=[
            habit_log("log-1", "2026-07-07", "completed"),
            habit_log("log-2", "2026-07-09", "completed"),
        ],
        focus_sessions=[
            {
                "id": "focus-1",
                "status": "completed",
                "started_at": "2026-07-08T10:00:00+00:00",
                "actual_minutes": 35,
                "metadata": {"entry_date": "2026-07-08"},
                "created_at": "2026-07-08T10:00:00+00:00",
                "updated_at": "2026-07-08T10:35:00+00:00",
            },
        ],
        daily_snapshots=daily_snapshots,
        feedback=[
            {
                "id": "feedback-1",
                "action_id": "log_habit:habit-1:2026-07-10",
                "action_kind": "habit",
                "feedback_type": "too_much",
                "context_mode": "steady",
                "rule_key": "log_habit",
                "created_at": "2026-07-10T12:00:00+00:00",
            },
        ],
    )


def weekly_habit() -> dict[str, Any]:
    return {
        "id": "habit-1",
        "title": "Walk",
        "frequency": "weekly",
        "target": 4,
        "active": True,
        "metadata": {
            "contract_version": "habit-v1",
            "cadence": "weekly_target",
            "lifecycle": "active",
            "started_on": "2026-06-01",
        },
        "created_at": "2026-06-01T08:00:00+00:00",
        "updated_at": "2026-07-01T08:00:00+00:00",
    }


def habit_log(row_id: str, entry_date: str, status: str) -> dict[str, Any]:
    return {
        "id": row_id,
        "habit_id": "habit-1",
        "entry_date": entry_date,
        "status": status,
        "value": 1 if status == "completed" else 0,
        "created_at": f"{entry_date}T18:00:00+00:00",
        "updated_at": f"{entry_date}T18:00:00+00:00",
    }


def daily_snapshot(day: int, *, mode: str = "steady") -> dict[str, Any]:
    entry_date = date(2026, 7, day).isoformat()
    return {
        "id": f"daily-{day}",
        "period_key": entry_date,
        "summary": {
            "daily_state": {
                "contract_version": "explainable-daily-state-v1",
                "target_date": entry_date,
                "mode": mode,
                "data_quality": "current",
            },
        },
        "generated_at": f"{entry_date}T20:00:00+00:00",
        "metadata": {},
    }


def test_generate_persists_exact_weekly_review_and_shrink_proposal() -> None:
    repository = FakeRepository()
    weekly_service, aggregator = service(repository)

    response = asyncio.run(
        weekly_service.generate(
            user_id="user-1",
            request=WeeklyReviewGenerateRequest(period_key=PERIOD, force=False),
        ),
    )

    assert response.freshness == "current"
    assert response.starts_on == date(2026, 7, 6)
    assert response.ends_on == date(2026, 7, 12)
    assert response.review is not None
    assert response.review.facts.tasks.model_dump() == {
        "completed": 1,
        "carried": 1,
        "overdue_carried": 1,
        "cancelled": 0,
        "goal_linked_completed": 1,
    }
    assert response.review.facts.habits.scheduled_opportunities == 4
    assert response.review.facts.habits.completed == 2
    assert response.review.facts.feedback.too_much == 1
    assert len(response.review.proposals) == 1
    proposal = response.review.proposals[0]
    assert proposal.operation == "shrink"
    assert proposal.application_mode == "direct_habit"
    assert proposal.change.before.cadence.weekly_target == 4
    assert proposal.change.after is not None
    assert proposal.change.after.cadence.weekly_target == 3
    assert proposal.change.model_dump(mode="json") == {
        "before": {
            "lifecycle": "active",
            "cadence": {
                "kind": "weekly_target",
                "weekly_target": 4,
                "scheduled_weekdays": [],
            },
        },
        "after": {
            "lifecycle": "active",
            "cadence": {
                "kind": "weekly_target",
                "weekly_target": 3,
                "scheduled_weekdays": [],
            },
        },
    }
    assert len(aggregator.calls) == 1
    assert aggregator.calls[0].scope == "weekly"
    assert aggregator.calls[0].target_date == date(2026, 7, 12)
    assert aggregator.calls[0].window_days == 7
    assert repository.persist_rows[0]["source_fingerprint"] == (
        response.review.provenance.source_fingerprint
    )
    assert repository.persist_rows[0]["proposals"][0]["change"]["after"] is not None


def test_current_generate_is_write_free_and_source_change_marks_stale() -> None:
    repository = FakeRepository()
    weekly_service, aggregator = service(repository)
    request = WeeklyReviewGenerateRequest(period_key=PERIOD, force=False)

    first = asyncio.run(weekly_service.generate(user_id="user-1", request=request))
    second = asyncio.run(weekly_service.generate(user_id="user-1", request=request))

    assert first.review is not None and second.review is not None
    assert first.review.id == second.review.id
    assert first.review.generated_at == second.review.generated_at
    assert len(aggregator.calls) == 1
    assert len(repository.persist_rows) == 1

    repository.context.habits[0]["metadata"]["irrelevant_note"] = "not-used"
    repository.context.daily_snapshots[0]["generated_at"] = (
        "2026-07-13T09:00:00+00:00"
    )
    still_current = asyncio.run(
        weekly_service.get_period(user_id="user-1", period_key=PERIOD),
    )
    assert still_current.freshness == "current"

    repository.context.habits[0]["target"] = 5
    stale = asyncio.run(weekly_service.get_period(user_id="user-1", period_key=PERIOD))
    assert stale.freshness == "stale"
    assert stale.needs_generation is True
    assert stale.stale_reasons == ["source_facts_changed"]


def test_deleting_all_source_facts_keeps_the_existing_review_visible_as_stale() -> None:
    repository = FakeRepository()
    weekly_service, aggregator = service(repository)
    request = WeeklyReviewGenerateRequest(period_key=PERIOD, force=False)
    generated = asyncio.run(
        weekly_service.generate(user_id="user-1", request=request),
    )
    assert generated.review is not None

    repository.context = WeeklyReviewContext([], [], [], [], [], [], [])

    stale = asyncio.run(
        weekly_service.get_period(user_id="user-1", period_key=PERIOD),
    )
    retry = asyncio.run(
        weekly_service.generate(user_id="user-1", request=request),
    )

    assert stale.freshness == "stale"
    assert stale.review is not None
    assert stale.review.id == generated.review.id
    assert stale.stale_reasons == ["source_facts_changed"]
    assert retry == stale
    assert len(aggregator.calls) == 1
    assert len(repository.persist_rows) == 1


def test_weekly_snapshot_identity_change_marks_review_stale() -> None:
    repository = FakeRepository()
    weekly_service, _ = service(repository)
    asyncio.run(
        weekly_service.generate(
            user_id="user-1",
            request=WeeklyReviewGenerateRequest(period_key=PERIOD, force=False),
        ),
    )
    assert repository.snapshot is not None
    repository.snapshot["generated_at"] = "2026-07-13T09:00:00+00:00"

    response = asyncio.run(
        weekly_service.get_period(user_id="user-1", period_key=PERIOD),
    )

    assert response.freshness == "stale"
    assert response.stale_reasons == ["source_snapshot_changed"]


def test_daily_opportunities_keep_outcomes_recovery_miss_and_unknown_distinct() -> None:
    context = weekly_context()
    context.habits[:] = [
        {
            **weekly_habit(),
            "frequency": "daily",
            "target": 1,
            "metadata": {
                "contract_version": "habit-v1",
                "cadence": "daily",
                "lifecycle": "active",
                "started_on": "2026-06-01",
            },
        },
    ]
    context.habit_logs[:] = [
        habit_log("log-completed", "2026-07-06", "completed"),
        habit_log("log-skipped", "2026-07-07", "skipped"),
    ]
    context.daily_snapshots[:] = [
        daily_snapshot(6),
        daily_snapshot(7),
        daily_snapshot(8, mode="recover"),
        # July 9 deliberately has no valid persisted Daily State.
        daily_snapshot(10),
        daily_snapshot(11),
        daily_snapshot(12),
    ]
    context.feedback.clear()
    repository = FakeRepository(context=context)
    weekly_service, _ = service(repository)

    response = asyncio.run(
        weekly_service.generate(
            user_id="user-1",
            request=WeeklyReviewGenerateRequest(period_key=PERIOD, force=False),
        ),
    )

    assert response.review is not None
    facts = response.review.facts.habits
    assert facts.scheduled_opportunities == 7
    assert facts.completed == 1
    assert facts.skipped == 1
    assert facts.recovery_open == 1
    assert facts.unknown == 1
    assert facts.missed == 3
    assert response.review.facts.recovery.observed_days == 6
    assert response.review.facts.recovery.recovery_days == 1
    assert response.review.proposals == []


def test_changed_definition_is_excluded_from_opportunities_and_proposals() -> None:
    context = weekly_context()
    context.habits[0]["updated_at"] = "2026-07-08T08:00:00+00:00"
    repository = FakeRepository(context=context)
    weekly_service, _ = service(repository)

    response = asyncio.run(
        weekly_service.generate(
            user_id="user-1",
            request=WeeklyReviewGenerateRequest(period_key=PERIOD, force=False),
        ),
    )

    assert response.review is not None
    assert response.review.facts.habits.stable_definitions == 0
    assert response.review.facts.habits.changed_definitions == 1
    assert response.review.facts.habits.scheduled_opportunities == 0
    assert response.review.proposals == []


def test_does_not_fit_is_staged_replace_and_setup_habit_never_direct() -> None:
    context = weekly_context()
    context.habits[0]["metadata"]["managed_by"] = "setup"
    context.feedback[0]["feedback_type"] = "does_not_fit"
    repository = FakeRepository(context=context)
    weekly_service, _ = service(repository)

    response = asyncio.run(
        weekly_service.generate(
            user_id="user-1",
            request=WeeklyReviewGenerateRequest(period_key=PERIOD, force=False),
        ),
    )

    assert response.review is not None
    proposal = response.review.proposals[0]
    assert proposal.operation == "replace"
    assert proposal.ownership == "setup"
    assert proposal.application_mode == "staged_only"
    assert proposal.change.after is None


def test_pause_uses_explicit_skips_and_never_plain_misses() -> None:
    context = weekly_context()
    context.habits[0].update(
        {
            "frequency": "daily",
            "target": 1,
            "metadata": {
                "contract_version": "habit-v1",
                "cadence": "daily",
                "lifecycle": "active",
                "started_on": "2026-06-01",
            },
        },
    )
    context.habit_logs[:] = [
        habit_log("skip-1", "2026-07-06", "skipped"),
        habit_log("skip-2", "2026-07-07", "skipped"),
    ]
    context.feedback.clear()
    repository = FakeRepository(context=context)
    weekly_service, _ = service(repository)

    response = asyncio.run(
        weekly_service.generate(
            user_id="user-1",
            request=WeeklyReviewGenerateRequest(period_key=PERIOD, force=False),
        ),
    )

    assert response.review is not None
    assert response.review.proposals[0].operation == "pause"
    assert response.review.proposals[0].application_mode == "direct_habit"
    assert response.review.proposals[0].change.after is not None
    assert response.review.proposals[0].change.after.lifecycle == "paused"

    context.habit_logs.clear()
    no_skip_repository = FakeRepository(context=context)
    no_skip_service, _ = service(no_skip_repository)
    no_skip = asyncio.run(
        no_skip_service.generate(
            user_id="user-1",
            request=WeeklyReviewGenerateRequest(period_key=PERIOD, force=False),
        ),
    )
    assert no_skip.review is not None
    assert all(item.operation != "pause" for item in no_skip.review.proposals)


def test_habit_feedback_requires_exact_kind_and_action_prefix() -> None:
    context = weekly_context()
    context.feedback[0]["action_kind"] = "task"
    repository = FakeRepository(context=context)
    weekly_service, _ = service(repository)

    response = asyncio.run(
        weekly_service.generate(
            user_id="user-1",
            request=WeeklyReviewGenerateRequest(period_key=PERIOD, force=False),
        ),
    )

    assert response.review is not None
    assert response.review.facts.feedback.too_much == 1
    assert all(item.operation != "shrink" for item in response.review.proposals)


def test_shrink_requires_all_seven_valid_daily_state_days() -> None:
    context = weekly_context()
    context.habit_logs[:] = [
        habit_log("done-1", "2026-07-06", "completed"),
        habit_log("done-2", "2026-07-07", "completed"),
        habit_log("done-3", "2026-07-08", "completed"),
        habit_log("done-4", "2026-07-09", "completed"),
    ]
    context.daily_snapshots.clear()
    repository = FakeRepository(context=context)
    weekly_service, _ = service(repository)

    response = asyncio.run(
        weekly_service.generate(
            user_id="user-1",
            request=WeeklyReviewGenerateRequest(period_key=PERIOD, force=False),
        ),
    )

    assert response.review is not None
    assert response.review.facts.habits.unknown == 0
    assert response.review.facts.recovery.observed_days == 0
    assert response.review.facts.feedback.too_much == 1
    assert all(item.operation != "shrink" for item in response.review.proposals)


def test_recovery_day_skips_do_not_trigger_pause() -> None:
    context = weekly_context()
    context.habits[0].update(
        {
            "frequency": "daily",
            "target": 1,
            "metadata": {
                "contract_version": "habit-v1",
                "cadence": "daily",
                "lifecycle": "active",
                "started_on": "2026-06-01",
            },
        },
    )
    context.habit_logs[:] = [
        habit_log("recovery-skip-1", "2026-07-06", "skipped"),
        habit_log("recovery-skip-2", "2026-07-07", "skipped"),
    ]
    context.daily_snapshots[:] = [
        daily_snapshot(6, mode="recover"),
        daily_snapshot(7, mode="recover"),
        *(daily_snapshot(day) for day in range(8, 13)),
    ]
    context.feedback.clear()
    repository = FakeRepository(context=context)
    weekly_service, _ = service(repository)

    response = asyncio.run(
        weekly_service.generate(
            user_id="user-1",
            request=WeeklyReviewGenerateRequest(period_key=PERIOD, force=False),
        ),
    )

    assert response.review is not None
    assert response.review.facts.habits.skipped == 2
    assert response.review.facts.recovery.recovery_days == 2
    assert response.review.facts.habits.recovery_open == 0
    assert (
        "explicit_habit_outcomes_overlap_recovery_days"
        in response.review.provenance.limitations
    )
    assert all(item.operation != "pause" for item in response.review.proposals)


def test_not_ready_is_returned_without_writes_for_incomplete_profile_or_no_evidence() -> None:
    repository = FakeRepository(context=WeeklyReviewContext([], [], [], [], [], [], []))
    weekly_service, aggregator = service(repository)

    no_evidence = asyncio.run(weekly_service.get_latest(user_id="user-1"))
    assert no_evidence.freshness == "not_ready"
    assert no_evidence.needs_generation is False

    repository.profile = WeeklyReviewProfile(timezone="Europe/Berlin", onboarded=False)
    not_onboarded = asyncio.run(
        weekly_service.generate(
            user_id="user-1",
            request=WeeklyReviewGenerateRequest(period_key=PERIOD, force=False),
        ),
    )
    assert not_onboarded.freshness == "not_ready"
    assert aggregator.calls == []
    assert repository.persist_rows == []


def test_only_latest_completed_local_iso_week_is_allowed() -> None:
    repository = FakeRepository()
    weekly_service, _ = service(repository)

    with pytest.raises(WeeklyReviewPeriodError):
        asyncio.run(
            weekly_service.get_period(user_id="user-1", period_key="2026-W27"),
        )


def test_local_week_uses_timezone_aware_dst_boundaries() -> None:
    repository = FakeRepository()
    repository.profile = WeeklyReviewProfile(
        timezone="Europe/Berlin",
        onboarded=True,
    )
    weekly_service = WeeklyReviewService(
        repository=repository,
        snapshot_aggregator=FakeSnapshotAggregator(repository),
        now_provider=lambda: datetime(2026, 3, 30, 8, tzinfo=UTC),
    )

    asyncio.run(weekly_service.get_latest(user_id="user-1"))

    call = repository.load_calls[0]
    assert call["starts_on"] == date(2026, 3, 23)
    assert call["ends_on"] == date(2026, 3, 29)
    assert call["starts_at"] == datetime(2026, 3, 22, 23, tzinfo=UTC)
    assert call["ends_at"] == datetime(2026, 3, 29, 22, tzinfo=UTC)


def test_latest_completed_week_uses_iso_year_across_calendar_boundary() -> None:
    repository = FakeRepository()
    weekly_service = WeeklyReviewService(
        repository=repository,
        snapshot_aggregator=FakeSnapshotAggregator(repository),
        now_provider=lambda: datetime(2027, 1, 4, 8, tzinfo=UTC),
    )

    response = asyncio.run(weekly_service.get_latest(user_id="user-1"))

    assert response.period_key == "2026-W53"
    assert response.starts_on == date(2026, 12, 28)
    assert response.ends_on == date(2027, 1, 3)
