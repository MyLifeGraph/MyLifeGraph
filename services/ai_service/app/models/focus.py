from __future__ import annotations

from datetime import date, datetime
from typing import Annotated, Any, Literal, Self
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, model_validator


FocusSourceKind = Literal[
    "manual",
    "deadline_plan_block",
    "planner_task_block",
]
ScheduledFocusSourceKind = Literal[
    "deadline_plan_block",
    "planner_task_block",
]


class FocusCapabilitiesResponse(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, frozen=True)

    contract_version: Literal["focus-capabilities-v1"] = "focus-capabilities-v1"
    origin: Literal["authenticated_backend"] = "authenticated_backend"
    focus_session_v2: Literal[True] = True


class ManualFocusStartRequest(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, frozen=True)

    contract_version: Literal["focus-start-v2"]
    request_id: UUID = Field(strict=False)
    source_kind: Literal["manual"]
    planned_minutes: int = Field(ge=5, le=240)
    recovery_minutes: int = Field(ge=0, le=60)
    target_kind: Literal["task", "habit"] | None
    target_id: UUID | None = Field(strict=False)
    label: str | None = Field(default=None, min_length=1, max_length=160)

    @model_validator(mode="before")
    @classmethod
    def validate_transport(cls, value: Any) -> Any:
        if isinstance(value, dict):
            _transport_uuid(value.get("request_id"), "request_id")
            _transport_optional_uuid(value.get("target_id"), "target_id")
        return value

    @model_validator(mode="after")
    def validate_manual(self) -> Self:
        if (self.target_kind is None) != (self.target_id is None):
            raise ValueError("manual Focus target is incomplete")
        if self.recovery_minutes != 0 and (
            self.recovery_minutes < 5 or self.recovery_minutes % 5 != 0
        ):
            raise ValueError("manual Focus recovery is invalid")
        if self.label is not None and self.label != self.label.strip():
            raise ValueError("manual Focus label must be trimmed")
        return self


class ScheduledFocusStartRequest(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, frozen=True)

    contract_version: Literal["focus-start-v2"]
    request_id: UUID = Field(strict=False)
    source_kind: ScheduledFocusSourceKind
    source_block_id: UUID = Field(strict=False)
    planned_minutes: int = Field(ge=5, le=240)

    @model_validator(mode="before")
    @classmethod
    def validate_transport(cls, value: Any) -> Any:
        if isinstance(value, dict):
            _transport_uuid(value.get("request_id"), "request_id")
            _transport_uuid(value.get("source_block_id"), "source_block_id")
        return value


FocusStartRequest = Annotated[
    ManualFocusStartRequest | ScheduledFocusStartRequest,
    Field(discriminator="source_kind"),
]


class FocusStartTarget(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, frozen=True)

    kind: Literal["task"]
    id: UUID = Field(strict=False)
    title: str = Field(min_length=1, max_length=160)


class FocusStartContextResponse(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, frozen=True)

    contract_version: Literal["focus-start-context-v2"]
    origin: Literal["authenticated_backend"]
    source_kind: ScheduledFocusSourceKind
    block_id: UUID = Field(strict=False)
    target: FocusStartTarget
    original_starts_at: datetime = Field(strict=False)
    original_ends_at: datetime = Field(strict=False)
    recovery_minutes: int = Field(ge=0, le=60)
    remaining_minutes: int = Field(ge=0, le=240)
    source_state: Literal["upcoming", "partial", "completed", "missed"]
    can_start: bool
    blocking_reason: (
        Literal[
            "source_fully_credited",
            "source_remaining_too_short",
            "active_focus_session",
            "deadline_plan_block",
            "planner_task_block",
            "fixed_commitment",
            "recurring_commitment",
            "availability_unavailable",
            "calendar_availability_unavailable",
            "calendar_busy",
        ]
        | None
    )

    @model_validator(mode="after")
    def validate_context(self) -> Self:
        _aware(self.original_starts_at, "original_starts_at")
        _aware(self.original_ends_at, "original_ends_at")
        if self.original_ends_at <= self.original_starts_at:
            raise ValueError("Focus source interval is invalid")
        if self.recovery_minutes != 0 and self.recovery_minutes % 5 != 0:
            raise ValueError("Focus source recovery is invalid")
        if self.can_start != (self.blocking_reason is None):
            raise ValueError("Focus startability is inconsistent")
        if (self.remaining_minutes == 0) != (self.source_state == "completed"):
            raise ValueError("Focus source completion is inconsistent")
        if self.remaining_minutes == 0 and (
            self.blocking_reason != "source_fully_credited"
        ):
            raise ValueError("Completed Focus source blocking reason is invalid")
        if 0 < self.remaining_minutes < 5 and (
            self.blocking_reason != "source_remaining_too_short"
        ):
            raise ValueError("Short Focus source blocking reason is invalid")
        if self.remaining_minutes >= 5 and self.blocking_reason in {
            "source_fully_credited",
            "source_remaining_too_short",
        }:
            raise ValueError("Focus source blocking reason is invalid")
        return self


