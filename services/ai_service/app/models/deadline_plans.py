import re
from datetime import date, datetime, time
from typing import Any, Literal, Self
from uuid import UUID
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from pydantic import BaseModel, ConfigDict, Field, field_validator, model_validator


DEADLINE_PLAN_CONTRACT_VERSION = "deadline-plan-v1"
PREPARATION_WORKLOAD_CONTRACT_VERSION = "preparation-workload-v1"

DeadlineKind = Literal["exam", "assignment"]
DeadlinePlanStatus = Literal["draft", "active", "completed", "cancelled"]
DeadlineRevisionState = Literal["proposed", "active", "superseded"]
DeadlineBlockState = Literal[
    "proposed",
    "upcoming",
    "partial",
    "completed",
    "missed",
]
DeadlineSourceKind = Literal["manual", "calendar_event"]
DeadlineSourceStatus = Literal["not_applicable", "current", "stale", "unavailable"]
EnergyWindow = Literal[
    "early_morning",
    "morning",
    "afternoon",
    "evening",
    "variable",
]


class PreparationWorkloadDay(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, frozen=True)

    local_date: date
    reserved_preparation_minutes: int = Field(ge=0, le=30_000)
    remaining_budget_minutes: int | None = Field(default=None, ge=0, le=480)
    over_budget_minutes: int = Field(ge=0, le=30_000)
    active_plan_count: int = Field(ge=0, le=50)
    fixed_commitment_minutes: int = Field(ge=0, le=1_440)


class PreparationWorkloadResponse(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, frozen=True)

    contract_version: Literal["preparation-workload-v1"]
    origin: Literal["authenticated_backend"]
    generated_at: datetime
    timezone: str = Field(min_length=1, max_length=100)
    daily_preparation_budget_minutes: int | None = Field(
        default=None,
        ge=25,
        le=480,
    )
    days: list[PreparationWorkloadDay] = Field(min_length=7, max_length=7)

    @model_validator(mode="after")
    def validate_workload(self) -> Self:
        if self.generated_at.tzinfo is None:
            raise ValueError("preparation workload timestamp must be timezone-aware")
        try:
            ZoneInfo(self.timezone)
        except ZoneInfoNotFoundError as exc:
            raise ValueError("preparation workload timezone is invalid") from exc
        if (
            self.daily_preparation_budget_minutes is not None
            and self.daily_preparation_budget_minutes % 5 != 0
        ):
            raise ValueError("preparation workload budget must use five-minute steps")
        for index, day in enumerate(self.days):
            if (
                index > 0
                and (day.local_date - self.days[index - 1].local_date).days != 1
            ):
                raise ValueError("preparation workload days must be consecutive")
            budget = self.daily_preparation_budget_minutes
            if budget is None:
                if (
                    day.remaining_budget_minutes is not None
                    or day.over_budget_minutes != 0
                ):
                    raise ValueError("unset preparation budget cannot imply capacity")
            elif (
                day.remaining_budget_minutes
                != max(0, budget - day.reserved_preparation_minutes)
                or day.over_budget_minutes
                != max(0, day.reserved_preparation_minutes - budget)
            ):
                raise ValueError(
                    "preparation workload budget arithmetic is inconsistent",
                )
        return self


