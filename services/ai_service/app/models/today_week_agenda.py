from __future__ import annotations

from datetime import date, datetime, timedelta
from typing import Literal, Self
from uuid import UUID
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from pydantic import BaseModel, ConfigDict, Field, model_validator


TODAY_WEEK_AGENDA_CONTRACT_VERSION = "today-week-agenda-v1"

TodayWeekAgendaCategory = Literal[
    "setup",
    "preparation",
    "calendar",
    "focus",
    "task",
    "habit",
    "fixed_commitment",
]
TodayWeekAgendaActionKind = Literal[
    "start_preparation_focus",
    "start_task_focus",
    "resume_focus",
    "reflect_focus",
    "open_preparation_plan",
    "open_habit",
]
TodayWeekAgendaStatus = Literal[
    "scheduled",
    "upcoming",
    "partial",
    "completed",
    "missed",
    "confirmed",
    "tentative",
    "active",
    "abandoned",
    "todo",
    "in_progress",
    "done",
    "cancelled",
    "open",
    "skipped",
]

_CATEGORY_STATUSES: dict[str, frozenset[str]] = {
    "setup": frozenset({"scheduled"}),
    "preparation": frozenset({"upcoming", "partial", "completed", "missed"}),
    "calendar": frozenset({"confirmed", "tentative"}),
    "focus": frozenset({"active", "completed", "abandoned"}),
    "task": frozenset({"todo", "in_progress", "done", "cancelled"}),
    "habit": frozenset({"open", "completed", "skipped"}),
    "fixed_commitment": frozenset({"scheduled"}),
}


class TodayWeekAgendaSourceState(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, frozen=True)

    status: Literal["current", "unavailable"]
    message: str | None = Field(default=None, min_length=1, max_length=160)

    @model_validator(mode="after")
    def validate_state(self) -> Self:
        if (self.status == "unavailable") != (self.message is not None):
            raise ValueError("week agenda source message must match its state")
        if self.message is not None and self.message.strip() != self.message:
            raise ValueError("week agenda source message must be trimmed")
        return self


class TodayWeekAgendaSourceStates(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, frozen=True)

    setup: TodayWeekAgendaSourceState
    preparation: TodayWeekAgendaSourceState
    calendar: TodayWeekAgendaSourceState
    focus: TodayWeekAgendaSourceState
    tasks: TodayWeekAgendaSourceState
    habits: TodayWeekAgendaSourceState
    fixed_commitments: TodayWeekAgendaSourceState


class TodayWeekAgendaAction(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, frozen=True)

    kind: TodayWeekAgendaActionKind
    target_id: UUID
    source_kind: Literal["deadline_plan_block", "planner_task_block"] | None = None
    local_date: date | None = None

    @model_validator(mode="after")
    def validate_action(self) -> Self:
        expected_source = {
            "start_preparation_focus": "deadline_plan_block",
            "start_task_focus": "planner_task_block",
            "resume_focus": None,
            "reflect_focus": None,
            "open_preparation_plan": None,
            "open_habit": None,
        }
        if self.source_kind != expected_source[self.kind]:
            raise ValueError("week agenda scheduled action source is invalid")
        if (self.kind == "open_habit") != (self.local_date is not None):
            raise ValueError("week agenda habit action date is invalid")
        return self


