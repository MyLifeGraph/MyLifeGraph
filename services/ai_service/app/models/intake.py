from datetime import datetime
from typing import Any, Literal

from pydantic import BaseModel, ConfigDict, Field, field_validator

FocusArea = Literal["focus", "energy", "sleep", "stress", "planning", "movement"]
CoachingStyle = Literal["direct", "gentle", "analytical", "accountability"]
EnergyWindow = Literal["early_morning", "morning", "afternoon", "evening", "variable"]
CalendarConnectionIntent = Literal["not_now", "later", "interested"]


class ReminderQuietHours(BaseModel):
    model_config = ConfigDict(extra="forbid")

    starts_at: str = Field(pattern=r"^\d{2}:\d{2}$")
    ends_at: str = Field(pattern=r"^\d{2}:\d{2}$")


class ReminderPreference(BaseModel):
    model_config = ConfigDict(extra="forbid")

    enabled: bool = True
    quiet_hours: ReminderQuietHours


class FixedCommitment(BaseModel):
    model_config = ConfigDict(extra="forbid")

    title: str = Field(min_length=1, max_length=120)
    location: str | None = Field(default=None, max_length=120)
    weekday: int = Field(ge=1, le=7)
    starts_at: str = Field(pattern=r"^\d{2}:\d{2}$")
    ends_at: str = Field(pattern=r"^\d{2}:\d{2}$")

    @field_validator("title", "location", mode="before")
    @classmethod
    def trim_optional_text(cls, value: object) -> object:
        if isinstance(value, str):
            return value.strip()
        return value


class IntakeResponses(BaseModel):
    model_config = ConfigDict(extra="forbid")

    display_name: str | None = Field(default=None, max_length=120)
    primary_focus_areas: list[FocusArea] = Field(min_length=1, max_length=6)
    goals: list[str] = Field(min_length=1, max_length=3)
    friction_points: list[str] = Field(min_length=1, max_length=5)
    weekday_shape: str = Field(min_length=1, max_length=500)
    best_energy_window: EnergyWindow
    coaching_style: CoachingStyle
    reminder_preference: ReminderPreference
    existing_habits: list[str] = Field(default_factory=list, max_length=5)
    fixed_commitments: list[FixedCommitment] = Field(default_factory=list, max_length=10)
    context_note: str | None = Field(default=None, max_length=1000)
    calendar_connection_intent: CalendarConnectionIntent = "not_now"

    @field_validator(
        "display_name",
        "weekday_shape",
        "context_note",
        mode="before",
    )
    @classmethod
    def trim_text(cls, value: object) -> object:
        if isinstance(value, str):
            value = value.strip()
            return value or None
        return value

    @field_validator("goals", "friction_points", "existing_habits", mode="before")
    @classmethod
    def trim_string_list(cls, value: object) -> object:
        if not isinstance(value, list):
            return value
        return [item.strip() for item in value if isinstance(item, str) and item.strip()]


class IntakeCompleteRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

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


class IntakeCompleteResponse(BaseModel):
    model_config = ConfigDict(extra="forbid")

    intake_response_id: str
    snapshot_id: str
    completed_at: datetime
    summary: SnapshotSummary
    recommendations: list[dict[str, Any]] = Field(default_factory=list)