class DeadlinePlanProposalRequest(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, frozen=True)

    request_id: UUID = Field(strict=False)
    plan_id: UUID = Field(strict=False)
    base_revision: int = Field(ge=0, le=199)
    kind: DeadlineKind
    title: str = Field(min_length=1, max_length=160)
    deadline_at: datetime = Field(strict=False)
    estimated_total_minutes: int = Field(ge=30, le=30_000)
    credited_prior_minutes: int = Field(ge=0, le=29_999)
    preferred_session_minutes: int = Field(ge=25, le=180)
    max_daily_minutes: int = Field(ge=25, le=480)
    planning_start_on: date = Field(strict=False)
    buffer_days: int = Field(ge=0, le=7)
    source_kind: DeadlineSourceKind
    source_calendar_event_id: UUID | None = Field(default=None, strict=False)
    source_calendar_event_fingerprint: str | None = Field(
        default=None,
        pattern=r"^[0-9a-f]{64}$",
    )
    use_calendar_availability: bool

    @model_validator(mode="before")
    @classmethod
    def reject_explicit_nulls(cls, value: Any) -> Any:
        if isinstance(value, dict) and any(item is None for item in value.values()):
            raise ValueError(
                "deadline proposal fields must be omitted rather than null",
            )
        if isinstance(value, dict):
            for key in ("request_id", "plan_id", "source_calendar_event_id"):
                if key in value:
                    _require_transport_uuid(value[key], field=key)
            raw_deadline = value.get("deadline_at")
            if not isinstance(raw_deadline, str) or not re.fullmatch(
                r"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}"
                r"(?:\.\d{1,6})?(?:Z|[+-]\d{2}:\d{2})",
                raw_deadline,
            ):
                raise ValueError("deadline_at must be an aware ISO-8601 string")
            raw_start = value.get("planning_start_on")
            if not isinstance(raw_start, str) or not re.fullmatch(
                r"\d{4}-\d{2}-\d{2}",
                raw_start,
            ):
                raise ValueError("planning_start_on must be an ISO date string")
        return value

    @field_validator("title")
    @classmethod
    def require_exact_title(cls, value: str) -> str:
        if value != value.strip():
            raise ValueError("title must not contain surrounding whitespace")
        return value

    @field_validator("deadline_at")
    @classmethod
    def require_aware_deadline(cls, value: datetime) -> datetime:
        if value.tzinfo is None or value.utcoffset() is None:
            raise ValueError("deadline_at must be timezone-aware")
        return value

    @model_validator(mode="after")
    def validate_exact_shape(self) -> Self:
        if self.credited_prior_minutes >= self.estimated_total_minutes:
            raise ValueError(
                "credited_prior_minutes must be below estimated_total_minutes",
            )
        if self.max_daily_minutes < self.preferred_session_minutes:
            raise ValueError(
                "max_daily_minutes must be at least preferred_session_minutes",
            )
        has_event_id = self.source_calendar_event_id is not None
        has_event_fingerprint = self.source_calendar_event_fingerprint is not None
        if self.source_kind == "calendar_event":
            if not has_event_id or not has_event_fingerprint:
                raise ValueError(
                    "calendar_event source requires its id and exact fingerprint",
                )
        elif has_event_id or has_event_fingerprint:
            raise ValueError("manual source cannot contain calendar event fields")
        return self


class DeadlinePlanMutationRequest(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, frozen=True)

    request_id: UUID = Field(strict=False)
    expected_revision: int = Field(ge=1)

    @model_validator(mode="before")
    @classmethod
    def reject_explicit_nulls(cls, value: Any) -> Any:
        if isinstance(value, dict) and any(item is None for item in value.values()):
            raise ValueError("deadline mutation fields cannot be null")
        if isinstance(value, dict) and "request_id" in value:
            _require_transport_uuid(value["request_id"], field="request_id")
        return value


class DeadlinePlanIdentity(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, frozen=True)

    id: UUID
    status: DeadlinePlanStatus
    kind: DeadlineKind
    title: str = Field(min_length=1, max_length=160)
    managed_task_id: UUID | None = None
    original_estimated_total_minutes: int = Field(ge=30, le=30_000)
    original_credited_prior_minutes: int = Field(ge=0, le=29_999)
    current_revision: int = Field(ge=0)
    latest_revision: int = Field(ge=1, le=200)
    created_at: datetime
    updated_at: datetime
    completed_at: datetime | None = None
    cancelled_at: datetime | None = None

    @model_validator(mode="after")
    def validate_identity(self) -> Self:
        timestamps = [self.created_at, self.updated_at]
        timestamps.extend(
            value for value in (self.completed_at, self.cancelled_at) if value
        )
        if any(value.tzinfo is None for value in timestamps):
            raise ValueError("deadline plan timestamps must be timezone-aware")
        if (
            self.original_credited_prior_minutes
            >= self.original_estimated_total_minutes
        ):
            raise ValueError("original prior credit must be below original estimate")
        if self.status == "completed":
            if self.completed_at is None or self.cancelled_at is not None:
                raise ValueError("completed plan lifecycle is invalid")
        elif self.status == "cancelled":
            if self.cancelled_at is None or self.completed_at is not None:
                raise ValueError("cancelled plan lifecycle is invalid")
        elif self.completed_at is not None or self.cancelled_at is not None:
            raise ValueError("open plan cannot have a terminal timestamp")
        if (self.current_revision == 0) != (self.managed_task_id is None):
            raise ValueError("managed task identity must match first activation")
        if self.latest_revision < max(1, self.current_revision):
            raise ValueError("latest deadline revision cannot precede the active one")
        return self


class DeadlinePlanBlock(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, frozen=True)

    id: UUID
    sequence: int = Field(ge=1, le=120)
    starts_at: datetime
    ends_at: datetime
    local_date: date
    local_start_time: time
    local_end_time: time
    planned_minutes: int = Field(ge=5, le=240)
    credited_tracked_minutes: int = Field(ge=0, le=240)
    state: DeadlineBlockState

    @model_validator(mode="after")
    def validate_block(self) -> Self:
        if self.starts_at.tzinfo is None or self.ends_at.tzinfo is None:
            raise ValueError("deadline block instants must be timezone-aware")
        if self.ends_at <= self.starts_at:
            raise ValueError("deadline block must have a positive interval")
        if self.credited_tracked_minutes > self.planned_minutes:
            raise ValueError("block credit cannot exceed planned minutes")
        return self


