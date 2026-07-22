from __future__ import annotations

import re
from datetime import date, datetime, time
from typing import Annotated, Any, Literal, Self
from uuid import UUID
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from pydantic import BaseModel, ConfigDict, Field, field_validator, model_validator


PLANNER_CONTRACT_VERSION = "planner-v1"
PLANNER_PREFERENCES_CONTRACT_VERSION = "planner-preferences-v1"


class PlannerPreferencesUpdateRequest(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, frozen=True)

    request_id: UUID = Field(strict=False)
    expected_updated_at: datetime | None = Field(strict=False)
    use_calendar_busy_time: bool

    @model_validator(mode="before")
    @classmethod
    def validate_transport(cls, value: Any) -> Any:
        if isinstance(value, dict):
            _require_transport_uuid(value.get("request_id"), field="request_id")
            _require_transport_datetime_or_none(
                value.get("expected_updated_at"),
                field="expected_updated_at",
            )
        return value

    @model_validator(mode="after")
    def validate_timestamp(self) -> Self:
        _aware_or_none(self.expected_updated_at, "expected_updated_at")
        return self


class PlannerPreferencesResponse(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, frozen=True)

    contract_version: Literal["planner-preferences-v1"]
    origin: Literal["authenticated_backend"]
    use_calendar_busy_time: bool
    updated_at: datetime | None
    current_calendar_import_id: UUID | None
    calendar_available: bool

    @model_validator(mode="after")
    def validate_preferences(self) -> Self:
        _aware_or_none(self.updated_at, "updated_at")
        if self.calendar_available != (self.current_calendar_import_id is not None):
            raise ValueError("planner calendar availability is inconsistent")
        return self


class PlannerHabitCadence(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, frozen=True)

    kind: Literal["daily", "weekdays", "weekly_target"]
    scheduled_weekdays: list[int] = Field(default_factory=list, max_length=7)
    weekly_target: int = Field(ge=1, le=7)

    @model_validator(mode="after")
    def validate_cadence(self) -> Self:
        if len(self.scheduled_weekdays) != len(set(self.scheduled_weekdays)):
            raise ValueError("habit weekdays must be unique")
        if any(day < 1 or day > 7 for day in self.scheduled_weekdays):
            raise ValueError("habit weekday is invalid")
        if self.kind == "daily":
            if self.scheduled_weekdays or self.weekly_target != 1:
                raise ValueError("daily habit cadence is invalid")
        elif self.kind == "weekdays":
            if not self.scheduled_weekdays or self.weekly_target != 1:
                raise ValueError("weekday habit cadence is invalid")
        elif self.scheduled_weekdays:
            raise ValueError("weekly-target cadence cannot pin weekdays")
        return self


class PlannerTaskTarget(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, frozen=True)

    kind: Literal["task"]
    operation: Literal["create", "update"]
    target_id: UUID = Field(strict=False)
    expected_updated_at: datetime | None = Field(strict=False)
    title: str = Field(min_length=1, max_length=160)
    description: str | None = Field(default=None, max_length=2_000)
    priority: Literal["low", "medium", "high", "critical"]
    estimated_minutes: int | None = Field(default=None, ge=5, le=480)
    deadline_at: datetime | None = Field(default=None, strict=False)
    preferred_session_minutes: int | None = Field(default=None, ge=5, le=240)

    @model_validator(mode="before")
    @classmethod
    def validate_transport(cls, value: Any) -> Any:
        if isinstance(value, dict):
            _require_transport_uuid(value.get("target_id"), field="target_id")
            _require_transport_datetime_or_none(
                value.get("expected_updated_at"),
                field="expected_updated_at",
            )
            _require_transport_datetime_or_none(
                value.get("deadline_at"),
                field="deadline_at",
            )
        return value

    @model_validator(mode="after")
    def validate_target(self) -> Self:
        _trimmed(self.title, "task title")
        _trimmed_or_none(self.description, "task description")
        _aware_or_none(self.expected_updated_at, "expected_updated_at")
        _aware_or_none(self.deadline_at, "deadline_at")
        if (self.operation == "create") != (self.expected_updated_at is None):
            raise ValueError("task operation does not match expected_updated_at")
        if (
            self.preferred_session_minutes is not None
            and self.preferred_session_minutes % 5 != 0
        ):
            raise ValueError("task session duration must use five-minute increments")
        return self


