from datetime import datetime
from typing import Literal
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field


DECISION_FEEDBACK_CONTRACT_VERSION = "decision-feedback-v1"
FeedbackType = Literal[
    "done",
    "later",
    "not_helpful",
    "too_much",
    "does_not_fit",
]
ActionKind = Literal["task", "habit", "focus", "planning", "recovery", "capture"]
BriefingMode = Literal["push", "steady", "recover", "plan"]


class DecisionFeedbackCreateRequest(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True)

    request_id: UUID = Field(strict=False)
    briefing_id: UUID = Field(strict=False)
    action_id: str = Field(min_length=1, max_length=200)
    feedback_type: FeedbackType


class DecisionFeedback(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, frozen=True)

    id: UUID
    request_id: UUID
    briefing_id: UUID
    recommendation_id: UUID | None
    action_id: str = Field(min_length=1, max_length=200)
    action_kind: ActionKind
    feedback_type: FeedbackType
    context_mode: BriefingMode
    estimated_minutes: int | None = Field(default=None, ge=1, le=480)
    rule_key: str = Field(min_length=1, max_length=100)
    created_at: datetime


class DecisionFeedbackResponse(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True)

    contract_version: Literal["decision-feedback-v1"]
    feedback: DecisionFeedback


class DecisionFeedbackListResponse(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True)

    contract_version: Literal["decision-feedback-v1"]
    feedback: list[DecisionFeedback] = Field(default_factory=list, max_length=200)


class DecisionFeedbackDeleteResponse(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True)

    contract_version: Literal["decision-feedback-v1"]
    deleted_id: UUID
