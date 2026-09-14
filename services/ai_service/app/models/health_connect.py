from datetime import date
from typing import Literal
from uuid import UUID
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from pydantic import AwareDatetime, BaseModel, ConfigDict, Field, model_validator


HEALTH_CONNECT_CONTRACT_VERSION = "health-connect-v1"
HEALTH_CONNECT_CONSENT_VERSION = "health-connect-cloud-consent-v1"


class HealthConnectDay(BaseModel):
    model_config = ConfigDict(extra="forbid")

    date: date
    steps: int | None = Field(default=None, ge=0, le=200_000, strict=True)
    sleep_minutes: float | None = Field(
        default=None, ge=0, le=1500, allow_inf_nan=False, strict=True
    )
    steps_sources: list[str] = Field(default_factory=list, max_length=20)
    sleep_sources: list[str] = Field(default_factory=list, max_length=20)

    @model_validator(mode="after")
    def validate_sources(self):
        for source in self.steps_sources + self.sleep_sources:
            if not 1 <= len(source) <= 200 or not all(
                character.isascii() and (character.isalnum() or character in "._")
                for character in source
            ):
                raise ValueError("Invalid Health Connect source.")
        return self


class HealthConnectCommand(BaseModel):
    model_config = ConfigDict(extra="forbid")

    contract_version: Literal["health-connect-v1"]
    request_id: UUID
    expected_revision: int = Field(ge=0, strict=True)
    command: Literal["connect", "disconnect", "delete_data", "sync"]
    device_id: UUID | None = None
    consent_version: Literal["health-connect-cloud-consent-v1"] | None = None
    timezone: str | None = Field(default=None, max_length=100)
    captured_at: AwareDatetime | None = None
    days: list[HealthConnectDay] = Field(default_factory=list, max_length=7)

    @model_validator(mode="after")
    def validate_command(self):
        if self.command == "connect":
            if self.device_id is None or self.consent_version is None:
                raise ValueError("Explicit device and cloud consent are required.")
        elif self.consent_version is not None:
            raise ValueError("Consent is accepted only by connect.")
        if self.command == "sync":
            if (
                self.device_id is None
                or self.timezone is None
                or self.captured_at is None
            ):
                raise ValueError("A sync requires device, timezone and capture time.")
            try:
                if self.timezone != self.timezone.strip():
                    raise ValueError(
                        "Timezone must not contain surrounding whitespace."
                    )
                ZoneInfo(self.timezone)
            except (ValueError, ZoneInfoNotFoundError) as error:
                raise ValueError("Invalid Health Connect timezone.") from error
            if len(self.days) != 7 or len({day.date for day in self.days}) != 7:
                raise ValueError("A complete seven-day window is required.")
        elif self.days or self.timezone is not None or self.captured_at is not None:
            raise ValueError("Only sync may contain health data.")
        if self.command in ("disconnect", "delete_data") and self.device_id is not None:
            raise ValueError("This command does not accept a device.")
        return self


class HealthConnectState(BaseModel):
    model_config = ConfigDict(extra="forbid")

    contract_version: Literal["health-connect-v1"] = HEALTH_CONNECT_CONTRACT_VERSION
    enabled: bool = Field(default=False, strict=True)
    revision: int = Field(default=0, ge=0, strict=True)
    device_id: UUID | None = None
    consent_version: str | None = None
    consented_at: AwareDatetime | None = None
    last_synced_at: AwareDatetime | None = None
    timezone: str
    window_start: date
    window_end: date

    @model_validator(mode="after")
    def validate_state(self):
        if self.enabled and (
            self.device_id is None
            or self.consented_at is None
            or self.consent_version != HEALTH_CONNECT_CONSENT_VERSION
        ):
            raise ValueError(
                "Enabled Health Connect requires explicit consent and device."
            )
        if (self.window_end - self.window_start).days != 6:
            raise ValueError("Invalid Health Connect window.")
        return self