class PlannerHabitTarget(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, frozen=True)

    kind: Literal["habit"]
    operation: Literal["create", "update"]
    target_id: UUID = Field(strict=False)
    expected_updated_at: datetime | None = Field(strict=False)
    title: str = Field(min_length=1, max_length=160)
    description: str | None = Field(default=None, max_length=2_000)
    cadence: PlannerHabitCadence
    duration_minutes: int = Field(ge=5, le=240)

    @model_validator(mode="before")
    @classmethod
    def validate_transport(cls, value: Any) -> Any:
        if isinstance(value, dict):
            _require_transport_uuid(value.get("target_id"), field="target_id")
            _require_transport_datetime_or_none(
                value.get("expected_updated_at"),
                field="expected_updated_at",
            )
        return value

    @model_validator(mode="after")
    def validate_target(self) -> Self:
        _trimmed(self.title, "habit title")
        _trimmed_or_none(self.description, "habit description")
        _aware_or_none(self.expected_updated_at, "expected_updated_at")
        if (self.operation == "create") != (self.expected_updated_at is None):
            raise ValueError("habit operation does not match expected_updated_at")
        if self.duration_minutes % 5 != 0:
            raise ValueError("habit duration must use five-minute increments")
        return self


PlannerActionTarget = Annotated[
    PlannerTaskTarget | PlannerHabitTarget,
    Field(discriminator="kind"),
]


class PlannerActionProposalRequest(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, frozen=True)

    request_id: UUID = Field(strict=False)
    plan_id: UUID = Field(strict=False)
    base_revision: int = Field(ge=0)
    planning_start_on: date = Field(strict=False)
    target: PlannerActionTarget

    @model_validator(mode="before")
    @classmethod
    def validate_transport(cls, value: Any) -> Any:
        if isinstance(value, dict):
            _require_transport_uuid(value.get("request_id"), field="request_id")
            _require_transport_uuid(value.get("plan_id"), field="plan_id")
            _require_transport_date(
                value.get("planning_start_on"),
                field="planning_start_on",
            )
        return value


class PlannerActionMutationRequest(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, frozen=True)

    request_id: UUID = Field(strict=False)
    expected_revision: int = Field(ge=1)

    @model_validator(mode="before")
    @classmethod
    def validate_transport(cls, value: Any) -> Any:
        if isinstance(value, dict):
            _require_transport_uuid(value.get("request_id"), field="request_id")
        return value


class PlannerTaskBlock(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, frozen=True)

    id: UUID
    sequence: int = Field(ge=1, le=1_500)
    starts_at: datetime
    ends_at: datetime
    local_date: date
    planned_minutes: int = Field(ge=5, le=240)
    state: Literal["proposed", "active", "released", "superseded"]

    @model_validator(mode="after")
    def validate_block(self) -> Self:
        _positive_interval(self.starts_at, self.ends_at, "task block")
        if self.planned_minutes % 5 != 0:
            raise ValueError("task block must use five-minute increments")
        return self


class PlannerHabitSlot(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, frozen=True)

    id: UUID
    weekday: int = Field(ge=1, le=7)
    starts_at: time
    ends_at: time
    duration_minutes: int = Field(ge=5, le=240)
    state: Literal["proposed", "active", "released", "superseded"]

    @model_validator(mode="after")
    def validate_slot(self) -> Self:
        if (
            self.starts_at.tzinfo is not None
            or self.ends_at.tzinfo is not None
            or self.ends_at <= self.starts_at
            or self.duration_minutes % 5 != 0
        ):
            raise ValueError("habit slot is invalid")
        return self


