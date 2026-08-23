from datetime import date, datetime
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field, model_validator


SLEEP_RECOMMENDATION_CONTRACT_VERSION = "sleep-recommendation-v1"
SleepRecommendationStatus = Literal["disabled", "collecting", "unstable", "ready"]
SleepRecommendationReason = Literal[
    "analysis_disabled",
    "insufficient_eligible_days",
    "no_recurring_pattern",
    "insufficient_comparison_days",
    "mixed_morning_outcomes",
    "mixed_focus_outcomes",
    "temporally_unstable_pattern",
    "ready",
]


class SleepRecommendationWindow(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, frozen=True)

    rolling_days: Literal[90]
    starts_at: datetime
    ends_at: datetime
    local_starts_on: date
    local_ends_on: date

    @model_validator(mode="after")
    def validate_window(self) -> "SleepRecommendationWindow":
        if (
            self.starts_at.utcoffset() is None
            or self.ends_at.utcoffset() is None
            or self.starts_at >= self.ends_at
            or (self.ends_at - self.starts_at).total_seconds() != 90 * 86400
            or self.local_starts_on > self.local_ends_on
        ):
            raise ValueError("sleep recommendation window is invalid")
        return self


class SleepRecommendationSample(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, frozen=True)

    valid_nights: int = Field(ge=0, le=91)
    eligible_focus_days: int = Field(ge=0, le=91)
    rated_sessions: int = Field(ge=0, le=10_000)
    required_eligible_days: Literal[30]
    progress: str = Field(pattern=r"^[0-9]{1,2}/30$")

    @model_validator(mode="after")
    def validate_sample(self) -> "SleepRecommendationSample":
        if (
            self.eligible_focus_days > self.valid_nights
            or self.progress != f"{min(self.eligible_focus_days, 30)}/30"
        ):
            raise ValueError("sleep recommendation sample is inconsistent")
        return self


class SleepClockWindow(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, frozen=True)

    start_local_time: str = Field(pattern=r"^(?:[01][0-9]|2[0-3]):[0-5][0-9]$")
    end_local_time: str = Field(pattern=r"^(?:[01][0-9]|2[0-3]):[0-5][0-9]$")
    end_day_offset: Literal[0, 1]
    width_minutes: int = Field(ge=0, le=60)


class SleepDurationWindow(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, frozen=True)

    minimum_minutes: int = Field(ge=0, le=960)
    maximum_minutes: int = Field(ge=1, le=960)

    @model_validator(mode="after")
    def validate_range(self) -> "SleepDurationWindow":
        if self.maximum_minutes < self.minimum_minutes:
            raise ValueError("sleep duration window is reversed")
        if self.maximum_minutes - self.minimum_minutes > 60:
            raise ValueError("sleep duration window is too wide")
        return self


class SleepRecommendationEvidence(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, frozen=True)

    candidate_days: int = Field(ge=10, le=91)
    comparison_days: int = Field(ge=10, le=91)
    morning_readiness_median_delta: float = Field(ge=-9, le=9)
    sleep_quality_median_delta: float = Field(ge=-9, le=9)
    morning_energy_median_delta: float = Field(ge=-9, le=9)
    useful_progress_median_delta: float = Field(ge=-4, le=4)
    focus_quality_median_delta: float = Field(ge=-4, le=4)
    completion_rate_delta: float = Field(ge=-1, le=1)
    consistent_in_both_halves: Literal[True]


class SleepRecommendationReady(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, frozen=True)

    bedtime: SleepClockWindow
    wake_time: SleepClockWindow
    duration: SleepDurationWindow
    wake_day_offset: Literal[0, 1]
    raw_median_duration_minutes: int = Field(ge=1, le=960)
    median_confirmed_sleep_target_minutes: int = Field(ge=300, le=720)
    warning: Literal["below_confirmed_sleep_target"] | None
    evidence: SleepRecommendationEvidence
    evidence_fingerprint: str = Field(pattern=r"^[0-9a-f]{64}$")

    @model_validator(mode="after")
    def validate_warning(self) -> "SleepRecommendationReady":
        expected = (
            "below_confirmed_sleep_target"
            if self.raw_median_duration_minutes
            < self.median_confirmed_sleep_target_minutes
            else None
        )
        if self.warning != expected:
            raise ValueError("sleep target warning is inconsistent")
        return self


class SleepRecommendationResponse(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, frozen=True)

    contract_version: Literal["sleep-recommendation-v1"]
    status: SleepRecommendationStatus
    reason: SleepRecommendationReason
    generated_at: datetime
    timezone: str = Field(min_length=1, max_length=80)
    window: SleepRecommendationWindow
    sample: SleepRecommendationSample
    recommendation: SleepRecommendationReady | None
    summary: str = Field(min_length=1, max_length=320)
    limitations: list[str] = Field(max_length=8)

    @model_validator(mode="after")
    def validate_state(self) -> "SleepRecommendationResponse":
        if self.generated_at.utcoffset() is None:
            raise ValueError("sleep recommendation generation time must be aware")
        if self.status == "ready":
            if self.reason != "ready" or self.recommendation is None:
                raise ValueError("ready sleep recommendation is incomplete")
        elif self.reason == "ready" or self.recommendation is not None:
            raise ValueError("non-ready sleep recommendation contains a window")
        if self.status == "disabled" and self.reason != "analysis_disabled":
            raise ValueError("disabled sleep recommendation reason is invalid")
        if self.status == "collecting" and self.reason != "insufficient_eligible_days":
            raise ValueError("collecting sleep recommendation reason is invalid")
        if self.status == "unstable" and self.reason in {
            "analysis_disabled",
            "insufficient_eligible_days",
            "ready",
        }:
            raise ValueError("unstable sleep recommendation reason is invalid")
        return self
