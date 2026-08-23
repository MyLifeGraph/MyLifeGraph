from datetime import date, datetime, time
from typing import Literal
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, model_validator

from app.models.deadline_plans import DeadlineKind, DeadlineSourceKind
from app.models.planner import PlannerActionTarget
from app.models.planning_timing import PlanningTimingProvenance


class DeadlineProposalPayload(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, frozen=True)

    plan_id: UUID
    base_revision: int = Field(ge=0, le=199)
    kind: DeadlineKind
    title: str = Field(min_length=1, max_length=160)
    deadline_at: datetime
    estimated_total_minutes: int = Field(ge=30, le=30_000)
    credited_prior_minutes: int = Field(ge=0, le=29_999)
    preferred_session_minutes: int = Field(ge=25, le=180)
    max_daily_minutes: int = Field(ge=25, le=480)
    planning_start_on: date
    buffer_days: int = Field(ge=0, le=7)
    source_kind: DeadlineSourceKind
    source_calendar_event_id: UUID | None
    source_calendar_event_fingerprint: str | None
    use_calendar_availability: bool
    timezone: str = Field(min_length=1, max_length=100)
    best_energy_window: str = Field(min_length=1, max_length=40)
    availability_connection_id: UUID | None
    availability_import_id: UUID | None
    planning_fingerprint: str = Field(pattern=r"^[0-9a-f]{64}$")
    timing_preference: PlanningTimingProvenance
    study_setup_revision: int | None = Field(default=None, ge=1)
    recovery_minutes: int = Field(ge=0, le=60)
    tracked_focus_minutes_at_proposal: int = Field(ge=0)
    remaining_minutes_at_proposal: int = Field(ge=0)
    planned_minutes: int = Field(ge=0)
    unscheduled_minutes: int = Field(ge=0)


class DeadlineBlockWrite(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, frozen=True)

    id: UUID
    sequence: int = Field(ge=1, le=120)
    starts_at: datetime
    ends_at: datetime
    recovery_minutes: int = Field(ge=0, le=60)
    reserved_ends_at: datetime
    local_date: date
    local_start_time: time
    local_end_time: time
    planned_minutes: int = Field(ge=1, le=240)

    @model_validator(mode="after")
    def validate_interval(self) -> "DeadlineBlockWrite":
        if (
            self.starts_at.tzinfo is None
            or self.ends_at.tzinfo is None
            or self.reserved_ends_at.tzinfo is None
            or not self.starts_at < self.ends_at <= self.reserved_ends_at
        ):
            raise ValueError("deadline block interval is invalid")
        return self


class DeadlineProposalWrite(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, frozen=True)

    proposal: DeadlineProposalPayload
    blocks: tuple[DeadlineBlockWrite, ...] = Field(max_length=120)

    def proposal_json(self) -> dict[str, object]:
        return self.proposal.model_dump(mode="json")

    def blocks_json(self) -> list[dict[str, object]]:
        return [block.model_dump(mode="json") for block in self.blocks]


class PlannerRevisionWrite(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, frozen=True)

    revision: int = Field(ge=1)
    base_revision: int = Field(ge=0)
    target: PlannerActionTarget
    timezone: str = Field(min_length=1, max_length=100)
    best_energy_window: str = Field(min_length=1, max_length=40)
    planning_start_on: date
    planning_fingerprint: str = Field(pattern=r"^[0-9a-f]{64}$")
    timing_preference: PlanningTimingProvenance
    calendar_import_id: UUID | None
    study_setup_revision: int | None = Field(default=None, ge=1)
    recovery_minutes: int = Field(ge=0, le=60)
    planned_minutes: int = Field(ge=0)
    unscheduled_minutes: int = Field(ge=0)

    @model_validator(mode="after")
    def validate_revision(self) -> "PlannerRevisionWrite":
        if self.revision != self.base_revision + 1:
            raise ValueError("planner revision must advance its base exactly once")
        return self


class PlannerTaskBlockWrite(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, frozen=True)

    id: UUID
    sequence: int = Field(ge=1, le=1_500)
    starts_at: datetime
    ends_at: datetime
    recovery_minutes: int = Field(ge=0, le=60)
    reserved_ends_at: datetime
    local_date: date
    planned_minutes: int = Field(ge=5, le=240)

    @model_validator(mode="after")
    def validate_interval(self) -> "PlannerTaskBlockWrite":
        if (
            self.starts_at.tzinfo is None
            or self.ends_at.tzinfo is None
            or self.reserved_ends_at.tzinfo is None
            or not self.starts_at < self.ends_at <= self.reserved_ends_at
        ):
            raise ValueError("planner task block interval is invalid")
        return self


class PlannerHabitSlotWrite(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, frozen=True)

    id: UUID
    weekday: int = Field(ge=1, le=7)
    starts_at: time
    ends_at: time
    duration_minutes: int = Field(ge=5, le=240)

    @model_validator(mode="after")
    def validate_interval(self) -> "PlannerHabitSlotWrite":
        if self.starts_at.tzinfo is not None or self.ends_at.tzinfo is not None:
            raise ValueError("planner habit slot must use local wall-clock times")
        if self.ends_at <= self.starts_at:
            raise ValueError("planner habit slot interval is invalid")
        return self


class PlannerProposalWrite(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, frozen=True)

    target_kind: Literal["task", "habit"]
    target_id: UUID
    target: PlannerActionTarget
    revision: PlannerRevisionWrite
    task_blocks: tuple[PlannerTaskBlockWrite, ...] = Field(max_length=1_500)
    habit_slots: tuple[PlannerHabitSlotWrite, ...] = Field(max_length=7)

    @model_validator(mode="after")
    def validate_consistency(self) -> "PlannerProposalWrite":
        if (
            self.target.kind != self.target_kind
            or self.target.target_id != self.target_id
            or self.revision.target != self.target
            or (self.target_kind == "task" and self.habit_slots)
            or (self.target_kind == "habit" and self.task_blocks)
        ):
            raise ValueError("planner proposal write components are inconsistent")
        return self

    def target_json(self) -> dict[str, object]:
        return self.target.model_dump(mode="json")

    def revision_json(self) -> dict[str, object]:
        return self.revision.model_dump(mode="json")

    def task_blocks_json(self) -> list[dict[str, object]]:
        return [block.model_dump(mode="json") for block in self.task_blocks]

    def habit_slots_json(self) -> list[dict[str, object]]:
        return [slot.model_dump(mode="json") for slot in self.habit_slots]