class PlannerActionRevision(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, frozen=True)

    revision: int = Field(ge=1)
    base_revision: int = Field(ge=0)
    state: Literal["proposed", "active", "superseded"]
    target: PlannerActionTarget
    timezone: str = Field(min_length=1, max_length=100)
    best_energy_window: Literal[
        "early_morning",
        "morning",
        "afternoon",
        "evening",
        "variable",
    ]
    planning_start_on: date
    planning_fingerprint: str = Field(pattern=r"^[0-9a-f]{64}$")
    calendar_import_id: UUID | None
    planned_minutes: int = Field(ge=0)
    unscheduled_minutes: int = Field(ge=0)
    task_blocks: list[PlannerTaskBlock] = Field(default_factory=list, max_length=1_500)
    habit_slots: list[PlannerHabitSlot] = Field(default_factory=list, max_length=7)
    created_at: datetime
    activated_at: datetime | None
    superseded_at: datetime | None

    @model_validator(mode="after")
    def validate_revision(self) -> Self:
        if self.base_revision + 1 != self.revision:
            raise ValueError("planner revision sequence is invalid")
        try:
            ZoneInfo(self.timezone)
        except ZoneInfoNotFoundError as exc:
            raise ValueError("planner revision timezone is invalid") from exc
        for value in (self.created_at, self.activated_at, self.superseded_at):
            _aware_or_none(value, "planner revision timestamp")
        if self.state == "proposed" and (
            self.activated_at is not None or self.superseded_at is not None
        ):
            raise ValueError("proposed planner revision has lifecycle timestamps")
        if self.state == "active" and (
            self.activated_at is None or self.superseded_at is not None
        ):
            raise ValueError("active planner revision timestamps are invalid")
        if self.state == "superseded" and self.superseded_at is None:
            raise ValueError("superseded planner revision requires a timestamp")
        if isinstance(self.target, PlannerTaskTarget):
            if self.habit_slots:
                raise ValueError("task revision cannot contain habit slots")
            if self.planned_minutes != sum(
                block.planned_minutes for block in self.task_blocks
            ):
                raise ValueError("task revision planned-minute total is invalid")
        else:
            if self.task_blocks:
                raise ValueError("habit revision cannot contain task blocks")
            if self.planned_minutes != sum(
                slot.duration_minutes for slot in self.habit_slots
            ):
                raise ValueError("habit revision planned-minute total is invalid")
        return self


class PlannerActionPlan(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, frozen=True)

    id: UUID
    target_kind: Literal["task", "habit"]
    target_id: UUID
    status: Literal["draft", "active", "unscheduled", "cancelled"]
    current_revision: int = Field(ge=0)
    latest_revision: int = Field(ge=1)
    needs_attention: bool
    attention_reasons: list[str] = Field(default_factory=list, max_length=12)
    active_revision: PlannerActionRevision | None
    pending_revision: PlannerActionRevision | None

    @model_validator(mode="after")
    def validate_plan(self) -> Self:
        if len(self.attention_reasons) != len(set(self.attention_reasons)):
            raise ValueError("planner attention reasons must be unique")
        if self.needs_attention != bool(self.attention_reasons):
            raise ValueError("planner attention state is inconsistent")
        if (self.current_revision == 0) != (self.active_revision is None):
            raise ValueError("planner active revision projection is inconsistent")
        if self.active_revision is not None:
            if self.active_revision.revision != self.current_revision:
                raise ValueError("planner current revision is inconsistent")
            if self.active_revision.target.kind != self.target_kind:
                raise ValueError("planner target kind is inconsistent")
        if self.pending_revision is not None:
            if self.pending_revision.revision != self.latest_revision:
                raise ValueError("planner latest revision is inconsistent")
            if self.pending_revision.state != "proposed":
                raise ValueError("planner pending revision state is invalid")
        return self


class PlannerActionPlanResponse(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, frozen=True)

    contract_version: Literal["planner-v1"]
    origin: Literal["authenticated_backend"]
    plan: PlannerActionPlan


