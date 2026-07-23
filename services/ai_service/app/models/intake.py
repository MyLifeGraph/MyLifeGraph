from datetime import date, datetime, time
from typing import Any, Literal
from uuid import UUID

from pydantic import (
    BaseModel,
    ConfigDict,
    Field,
    field_validator,
    model_validator,
)


FocusArea = Literal["focus", "energy", "sleep", "stress", "planning", "movement"]
CoachingStyle = Literal["direct", "gentle", "analytical", "accountability"]
EnergyWindow = Literal[
    "early_morning",
    "morning",
    "afternoon",
    "evening",
    "variable",
]
CalendarConnectionIntent = Literal["not_now", "later", "interested"]
GoalStatus = Literal["active", "paused", "archived"]
RoutineStatus = Literal["candidate", "active", "paused", "archived"]
CommitmentStatus = Literal["active", "archived"]
IntakeState = Literal["pending", "applied"]


class ReminderQuietHours(BaseModel):
    model_config = ConfigDict(extra="forbid")

    starts_at: time
    ends_at: time


class ReminderPreference(BaseModel):
    model_config = ConfigDict(extra="forbid")

    enabled: bool
    quiet_hours: ReminderQuietHours | None = None

    @model_validator(mode="after")
    def validate_quiet_hours(self) -> "ReminderPreference":
        if self.enabled and self.quiet_hours is None:
            raise ValueError("enabled reminders require quiet_hours")
        return self


class SetupGoal(BaseModel):
    model_config = ConfigDict(extra="forbid")

    key: UUID
    title: str = Field(min_length=1, max_length=200)
    status: GoalStatus = "active"

    @field_validator("title", mode="before")
    @classmethod
    def trim_title(cls, value: object) -> object:
        return value.strip() if isinstance(value, str) else value


class SetupRoutine(BaseModel):
    model_config = ConfigDict(extra="forbid")

    key: UUID
    title: str = Field(min_length=1, max_length=200)
    status: RoutineStatus = "candidate"
    cadence_confirmed: bool = False
    frequency: Literal["daily", "weekly"] | None = None
    target: int | None = Field(default=None, ge=1, le=7)

    @field_validator("title", mode="before")
    @classmethod
    def trim_title(cls, value: object) -> object:
        return value.strip() if isinstance(value, str) else value

    @model_validator(mode="after")
    def validate_cadence(self) -> "SetupRoutine":
        has_complete_cadence = self.frequency is not None and self.target is not None
        if self.cadence_confirmed != has_complete_cadence:
            raise ValueError(
                "cadence_confirmed requires both frequency and target, and "
                "unconfirmed routines must not carry cadence values",
            )
        if self.status in {"active", "paused"} and not self.cadence_confirmed:
            raise ValueError(
                "active or paused routines require explicitly confirmed cadence",
            )
        if self.frequency == "daily" and self.target != 1:
            raise ValueError("daily routines must use target 1")
        return self


class FixedCommitment(BaseModel):
    model_config = ConfigDict(extra="forbid")

    key: UUID
    title: str = Field(min_length=1, max_length=120)
    location: str | None = Field(default=None, max_length=120)
    weekday: int = Field(ge=1, le=7)
    starts_at: time
    ends_at: time
    valid_from: date | None = None
    valid_until: date | None = None
    status: CommitmentStatus = "active"

    @field_validator("title", mode="before")
    @classmethod
    def trim_title(cls, value: object) -> object:
        return value.strip() if isinstance(value, str) else value

    @field_validator("location", mode="before")
    @classmethod
    def trim_location(cls, value: object) -> object:
        if isinstance(value, str):
            value = value.strip()
            return value or None
        return value

    @model_validator(mode="after")
    def validate_time_range(self) -> "FixedCommitment":
        if self.ends_at <= self.starts_at:
            raise ValueError("ends_at must be later than starts_at")
        if (
            self.valid_from is not None
            and self.valid_until is not None
            and self.valid_until < self.valid_from
        ):
            raise ValueError("valid_until must not be before valid_from")
        return self


