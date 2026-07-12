from datetime import UTC, datetime, timedelta
from typing import Any
from uuid import UUID

from app.models.feedback import (
    DECISION_FEEDBACK_CONTRACT_VERSION,
    DecisionFeedbackCreateRequest,
    DecisionFeedbackDeleteResponse,
    DecisionFeedbackListResponse,
    DecisionFeedbackResponse,
)
from app.repositories.feedback_repository import FeedbackRepository


class FeedbackConflictError(ValueError):
    pass


class FeedbackNotFoundError(ValueError):
    pass


class FeedbackService:
    def __init__(self, *, repository: FeedbackRepository) -> None:
        self._repository = repository

    async def create(
        self,
        *,
        user_id: str,
        request: DecisionFeedbackCreateRequest,
    ) -> DecisionFeedbackResponse:
        existing = await self._repository.get_by_request(
            user_id=user_id,
            request_id=request.request_id,
        )
        if existing is not None:
            if (
                existing.briefing_id == request.briefing_id
                and existing.action_id == request.action_id
                and existing.feedback_type == request.feedback_type
            ):
                return _response(existing)
            raise FeedbackConflictError("Feedback request id was already used.")

        briefing = await self._repository.get_briefing(
            user_id=user_id,
            briefing_id=request.briefing_id,
        )
        if briefing is None:
            raise FeedbackNotFoundError("Briefing is unavailable.")
        action = _find_action(briefing=briefing, action_id=request.action_id)
        target = action.get("target")
        if not isinstance(target, dict):
            raise ValueError("Persisted briefing action is invalid.")
        recommendation_id = action.get("recommendation_id")
        if recommendation_id is not None:
            recommendation = await self._repository.get_recommendation(
                user_id=user_id,
                recommendation_id=str(recommendation_id),
            )
            if recommendation is None:
                raise ValueError("Referenced recommendation is unavailable.")
        action_kind = target.get("kind")
        mode = briefing.get("mode")
        estimated_minutes = target.get("estimated_minutes")
        command = target.get("command")
        if not isinstance(action_kind, str) or not isinstance(mode, str):
            raise ValueError("Persisted briefing context is invalid.")
        feedback = await self._repository.insert(
            row={
                "user_id": user_id,
                "request_id": str(request.request_id),
                "briefing_id": str(request.briefing_id),
                "recommendation_id": recommendation_id,
                "action_id": request.action_id,
                "action_kind": action_kind,
                "feedback_type": request.feedback_type,
                "context_mode": mode,
                "estimated_minutes": estimated_minutes,
                "rule_key": str(command),
                "metadata": {
                    "contract_version": DECISION_FEEDBACK_CONTRACT_VERSION,
                    "briefing_date": str(briefing.get("briefing_date")),
                },
            },
        )
        return _response(feedback)

    async def list_recent(self, *, user_id: str) -> DecisionFeedbackListResponse:
        feedback = await self._repository.list_recent(
            user_id=user_id,
            since=datetime.now(UTC) - timedelta(days=28),
        )
        return DecisionFeedbackListResponse(
            contract_version=DECISION_FEEDBACK_CONTRACT_VERSION,
            feedback=feedback,
        )

    async def delete(
        self,
        *,
        user_id: str,
        feedback_id: UUID,
    ) -> DecisionFeedbackDeleteResponse:
        deleted = await self._repository.delete(
            user_id=user_id,
            feedback_id=feedback_id,
        )
        if not deleted:
            raise FeedbackNotFoundError("Feedback is unavailable.")
        return DecisionFeedbackDeleteResponse(
            contract_version=DECISION_FEEDBACK_CONTRACT_VERSION,
            deleted_id=feedback_id,
        )


def _find_action(*, briefing: dict[str, Any], action_id: str) -> dict[str, Any]:
    raw_actions = [briefing.get("primary_action")]
    support = briefing.get("support_actions")
    if isinstance(support, list):
        raw_actions.extend(support)
    for action in raw_actions:
        if not isinstance(action, dict):
            continue
        target = action.get("target")
        if isinstance(target, dict) and target.get("id") == action_id:
            return action
    raise FeedbackNotFoundError("Action is not part of the referenced briefing.")


def _response(feedback: Any) -> DecisionFeedbackResponse:
    return DecisionFeedbackResponse(
        contract_version=DECISION_FEEDBACK_CONTRACT_VERSION,
        feedback=feedback,
    )
