from __future__ import annotations

from datetime import date, datetime
from typing import Annotated, Literal, Self
from uuid import UUID
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from pydantic import BaseModel, ConfigDict, Field, model_validator


TODAY_OVERVIEW_CONTRACT_VERSION = "today-overview-v1"
TODAY_OVERVIEW_V2_CONTRACT_VERSION = "today-overview-v2"

TodaySourceStatus = Literal["current", "unavailable"]
TodayProgressSource = Literal["check_ins", "tasks", "habits", "preparation"]
TodayTaskStatus = Literal["todo", "in_progress", "done", "cancelled"]
TodayTaskReason = Literal[
    "overdue",
    "due_today",
    "in_progress",
    "completed_today",
]
TodayHabitCadence = Literal["daily", "weekdays", "weekly_target"]
TodayHabitOutcome = Literal["completed", "skipped"]


class TodaySourceState(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, frozen=True)

    status: TodaySourceStatus
    message: str | None = Field(default=None, min_length=1, max_length=160)

    @model_validator(mode="after")
    def validate_message(self) -> Self:
        if (self.status == "unavailable") != (self.message is not None):
            raise ValueError("today source message must match its availability")
        if self.message is not None and self.message.strip() != self.message:
            raise ValueError("today source message must be trimmed")
        return self


class TodaySourceStates(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, frozen=True)

    check_ins: TodaySourceState
    tasks: TodaySourceState
    habits: TodaySourceState
    setup_commitments: TodaySourceState
    preparation: TodaySourceState
    calendar_events: TodaySourceState
    focus_sessions: TodaySourceState


class TodayCheckIns(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, frozen=True)

    morning_saved: bool
    evening_saved: bool
    completed_days_streak: int = Field(ge=0)


class TodayProgress(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, frozen=True)

    completed: int = Field(ge=0)
    total: int = Field(ge=2)

    @model_validator(mode="after")
    def validate_arithmetic(self) -> Self:
        if self.completed > self.total:
            raise ValueError("today progress cannot exceed its total")
        return self


class TodayTask(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, frozen=True)

    id: UUID
    title: str = Field(min_length=1, max_length=160)
    description: str | None = Field(default=None, max_length=2_000)
    status: TodayTaskStatus
    priority: Literal["low", "medium", "high", "critical"]
    deadline: datetime | None = None
    estimated_minutes: int | None = Field(default=None, ge=5, le=480)
    completed_at: datetime | None = None
    source: str = Field(min_length=1, max_length=100)
    deadline_plan_id: UUID | None = None
    today_reason: TodayTaskReason | None = None

    @model_validator(mode="after")
    def validate_task(self) -> Self:
        if self.title.strip() != self.title:
            raise ValueError("today task title must be trimmed")
        if (
            self.description is not None
            and self.description.strip() != self.description
        ):
            raise ValueError("today task description must be trimmed")
        if any(
            value is not None and (value.tzinfo is None or value.utcoffset() is None)
            for value in (self.deadline, self.completed_at)
        ):
            raise ValueError("today task timestamps must be timezone-aware")
        managed = self.source == "deadline-plan-v1"
        if managed != (self.deadline_plan_id == self.id):
            raise ValueError("today task planner ownership is inconsistent")
        if self.status == "done" and self.completed_at is None:
            raise ValueError("completed today task requires completed_at")
        if self.status != "done" and self.completed_at is not None:
            raise ValueError("open today task cannot carry completed_at")
        return self


class TodayTasks(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, frozen=True)

    today: list[TodayTask] = Field(default_factory=list, max_length=1_000)
    all: list[TodayTask] = Field(default_factory=list, max_length=1_000)

    @model_validator(mode="after")
    def validate_projection(self) -> Self:
        all_ids = [task.id for task in self.all]
        today_ids = [task.id for task in self.today]
        if len(all_ids) != len(set(all_ids)) or len(today_ids) != len(set(today_ids)):
            raise ValueError("today task projections cannot contain duplicates")
        if not set(today_ids).issubset(set(all_ids)):
            raise ValueError("today tasks must be included in the all-task projection")
        if any(task.today_reason is None for task in self.today):
            raise ValueError("today task requires a selection reason")
        return self


