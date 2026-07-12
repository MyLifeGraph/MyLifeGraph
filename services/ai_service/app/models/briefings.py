from datetime import date, datetime
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field, model_serializer

from app.models.executable_actions import ExecutableActionTarget


DAILY_BRIEFING_CONTRACT_VERSION = "daily-briefing-v1"

BriefingMode = Literal["push", "steady", "recover", "plan"]
BriefingDataQuality = Literal["missing", "partial", "current", "stale"]
BriefingFreshness = Literal["missing", "current", "stale"]


class BriefingEvidenceRef(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, frozen=True)

    table: str = Field(min_length=1, max_length=64)
    id: str = Field(min_length=1, max_length=200)
    field: str = Field(min_length=1, max_length=200)


class BriefingAction(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, frozen=True)

    target: ExecutableActionTarget
    title: str = Field(min_length=1, max_length=200)
    reason: str = Field(min_length=1, max_length=300)
    recommendation_id: str | None = None
    evidence_refs: list[BriefingEvidenceRef] = Field(
        default_factory=list,
        max_length=8,
    )

    @model_serializer(mode="plain")
    def serialize_action(self) -> dict[str, object]:
        payload: dict[str, object] = {
            "target": self.target.model_dump(mode="json", exclude_none=True),
            "title": self.title,
            "reason": self.reason,
            "evidence_refs": [
                ref.model_dump(mode="json") for ref in self.evidence_refs
            ],
        }
        if self.recommendation_id is not None:
            payload["recommendation_id"] = self.recommendation_id
        return payload


class BriefingProvenance(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, frozen=True)

    engine: Literal["deterministic"]
    contract_version: Literal["daily-briefing-v1"]
    daily_state_contract_version: Literal["explainable-daily-state-v1"]
    executable_action_contract_version: Literal["executable-action-v1"]
    source_snapshot_id: str
    source_snapshot_generated_at: datetime
    baseline: Literal["none"]
    llm_used: Literal[False]
    feedback_ranking: "FeedbackRankingProvenance"


class FeedbackRankingProvenance(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, frozen=True)

    contract_version: Literal["feedback-ranking-v1"]
    lookback_days: Literal[28]
    event_count: int = Field(ge=0, le=200)
    applied_count: int = Field(ge=0, le=200)
    primary_contribution: int = Field(ge=-240, le=120)
    reasons: list[str] = Field(default_factory=list, max_length=4)


class DailyBriefing(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, frozen=True)

    id: str
    briefing_date: date
    mode: BriefingMode
    data_quality: BriefingDataQuality
    capacity_minutes: int | None = Field(default=None, ge=1, le=480)
    capacity_note: str = Field(min_length=1, max_length=240)
    summary: str = Field(min_length=1, max_length=400)
    primary_action: BriefingAction
    support_actions: list[BriefingAction] = Field(
        default_factory=list,
        max_length=2,
    )
    evidence_refs: list[BriefingEvidenceRef] = Field(
        default_factory=list,
        max_length=20,
    )
    provenance: BriefingProvenance
    generated_at: datetime
    updated_at: datetime


class BriefingReadResponse(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True)

    contract_version: Literal["daily-briefing-v1"]
    briefing_date: date
    freshness: BriefingFreshness
    needs_generation: bool
    stale_reasons: list[str] = Field(default_factory=list, max_length=8)
    briefing: DailyBriefing | None


class BriefingGenerateRequest(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True)

    force: bool = False


BriefingGenerateResponse = BriefingReadResponse