class FocusScheduleSource(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, frozen=True)

    source_kind: ScheduledFocusSourceKind
    block_id: UUID = Field(strict=False)
    original_starts_at: datetime = Field(strict=False)
    original_ends_at: datetime = Field(strict=False)
    original_recovery_minutes: int = Field(ge=0, le=60)

    @model_validator(mode="after")
    def validate_source(self) -> Self:
        _aware(self.original_starts_at, "original_starts_at")
        _aware(self.original_ends_at, "original_ends_at")
        if self.original_ends_at <= self.original_starts_at:
            raise ValueError("Focus schedule source interval is invalid")
        if (
            self.original_recovery_minutes != 0
            and self.original_recovery_minutes % 5 != 0
        ):
            raise ValueError("Focus schedule source recovery is invalid")
        return self


class FocusSessionResponse(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, frozen=True)

    contract_version: Literal["focus-session-v2"]
    origin: Literal["authenticated_backend"]
    replayed: bool
    id: UUID = Field(strict=False)
    status: Literal["active", "completed", "abandoned"]
    started_at: datetime = Field(strict=False)
    ended_at: datetime | None = Field(strict=False)
    planned_minutes: int = Field(ge=5, le=240)
    actual_minutes: int | None = Field(default=None, ge=0)
    label: str | None = Field(default=None, max_length=160)
    task_id: UUID | None = Field(strict=False)
    habit_id: UUID | None = Field(strict=False)
    entry_date: date = Field(strict=False)
    recovery_minutes: int = Field(ge=0, le=60)
    updated_at: datetime = Field(strict=False)
    schedule_source: FocusScheduleSource | None

    @model_validator(mode="after")
    def validate_session(self) -> Self:
        _aware(self.started_at, "started_at")
        _aware(self.ended_at, "ended_at")
        _aware(self.updated_at, "updated_at")
        if self.task_id is not None and self.habit_id is not None:
            raise ValueError("Focus session has multiple targets")
        active = self.status == "active"
        if active != (self.ended_at is None and self.actual_minutes is None):
            raise ValueError("Focus session lifecycle is invalid")
        if self.ended_at is not None:
            if self.ended_at < self.started_at:
                raise ValueError("Focus session end precedes start")
            elapsed = int((self.ended_at - self.started_at).total_seconds() // 60)
            if elapsed != self.actual_minutes:
                raise ValueError("Focus actual duration is invalid")
        if self.recovery_minutes != 0 and self.recovery_minutes % 5 != 0:
            raise ValueError("Focus recovery is invalid")
        if self.schedule_source is not None:
            if self.task_id is None or self.habit_id is not None:
                raise ValueError("Scheduled Focus must target one task")
            if self.schedule_source.original_recovery_minutes != self.recovery_minutes:
                raise ValueError("Scheduled Focus recovery changed")
        return self


def _transport_uuid(value: object, field: str) -> None:
    if not isinstance(value, str):
        raise ValueError(f"{field} must be a UUID string")
    parsed = UUID(value)
    if str(parsed) != value:
        raise ValueError(f"{field} must be a canonical lowercase UUID")


def _transport_optional_uuid(value: object, field: str) -> None:
    if value is not None:
        _transport_uuid(value, field)


def _aware(value: datetime | None, field: str) -> None:
    if value is not None and (value.tzinfo is None or value.utcoffset() is None):
        raise ValueError(f"{field} must include a timezone")