class TodayHabit(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, frozen=True)

    id: UUID
    title: str = Field(min_length=1, max_length=160)
    description: str | None = Field(default=None, max_length=2_000)
    cadence: TodayHabitCadence
    cadence_label: str = Field(min_length=1, max_length=80)
    outcome: TodayHabitOutcome | None = None
    weekly_completed: int = Field(ge=0, le=7)
    weekly_target: int = Field(ge=1, le=7)
    setup_managed: bool

    @model_validator(mode="after")
    def validate_habit(self) -> Self:
        if (
            self.title.strip() != self.title
            or self.cadence_label.strip() != self.cadence_label
        ):
            raise ValueError("today habit text must be trimmed")
        if (
            self.description is not None
            and self.description.strip() != self.description
        ):
            raise ValueError("today habit description must be trimmed")
        if self.cadence != "weekly_target" and self.weekly_target != 1:
            raise ValueError("scheduled today habit must have a one-day target")
        return self


class _TodayTimedItem(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, frozen=True)

    id: UUID
    title: str = Field(min_length=1, max_length=200)
    location: str | None = Field(default=None, max_length=300)
    all_day: Literal[False]
    starts_at: datetime
    ends_at: datetime

    @model_validator(mode="after")
    def validate_interval(self) -> Self:
        if self.title.strip() != self.title:
            raise ValueError("today timeline title must be trimmed")
        if self.location is not None and self.location.strip() != self.location:
            raise ValueError("today timeline location must be trimmed")
        if (
            self.starts_at.tzinfo is None
            or self.ends_at.tzinfo is None
            or self.starts_at.utcoffset() is None
            or self.ends_at.utcoffset() is None
            or self.ends_at <= self.starts_at
        ):
            raise ValueError("today timeline interval is invalid")
        return self


class TodaySetupCommitment(_TodayTimedItem):
    kind: Literal["setup_commitment"]


class TodayPreparationBlock(_TodayTimedItem):
    kind: Literal["preparation"]
    plan_id: UUID
    block_id: UUID
    managed_task_id: UUID
    state: Literal["upcoming", "partial", "completed", "missed"]
    planned_minutes: int = Field(ge=5, le=240)
    credited_tracked_minutes: int = Field(ge=0, le=240)

    @model_validator(mode="after")
    def validate_preparation(self) -> Self:
        if self.block_id != self.id or self.managed_task_id != self.plan_id:
            raise ValueError("today preparation identity is inconsistent")
        if self.credited_tracked_minutes > self.planned_minutes:
            raise ValueError("today preparation credit exceeds its block")
        return self


class TodayFocusSession(_TodayTimedItem):
    kind: Literal["focus_session"]
    status: Literal["active", "completed", "abandoned"]
    actual_minutes: int | None = Field(default=None, ge=0)

    @model_validator(mode="after")
    def validate_focus(self) -> Self:
        if self.status == "active" and self.actual_minutes is not None:
            raise ValueError("active focus cannot have actual minutes")
        if self.status != "active" and self.actual_minutes is None:
            raise ValueError("terminal focus requires actual minutes")
        return self


class TodayCalendarEvent(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, frozen=True)

    kind: Literal["calendar_event"]
    id: UUID
    title: str = Field(min_length=1, max_length=200)
    location: str | None = Field(default=None, max_length=300)
    source_label: str = Field(min_length=1, max_length=80)
    all_day: bool
    starts_at: datetime | None = None
    ends_at: datetime | None = None
    starts_on: date | None = None
    ends_on: date | None = None

    @model_validator(mode="after")
    def validate_event(self) -> Self:
        if (
            self.title.strip() != self.title
            or self.source_label.strip() != self.source_label
        ):
            raise ValueError("today calendar event text must be trimmed")
        if self.location is not None and self.location.strip() != self.location:
            raise ValueError("today calendar location must be trimmed")
        if self.all_day:
            if (
                self.starts_on is None
                or self.ends_on is None
                or self.ends_on <= self.starts_on
                or self.starts_at is not None
                or self.ends_at is not None
            ):
                raise ValueError("today all-day calendar event is invalid")
        elif (
            self.starts_at is None
            or self.ends_at is None
            or self.starts_at.tzinfo is None
            or self.ends_at.tzinfo is None
            or self.starts_at.utcoffset() is None
            or self.ends_at.utcoffset() is None
            or self.ends_at <= self.starts_at
            or self.starts_on is not None
            or self.ends_on is not None
        ):
            raise ValueError("today timed calendar event is invalid")
        return self


TodayTimelineItem = Annotated[
    TodaySetupCommitment
    | TodayPreparationBlock
    | TodayCalendarEvent
    | TodayFocusSession,
    Field(discriminator="kind"),
]


