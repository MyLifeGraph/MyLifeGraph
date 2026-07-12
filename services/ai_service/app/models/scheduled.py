from datetime import date, datetime
from typing import Literal
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field


ScheduledRefreshStatus = Literal["succeeded", "failed"]
ScheduledSelectionReason = Literal[
    "missing_snapshot",
    "missing_briefing",
    "stale_briefing",
    "invalid_timezone",
    "recommendation_refresh",
]
ScheduledSnapshotStatus = Literal["generated", "reused"]
ScheduledBriefingStatus = Literal["generated", "refreshed", "unchanged"]
ScheduledFailureStage = Literal[
    "profile_date",
    "snapshot",
    "briefing",
    "recommendations",
]


class ScheduledRefreshRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    target_date: date | None = None
    window_days: int = Field(default=7, ge=1, le=90)
    limit: int = Field(default=100, ge=1, le=500)
    profile_ids: list[UUID] = Field(default_factory=list, max_length=20)
    include_recommendations: bool = False
    recommendation_window_days: int = Field(default=28, ge=1, le=365)


class ScheduledUserRefreshResult(BaseModel):
    model_config = ConfigDict(extra="forbid")

    user_id: str
    status: ScheduledRefreshStatus
    briefing_date: date | None = None
    selection_reason: ScheduledSelectionReason | None = None
    snapshot_id: str | None = None
    period_key: str | None = None
    snapshot_status: ScheduledSnapshotStatus | None = None
    briefing_id: str | None = None
    briefing_status: ScheduledBriefingStatus | None = None
    recommendation_count: int | None = None
    failed_stage: ScheduledFailureStage | None = None
    error: str | None = None


class ScheduledRefreshResponse(BaseModel):
    model_config = ConfigDict(extra="forbid")

    run_at: datetime
    target_date: date | None
    processed: int
    succeeded: int
    failed: int
    results: list[ScheduledUserRefreshResult] = Field(default_factory=list)
