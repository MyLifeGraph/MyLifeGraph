from datetime import date
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field


ScheduledRefreshStatus = Literal["succeeded", "failed"]


class ScheduledRefreshRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    target_date: date | None = None
    window_days: int = Field(default=7, ge=1, le=90)
    limit: int = Field(default=100, ge=1, le=500)
    include_recommendations: bool = False
    recommendation_window_days: int = Field(default=28, ge=1, le=365)


class ScheduledUserRefreshResult(BaseModel):
    model_config = ConfigDict(extra="forbid")

    user_id: str
    status: ScheduledRefreshStatus
    snapshot_id: str | None = None
    period_key: str | None = None
    recommendation_count: int | None = None
    error: str | None = None


class ScheduledRefreshResponse(BaseModel):
    model_config = ConfigDict(extra="forbid")

    target_date: date
    processed: int
    succeeded: int
    failed: int
    results: list[ScheduledUserRefreshResult] = Field(default_factory=list)
