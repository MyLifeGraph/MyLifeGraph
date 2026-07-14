from datetime import date, datetime
from typing import Literal
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, model_validator

from app.models.notifications import NotificationGenerationStatus


ScheduledRefreshStatus = Literal["succeeded", "failed"]
ScheduledSelectionReason = Literal[
    "missing_snapshot",
    "missing_briefing",
    "stale_briefing",
    "invalid_timezone",
    "recommendation_refresh",
    "notification_delivery",
]
ScheduledSnapshotStatus = Literal["generated", "reused"]
ScheduledBriefingStatus = Literal["generated", "refreshed", "unchanged"]
ScheduledFailureStage = Literal[
    "profile_date",
    "snapshot",
    "briefing",
    "recommendations",
    "notifications",
]


class ScheduledRefreshRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    target_date: date | None = None
    window_days: int = Field(default=7, ge=1, le=90)
    limit: int = Field(default=100, ge=1, le=500)
    profile_ids: list[UUID] = Field(default_factory=list, max_length=20)
    include_recommendations: bool = False
    recommendation_window_days: int = Field(default=28, ge=1, le=365)
    include_notifications: bool = False

    @model_validator(mode="after")
    def reject_notification_backfill(self) -> "ScheduledRefreshRequest":
        if self.include_notifications and self.target_date is not None:
            raise ValueError(
                "notification delivery is unavailable for target_date backfills",
            )
        return self


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
    notification_status: NotificationGenerationStatus | None = None
    notification_created_count: int | None = Field(default=None, ge=0, le=3)
    notification_duplicate_count: int | None = Field(default=None, ge=0, le=3)
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
