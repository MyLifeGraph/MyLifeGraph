from datetime import date, datetime
from typing import Literal, Self
from uuid import UUID

from pydantic import (
    BaseModel,
    ConfigDict,
    Field,
    field_validator,
    model_validator,
)


CALENDAR_IMPORT_CONTRACT_VERSION = "calendar-import-v1"
CALENDAR_IMPORT_CONSENT_VERSION = "calendar-import-consent-v1"

CalendarConnectionStatus = Literal["connected", "disconnected"]
CalendarEventKind = Literal["timed", "all_day"]
CalendarEventStatus = Literal["confirmed", "tentative"]
CalendarTransparency = Literal["opaque", "transparent"]
CalendarTimezoneSource = Literal[
    "utc",
    "event",
    "profile",
]


class CalendarImportConsent(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, frozen=True)

    consent_version: Literal["calendar-import-consent-v1"]
    read_calendar_events: Literal[True]
    store_event_basics: Literal[True]
    provider_writes: Literal[False]
    llm_processing: Literal[False]


class CalendarConnectionCreateRequest(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True)

    request_id: UUID = Field(strict=False)
    source_kind: Literal["ical_file"]
    source_label: str = Field(min_length=1, max_length=80)
    consent: CalendarImportConsent

    @field_validator("source_label")
    @classmethod
    def normalize_source_label(cls, value: str) -> str:
        normalized = value.strip()
        if not normalized:
            raise ValueError("source_label cannot be blank")
        return normalized


class CalendarFileImportRequest(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True)

    request_id: UUID = Field(strict=False)
    calendar_text: str = Field(min_length=1, max_length=524_288)


class CalendarConnectionMutationRequest(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True)

    request_id: UUID = Field(strict=False)


class CalendarImportWindow(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, frozen=True)

    starts_on: date
    ends_before: date
    timezone: str = Field(min_length=1, max_length=100)

    @model_validator(mode="after")
    def validate_window(self) -> Self:
        if self.ends_before.toordinal() - self.starts_on.toordinal() != 105:
            raise ValueError("calendar import window must cover exactly 105 days")
        return self


class CalendarImportCounts(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, frozen=True)

    accepted: int = Field(ge=0, le=500)
    cancelled: int = Field(ge=0, le=2_000)
    out_of_window: int = Field(ge=0, le=2_000)
    unsupported_recurring: int = Field(ge=0, le=2_000)
    invalid: int = Field(ge=0, le=2_000)


class CalendarImportSummary(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, frozen=True)

    id: UUID
    imported_at: datetime
    window: CalendarImportWindow
    counts: CalendarImportCounts
    source_fingerprint: str = Field(pattern=r"^[0-9a-f]{64}$")

    @model_validator(mode="after")
    def validate_timestamp(self) -> Self:
        if self.imported_at.tzinfo is None:
            raise ValueError("calendar import completion time must be timezone-aware")
        return self


class CalendarConnection(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, frozen=True)

    id: UUID
    origin: Literal["authenticated_backend"]
    source_kind: Literal["ical_file"]
    contract_version: Literal["calendar-import-v1"]
    source_label: str = Field(min_length=1, max_length=80)
    status: CalendarConnectionStatus
    consent: CalendarImportConsent
    consented_at: datetime
    connected_at: datetime
    disconnected_at: datetime | None = None
    imported_data_deleted_at: datetime | None = None
    last_import: CalendarImportSummary | None = None
    provider_writes: Literal[False]
    llm_processed: Literal[False]

    @model_validator(mode="after")
    def validate_connection(self) -> Self:
        timestamps = [self.consented_at, self.connected_at]
        timestamps.extend(
            value
            for value in [self.disconnected_at, self.imported_data_deleted_at]
            if value is not None
        )
        if any(value.tzinfo is None for value in timestamps):
            raise ValueError("calendar connection timestamps must be timezone-aware")
        if self.status == "connected" and self.disconnected_at is not None:
            raise ValueError("connected calendar source cannot be disconnected")
        if self.status == "disconnected" and self.disconnected_at is None:
            raise ValueError("disconnected calendar source requires a timestamp")
        return self


