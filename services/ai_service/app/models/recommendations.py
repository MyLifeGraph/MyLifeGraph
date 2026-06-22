from datetime import datetime
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field


RecommendationCategory = Literal["focus", "recovery", "movement", "planning"]
RecommendationPriority = Literal["low", "medium", "high", "critical"]
RecommendationStaleReason = Literal[
    "missing",
    "older_than_7_days",
    "period_mismatch",
]


class RecommendationMetadata(BaseModel):
    rule_id: str
    fingerprint: str
    evidence_refs: list[dict[str, str]] = Field(default_factory=list)
    period_key: str
    source_engine_version: str
    invalidation_dependencies: list[str] = Field(default_factory=list)
    deterministic_scores: dict[str, float] = Field(default_factory=dict)
    model: str | None = None


class RecommendationItem(BaseModel):
    id: str
    title: str
    reason: str
    action_label: str
    category: RecommendationCategory
    priority: RecommendationPriority
    confidence: float = Field(ge=0, le=1)
    generated_at: datetime
    metadata: RecommendationMetadata


class RecommendationListResponse(BaseModel):
    items: list[RecommendationItem] = Field(default_factory=list)
    needs_generation: bool
    generated_at: datetime | None
    period_key: str
    stale_reason: RecommendationStaleReason | None


class RecommendationGenerateRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    window_days: int = Field(default=28, ge=1, le=365)
    force: bool = False
    allow_llm_wording: bool = False


RecommendationGenerateResponse = RecommendationListResponse
