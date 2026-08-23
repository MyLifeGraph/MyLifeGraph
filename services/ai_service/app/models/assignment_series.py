import re
from datetime import datetime
from typing import Any, Literal, Self
from uuid import UUID
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from pydantic import BaseModel, ConfigDict, Field, field_validator, model_validator


ASSIGNMENT_SERIES_CONTRACT_VERSION = "assignment-series-v1"

AssignmentSeriesStatus = Literal["draft", "active", "cancelled"]
AssignmentSeriesRevisionState = Literal["proposed", "active", "superseded"]
AssignmentSeriesOccurrenceAction = Literal["retain", "upsert", "cancel"]


def _require_transport_uuid(value: Any, *, field: str) -> None:
    if not isinstance(value, str) or not re.fullmatch(
        r"[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-"
        r"[89aAbB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}",
        value,
    ):
        raise ValueError(f"{field} must be a canonical UUID string")


class AssignmentSeriesProposalRequest(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, frozen=True)

    contract_version: Literal["assignment-series-v1"]
    request_id: UUID = Field(strict=False)
    series_id: UUID = Field(strict=False)
    base_revision: int = Field(ge=0, le=199)
    title: str = Field(min_length=1, max_length=160)
    next_deadline_at: datetime = Field(strict=False)
    remaining_occurrences: int = Field(ge=1, le=20)
    estimated_total_minutes: int = Field(ge=30, le=30_000)
    preferred_session_minutes: int = Field(ge=25, le=180)
    max_daily_minutes: int = Field(ge=25, le=480)
    buffer_days: int = Field(ge=0, le=7)
    use_calendar_availability: bool

    @model_validator(mode="before")
    @classmethod
    def reject_invalid_transport(cls, value: Any) -> Any:
        if isinstance(value, dict):
            if any(item is None for item in value.values()):
                raise ValueError("assignment series fields cannot be null")
            for key in ("request_id", "series_id"):
                if key in value:
                    _require_transport_uuid(value[key], field=key)
            raw_deadline = value.get("next_deadline_at")
            if not isinstance(raw_deadline, str) or not re.fullmatch(
                r"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}"
                r"(?:\.\d{1,6})?(?:Z|[+-]\d{2}:\d{2})",
                raw_deadline,
            ):
                raise ValueError(
                    "next_deadline_at must be an aware ISO-8601 string",
                )
        return value

    @field_validator("title")
    @classmethod
    def require_trimmed_title(cls, value: str) -> str:
        if value != value.strip():
            raise ValueError("title must not contain surrounding whitespace")
        return value

    @field_validator("next_deadline_at")
    @classmethod
    def require_aware_deadline(cls, value: datetime) -> datetime:
        if value.tzinfo is None or value.utcoffset() is None:
            raise ValueError("next_deadline_at must be timezone-aware")
        return value

    @model_validator(mode="after")
    def validate_series_input(self) -> Self:
        if self.base_revision == 0 and self.remaining_occurrences < 2:
            raise ValueError("a new assignment series needs 2 to 20 occurrences")
        if self.max_daily_minutes < self.preferred_session_minutes:
            raise ValueError(
                "max_daily_minutes must be at least preferred_session_minutes",
            )
        return self


class AssignmentSeriesMutationRequest(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, frozen=True)

    contract_version: Literal["assignment-series-v1"]
    request_id: UUID = Field(strict=False)
    expected_revision: int = Field(ge=1, le=200)

    @model_validator(mode="before")
    @classmethod
    def reject_invalid_transport(cls, value: Any) -> Any:
        if isinstance(value, dict):
            if any(item is None for item in value.values()):
                raise ValueError("assignment series mutation fields cannot be null")
            if "request_id" in value:
                _require_transport_uuid(value["request_id"], field="request_id")
        return value


class AssignmentSeriesIdentity(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, frozen=True)

    id: UUID
    status: AssignmentSeriesStatus
    title: str = Field(min_length=1, max_length=160)
    current_revision: int = Field(ge=0, le=200)
    latest_revision: int = Field(ge=1, le=200)
    created_at: datetime
    updated_at: datetime
    first_activated_at: datetime | None = None
    cancelled_at: datetime | None = None

    @model_validator(mode="after")
    def validate_identity(self) -> Self:
        timestamps = [self.created_at, self.updated_at]
        timestamps.extend(
            value
            for value in (self.first_activated_at, self.cancelled_at)
            if value is not None
        )
        if any(value.tzinfo is None for value in timestamps):
            raise ValueError("assignment series timestamps must be timezone-aware")
        if self.latest_revision < max(1, self.current_revision):
            raise ValueError("assignment series revision counters are inconsistent")
        if self.status == "draft":
            if self.current_revision != 0 or self.first_activated_at is not None:
                raise ValueError("draft assignment series lifecycle is invalid")
        elif self.status == "active":
            if self.current_revision < 1 or self.first_activated_at is None:
                raise ValueError("active assignment series lifecycle is invalid")
        if (self.status == "cancelled") != (self.cancelled_at is not None):
            raise ValueError("cancelled assignment series lifecycle is invalid")
        return self


