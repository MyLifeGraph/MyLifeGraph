from __future__ import annotations

import math
import re
from datetime import date, datetime
from typing import Any, Literal, Self
from uuid import UUID
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from pydantic import BaseModel, ConfigDict, Field, field_validator, model_validator


EXAM_PLAN_HEALTH_CONTRACT_VERSION = "exam-plan-health-v1"

ExamPlanHealthStatus = Literal["green", "yellow", "red", "unknown"]
ExamPlanHealthReason = Literal[
    "overdue_remaining",
    "capacity_deficit",
    "low_percentage_reserve",
    "low_session_reserve",
    "latest_safe_start_near",
    "calendar_import_unavailable",
    "calendar_window_incomplete",
    "recurring_availability_invalid",
    "higher_priority_capacity_unknown",
]
ExamPlanHealthMissingSource = Literal[
    "calendar_import",
    "calendar_horizon",
    "recurring_availability",
    "higher_priority_exam_capacity",
]


class ExamPlanHealthItem(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, frozen=True)

    plan_id: UUID
    title: str = Field(min_length=1, max_length=160)
    deadline_at: datetime
    local_deadline_date: date
    status: ExamPlanHealthStatus
    remaining_minutes: int = Field(ge=0, le=30_000)
    preferred_session_minutes: int = Field(ge=25, le=180)
    sessions_needed: int = Field(ge=0, le=1_200)
    future_reserved_minutes: int = Field(ge=0, le=30_000)
    minutes_to_schedule: int = Field(ge=0, le=30_000)
    available_replan_capacity_minutes: int | None = Field(
        default=None,
        ge=0,
        le=200_000,
    )
    reserve_minutes: int | None = Field(default=None, ge=-30_000, le=200_000)
    reserve_full_sessions: int | None = Field(default=None, ge=0, le=8_000)
    latest_safe_start_on: date | None = None
    recommended_start_on: date | None = None
    recommended_start_reason: str | None = Field(default=None, max_length=240)
    reasons: list[ExamPlanHealthReason] = Field(max_length=9)
    missing_sources: list[ExamPlanHealthMissingSource] = Field(max_length=4)

    @field_validator("title")
    @classmethod
    def require_exact_title(cls, value: str) -> str:
        if value != value.strip():
            raise ValueError(
                "exam health title must not contain surrounding whitespace"
            )
        return value

    @field_validator("deadline_at")
    @classmethod
    def require_aware_deadline(cls, value: datetime) -> datetime:
        if value.tzinfo is None or value.utcoffset() is None:
            raise ValueError("exam health deadline must be timezone-aware")
        return value

    @model_validator(mode="after")
    def validate_health_arithmetic(self) -> Self:
        expected_sessions = (
            math.ceil(self.remaining_minutes / self.preferred_session_minutes)
            if self.remaining_minutes
            else 0
        )
        if self.sessions_needed != expected_sessions:
            raise ValueError("exam health session count is inconsistent")
        if self.minutes_to_schedule != max(
            0,
            self.remaining_minutes - self.future_reserved_minutes,
        ):
            raise ValueError("exam health uncovered minutes are inconsistent")
        if len(self.reasons) != len(set(self.reasons)) or len(
            self.missing_sources,
        ) != len(set(self.missing_sources)):
            raise ValueError("exam health reasons and missing sources must be unique")
        capacities = (
            self.available_replan_capacity_minutes,
            self.reserve_minutes,
            self.reserve_full_sessions,
        )
        if self.missing_sources:
            if any(value is not None for value in capacities):
                raise ValueError("unknown capacity cannot contain authoritative totals")
            if self.latest_safe_start_on is not None:
                raise ValueError("unknown capacity cannot contain a latest safe start")
            if self.status not in {"unknown", "red"}:
                raise ValueError("missing authority must be unknown unless overdue")
        else:
            if any(value is None for value in capacities):
                raise ValueError("complete capacity requires all totals")
            if self.reserve_minutes != (
                self.available_replan_capacity_minutes - self.minutes_to_schedule
            ):
                raise ValueError("exam health reserve arithmetic is inconsistent")
            if self.reserve_full_sessions != max(0, self.reserve_minutes) // (
                self.preferred_session_minutes
            ):
                raise ValueError("exam health session reserve is inconsistent")
        if self.recommended_start_on is None:
            if not self.recommended_start_reason:
                raise ValueError("missing recommendation requires an explanation")
        elif self.recommended_start_reason is not None:
            raise ValueError("available recommendation cannot contain an explanation")
        if self.latest_safe_start_on and self.recommended_start_on:
            if self.recommended_start_on > self.latest_safe_start_on:
                raise ValueError(
                    "recommended start cannot follow the latest safe start"
                )
        if self.status == "green" and self.reasons:
            raise ValueError("green exam health cannot contain warning reasons")
        if self.status == "yellow" and not any(
            reason
            in {
                "low_percentage_reserve",
                "low_session_reserve",
                "latest_safe_start_near",
            }
            for reason in self.reasons
        ):
            raise ValueError("yellow exam health requires a warning threshold")
        if self.status == "red" and not any(
            reason in {"overdue_remaining", "capacity_deficit"}
            for reason in self.reasons
        ):
            raise ValueError("red exam health requires a deficit reason")
        if self.status == "unknown" and not self.missing_sources:
            raise ValueError("unknown exam health requires missing authority")
        return self

    def validate_for_envelope(
        self, *, generated_at: datetime, local_date: date
    ) -> None:
        authority_reasons = {
            "calendar_import": "calendar_import_unavailable",
            "calendar_horizon": "calendar_window_incomplete",
            "recurring_availability": "recurring_availability_invalid",
            "higher_priority_exam_capacity": "higher_priority_capacity_unknown",
        }
        expected_reasons = [
            authority_reasons[source] for source in self.missing_sources
        ]
        overdue = self.deadline_at <= generated_at and self.remaining_minutes > 0
        if overdue:
            expected_status: ExamPlanHealthStatus = "red"
            expected_reasons.insert(0, "overdue_remaining")
        elif self.missing_sources:
            expected_status = "unknown"
        elif self.reserve_minutes is not None and self.reserve_minutes < 0:
            expected_status = "red"
            expected_reasons = ["capacity_deficit"]
        else:
            if self.minutes_to_schedule > 0:
                if self.reserve_minutes * 5 < self.minutes_to_schedule:
                    expected_reasons.append("low_percentage_reserve")
                if self.reserve_minutes < 2 * self.preferred_session_minutes:
                    expected_reasons.append("low_session_reserve")
                if (
                    self.latest_safe_start_on is not None
                    and (self.latest_safe_start_on - local_date).days <= 7
                ):
                    expected_reasons.append("latest_safe_start_near")
            expected_status = "yellow" if expected_reasons else "green"
        if self.status != expected_status or self.reasons != expected_reasons:
            raise ValueError("exam health status thresholds are inconsistent")