class TodayWeekAgendaItem(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, frozen=True)

    id: UUID
    category: TodayWeekAgendaCategory
    source_id: UUID
    plan_id: UUID | None = None
    habit_id: UUID | None = None
    local_date: date
    title: str = Field(min_length=1, max_length=200)
    detail: str | None = Field(default=None, max_length=300)
    status: TodayWeekAgendaStatus
    planned_minutes: int | None = Field(default=None, ge=5, le=240)
    credited_tracked_minutes: int | None = Field(default=None, ge=0, le=240)
    remaining_minutes: int | None = Field(default=None, ge=0, le=240)
    all_day: bool
    local_starts_at: str | None = Field(default=None, max_length=19)
    local_ends_at: str | None = Field(default=None, max_length=19)
    starts_at: datetime | None = None
    ends_at: datetime | None = None
    action: TodayWeekAgendaAction | None = None

    @model_validator(mode="after")
    def validate_item(self) -> Self:
        if self.title.strip() != self.title:
            raise ValueError("week agenda title must be trimmed")
        if self.detail is not None and self.detail.strip() != self.detail:
            raise ValueError("week agenda detail must be trimmed")
        if self.status not in _CATEGORY_STATUSES[self.category]:
            raise ValueError("week agenda status does not match its category")
        preparation_values = (
            self.plan_id,
            self.planned_minutes,
            self.credited_tracked_minutes,
            self.remaining_minutes,
        )
        if self.category == "preparation":
            if any(value is None for value in preparation_values):
                raise ValueError("week agenda Preparation facts are incomplete")
            assert self.planned_minutes is not None
            assert self.credited_tracked_minutes is not None
            assert self.remaining_minutes is not None
            if (
                self.credited_tracked_minutes > self.planned_minutes
                or self.remaining_minutes
                != self.planned_minutes - self.credited_tracked_minutes
            ):
                raise ValueError("week agenda Preparation credit is invalid")
        elif any(value is not None for value in preparation_values):
            raise ValueError("non-Preparation item cannot carry Preparation facts")
        if (self.category == "habit") != (self.habit_id is not None):
            raise ValueError("week agenda Habit identity is invalid")
        local_values = (self.local_starts_at, self.local_ends_at)
        utc_values = (self.starts_at, self.ends_at)
        if self.all_day:
            if any(value is not None for value in (*local_values, *utc_values)):
                raise ValueError("week agenda all-day item cannot carry times")
        else:
            if any(value is None for value in (*local_values, *utc_values)):
                raise ValueError("week agenda timed item requires all times")
            assert self.local_starts_at is not None
            assert self.local_ends_at is not None
            assert self.starts_at is not None
            assert self.ends_at is not None
            try:
                local_start = datetime.fromisoformat(self.local_starts_at)
                local_end = datetime.fromisoformat(self.local_ends_at)
            except ValueError as exc:
                raise ValueError("week agenda local time is invalid") from exc
            if (
                local_start.tzinfo is not None
                or local_end.tzinfo is not None
                or local_start.isoformat(timespec="seconds") != self.local_starts_at
                or local_end.isoformat(timespec="seconds") != self.local_ends_at
                or local_start.date() != self.local_date
                or local_end.date()
                not in {self.local_date, self.local_date + timedelta(days=1)}
            ):
                raise ValueError("week agenda local interval is invalid")
            if (
                self.starts_at.tzinfo is None
                or self.ends_at.tzinfo is None
                or self.starts_at.utcoffset() is None
                or self.ends_at.utcoffset() is None
                or self.ends_at <= self.starts_at
            ):
                raise ValueError("week agenda UTC interval is invalid")
        if self.action is not None:
            expected_categories = {
                "start_preparation_focus": "preparation",
                "start_task_focus": "task",
                "resume_focus": "focus",
                "reflect_focus": "focus",
                "open_preparation_plan": "preparation",
                "open_habit": "habit",
            }
            if expected_categories[self.action.kind] != self.category:
                raise ValueError("week agenda action does not match its category")
            if (
                self.action.kind
                in {
                    "start_preparation_focus",
                    "start_task_focus",
                    "resume_focus",
                    "reflect_focus",
                }
                and self.action.target_id != self.source_id
            ):
                raise ValueError("week agenda action target does not match its item")
            if self.action.kind == "open_preparation_plan" and (
                self.plan_id is None or self.action.target_id != self.plan_id
            ):
                raise ValueError("week agenda Preparation action target is invalid")
            if self.action.kind == "open_habit" and (
                self.habit_id is None
                or self.action.target_id != self.habit_id
                or self.action.local_date != self.local_date
            ):
                raise ValueError("week agenda habit action date does not match")
            if self.action.kind == "start_preparation_focus" and (
                self.status not in {"upcoming", "partial", "missed"}
                or self.remaining_minutes is None
                or self.remaining_minutes < 5
            ):
                raise ValueError("week agenda Preparation start action is invalid")
            if self.action.kind == "start_task_focus" and self.status not in {
                "todo",
                "in_progress",
            }:
                raise ValueError("week agenda Task start action is invalid")
            if self.action.kind == "resume_focus" and self.status != "active":
                raise ValueError("week agenda Focus resume action is invalid")
            if self.action.kind == "reflect_focus" and self.status not in {
                "completed",
                "abandoned",
            }:
                raise ValueError("week agenda Focus reflection action is invalid")
        return self


