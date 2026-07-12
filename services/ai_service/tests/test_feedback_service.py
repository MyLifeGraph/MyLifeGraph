import asyncio
from datetime import UTC, datetime
from uuid import UUID

import pytest

from app.models.feedback import DecisionFeedback, DecisionFeedbackCreateRequest
from app.services.feedback_service import (
    FeedbackConflictError,
    FeedbackNotFoundError,
    FeedbackService,
)


USER_ID = "user-123"
BRIEFING_ID = UUID("11111111-1111-4111-8111-111111111111")
REQUEST_ID = UUID("22222222-2222-4222-8222-222222222222")
FEEDBACK_ID = UUID("33333333-3333-4333-8333-333333333333")
ACTION_ID = "open_task:44444444-4444-4444-8444-444444444444"


class FakeRepository:
    def __init__(self) -> None:
        self.existing = None
        self.inserted = []
        self.deleted = True
        self.briefing = {
            "id": str(BRIEFING_ID),
            "briefing_date": "2026-07-12",
            "mode": "steady",
            "primary_action": {
                "target": {
                    "id": ACTION_ID,
                    "kind": "task",
                    "command": "open_task",
                    "estimated_minutes": 30,
                },
                "recommendation_id": None,
            },
            "support_actions": [],
        }

    async def get_by_request(self, **_):
        return self.existing

    async def get_briefing(self, **_):
        return self.briefing

    async def get_recommendation(self, **_):
        return {"id": "recommendation"}

    async def insert(self, *, row):
        self.inserted.append(row)
        return feedback()

    async def list_recent(self, **_):
        return [feedback()]

    async def delete(self, **_):
        return self.deleted


def feedback(*, feedback_type="too_much") -> DecisionFeedback:
    return DecisionFeedback(
        id=FEEDBACK_ID,
        request_id=REQUEST_ID,
        briefing_id=BRIEFING_ID,
        recommendation_id=None,
        action_id=ACTION_ID,
        action_kind="task",
        feedback_type=feedback_type,
        context_mode="steady",
        estimated_minutes=30,
        rule_key="open_task",
        created_at=datetime(2026, 7, 12, 8, tzinfo=UTC),
    )


def request(*, feedback_type="too_much") -> DecisionFeedbackCreateRequest:
    return DecisionFeedbackCreateRequest(
        request_id=REQUEST_ID,
        briefing_id=BRIEFING_ID,
        action_id=ACTION_ID,
        feedback_type=feedback_type,
    )


def test_create_derives_context_from_owned_briefing() -> None:
    repository = FakeRepository()
    service = FeedbackService(repository=repository)

    response = asyncio.run(service.create(user_id=USER_ID, request=request()))

    assert response.feedback.id == FEEDBACK_ID
    assert repository.inserted == [
        {
            "user_id": USER_ID,
            "request_id": str(REQUEST_ID),
            "briefing_id": str(BRIEFING_ID),
            "recommendation_id": None,
            "action_id": ACTION_ID,
            "action_kind": "task",
            "feedback_type": "too_much",
            "context_mode": "steady",
            "estimated_minutes": 30,
            "rule_key": "open_task",
            "metadata": {
                "contract_version": "decision-feedback-v1",
                "briefing_date": "2026-07-12",
            },
        },
    ]


def test_exact_request_replay_is_idempotent_but_changed_replay_conflicts() -> None:
    repository = FakeRepository()
    repository.existing = feedback()
    service = FeedbackService(repository=repository)

    replay = asyncio.run(service.create(user_id=USER_ID, request=request()))
    assert replay.feedback.id == FEEDBACK_ID
    assert repository.inserted == []

    with pytest.raises(FeedbackConflictError):
        asyncio.run(
            service.create(
                user_id=USER_ID,
                request=request(feedback_type="not_helpful"),
            ),
        )


def test_action_must_belong_to_owned_briefing() -> None:
    repository = FakeRepository()
    service = FeedbackService(repository=repository)
    invalid = request().model_copy(update={"action_id": "open_task:other"})

    with pytest.raises(FeedbackNotFoundError):
        asyncio.run(service.create(user_id=USER_ID, request=invalid))


def test_list_is_bounded_to_recent_window_and_delete_is_owner_scoped() -> None:
    repository = FakeRepository()
    service = FeedbackService(repository=repository)

    listed = asyncio.run(service.list_recent(user_id=USER_ID))
    assert listed.feedback == [feedback()]

    deleted = asyncio.run(service.delete(user_id=USER_ID, feedback_id=FEEDBACK_ID))
    assert deleted.deleted_id == FEEDBACK_ID

    repository.deleted = False
    with pytest.raises(FeedbackNotFoundError):
        asyncio.run(service.delete(user_id=USER_ID, feedback_id=FEEDBACK_ID))