class ExamPlanHealthResponse(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, frozen=True)

    contract_version: Literal["exam-plan-health-v1"]
    origin: Literal["authenticated_backend"]
    generated_at: datetime
    timezone: str = Field(min_length=1, max_length=100)
    local_date: date
    exams: list[ExamPlanHealthItem] = Field(max_length=2_000)

    @model_validator(mode="after")
    def validate_response(self) -> Self:
        if self.generated_at.tzinfo is None or self.generated_at.utcoffset() is None:
            raise ValueError("exam health timestamp must be timezone-aware")
        try:
            zone = ZoneInfo(self.timezone)
        except ZoneInfoNotFoundError as exc:
            raise ValueError("exam health timezone is invalid") from exc
        if self.local_date != self.generated_at.astimezone(zone).date():
            raise ValueError("exam health local date is inconsistent")
        keys = [
            (item.deadline_at, -item.remaining_minutes, str(item.plan_id))
            for item in self.exams
        ]
        if keys != sorted(keys):
            raise ValueError("exam health items must use stable priority order")
        if len({item.plan_id for item in self.exams}) != len(self.exams):
            raise ValueError("exam health plan ids must be unique")
        for item in self.exams:
            if item.local_deadline_date != item.deadline_at.astimezone(zone).date():
                raise ValueError("exam health local deadline is inconsistent")
            item.validate_for_envelope(
                generated_at=self.generated_at,
                local_date=self.local_date,
            )
        return self