class IntakeResponses(BaseModel):
    model_config = ConfigDict(extra="forbid")

    display_name: str | None = Field(default=None, max_length=120)
    primary_focus_areas: list[FocusArea] = Field(min_length=1, max_length=6)
    goals: list[SetupGoal] = Field(default_factory=list, max_length=3)
    friction_points: list[str] = Field(default_factory=list, max_length=5)
    weekday_shape: str = Field(min_length=1, max_length=500)
    best_energy_window: EnergyWindow
    coaching_style: CoachingStyle
    reminder_preference: ReminderPreference
    routines: list[SetupRoutine] = Field(default_factory=list, max_length=5)
    fixed_commitments: list[FixedCommitment] = Field(
        default_factory=list,
        max_length=10,
    )
    context_note: str | None = Field(default=None, max_length=1000)
    calendar_connection_intent: CalendarConnectionIntent | None = None

    @field_validator("display_name", "context_note", mode="before")
    @classmethod
    def trim_optional_text(cls, value: object) -> object:
        if isinstance(value, str):
            value = value.strip()
            return value or None
        return value

    @field_validator("weekday_shape", mode="before")
    @classmethod
    def trim_required_text(cls, value: object) -> object:
        return value.strip() if isinstance(value, str) else value

    @field_validator("friction_points", mode="before")
    @classmethod
    def trim_string_list(cls, value: object) -> object:
        if not isinstance(value, list):
            return value
        normalized: list[str] = []
        for item in value:
            if not isinstance(item, str):
                raise ValueError("friction_points items must be strings")
            if stripped := item.strip():
                normalized.append(stripped)
        return normalized

    @model_validator(mode="after")
    def validate_unique_item_keys(self) -> "IntakeResponses":
        keys = [
            *(item.key for item in self.goals),
            *(item.key for item in self.routines),
            *(item.key for item in self.fixed_commitments),
        ]
        if len(keys) != len(set(keys)):
            raise ValueError("setup item keys must be unique across the intake")
        if len(self.primary_focus_areas) != len(set(self.primary_focus_areas)):
            raise ValueError("primary_focus_areas must not contain duplicates")
        return self


class IntakeCompleteRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    request_id: UUID
    base_revision: int = Field(ge=0)
    version: Literal["intake-v1"] = "intake-v1"
    responses: IntakeResponses
    metadata: dict[str, Any] = Field(default_factory=dict)


class SnapshotSummary(BaseModel):
    model_config = ConfigDict(extra="forbid")

    primary_focus_areas: list[FocusArea]
    goals: list[str]
    friction_points: list[str]
    best_energy_window: EnergyWindow
    coaching_style: CoachingStyle
    reminder_enabled: bool
    fixed_commitment_count: int
    existing_habit_count: int
    routine_candidate_count: int
    active_habit_count: int


class IntakeSetupResponse(BaseModel):
    model_config = ConfigDict(extra="forbid")

    exists: bool
    revision: int = Field(ge=0)
    base_revision: int = Field(ge=0)
    request_id: UUID | None = None
    status: IntakeState | None = None
    intake_response_id: str | None = None
    snapshot_id: str | None = None
    completed_at: datetime | None = None
    responses: IntakeResponses | None = None
    summary: SnapshotSummary | None = None


class IntakeCompleteResponse(IntakeSetupResponse):
    model_config = ConfigDict(extra="forbid")

    exists: Literal[True] = True
    request_id: UUID
    revision: int = Field(ge=1)
    base_revision: int = Field(ge=0)
    status: Literal["applied"] = "applied"
    intake_response_id: str
    snapshot_id: str
    completed_at: datetime
    responses: IntakeResponses
    summary: SnapshotSummary
    recommendations: list[dict[str, Any]] = Field(default_factory=list)