class AssignmentSeriesOccurrence(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, frozen=True)

    position: int = Field(ge=1, le=200)
    action: AssignmentSeriesOccurrenceAction
    plan_id: UUID
    plan_revision: int = Field(ge=1, le=200)
    deadline_at: datetime

    @model_validator(mode="after")
    def validate_occurrence(self) -> Self:
        if self.deadline_at.tzinfo is None:
            raise ValueError("assignment occurrence deadline must be aware")
        return self


class AssignmentSeriesRevision(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, frozen=True)

    series_id: UUID
    revision: int = Field(ge=1, le=200)
    base_revision: int = Field(ge=0, le=199)
    state: AssignmentSeriesRevisionState
    title: str = Field(min_length=1, max_length=160)
    next_deadline_at: datetime
    remaining_occurrences: int = Field(ge=1, le=20)
    estimated_total_minutes: int = Field(ge=30, le=30_000)
    preferred_session_minutes: int = Field(ge=25, le=180)
    max_daily_minutes: int = Field(ge=25, le=480)
    buffer_days: int = Field(ge=0, le=7)
    use_calendar_availability: bool
    timezone: str = Field(min_length=1, max_length=100)
    planned_minutes: int = Field(ge=0, le=600_000)
    unscheduled_minutes: int = Field(ge=0, le=600_000)
    created_at: datetime
    activated_at: datetime | None = None
    superseded_at: datetime | None = None
    occurrences: list[AssignmentSeriesOccurrence] = Field(max_length=40)

    @model_validator(mode="after")
    def validate_revision(self) -> Self:
        if self.revision != self.base_revision + 1:
            raise ValueError("assignment series revision must advance its base")
        if self.next_deadline_at.tzinfo is None or self.created_at.tzinfo is None:
            raise ValueError("assignment series revision timestamps must be aware")
        try:
            ZoneInfo(self.timezone)
        except ZoneInfoNotFoundError as exc:
            raise ValueError("assignment series timezone is invalid") from exc
        if self.max_daily_minutes < self.preferred_session_minutes:
            raise ValueError("assignment series daily limit is invalid")
        if self.state == "proposed":
            if self.activated_at is not None or self.superseded_at is not None:
                raise ValueError("proposed assignment series lifecycle is invalid")
        elif self.state == "active":
            if self.activated_at is None or self.superseded_at is not None:
                raise ValueError("active assignment series lifecycle is invalid")
        elif self.superseded_at is None:
            raise ValueError("superseded assignment series needs a timestamp")
        keys = [(item.position, item.plan_id) for item in self.occurrences]
        if len(keys) != len(set(keys)):
            raise ValueError("assignment series occurrences must be unique")
        active_count = sum(item.action != "cancel" for item in self.occurrences)
        if active_count < self.remaining_occurrences:
            raise ValueError("assignment series occurrence projection is incomplete")
        return self


class AssignmentSeriesDetail(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, frozen=True)

    series: AssignmentSeriesIdentity
    active_revision: AssignmentSeriesRevision | None = None
    pending_revision: AssignmentSeriesRevision | None = None

    @model_validator(mode="after")
    def validate_detail(self) -> Self:
        if self.active_revision is not None and (
            self.active_revision.series_id != self.series.id
            or self.active_revision.state != "active"
            or self.active_revision.revision != self.series.current_revision
        ):
            raise ValueError("active assignment series revision is inconsistent")
        if self.pending_revision is not None and (
            self.pending_revision.series_id != self.series.id
            or self.pending_revision.state != "proposed"
            or self.pending_revision.revision != self.series.latest_revision
        ):
            raise ValueError("pending assignment series revision is inconsistent")
        if self.series.status == "draft" and self.pending_revision is None:
            raise ValueError("draft assignment series needs a pending revision")
        if self.series.status == "active" and self.active_revision is None:
            raise ValueError("active assignment series needs an active revision")
        return self


class AssignmentSeriesResponse(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, frozen=True)

    contract_version: Literal["assignment-series-v1"]
    origin: Literal["authenticated_backend"]
    assignment_series: AssignmentSeriesDetail


class AssignmentSeriesListResponse(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, frozen=True)

    contract_version: Literal["assignment-series-v1"]
    origin: Literal["authenticated_backend"]
    assignment_series: list[AssignmentSeriesDetail] = Field(max_length=20)