class ExamPlanHealthPreviewRequest(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, frozen=True)

    contract_version: Literal["exam-plan-health-v1"]
    plan_id: UUID | None = Field(default=None, strict=False)
    base_revision: int | None = Field(default=None, ge=1, le=500)
    kind: Literal["exam"]
    title: str = Field(min_length=1, max_length=160)
    deadline_at: datetime = Field(strict=False)
    estimated_total_minutes: int = Field(ge=30, le=30_000)
    credited_prior_minutes: int = Field(ge=0, le=29_999)
    preferred_session_minutes: int = Field(ge=25, le=180)
    max_daily_minutes: int = Field(ge=25, le=480)
    planning_start_on: date = Field(strict=False)
    buffer_days: int = Field(ge=0, le=7)
    source_kind: Literal["manual", "calendar_event"]
    source_calendar_event_id: UUID | None = Field(default=None, strict=False)
    source_calendar_event_fingerprint: str | None = Field(
        default=None,
        pattern=r"^[0-9a-f]{64}$",
    )
    use_calendar_availability: bool

    @model_validator(mode="before")
    @classmethod
    def require_transport_shapes(cls, value: Any) -> Any:
        if not isinstance(value, dict):
            return value
        raw_deadline = value.get("deadline_at")
        if not isinstance(raw_deadline, str) or not re.fullmatch(
            r"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}"
            r"(?:\.\d{1,6})?(?:Z|[+-]\d{2}:\d{2})",
            raw_deadline or "",
        ):
            raise ValueError("deadline_at must be an aware ISO-8601 string")
        raw_start = value.get("planning_start_on")
        if not isinstance(raw_start, str) or not re.fullmatch(
            r"\d{4}-\d{2}-\d{2}",
            raw_start or "",
        ):
            raise ValueError("planning_start_on must be an ISO date string")
        return value

    @field_validator("title")
    @classmethod
    def require_exact_title(cls, value: str) -> str:
        if value != value.strip():
            raise ValueError("preview title must not contain surrounding whitespace")
        return value

    @field_validator("deadline_at")
    @classmethod
    def require_aware_deadline(cls, value: datetime) -> datetime:
        if value.tzinfo is None or value.utcoffset() is None:
            raise ValueError("preview deadline must be timezone-aware")
        return value

    @model_validator(mode="after")
    def validate_preview(self) -> Self:
        if (self.plan_id is None) != (self.base_revision is None):
            raise ValueError(
                "preview plan_id and base_revision must be supplied together",
            )
        if self.credited_prior_minutes >= self.estimated_total_minutes:
            raise ValueError("preview credit must be below the estimate")
        if self.max_daily_minutes < self.preferred_session_minutes:
            raise ValueError("preview daily limit must cover one preferred session")
        has_id = self.source_calendar_event_id is not None
        has_fingerprint = self.source_calendar_event_fingerprint is not None
        if self.source_kind == "calendar_event":
            if not has_id or not has_fingerprint:
                raise ValueError("calendar preview source requires id and fingerprint")
        elif has_id or has_fingerprint:
            raise ValueError("manual preview source cannot contain event identity")
        return self


class ExamPlanHealthPreviewResponse(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, frozen=True)

    contract_version: Literal["exam-plan-health-v1"]
    origin: Literal["authenticated_backend_preview"]
    generated_at: datetime
    timezone: str = Field(min_length=1, max_length=100)
    local_date: date
    exam: ExamPlanHealthItem

    @model_validator(mode="after")
    def validate_response(self) -> Self:
        if self.generated_at.tzinfo is None or self.generated_at.utcoffset() is None:
            raise ValueError("exam health preview timestamp must be timezone-aware")
        try:
            zone = ZoneInfo(self.timezone)
        except ZoneInfoNotFoundError as exc:
            raise ValueError("exam health preview timezone is invalid") from exc
        if self.local_date != self.generated_at.astimezone(zone).date():
            raise ValueError("exam health preview local date is inconsistent")
        if (
            self.exam.local_deadline_date
            != self.exam.deadline_at.astimezone(zone).date()
        ):
            raise ValueError("exam health preview local deadline is inconsistent")
        self.exam.validate_for_envelope(
            generated_at=self.generated_at,
            local_date=self.local_date,
        )
        return self
