import re
from datetime import datetime
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
NotificationLifecycleCommand = Literal["mark_read", "mark_unread", "dismiss"]


class NotificationLifecycleActionRequest(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, frozen=True)

    contract_version: Literal["notification-lifecycle-v1"]
    request_id: UUID = Field(strict=False)
    command: NotificationLifecycleCommand
    expected_updated_at: AwareDatetime

    @field_validator("expected_updated_at", mode="before")
    @classmethod
    def require_aware_iso_string(cls, value: object) -> datetime:
        if not isinstance(value, str) or re.fullmatch(
            r"\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}:\d{2}"
            r"(?:\.\d{1,6})?(?:Z|[+-]\d{2}:\d{2})",
            value,
        ) is None:
            raise ValueError("expected_updated_at must be an ISO-8601 string")
        try:
            parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
        except ValueError as exc:
            raise ValueError(
                "expected_updated_at must be an ISO-8601 string",
            ) from exc
        if parsed.tzinfo is None or parsed.utcoffset() is None:
            raise ValueError("expected_updated_at must include a timezone offset")
        return parsed


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
