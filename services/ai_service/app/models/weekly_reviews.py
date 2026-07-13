from datetime import date, datetime
from typing import Literal, Self

from pydantic import BaseModel, ConfigDict, Field, model_validator


WEEKLY_REVIEW_CONTRACT_VERSION = "weekly-review-v1"

WeeklyReviewFreshness = Literal["not_ready", "missing", "current", "stale"]
WeeklyReviewDataQuality = Literal["insufficient", "partial", "sufficient"]
WeeklyReviewOperation = Literal[
    "keep",
    "shrink",
    "pause",
    "replace",
    "archive",
    "defer",
]
WeeklyReviewOwnership = Literal["manual", "setup"]
WeeklyReviewApplicationMode = Literal[
    "direct_habit",
    "settings_setup",
    "staged_only",
    "none",
]
HabitLifecycle = Literal["active", "paused", "archived"]
HabitCadenceKind = Literal["daily", "weekdays", "weekly_target"]


class WeeklyReviewGenerateRequest(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True)

    period_key: str = Field(pattern=r"^\d{4}-W\d{2}$")
    force: bool = False


class WeeklyReviewEvidenceRef(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, frozen=True)

    table: str = Field(min_length=1, max_length=64)
    id: str = Field(min_length=1, max_length=200)
    field: str = Field(min_length=1, max_length=200)


class WeeklyReviewEvidenceWindow(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, frozen=True)

    starts_on: date
    ends_on: date
    days: Literal[7]

    @model_validator(mode="after")
    def validate_period(self) -> Self:
        if self.starts_on.isoweekday() != 1:
            raise ValueError("weekly review evidence must start on Monday")
        if self.ends_on != date.fromordinal(self.starts_on.toordinal() + 6):
            raise ValueError("weekly review evidence must cover exactly seven days")
        return self


class WeeklyReviewProvenance(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, frozen=True)

    engine: Literal["deterministic"]
    contract_version: Literal["weekly-review-v1"]
    source_snapshot_id: str = Field(min_length=1, max_length=200)
    source_snapshot_generated_at: datetime
    evidence_window: WeeklyReviewEvidenceWindow
    source_fingerprint: str = Field(pattern=r"^[0-9a-f]{64}$")
    baseline: Literal["none"]
    limitations: list[str] = Field(default_factory=list, max_length=10)
    llm_used: Literal[False]

    @model_validator(mode="after")
    def validate_timestamp(self) -> Self:
        if self.source_snapshot_generated_at.tzinfo is None:
            raise ValueError("source snapshot timestamp must be timezone-aware")
        return self


class WeeklyTaskFacts(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, frozen=True)

    completed: int = Field(ge=0)
    carried: int = Field(ge=0)
    overdue_carried: int = Field(ge=0)
    cancelled: int = Field(ge=0)
    goal_linked_completed: int = Field(ge=0)


class WeeklyHabitFacts(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, frozen=True)

    active: int = Field(ge=0)
    paused: int = Field(ge=0)
    archived: int = Field(ge=0)
    stable_definitions: int = Field(ge=0)
    changed_definitions: int = Field(ge=0)
    scheduled_opportunities: int = Field(ge=0)
    completed: int = Field(ge=0)
    skipped: int = Field(ge=0)
    missed: int = Field(ge=0)
    recovery_open: int = Field(ge=0)
    unknown: int = Field(ge=0)


class WeeklyFocusFacts(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, frozen=True)

    completed_sessions: int = Field(ge=0)
    abandoned_sessions: int = Field(ge=0)
    active_sessions: int = Field(ge=0)
    actual_minutes: int = Field(ge=0)


class WeeklyRecoveryFacts(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, frozen=True)

    observed_days: int = Field(ge=0, le=7)
    recovery_days: int = Field(ge=0, le=7)

    @model_validator(mode="after")
    def validate_counts(self) -> Self:
        if self.recovery_days > self.observed_days:
            raise ValueError("recovery days cannot exceed observed days")
        return self