class PlannerCommitmentCreateRequest(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, frozen=True)

    request_id: UUID = Field(strict=False)
    commitment_id: UUID = Field(strict=False)
    title: str = Field(min_length=1, max_length=160)
    location: str | None = Field(default=None, max_length=300)
    recurrence: Literal["one_off", "weekly"]
    starts_at: datetime | None = Field(strict=False)
    ends_at: datetime | None = Field(strict=False)
    weekday: int | None = Field(default=None, ge=1, le=7)
    local_starts_at: time | None = Field(strict=False)
    local_ends_at: time | None = Field(strict=False)

    @model_validator(mode="before")
    @classmethod
    def validate_transport(cls, value: Any) -> Any:
        if isinstance(value, dict):
            _require_transport_uuid(value.get("request_id"), field="request_id")
            _require_transport_uuid(
                value.get("commitment_id"),
                field="commitment_id",
            )
            for field in ("starts_at", "ends_at"):
                _require_transport_datetime_or_none(value.get(field), field=field)
            for field in ("local_starts_at", "local_ends_at"):
                _require_transport_time_or_none(value.get(field), field=field)
        return value

    @model_validator(mode="after")
    def validate_commitment(self) -> Self:
        _trimmed(self.title, "commitment title")
        _trimmed_or_none(self.location, "commitment location")
        _commitment_shape(self)
        return self


class PlannerCommitmentUpdateRequest(PlannerCommitmentCreateRequest):
    expected_updated_at: datetime = Field(strict=False)

    @model_validator(mode="before")
    @classmethod
    def validate_update_transport(cls, value: Any) -> Any:
        if isinstance(value, dict):
            _require_transport_datetime(
                value.get("expected_updated_at"),
                field="expected_updated_at",
            )
        return value

    @model_validator(mode="after")
    def validate_update(self) -> Self:
        _aware_or_none(self.expected_updated_at, "expected_updated_at")
        return self


class PlannerCommitmentArchiveRequest(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, frozen=True)

    request_id: UUID = Field(strict=False)
    expected_updated_at: datetime = Field(strict=False)

    @model_validator(mode="before")
    @classmethod
    def validate_transport(cls, value: Any) -> Any:
        if isinstance(value, dict):
            _require_transport_uuid(value.get("request_id"), field="request_id")
            _require_transport_datetime(
                value.get("expected_updated_at"),
                field="expected_updated_at",
            )
        return value

    @model_validator(mode="after")
    def validate_update(self) -> Self:
        _aware_or_none(self.expected_updated_at, "expected_updated_at")
        return self


class PlannerCommitment(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, frozen=True)

    id: UUID
    title: str = Field(min_length=1, max_length=160)
    location: str | None = Field(default=None, max_length=300)
    recurrence: Literal["one_off", "weekly"]
    status: Literal["active", "archived"]
    starts_at: datetime | None
    ends_at: datetime | None
    weekday: int | None = Field(default=None, ge=1, le=7)
    local_starts_at: time | None
    local_ends_at: time | None
    created_at: datetime
    updated_at: datetime
    archived_at: datetime | None

    @model_validator(mode="after")
    def validate_commitment(self) -> Self:
        _trimmed(self.title, "commitment title")
        _trimmed_or_none(self.location, "commitment location")
        _commitment_shape(self)
        for value in (self.created_at, self.updated_at, self.archived_at):
            _aware_or_none(value, "commitment timestamp")
        if (self.status == "archived") != (self.archived_at is not None):
            raise ValueError("commitment archive state is inconsistent")
        return self


class PlannerCommitmentResponse(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, frozen=True)

    contract_version: Literal["planner-v1"]
    origin: Literal["authenticated_backend"]
    commitment: PlannerCommitment
    affected_plan_ids: list[UUID] = Field(default_factory=list, max_length=100)
    replayed: bool


class PlannerDayItem(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, frozen=True)

    id: UUID
    kind: Literal[
        "setup_commitment",
        "manual_commitment",
        "task_block",
        "habit_slot",
        "preparation",
        "calendar_event",
    ]
    title: str = Field(min_length=1, max_length=200)
    source_id: UUID
    starts_at: datetime | None
    ends_at: datetime | None
    all_day: bool
    state: str | None = Field(default=None, max_length=40)

    @model_validator(mode="after")
    def validate_item(self) -> Self:
        _trimmed(self.title, "planner day item title")
        if self.all_day:
            if self.starts_at is not None or self.ends_at is not None:
                raise ValueError("all-day planner item cannot carry timestamps")
        elif self.starts_at is None or self.ends_at is None:
            raise ValueError("timed planner item requires timestamps")
        else:
            _positive_interval(self.starts_at, self.ends_at, "planner day item")
        return self