class TodayWeekAgendaDay(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, frozen=True)

    local_date: date
    items: list[TodayWeekAgendaItem] = Field(default_factory=list, max_length=4_000)

    @model_validator(mode="after")
    def validate_day(self) -> Self:
        if any(item.local_date != self.local_date for item in self.items):
            raise ValueError("week agenda day contains an item for another date")
        ids = [item.id for item in self.items]
        if len(ids) != len(set(ids)):
            raise ValueError("week agenda day contains duplicate items")
        return self


class TodayWeekAgendaResponse(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, frozen=True)

    contract_version: Literal["today-week-agenda-v1"]
    origin: Literal["authenticated_backend"]
    generated_at: datetime
    timezone: str = Field(min_length=1, max_length=100)
    local_today: date
    week_starts_on: date
    week_ends_on: date
    days: list[TodayWeekAgendaDay] = Field(min_length=7, max_length=7)
    source_states: TodayWeekAgendaSourceStates

    @model_validator(mode="after")
    def validate_response(self) -> Self:
        if self.generated_at.tzinfo is None or self.generated_at.utcoffset() is None:
            raise ValueError("week agenda generation time must be aware")
        try:
            zone = ZoneInfo(self.timezone)
        except ZoneInfoNotFoundError as exc:
            raise ValueError("week agenda timezone is invalid") from exc
        if self.generated_at.astimezone(zone).date() != self.local_today:
            raise ValueError("week agenda local today is invalid")
        if (
            self.week_starts_on.isoweekday() != 1
            or self.week_ends_on != self.week_starts_on + timedelta(days=6)
            or not self.week_starts_on <= self.local_today <= self.week_ends_on
        ):
            raise ValueError("week agenda bounds are invalid")
        expected_dates = [
            self.week_starts_on + timedelta(days=offset) for offset in range(7)
        ]
        if [day.local_date for day in self.days] != expected_dates:
            raise ValueError("week agenda must contain the complete ordered week")
        category_sources = {
            "setup": "setup",
            "preparation": "preparation",
            "calendar": "calendar",
            "focus": "focus",
            "task": "tasks",
            "habit": "habits",
            "fixed_commitment": "fixed_commitments",
        }
        for day in self.days:
            for item in day.items:
                if (
                    getattr(self.source_states, category_sources[item.category]).status
                    != "current"
                ):
                    raise ValueError("unavailable week source cannot expose items")
                if (
                    item.action is not None
                    and item.action.kind == "open_habit"
                    and item.action.local_date != self.local_today
                ):
                    raise ValueError(
                        "week agenda Habit action is not for local today",
                    )
                if item.all_day:
                    continue
                assert item.starts_at is not None
                assert item.ends_at is not None
                assert item.local_starts_at is not None
                assert item.local_ends_at is not None
                expected_start = item.starts_at.astimezone(zone).replace(tzinfo=None)
                expected_end = item.ends_at.astimezone(zone).replace(tzinfo=None)
                if (
                    expected_start.isoformat(timespec="seconds") != item.local_starts_at
                    or expected_end.isoformat(timespec="seconds") != item.local_ends_at
                ):
                    raise ValueError(
                        "week agenda local interval does not match its timezone",
                    )
        return self
