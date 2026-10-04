from datetime import date
from typing import Literal
from uuid import UUID
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from pydantic import AwareDatetime, BaseModel, ConfigDict, Field, model_validator

COACH_PHONE_DATA_VERSION = "coach-phone-data-v1"
COACH_PHONE_CONSENT_VERSION = "coach-phone-consent-v1"


class PhoneDay(BaseModel):
    model_config = ConfigDict(extra="forbid")
    date: date
    minutes: int = Field(ge=0, le=2880, strict=True)


class PhoneApp(BaseModel):
    model_config = ConfigDict(extra="forbid")
    name: str = Field(min_length=1, max_length=80)
    minutes: int = Field(ge=0, le=20160, strict=True)


class PhoneSample(BaseModel):
    model_config = ConfigDict(extra="forbid")
    timezone: str = Field(max_length=100)
    captured_at: AwareDatetime
    days: list[PhoneDay] = Field(min_length=7, max_length=7)
    apps: list[PhoneApp] = Field(max_length=10)
    attempts_today: int | None = Field(default=None, ge=0, le=1000000, strict=True)

    @model_validator(mode="after")
    def validate_window(self):
        try:
            zone = ZoneInfo(self.timezone)
        except (ZoneInfoNotFoundError, ValueError) as exc:
            raise ValueError("A valid IANA timezone is required.") from exc
        today = self.captured_at.astimezone(zone).date()
        if {(today - day.date).days for day in self.days} != set(range(7)):
            raise ValueError("A complete profile-local week is required.")
        return self


class PhoneCommand(BaseModel):
    model_config = ConfigDict(extra="forbid")
    contract_version: Literal["coach-phone-data-v1"]
    request_id: UUID
    expected_revision: int = Field(ge=0, strict=True)
    command: Literal["enable", "disable", "sync", "delete"]
    device_id: UUID | None = None
    consent_version: Literal["coach-phone-consent-v1"] | None = None
    data: PhoneSample | None = None

    @model_validator(mode="after")
    def validate_command(self):
        if (self.command == "enable") != (self.consent_version is not None):
            raise ValueError("Explicit phone sharing consent is required.")
        if (self.command in {"enable", "sync"}) != (self.device_id is not None):
            raise ValueError("Device binding is required.")
        if (self.command == "sync") != (self.data is not None):
            raise ValueError("Only sync accepts a sample.")
        return self


class PhoneState(BaseModel):
    model_config = ConfigDict(extra="forbid")
    contract_version: Literal["coach-phone-data-v1"] = COACH_PHONE_DATA_VERSION
    enabled: bool = False
    revision: int = Field(default=0, ge=0)
    device_id: UUID | None = None
    consent_version: str | None = None
    data: PhoneSample | None = None
    timezone: str