class PlannerDay(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, frozen=True)

    local_date: date
    items: list[PlannerDayItem] = Field(default_factory=list, max_length=1_500)


class PlannerAttentionItem(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, frozen=True)

    id: str = Field(min_length=1, max_length=200)
    kind: Literal["conflict", "unscheduled", "stale_preview"]
    title: str = Field(min_length=1, max_length=160)
    detail: str = Field(min_length=1, max_length=240)
    plan_id: UUID | None
    unplaced_minutes: int = Field(ge=0)


class PlannerPreparationSummary(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, frozen=True)

    plan_id: UUID
    title: str = Field(min_length=1, max_length=160)
    status: Literal["draft", "active", "completed", "cancelled"]
    remaining_minutes: int = Field(ge=0)
    next_block_starts_at: datetime | None
    has_pending_preview: bool

    @model_validator(mode="after")
    def validate_next_block(self) -> Self:
        _aware_or_none(self.next_block_starts_at, "next preparation block")
        return self


class PlannerUnscheduledItem(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, frozen=True)

    id: UUID
    kind: Literal["task", "habit"]
    title: str = Field(min_length=1, max_length=160)
    reason: Literal["not_planned", "released", "missing_scheduling_inputs"]
    expected_updated_at: datetime | None
    description: str | None = Field(default=None, max_length=2_000)
    priority: Literal["low", "medium", "high", "critical"] | None
    estimated_minutes: int | None = Field(default=None, ge=5, le=480)
    deadline_at: datetime | None
    preferred_session_minutes: int | None = Field(default=None, ge=5, le=240)
    cadence: PlannerHabitCadence | None
    duration_minutes: int | None = Field(default=None, ge=5, le=240)

    @model_validator(mode="after")
    def validate_target_summary(self) -> Self:
        _trimmed(self.title, "unscheduled target title")
        _trimmed_or_none(self.description, "unscheduled target description")
        _aware_or_none(self.expected_updated_at, "unscheduled target version")
        _aware_or_none(self.deadline_at, "unscheduled task deadline")
        if self.preferred_session_minutes is not None and (
            self.preferred_session_minutes % 5 != 0
        ):
            raise ValueError("unscheduled task session must use five-minute steps")
        if self.duration_minutes is not None and self.duration_minutes % 5 != 0:
            raise ValueError("unscheduled habit duration must use five-minute steps")
        if self.kind == "task":
            if (
                self.priority is None
                or self.cadence is not None
                or self.duration_minutes is not None
            ):
                raise ValueError("unscheduled task summary is inconsistent")
        elif any(
            value is not None
            for value in (
                self.priority,
                self.estimated_minutes,
                self.deadline_at,
                self.preferred_session_minutes,
            )
        ) or self.cadence is None:
            raise ValueError("unscheduled habit summary is inconsistent")
        return self


class PlannerOverviewResponse(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, frozen=True)

    contract_version: Literal["planner-v1"]
    origin: Literal["authenticated_backend"]
    generated_at: datetime
    timezone: str = Field(min_length=1, max_length=100)
    local_date: date
    preferences: PlannerPreferencesResponse
    action_plans: list[PlannerActionPlan] = Field(
        default_factory=list,
        max_length=1_000,
    )
    commitments: list[PlannerCommitment] = Field(
        default_factory=list,
        max_length=1_000,
    )
    needs_attention: list[PlannerAttentionItem] = Field(
        default_factory=list,
        max_length=500,
    )
    days: list[PlannerDay] = Field(min_length=7, max_length=7)
    ongoing_preparation: list[PlannerPreparationSummary] = Field(
        default_factory=list,
        max_length=50,
    )
    unscheduled: list[PlannerUnscheduledItem] = Field(
        default_factory=list,
        max_length=1_000,
    )
    history: list[PlannerUnscheduledItem] = Field(
        default_factory=list,
        max_length=1_000,
    )

    @model_validator(mode="after")
    def validate_overview(self) -> Self:
        _aware_or_none(self.generated_at, "generated_at")
        try:
            zone = ZoneInfo(self.timezone)
        except ZoneInfoNotFoundError as exc:
            raise ValueError("planner timezone is invalid") from exc
        if self.generated_at.astimezone(zone).date() != self.local_date:
            raise ValueError("planner local date is inconsistent")
        expected_days = [
            date.fromordinal(self.local_date.toordinal() + offset)
            for offset in range(7)
        ]
        if [day.local_date for day in self.days] != expected_days:
            raise ValueError("planner overview must contain seven consecutive days")
        return self


