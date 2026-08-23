import re
from datetime import date, datetime
from typing import Literal
from uuid import UUID

from pydantic import (
    AwareDatetime,
    BaseModel,
    ConfigDict,
    Field,
    field_validator,
    model_validator,
)


NOTIFICATION_LIFECYCLE_CONTRACT_VERSION = "notification-lifecycle-v1"
NOTIFICATION_SETTINGS_CONTRACT_VERSION = "notification-settings-v1"
NOTIFICATION_CONSENT_VERSION = "in-app-notification-consent-v1"
NOTIFICATION_GENERATION_CONTRACT_VERSION = "notification-generation-v1"
NOTIFICATION_DELIVERY_CONTRACT_VERSION = "in-app-notification-delivery-v1"
NotificationLifecycleCommand = Literal["mark_read", "mark_unread", "dismiss"]
NotificationCategory = Literal[
    "focus_prompt",
    "recovery_prompt",
    "weekly_summary",
]
NotificationGenerationStatus = Literal[
    "created",
    "duplicate",
    "not_consented",
    "category_disabled",
    "quiet_hours",
    "daily_limit",
    "no_candidate",
]


_AWARE_DATETIME_PATTERN = re.compile(
    r"\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}:\d{2}"
    r"(?:\.\d{1,6})?(?:Z|[+-]\d{2}:\d{2})",
)
_CLOCK_TIME_PATTERN = re.compile(r"(?:[01]\d|2[0-3]):[0-5]\d")


def _require_aware_iso_string(value: object, *, field: str) -> datetime:
    if not isinstance(value, str) or _AWARE_DATETIME_PATTERN.fullmatch(value) is None:
        raise ValueError(f"{field} must be an ISO-8601 string")
    try:
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError as exc:
        raise ValueError(f"{field} must be an ISO-8601 string") from exc
    if parsed.tzinfo is None or parsed.utcoffset() is None:
        raise ValueError(f"{field} must include a timezone offset")
    return parsed


class NotificationCategories(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, frozen=True)

    focus_prompt: bool
    recovery_prompt: bool
    weekly_summary: bool


class NotificationQuietHours(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, frozen=True)

    starts_at: str
    ends_at: str

    @field_validator("starts_at", "ends_at")
    @classmethod
    def require_clock_time(cls, value: str) -> str:
        if _CLOCK_TIME_PATTERN.fullmatch(value) is None:
            raise ValueError("quiet hours must use HH:mm")
        return value


class NotificationSettingsUpdateRequest(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, frozen=True)

    contract_version: Literal["notification-settings-v1"]
    request_id: UUID = Field(strict=False)
    expected_updated_at: AwareDatetime
    in_app_delivery_enabled: bool
    consent_version: Literal["in-app-notification-consent-v1"]
    categories: NotificationCategories
    quiet_hours: NotificationQuietHours | None
    daily_limit: int = Field(ge=1, le=5)

    @field_validator("expected_updated_at", mode="before")
    @classmethod
    def require_aware_iso_string(cls, value: object) -> datetime:
        return _require_aware_iso_string(value, field="expected_updated_at")


class NotificationSettingsResponse(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, frozen=True)

    contract_version: Literal["notification-settings-v1"]
    in_app_delivery_enabled: bool
    consent_version: Literal["in-app-notification-consent-v1"] | None
    consented_at: AwareDatetime | None
    disabled_at: AwareDatetime | None
    categories: NotificationCategories
    quiet_hours: NotificationQuietHours | None
    daily_limit: int = Field(ge=1, le=5)
    updated_at: AwareDatetime
    replayed: bool

    @model_validator(mode="after")
    def validate_consent_projection(self) -> "NotificationSettingsResponse":
        if self.in_app_delivery_enabled:
            if (
                self.consent_version != NOTIFICATION_CONSENT_VERSION
                or self.consented_at is None
                or self.disabled_at is not None
            ):
                raise ValueError("enabled in-app delivery requires active consent")
        elif self.consented_at is None:
            if self.consent_version is not None or self.disabled_at is not None:
                raise ValueError("never-enabled delivery must not claim consent")
        elif (
            self.consent_version != NOTIFICATION_CONSENT_VERSION
            or self.disabled_at is None
            or self.disabled_at < self.consented_at
        ):
            raise ValueError("disabled delivery consent projection is invalid")
        if self.consented_at is not None and self.consented_at > self.updated_at:
            raise ValueError("consented_at must not be newer than updated_at")
        if self.disabled_at is not None and self.disabled_at > self.updated_at:
            raise ValueError("disabled_at must not be newer than updated_at")
        return self


class NotificationDeliveryReceiptRequest(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, frozen=True)

    contract_version: Literal["in-app-notification-delivery-v1"]


class NotificationDeliveryReceiptResponse(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, frozen=True)

    contract_version: Literal["in-app-notification-delivery-v1"]
    notification_id: UUID = Field(strict=False)
    channel: Literal["in_app"]
    delivered_at: AwareDatetime
    replayed: bool


class NotificationGenerationResult(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, frozen=True)

    status: NotificationGenerationStatus
    category: NotificationCategory | None = None
    delivery_date: date
    created_count: int = Field(ge=0, le=3)
    duplicate_count: int = Field(ge=0, le=3)


class NotificationLifecycleActionRequest(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, frozen=True)

    contract_version: Literal["notification-lifecycle-v1"]
    request_id: UUID = Field(strict=False)
    command: NotificationLifecycleCommand
    expected_updated_at: AwareDatetime

    @field_validator("expected_updated_at", mode="before")
    @classmethod
    def require_aware_iso_string(cls, value: object) -> datetime:
        return _require_aware_iso_string(value, field="expected_updated_at")


class NotificationLifecycleActionResponse(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, frozen=True)

    contract_version: Literal["notification-lifecycle-v1"]
    notification_id: UUID = Field(strict=False)
    command: NotificationLifecycleCommand
    is_read: bool
    read_at: AwareDatetime | None
    dismissed_at: AwareDatetime | None
    updated_at: AwareDatetime
    replayed: bool

    @model_validator(mode="after")
    def validate_lifecycle_projection(self) -> "NotificationLifecycleActionResponse":
        if self.is_read != (self.read_at is not None):
            raise ValueError("is_read and read_at must describe the same state")
        if self.command == "mark_read" and (
            not self.is_read or self.dismissed_at is not None
        ):
            raise ValueError("mark_read must return an active read notification")
        if self.command == "mark_unread" and (
            self.is_read or self.dismissed_at is not None
        ):
            raise ValueError("mark_unread must return an active unread notification")
        if self.command == "dismiss" and (
            not self.is_read or self.dismissed_at is None
        ):
            raise ValueError("dismiss must return a read tombstone")
        if self.read_at is not None and self.read_at > self.updated_at:
            raise ValueError("read_at must not be newer than updated_at")
        if self.dismissed_at is not None and self.dismissed_at > self.updated_at:
            raise ValueError("dismissed_at must not be newer than updated_at")
        return self