class TodayOverviewResponse(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, frozen=True)

    contract_version: Literal["today-overview-v1"]
    origin: Literal["authenticated_backend"]
    local_date: date
    timezone: str = Field(min_length=1, max_length=100)
    generated_at: datetime
    check_ins: TodayCheckIns | None
    progress: TodayProgress | None
    progress_unavailable_sources: list[TodayProgressSource] = Field(max_length=4)
    timeline: list[TodayTimelineItem] = Field(default_factory=list, max_length=1_500)
    tasks: TodayTasks
    habits: list[TodayHabit] = Field(default_factory=list, max_length=500)
    source_states: TodaySourceStates

    @model_validator(mode="after")
    def validate_overview(self) -> Self:
        if self.generated_at.tzinfo is None or self.generated_at.utcoffset() is None:
            raise ValueError("today overview timestamp must be timezone-aware")
        try:
            zone = ZoneInfo(self.timezone)
        except ZoneInfoNotFoundError as exc:
            raise ValueError("today overview timezone is invalid") from exc
        if self.generated_at.astimezone(zone).date() != self.local_date:
            raise ValueError("today overview date does not match its timestamp")

        unavailable = self.progress_unavailable_sources
        if len(unavailable) != len(set(unavailable)):
            raise ValueError("today unavailable progress sources must be unique")
        expected_unavailable = [
            name
            for name in ("check_ins", "tasks", "habits", "preparation")
            if getattr(self.source_states, name).status == "unavailable"
        ]
        if unavailable != expected_unavailable:
            raise ValueError("today unavailable progress sources are inconsistent")
        if bool(unavailable) != (self.progress is None):
            raise ValueError("today progress availability is inconsistent")
        if self.source_states.check_ins.status == "current" and self.check_ins is None:
            raise ValueError("current today check-ins require a projection")
        if (
            self.source_states.check_ins.status == "unavailable"
            and self.check_ins is not None
        ):
            raise ValueError("unavailable today check-ins cannot have a projection")

        if self.progress is not None:
            assert self.check_ins is not None
            preparation = [
                item
                for item in self.timeline
                if isinstance(item, TodayPreparationBlock)
            ]
            expected_total = (
                2 + len(self.tasks.today) + len(self.habits) + len(preparation)
            )
            expected_completed = (
                int(self.check_ins.morning_saved)
                + int(self.check_ins.evening_saved)
                + sum(task.status == "done" for task in self.tasks.today)
                + sum(habit.outcome == "completed" for habit in self.habits)
                + sum(item.state == "completed" for item in preparation)
            )
            if (
                self.progress.total != expected_total
                or self.progress.completed != expected_completed
            ):
                raise ValueError(
                    "today progress does not match its counted projections",
                )
        return self


TodayTaskReasonV2 = Literal[
    "overdue",
    "due_today",
    "in_progress",
    "completed_today",
    "scheduled_today",
]
TodayProgressSourceV2 = Literal[
    "check_ins",
    "tasks",
    "habits",
    "preparation",
    "planner",
]


class TodayTaskV2(TodayTask):
    today_reason: TodayTaskReasonV2 | None = None
    scheduled_today: bool


class TodayTasksV2(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, frozen=True)

    today: list[TodayTaskV2] = Field(default_factory=list, max_length=1_000)
    all: list[TodayTaskV2] = Field(default_factory=list, max_length=1_000)

    @model_validator(mode="after")
    def validate_projection(self) -> Self:
        all_ids = [task.id for task in self.all]
        today_ids = [task.id for task in self.today]
        if len(all_ids) != len(set(all_ids)) or len(today_ids) != len(set(today_ids)):
            raise ValueError("today-v2 task projections cannot contain duplicates")
        if not set(today_ids).issubset(set(all_ids)):
            raise ValueError("today-v2 tasks must be included in the all projection")
        if any(task.today_reason is None for task in self.today):
            raise ValueError("today-v2 selected task requires a reason")
        scheduled_ids = {task.id for task in self.today if task.scheduled_today}
        if scheduled_ids != {task.id for task in self.all if task.scheduled_today}:
            raise ValueError("today-v2 scheduled task projection is inconsistent")
        return self


class TodayHabitV2(TodayHabit):
    scheduled_today: bool


class TodayPlannerTaskBlock(_TodayTimedItem):
    kind: Literal["task_block"]
    task_id: UUID
    planned_minutes: int = Field(ge=5, le=240)


