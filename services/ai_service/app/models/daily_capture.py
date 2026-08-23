from datetime import date, datetime
from typing import Any, Literal
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, model_validator


DailyCaptureBranch = Literal["morning", "evening"]


class DailyCaptureExpectedCapture(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, frozen=True)

    capture_id: str = Field(min_length=1, max_length=160)
    captured_at: datetime = Field(strict=False)

    @model_validator(mode="after")
    def validate_timestamp(self) -> "DailyCaptureExpectedCapture":
        if self.captured_at.tzinfo is None:
            raise ValueError("captured_at must be timezone-aware")
        return self


class DailyCaptureWriteRequest(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, frozen=True)

    contract_version: Literal["daily-capture-write-v1"]
    request_id: UUID = Field(strict=False)
    expected_capture: DailyCaptureExpectedCapture | None
    capture: dict[str, Any]


class DailyCaptureWriteResponse(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, frozen=True)

    contract_version: Literal["daily-capture-write-v1"]
    entry_date: date = Field(strict=False)
    branch: DailyCaptureBranch
    capture_id: str = Field(min_length=1, max_length=160)
    captured_at: datetime = Field(strict=False)
    updated_at: datetime = Field(strict=False)
    replayed: bool

    @model_validator(mode="after")
    def validate_timestamps(self) -> "DailyCaptureWriteResponse":
        if self.captured_at.tzinfo is None or self.updated_at.tzinfo is None:
            raise ValueError("Capture response timestamps must be timezone-aware")
        return self
