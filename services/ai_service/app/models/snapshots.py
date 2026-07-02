from datetime import date, datetime
from typing import Any, Literal

from pydantic import BaseModel, ConfigDict, Field


SnapshotScope = Literal["daily", "weekly"]


class SnapshotGenerateRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    scope: SnapshotScope = "daily"
    target_date: date | None = None
    window_days: int = Field(default=7, ge=1, le=90)


class SnapshotGenerateResponse(BaseModel):
    model_config = ConfigDict(extra="forbid")

    snapshot_id: str
    scope: SnapshotScope
    period_key: str
    generated_at: datetime
    summary: dict[str, Any]
    signals: dict[str, Any]