class WeeklyFeedbackFacts(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, frozen=True)

    total: int = Field(ge=0)
    done: int = Field(ge=0)
    later: int = Field(ge=0)
    not_helpful: int = Field(ge=0)
    too_much: int = Field(ge=0)
    does_not_fit: int = Field(ge=0)

    @model_validator(mode="after")
    def validate_total(self) -> Self:
        expected = (
            self.done
            + self.later
            + self.not_helpful
            + self.too_much
            + self.does_not_fit
        )
        if self.total != expected:
            raise ValueError("feedback total must equal the typed outcome counts")
        return self


class WeeklyReviewFacts(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, frozen=True)

    tasks: WeeklyTaskFacts
    habits: WeeklyHabitFacts
    focus: WeeklyFocusFacts
    recovery: WeeklyRecoveryFacts
    feedback: WeeklyFeedbackFacts


class WeeklyReviewHabitCadence(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, frozen=True)

    kind: HabitCadenceKind
    weekly_target: int | None = Field(default=None, strict=True, ge=1, le=7)
    scheduled_weekdays: list[int] = Field(default_factory=list, max_length=7)

    @model_validator(mode="after")
    def validate_shape(self) -> Self:
        weekdays = self.scheduled_weekdays
        if any(isinstance(day, bool) or not 1 <= day <= 7 for day in weekdays):
            raise ValueError("scheduled_weekdays must contain ISO weekdays")
        if weekdays != sorted(set(weekdays)):
            raise ValueError("scheduled_weekdays must be sorted and unique")
        if self.kind == "weekdays":
            if not weekdays or self.weekly_target is not None:
                raise ValueError("weekdays cadence requires weekdays only")
        elif self.kind == "weekly_target":
            if self.weekly_target is None or weekdays:
                raise ValueError("weekly_target cadence requires a target only")
        elif self.weekly_target is not None or weekdays:
            raise ValueError("daily cadence accepts no target or weekdays")
        return self


class WeeklyReviewHabitState(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, frozen=True)

    lifecycle: HabitLifecycle
    cadence: WeeklyReviewHabitCadence


class WeeklyReviewProposalChange(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, frozen=True)

    before: WeeklyReviewHabitState
    after: WeeklyReviewHabitState | None


class WeeklyReviewProposal(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, frozen=True)

    id: str = Field(min_length=1, max_length=200)
    operation: WeeklyReviewOperation
    target_kind: Literal["habit"]
    target_id: str = Field(min_length=1, max_length=200)
    target_title: str = Field(min_length=1, max_length=160)
    ownership: WeeklyReviewOwnership
    application_mode: WeeklyReviewApplicationMode
    expected_updated_at: datetime
    reason_code: str = Field(min_length=1, max_length=100)
    reason: str = Field(min_length=1, max_length=300)
    evidence_refs: list[WeeklyReviewEvidenceRef] = Field(
        default_factory=list,
        max_length=8,
    )
    change: WeeklyReviewProposalChange

    @model_validator(mode="after")
    def validate_application(self) -> Self:
        if self.expected_updated_at.tzinfo is None:
            raise ValueError("expected_updated_at must be timezone-aware")
        before = self.change.before
        after = self.change.after
        if self.operation in {"replace", "defer"}:
            if self.application_mode != "staged_only" or after is not None:
                raise ValueError("replace/defer proposals must remain staged")
            return self
        if after is None:
            raise ValueError("non-staged proposals require an after state")
        if self.operation == "keep":
            if self.application_mode != "none" or after != before:
                raise ValueError("keep proposals must preserve the habit state")
            return self
        if self.operation == "shrink":
            if (
                before.lifecycle != "active"
                or before.cadence.kind != "weekly_target"
                or before.cadence.weekly_target is None
                or before.cadence.weekly_target < 2
                or after.lifecycle != "active"
                or after.cadence.kind != "weekly_target"
                or after.cadence.weekly_target
                != before.cadence.weekly_target - 1
                or after.cadence.scheduled_weekdays
                != before.cadence.scheduled_weekdays
            ):
                raise ValueError("shrink must reduce one active weekly target by one")
        elif self.operation == "pause":
            if (
                before.lifecycle != "active"
                or after.lifecycle != "paused"
                or after.cadence != before.cadence
            ):
                raise ValueError("pause must preserve cadence and pause an active habit")
        elif self.operation == "archive":
            if (
                before.lifecycle != "paused"
                or after.lifecycle != "archived"
                or after.cadence != before.cadence
            ):
                raise ValueError("archive must preserve cadence and archive a paused habit")
        if self.application_mode == "direct_habit":
            if self.ownership != "manual" or self.operation not in {
                "shrink",
                "pause",
                "archive",
            }:
                raise ValueError("direct habit changes require a manual habit")
        elif self.application_mode == "settings_setup":
            if self.ownership != "setup":
                raise ValueError("Settings Setup is reserved for Setup ownership")
        else:
            raise ValueError("habit mutations require an applicable command path")
        return self


