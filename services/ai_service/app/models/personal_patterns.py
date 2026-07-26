from datetime import date, datetime
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field, model_validator


PERSONAL_PATTERNS_CONTRACT_VERSION = "personal-patterns-v1"
PersonalPatternsStatus = Literal["disabled", "collecting", "emerging", "stable"]
PersonalPatternKind = Literal[
    "focus_timing",
    "sleep",
    "session_length_or_spacing",
]
PlannerPatternReason = Literal[
    "eligible",
    "analysis_disabled",
    "insufficient_ratings",
    "baseline_not_stable",
    "no_daytime_comparison",
    "coverage_too_low",
    "insufficient_distinct_days",
    "inconsistent_halves",
    "thresholds_not_met",
]
FocusTimeWindow = Literal["05-09", "09-13", "13-18", "18-23"]


class PersonalPatternsWindow(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, frozen=True)

    rolling_days: Literal[90]
    starts_at: datetime
    ends_at: datetime
    local_starts_on: date
    local_ends_on: date

    @model_validator(mode="after")
    def validate_window(self) -> "PersonalPatternsWindow":
        if (
            self.starts_at.utcoffset() is None
            or self.ends_at.utcoffset() is None
            or self.starts_at >= self.ends_at
            or (self.ends_at - self.starts_at).total_seconds() != 90 * 86400
            or self.local_starts_on > self.local_ends_on
        ):
            raise ValueError("personal pattern window is invalid")
        return self


class PersonalPatternsSample(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, frozen=True)

    terminal_sessions: int = Field(ge=0, le=10_000)
    rated_sessions: int = Field(ge=0, le=10_000)
    rated_local_days: int = Field(ge=0, le=90)
    rating_coverage: float = Field(ge=0, le=1)
    first_rated_local_date: date | None
    last_rated_local_date: date | None

    @model_validator(mode="after")
    def validate_sample(self) -> "PersonalPatternsSample":
        expected = (
            0.0
            if self.terminal_sessions == 0
            else self.rated_sessions / self.terminal_sessions
        )
        if (
            self.rated_sessions > self.terminal_sessions
            or abs(self.rating_coverage - expected) > 0.0001
            or (self.first_rated_local_date is None)
            != (self.last_rated_local_date is None)
            or (
                self.first_rated_local_date is not None
                and self.last_rated_local_date is not None
                and self.first_rated_local_date > self.last_rated_local_date
            )
        ):
            raise ValueError("personal pattern sample is inconsistent")
        return self


class PersonalPatternsBaseline(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, frozen=True)

    median_focus_quality: float = Field(ge=1, le=5)
    median_useful_progress: float = Field(ge=1, le=5)
    completion_rate: float = Field(ge=0, le=1)


class PersonalPatternEvidence(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, frozen=True)

    preferred_group: str = Field(min_length=1, max_length=80)
    comparison_group: str = Field(min_length=1, max_length=80)
    preferred_count: int = Field(ge=1, le=10_000)
    comparison_count: int = Field(ge=1, le=10_000)
    useful_progress_median_delta: float = Field(ge=-4, le=4)
    focus_quality_median_delta: float = Field(ge=-4, le=4)
    completion_rate_delta: float = Field(ge=-1, le=1)
    details: list[str] = Field(min_length=1, max_length=6)


class PersonalPattern(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, frozen=True)

    kind: PersonalPatternKind
    maturity: Literal["emerging", "stable"]
    title: str = Field(min_length=1, max_length=80)
    summary: str = Field(min_length=1, max_length=320)
    evidence: PersonalPatternEvidence


class LearnedFocusPlannerPreference(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, frozen=True)

    eligible: bool
    reason: PlannerPatternReason
    window: FocusTimeWindow | None
    window_label: str | None = Field(default=None, max_length=80)
    evidence_count: int = Field(ge=0, le=10_000)
    evidence_starts_on: date | None
    evidence_ends_on: date | None
    evidence_fingerprint: str | None = Field(
        default=None,
        pattern=r"^[0-9a-f]{64}$",
    )

    @model_validator(mode="after")
    def validate_preference(self) -> "LearnedFocusPlannerPreference":
        paired = (
            self.window,
            self.window_label,
            self.evidence_starts_on,
            self.evidence_ends_on,
            self.evidence_fingerprint,
        )
        if self.eligible:
            if self.reason != "eligible" or any(value is None for value in paired):
                raise ValueError("eligible learned preference is incomplete")
        elif self.reason == "eligible":
            raise ValueError("ineligible learned preference has eligible reason")
        if (self.evidence_starts_on is None) != (self.evidence_ends_on is None):
            raise ValueError("learned preference evidence dates are incomplete")
        return self


class PersonalPatternCorrelationPoint(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, frozen=True)

    local_date: date
    local_started_at: datetime
    focus_quality: int = Field(ge=1, le=5)
    useful_progress: int = Field(ge=1, le=5)
    planned_focus_minutes: int = Field(ge=5, le=240)
    actual_focus_minutes: int = Field(ge=0, le=90 * 24 * 60)
    completed: int = Field(ge=0, le=1)
    sleep_hours: float | None = Field(default=None, gt=0, le=16)
    sleep_target_deviation_minutes: int | None = Field(
        default=None,
        ge=-720,
        le=660,
    )
    sleep_quality: int | None = Field(default=None, ge=1, le=10)
    morning_energy: int | None = Field(default=None, ge=1, le=10)

    @model_validator(mode="after")
    def validate_point(self) -> "PersonalPatternCorrelationPoint":
        if self.local_started_at.utcoffset() is None:
            raise ValueError("correlation point timestamp must be aware")
        return self


class PersonalPatternsResponse(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, frozen=True)

    contract_version: Literal["personal-patterns-v1"]
    status: PersonalPatternsStatus
    generated_at: datetime
    timezone: str = Field(min_length=1, max_length=100)
    window: PersonalPatternsWindow
    summary: str = Field(min_length=1, max_length=360)
    sample: PersonalPatternsSample
    baseline: PersonalPatternsBaseline | None
    patterns: list[PersonalPattern] = Field(max_length=3)
    planner_preference: LearnedFocusPlannerPreference
    limitations: list[str] = Field(min_length=1, max_length=6)
    correlation_points: list[PersonalPatternCorrelationPoint] = Field(
        max_length=500,
    )
    evidence_fingerprint: str | None = Field(
        default=None,
        pattern=r"^[0-9a-f]{64}$",
    )

    @model_validator(mode="after")
    def validate_response(self) -> "PersonalPatternsResponse":
        if self.generated_at.utcoffset() is None:
            raise ValueError("personal pattern generation timestamp must be aware")
        expected_order = [
            "focus_timing",
            "sleep",
            "session_length_or_spacing",
        ]
        order = [expected_order.index(pattern.kind) for pattern in self.patterns]
        if order != sorted(order) or len(order) != len(set(order)):
            raise ValueError("personal patterns are not in deterministic order")
        if self.status == "disabled" and (
            self.baseline is not None
            or self.patterns
            or self.correlation_points
            or self.evidence_fingerprint is not None
            or self.planner_preference.reason != "analysis_disabled"
        ):
            raise ValueError("disabled personal patterns contain evidence")
        if self.sample.rated_sessions < 3 and self.baseline is not None:
            raise ValueError("baseline requires at least three ratings")
        return self