class DeadlinePlanRevision(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, frozen=True)

    plan_id: UUID
    revision: int = Field(ge=1, le=200)
    base_revision: int = Field(ge=0, le=199)
    state: DeadlineRevisionState
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
    source_calendar_event_id: UUID | None = None
    source_calendar_event_fingerprint: str | None = Field(
        default=None,
        pattern=r"^[0-9a-f]{64}$",
    )
    source_status: DeadlineSourceStatus
    use_calendar_availability: bool
    availability_connection_id: UUID | None = None
    availability_import_id: UUID | None = None
    timezone: str = Field(min_length=1, max_length=100)
    best_energy_window: EnergyWindow
    planning_fingerprint: str = Field(pattern=r"^[0-9a-f]{64}$")
    tracked_focus_minutes_at_proposal: int = Field(ge=0)
    remaining_minutes_at_proposal: int = Field(ge=0, le=30_000)
    planned_minutes: int = Field(ge=0, le=30_000)
    unscheduled_minutes: int = Field(ge=0, le=30_000)
    created_at: datetime
    activated_at: datetime | None = None
    superseded_at: datetime | None = None
    blocks: list[DeadlinePlanBlock] = Field(default_factory=list, max_length=120)

    @model_validator(mode="after")
    def validate_revision(self) -> Self:
        if self.deadline_at.tzinfo is None or self.created_at.tzinfo is None:
            raise ValueError("deadline revision timestamps must be timezone-aware")
        if any(
            value is not None and value.tzinfo is None
            for value in (self.activated_at, self.superseded_at)
        ):
            raise ValueError("deadline revision timestamps must be timezone-aware")
        if self.credited_prior_minutes >= self.estimated_total_minutes:
            raise ValueError("prior credit must be below estimate")
        if self.revision != self.base_revision + 1:
            raise ValueError("deadline revision must advance its exact base")
        if self.source_kind == "manual":
            if (
                self.source_calendar_event_id is not None
                or self.source_calendar_event_fingerprint is not None
                or self.source_status != "not_applicable"
            ):
                raise ValueError("manual deadline source projection is invalid")
        elif (
            self.source_calendar_event_id is None
            or self.source_calendar_event_fingerprint is None
            or self.source_status not in {"current", "stale", "unavailable"}
        ):
            raise ValueError("calendar deadline source projection is invalid")
        has_connection = self.availability_connection_id is not None
        has_import = self.availability_import_id is not None
        if (
            has_connection != has_import
            or self.use_calendar_availability != has_connection
        ):
            raise ValueError("calendar availability provenance is inconsistent")
        expected_remaining = max(
            0,
            self.estimated_total_minutes
            - self.credited_prior_minutes
            - self.tracked_focus_minutes_at_proposal,
        )
        if self.remaining_minutes_at_proposal != expected_remaining:
            raise ValueError("deadline proposal remaining minutes are inconsistent")
        if self.planned_minutes + self.unscheduled_minutes != expected_remaining:
            raise ValueError("deadline revision minute summary is inconsistent")
        if self.planned_minutes != sum(block.planned_minutes for block in self.blocks):
            raise ValueError("deadline block minutes do not match revision summary")
        try:
            zone = ZoneInfo(self.timezone)
        except ZoneInfoNotFoundError as exc:
            raise ValueError("deadline revision timezone is invalid") from exc
        if sorted(block.sequence for block in self.blocks) != list(
            range(1, len(self.blocks) + 1),
        ):
            raise ValueError("deadline block sequences must be contiguous")
        for block in self.blocks:
            starts_local = block.starts_at.astimezone(zone)
            ends_local = block.ends_at.astimezone(zone)
            if (block.ends_at - block.starts_at).total_seconds() != (
                block.planned_minutes * 60
            ):
                raise ValueError("deadline block duration is inconsistent")
            if (
                block.local_date != starts_local.date()
                or block.local_date != ends_local.date()
                or block.local_start_time != starts_local.time().replace(tzinfo=None)
                or block.local_end_time != ends_local.time().replace(tzinfo=None)
            ):
                raise ValueError("deadline block local projection is inconsistent")
        if self.state == "proposed":
            if self.activated_at is not None or self.superseded_at is not None:
                raise ValueError("proposed deadline revision has lifecycle timestamps")
        elif self.state == "active":
            if self.activated_at is None or self.superseded_at is not None:
                raise ValueError("active deadline revision lifecycle is invalid")
        elif self.superseded_at is None:
            raise ValueError("superseded deadline revision requires superseded_at")
        return self


