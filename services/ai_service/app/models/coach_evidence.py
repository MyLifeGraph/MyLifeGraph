from datetime import date, datetime
from typing import Literal, Self
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, model_validator


COACH_EVIDENCE_CONTRACT_VERSION = "coach-evidence-v1"

CoachEvidenceMode = Literal["patterns", "focus", "review"]
CoachEvidenceStatus = Literal["available", "empty", "partial"]
CoachEvidenceGranularity = Literal["week", "month", "quarter", "year"]
CoachEvidenceSourceName = Literal[
    "daily_capture",
    "focus_reflections",
    "habit_outcomes",
    "weekly_reviews",
    "task_lifecycle",
]
CoachEvidenceMetric = int | float | str | None


class CoachEvidenceWindow(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, frozen=True)

    starts_on: date
    ends_on: date
    horizon: Literal[
        "90_days",
        "1_year",
        "all_available",
        "selected_focus_with_90_day_baseline",
        "previous_two_full_iso_weeks",
    ]
    granularity: CoachEvidenceGranularity

    @model_validator(mode="after")
    def validate_dates(self) -> Self:
        if self.starts_on > self.ends_on:
            raise ValueError("Coach evidence window is inverted")
        return self


class CoachEvidenceSourceSummary(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, frozen=True)

    source: CoachEvidenceSourceName
    available_count: int = Field(ge=0)
    included_count: int = Field(ge=0)
    partial: bool

    @model_validator(mode="after")
    def validate_counts(self) -> Self:
        if self.included_count > self.available_count:
            raise ValueError("Coach evidence source counts are inconsistent")
        if not self.partial and self.included_count != self.available_count:
            raise ValueError("complete Coach evidence must include all rows")
        return self


class CoachEvidenceBucket(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, frozen=True)

    key: str = Field(min_length=1, max_length=20)
    starts_on: date
    ends_on: date
    metrics: dict[str, CoachEvidenceMetric] = Field(max_length=40)

    @model_validator(mode="after")
    def validate_dates(self) -> Self:
        if self.starts_on > self.ends_on:
            raise ValueError("Coach evidence bucket is inverted")
        return self


class CoachFocusEvidenceSelection(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, frozen=True)

    focus_session_id: UUID = Field(strict=False)
    status: Literal["completed", "abandoned"]
    local_started_at: datetime = Field(strict=False)
    planned_minutes: int = Field(ge=5, le=240)
    actual_minutes: int = Field(ge=0, le=90 * 24 * 60)
    focus_quality: int | None = Field(default=None, ge=1, le=5)
    useful_progress: int | None = Field(default=None, ge=1, le=5)
    obstacles: list[
        Literal[
            "tired",
            "distracted",
            "interrupted",
            "unclear_goal",
            "material_too_difficult",
            "session_too_long",
            "environment",
            "other",
        ]
    ] = Field(default_factory=list, max_length=2)

    @model_validator(mode="after")
    def validate_selection(self) -> Self:
        if self.local_started_at.utcoffset() is None:
            raise ValueError("selected Focus timestamp must be timezone-aware")
        if (self.focus_quality is None) != (self.useful_progress is None):
            raise ValueError("selected Focus ratings must be paired")
        return self


class CoachEvidenceDigest(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, frozen=True)

    contract_version: Literal["coach-evidence-v1"]
    mode: CoachEvidenceMode
    status: CoachEvidenceStatus
    generated_at: datetime = Field(strict=False)
    timezone: str = Field(min_length=1, max_length=100)
    window: CoachEvidenceWindow
    sources: list[CoachEvidenceSourceSummary] = Field(
        min_length=1,
        max_length=5,
    )
    buckets: list[CoachEvidenceBucket] = Field(max_length=24)
    summary_metrics: dict[str, CoachEvidenceMetric] = Field(max_length=50)
    selected_focus: CoachFocusEvidenceSelection | None = None
    limitations: list[str] = Field(min_length=1, max_length=8)
    evidence_fingerprint: str = Field(pattern=r"^[0-9a-f]{64}$")

    @model_validator(mode="after")
    def validate_digest(self) -> Self:
        if self.generated_at.utcoffset() is None:
            raise ValueError("Coach evidence generation timestamp must be aware")
        if self.mode == "focus" and self.selected_focus is None:
            raise ValueError("Focus evidence requires the selected session")
        if self.mode != "focus" and self.selected_focus is not None:
            raise ValueError("only Focus evidence may carry a selected session")
        partial = any(source.partial for source in self.sources)
        if (self.status == "partial") != partial:
            raise ValueError("Coach evidence partial status is inconsistent")
        if self.status == "empty" and self.buckets:
            raise ValueError("empty Coach evidence cannot carry buckets")
        return self