class CalendarConnectionResponse(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True)

    contract_version: Literal["calendar-import-v1"]
    origin: Literal["authenticated_backend"]
    connection: CalendarConnection | None


class CalendarImportResponse(BaseModel):
    model_config = ConfigDict(
        extra="forbid",
        strict=True,
        populate_by_name=True,
    )

    contract_version: Literal["calendar-import-v1"]
    origin: Literal["authenticated_backend"]
    connection: CalendarConnection
    import_summary: CalendarImportSummary = Field(
        alias="import",
        serialization_alias="import",
    )


class CalendarEventProvenance(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, frozen=True)

    kind: Literal["integration"]
    contract_version: Literal["calendar-import-v1"]
    source_kind: Literal["ical_file"]
    source_label: str = Field(min_length=1, max_length=80)
    provider_writes: Literal[False]
    llm_processed: Literal[False]


class CalendarEvent(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, frozen=True)

    id: UUID
    title: str = Field(min_length=1, max_length=200)
    location: str | None = Field(default=None, max_length=300)
    event_kind: CalendarEventKind
    busy_status: Literal["busy", "free"]
    event_status: CalendarEventStatus
    event_timezone: str = Field(min_length=1, max_length=100)
    timezone_source: CalendarTimezoneSource
    starts_at: datetime | None = None
    ends_at: datetime | None = None
    local_starts_at: datetime | None = None
    local_ends_at: datetime | None = None
    starts_on: date | None = None
    ends_on: date | None = None
    imported_at: datetime
    last_seen_at: datetime
    source_fingerprint: str = Field(pattern=r"^[0-9a-f]{64}$")
    provenance: CalendarEventProvenance

    @model_validator(mode="after")
    def validate_event_shape(self) -> Self:
        if self.imported_at.tzinfo is None or self.last_seen_at.tzinfo is None:
            raise ValueError("calendar event timestamps must be timezone-aware")
        if self.last_seen_at < self.imported_at:
            raise ValueError("calendar event last-seen time precedes its import time")
        if self.event_kind == "timed":
            if (
                self.starts_at is None
                or self.ends_at is None
                or self.local_starts_at is None
                or self.local_ends_at is None
                or self.starts_on is not None
                or self.ends_on is not None
            ):
                raise ValueError("timed calendar event has an invalid shape")
            if self.starts_at.tzinfo is None or self.ends_at.tzinfo is None:
                raise ValueError("timed calendar instants must be timezone-aware")
            if (
                self.local_starts_at.tzinfo is not None
                or self.local_ends_at.tzinfo is not None
            ):
                raise ValueError("event-local projections must not carry an offset")
            if self.ends_at <= self.starts_at:
                raise ValueError("timed calendar event must have a positive interval")
            return self
        if (
            self.starts_on is None
            or self.ends_on is None
            or self.starts_at is not None
            or self.ends_at is not None
            or self.local_starts_at is not None
            or self.local_ends_at is not None
        ):
            raise ValueError("all-day calendar event has an invalid shape")
        if self.ends_on <= self.starts_on:
            raise ValueError("all-day calendar event must have a positive interval")
        return self


class CalendarEventsResponse(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True)

    contract_version: Literal["calendar-import-v1"]
    origin: Literal["authenticated_backend"]
    connection_id: UUID
    import_id: UUID | None = None
    events: list[CalendarEvent] = Field(default_factory=list, max_length=50)
    next_cursor: str | None = Field(default=None, max_length=512)


CalendarConnectionsResponse = CalendarConnectionResponse
CalendarDisconnectResponse = CalendarConnectionResponse
CalendarImportedDataDeleteResponse = CalendarConnectionResponse