class DeadlinePlanProgress(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, frozen=True)

    estimated_total_minutes: int = Field(ge=30, le=30_000)
    credited_prior_minutes: int = Field(ge=0, le=29_999)
    tracked_focus_minutes: int = Field(ge=0)
    accounted_minutes: int = Field(ge=0)
    remaining_minutes: int = Field(ge=0, le=30_000)
    completion_suggested: bool

    @model_validator(mode="after")
    def validate_progress(self) -> Self:
        if self.accounted_minutes != min(
            self.estimated_total_minutes,
            self.credited_prior_minutes + self.tracked_focus_minutes,
        ):
            raise ValueError("deadline progress accounting is inconsistent")
        if self.remaining_minutes != (
            self.estimated_total_minutes - self.accounted_minutes
        ):
            raise ValueError("deadline remaining minutes are inconsistent")
        if self.completion_suggested != (self.remaining_minutes == 0):
            raise ValueError("deadline completion suggestion is inconsistent")
        return self


class DeadlinePlanDetail(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, frozen=True)

    plan: DeadlinePlanIdentity
    active_revision: DeadlinePlanRevision | None = None
    pending_revision: DeadlinePlanRevision | None = None
    progress: DeadlinePlanProgress

    @model_validator(mode="after")
    def validate_detail(self) -> Self:
        if self.active_revision is not None:
            if (
                self.active_revision.plan_id != self.plan.id
                or self.active_revision.state != "active"
                or self.active_revision.revision != self.plan.current_revision
            ):
                raise ValueError("active deadline revision does not match plan")
        if self.pending_revision is not None:
            if (
                self.pending_revision.plan_id != self.plan.id
                or self.pending_revision.state != "proposed"
                or self.pending_revision.revision != self.plan.latest_revision
            ):
                raise ValueError("pending deadline revision does not match plan")
        if self.plan.status == "draft":
            if self.active_revision is not None or self.pending_revision is None:
                raise ValueError("draft deadline plan requires one pending revision")
            if (
                self.plan.current_revision != 0
                or self.plan.latest_revision != self.pending_revision.revision
                or self.plan.kind != self.pending_revision.kind
                or self.plan.title != self.pending_revision.title
            ):
                raise ValueError("draft deadline identity does not match proposal")
        elif self.plan.status == "active":
            if (
                self.active_revision is None
                or self.plan.managed_task_id != self.plan.id
            ):
                raise ValueError("active deadline plan projection is incomplete")
            if (
                self.plan.kind != self.active_revision.kind
                or self.plan.title != self.active_revision.title
            ):
                raise ValueError("active deadline identity does not match revision")
            if self.pending_revision is None:
                if self.plan.latest_revision != self.plan.current_revision:
                    raise ValueError("active deadline latest revision is inconsistent")
            elif (
                self.plan.latest_revision != self.pending_revision.revision
                or self.pending_revision.revision <= self.plan.current_revision
            ):
                raise ValueError("active pending revision sequence is inconsistent")
        elif self.plan.status == "completed" or (
            self.plan.status == "cancelled" and self.plan.current_revision > 0
        ):
            if self.active_revision is None or self.pending_revision is not None:
                raise ValueError("terminal activated deadline plan is inconsistent")
            if (
                self.plan.kind != self.active_revision.kind
                or self.plan.title != self.active_revision.title
            ):
                raise ValueError("terminal deadline identity does not match revision")
        elif self.plan.status == "cancelled":
            if self.active_revision is not None or self.pending_revision is not None:
                raise ValueError("cancelled draft deadline plan retained a revision")
        projection = self.active_revision or self.pending_revision
        expected_estimate = (
            projection.estimated_total_minutes
            if projection is not None
            else self.plan.original_estimated_total_minutes
        )
        expected_prior = (
            projection.credited_prior_minutes
            if projection is not None
            else self.plan.original_credited_prior_minutes
        )
        if (
            self.progress.estimated_total_minutes != expected_estimate
            or self.progress.credited_prior_minutes != expected_prior
        ):
            raise ValueError("deadline progress does not match its current projection")
        return self


class DeadlinePlanResponse(DeadlinePlanDetail):
    contract_version: Literal["deadline-plan-v1"]
    origin: Literal["authenticated_backend"]


class DeadlinePlansResponse(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, frozen=True)

    contract_version: Literal["deadline-plan-v1"]
    origin: Literal["authenticated_backend"]
    plans: list[DeadlinePlanDetail] = Field(default_factory=list, max_length=50)


def _require_transport_uuid(value: Any, *, field: str) -> None:
    if not isinstance(value, str) or value != value.strip():
        raise ValueError(f"{field} must be a canonical UUID string")
    try:
        parsed = UUID(value)
    except ValueError as exc:
        raise ValueError(f"{field} must be a canonical UUID string") from exc
    if str(parsed) != value:
        raise ValueError(f"{field} must be a canonical UUID string")