class TodayPlannerHabitSlot(_TodayTimedItem):
    kind: Literal["habit_slot"]
    habit_id: UUID
    planned_minutes: int = Field(ge=5, le=240)


class TodayManualCommitment(_TodayTimedItem):
    kind: Literal["manual_commitment"]
    commitment_id: UUID


TodayTimelineItemV2 = Annotated[
    TodaySetupCommitment
    | TodayPreparationBlock
    | TodayCalendarEvent
    | TodayFocusSession
    | TodayPlannerTaskBlock
    | TodayPlannerHabitSlot
    | TodayManualCommitment,
    Field(discriminator="kind"),
]


class TodaySourceStatesV2(TodaySourceStates):
    planner: TodaySourceState


class TodayOverviewV2Response(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, frozen=True)

    contract_version: Literal["today-overview-v2"]
    origin: Literal["authenticated_backend"]
    local_date: date
    timezone: str = Field(min_length=1, max_length=100)
    generated_at: datetime
    check_ins: TodayCheckIns | None
    progress: TodayProgress | None
    progress_unavailable_sources: list[TodayProgressSourceV2] = Field(max_length=5)
    timeline: list[TodayTimelineItemV2] = Field(default_factory=list, max_length=2_000)
    tasks: TodayTasksV2
    habits: list[TodayHabitV2] = Field(default_factory=list, max_length=500)
    source_states: TodaySourceStatesV2

    @model_validator(mode="after")
    def validate_overview(self) -> Self:
        if self.generated_at.tzinfo is None or self.generated_at.utcoffset() is None:
            raise ValueError("today-v2 timestamp must be timezone-aware")
        try:
            zone = ZoneInfo(self.timezone)
        except ZoneInfoNotFoundError as exc:
            raise ValueError("today-v2 timezone is invalid") from exc
        if self.generated_at.astimezone(zone).date() != self.local_date:
            raise ValueError("today-v2 date does not match its timestamp")
        unavailable = self.progress_unavailable_sources
        if len(unavailable) != len(set(unavailable)):
            raise ValueError("today-v2 unavailable progress sources must be unique")
        expected_unavailable = [
            name
            for name in ("check_ins", "tasks", "habits", "preparation", "planner")
            if getattr(self.source_states, name).status == "unavailable"
        ]
        if unavailable != expected_unavailable:
            raise ValueError("today-v2 unavailable progress sources are inconsistent")
        if bool(unavailable) != (self.progress is None):
            raise ValueError("today-v2 progress availability is inconsistent")
        if self.source_states.check_ins.status == "current" and self.check_ins is None:
            raise ValueError("current today-v2 check-ins require a projection")
        if self.source_states.check_ins.status == "unavailable" and self.check_ins:
            raise ValueError("unavailable today-v2 check-ins cannot have a projection")
        scheduled_task_ids = {
            item.task_id
            for item in self.timeline
            if isinstance(item, TodayPlannerTaskBlock)
        }
        scheduled_habit_ids = {
            item.habit_id
            for item in self.timeline
            if isinstance(item, TodayPlannerHabitSlot)
        }
        if scheduled_task_ids != {
            task.id for task in self.tasks.all if task.scheduled_today
        } or scheduled_habit_ids != {
            habit.id for habit in self.habits if habit.scheduled_today
        }:
            raise ValueError("today-v2 Planner target projections are inconsistent")
        for item in self.timeline:
            if isinstance(item, (TodayPlannerTaskBlock, TodayPlannerHabitSlot)):
                minutes = int(
                    (item.ends_at - item.starts_at).total_seconds() // 60,
                )
                if minutes != item.planned_minutes:
                    raise ValueError("today-v2 Planner duration is inconsistent")
        if self.progress is not None:
            assert self.check_ins is not None
            preparation = [
                item
                for item in self.timeline
                if isinstance(item, TodayPreparationBlock)
            ]
            expected_total = (
                2 + len(self.tasks.today) + len(self.habits) + len(preparation)
            )
            expected_completed = (
                int(self.check_ins.morning_saved)
                + int(self.check_ins.evening_saved)
                + sum(task.status == "done" for task in self.tasks.today)
                + sum(habit.outcome == "completed" for habit in self.habits)
                + sum(item.state == "completed" for item in preparation)
            )
            if (
                self.progress.total != expected_total
                or self.progress.completed != expected_completed
            ):
                raise ValueError("today-v2 progress does not match unique targets")
        return self