class WeeklyReview(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, frozen=True)

    id: str = Field(min_length=1, max_length=200)
    data_quality: WeeklyReviewDataQuality
    narrative: str = Field(min_length=1, max_length=500)
    facts: WeeklyReviewFacts
    proposals: list[WeeklyReviewProposal] = Field(default_factory=list, max_length=2)
    evidence_refs: list[WeeklyReviewEvidenceRef] = Field(
        default_factory=list,
        max_length=40,
    )
    provenance: WeeklyReviewProvenance
    generated_at: datetime
    updated_at: datetime

    @model_validator(mode="after")
    def validate_review(self) -> Self:
        if self.generated_at.tzinfo is None or self.updated_at.tzinfo is None:
            raise ValueError("weekly review timestamps must be timezone-aware")
        proposal_ids = [proposal.id for proposal in self.proposals]
        target_ids = [proposal.target_id for proposal in self.proposals]
        if len(proposal_ids) != len(set(proposal_ids)):
            raise ValueError("weekly review proposal ids must be unique")
        if len(target_ids) != len(set(target_ids)):
            raise ValueError("weekly review proposal targets must be unique")
        return self


class WeeklyReviewReadResponse(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True)

    contract_version: Literal["weekly-review-v1"]
    period_key: str = Field(pattern=r"^\d{4}-W\d{2}$")
    starts_on: date
    ends_on: date
    timezone: str = Field(min_length=1, max_length=100)
    freshness: WeeklyReviewFreshness
    needs_generation: bool
    stale_reasons: list[str] = Field(default_factory=list, max_length=8)
    review: WeeklyReview | None

    @model_validator(mode="after")
    def validate_response(self) -> Self:
        if self.starts_on.isoweekday() != 1:
            raise ValueError("weekly review period must start on Monday")
        if self.ends_on.toordinal() != self.starts_on.toordinal() + 6:
            raise ValueError("weekly review period must cover exactly seven days")
        iso_year, iso_week, _ = self.starts_on.isocalendar()
        if self.period_key != f"{iso_year}-W{iso_week:02d}":
            raise ValueError("weekly review period key does not match its dates")
        if self.freshness in {"not_ready", "missing"}:
            if self.review is not None or self.stale_reasons:
                raise ValueError("unavailable weekly reviews cannot carry review data")
        else:
            if self.review is None:
                raise ValueError("current or stale weekly review requires review data")
        if self.needs_generation != (self.freshness in {"missing", "stale"}):
            raise ValueError("weekly review generation flag does not match freshness")
        if self.freshness == "stale" and not self.stale_reasons:
            raise ValueError("stale weekly review requires a reason")
        if self.freshness != "stale" and self.stale_reasons:
            raise ValueError("only stale weekly reviews may carry stale reasons")
        if self.review is not None and (
            self.review.provenance.evidence_window.starts_on != self.starts_on
            or self.review.provenance.evidence_window.ends_on != self.ends_on
        ):
            raise ValueError("weekly review evidence window must match its envelope")
        return self


WeeklyReviewGenerateResponse = WeeklyReviewReadResponse