def _commitment_shape(value: object) -> None:
    recurrence = getattr(value, "recurrence")
    starts_at = getattr(value, "starts_at")
    ends_at = getattr(value, "ends_at")
    weekday = getattr(value, "weekday")
    local_starts_at = getattr(value, "local_starts_at")
    local_ends_at = getattr(value, "local_ends_at")
    if recurrence == "one_off":
        if (
            starts_at is None
            or ends_at is None
            or weekday is not None
            or local_starts_at is not None
            or local_ends_at is not None
        ):
            raise ValueError("one-off commitment shape is invalid")
        _positive_interval(starts_at, ends_at, "one-off commitment")
    elif (
        starts_at is not None
        or ends_at is not None
        or weekday is None
        or local_starts_at is None
        or local_ends_at is None
        or local_starts_at.tzinfo is not None
        or local_ends_at.tzinfo is not None
        or local_ends_at <= local_starts_at
    ):
        raise ValueError("weekly commitment shape is invalid")


def _trimmed(value: str, field: str) -> None:
    if value.strip() != value:
        raise ValueError(f"{field} must be trimmed")


def _trimmed_or_none(value: str | None, field: str) -> None:
    if value is not None:
        _trimmed(value, field)


def _aware_or_none(value: datetime | None, field: str) -> None:
    if value is not None and (value.tzinfo is None or value.utcoffset() is None):
        raise ValueError(f"{field} must be timezone-aware")


def _positive_interval(starts_at: datetime, ends_at: datetime, field: str) -> None:
    _aware_or_none(starts_at, field)
    _aware_or_none(ends_at, field)
    if ends_at <= starts_at:
        raise ValueError(f"{field} interval is invalid")


def _require_transport_uuid(value: Any, *, field: str) -> None:
    if not isinstance(value, str) or value != value.strip():
        raise ValueError(f"{field} must be a canonical UUID string")
    try:
        parsed = UUID(value)
    except ValueError as exc:
        raise ValueError(f"{field} must be a canonical UUID string") from exc
    if str(parsed) != value:
        raise ValueError(f"{field} must be a canonical UUID string")


def _require_transport_datetime(value: Any, *, field: str) -> None:
    if not isinstance(value, str) or not re.fullmatch(
        r"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}"
        r"(?:\.\d{1,6})?(?:Z|[+-]\d{2}:\d{2})",
        value,
    ):
        raise ValueError(f"{field} must be an aware ISO-8601 string")


def _require_transport_datetime_or_none(value: Any, *, field: str) -> None:
    if value is not None:
        _require_transport_datetime(value, field=field)


def _require_transport_date(value: Any, *, field: str) -> None:
    if not isinstance(value, str) or not re.fullmatch(r"\d{4}-\d{2}-\d{2}", value):
        raise ValueError(f"{field} must be an ISO-8601 date string")
    try:
        parsed = date.fromisoformat(value)
    except ValueError as exc:
        raise ValueError(f"{field} must be an ISO-8601 date string") from exc
    if parsed.isoformat() != value:
        raise ValueError(f"{field} must be an ISO-8601 date string")


def _require_transport_time_or_none(value: Any, *, field: str) -> None:
    if value is None:
        return
    if not isinstance(value, str) or not re.fullmatch(
        r"(?:[01]\d|2[0-3]):[0-5]\d:[0-5]\d(?:\.\d{1,6})?",
        value,
    ):
        raise ValueError(f"{field} must be an ISO-8601 wall time string")
