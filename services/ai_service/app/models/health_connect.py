from datetime import date
from typing import Literal
from uuid import UUID
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from pydantic import AwareDatetime, BaseModel, ConfigDict, Field, model_validator


HEALTH_CONNECT_CONTRACT_VERSION = "health-connect-v1"
HEALTH_CONNECT_CONSENT_VERSION = "health-connect-cloud-consent-v1"
HEALTH_VITALS_CONSENT_VERSION = "health-vitals-cloud-consent-v1"


class HealthConnectDay(BaseModel):
    model_config = ConfigDict(extra="forbid")

    date: date
    steps: int | None = Field(default=None, ge=0, le=200_000, strict=True)
    sleep_minutes: float | None = Field(
        default=None, ge=0, le=1500, allow_inf_nan=False, strict=True
    )
    steps_sources: list[str] = Field(default_factory=list, max_length=20)
    sleep_sources: list[str] = Field(default_factory=list, max_length=20)
    heart_rate: int | None = Field(default=None, ge=1, le=300, strict=True)
    resting_heart_rate: int | None = Field(default=None, ge=1, le=300, strict=True)
    heart_rate_read: bool = Field(default=False, strict=True)
    resting_heart_rate_read: bool = Field(default=False, strict=True)
    heart_rate_sources: list[str] = Field(default_factory=list, max_length=20)
    resting_heart_rate_sources: list[str] = Field(default_factory=list, max_length=20)

    @model_validator(mode="after")
    def validate_sources(self):
        for metric in ("heart_rate", "resting_heart_rate"):
            if (getattr(self, metric) is not None or getattr(self, metric + "_sources")) and not getattr(self, metric + "_read"):
                raise ValueError("A vital requires an authoritative read.")
        for source in self.steps_sources + self.sleep_sources + self.heart_rate_sources + self.resting_heart_rate_sources:
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
    command: Literal["connect", "disconnect", "delete_data", "sync", "enable_vitals", "disable_vitals"]
    vitals_consent_version: Literal["health-vitals-cloud-consent-v1"] | None = None
    device_id: UUID | None = None
    consent_version: Literal["health-connect-cloud-consent-v1"] | None = None
    timezone: str | None = Field(default=None, max_length=100)
    captured_at: AwareDatetime | None = None
    days: list[HealthConnectDay] = Field(default_factory=list, max_length=7)

    @model_validator(mode="after")
    def validate_command(self):
        if (self.command == "enable_vitals") != (self.vitals_consent_version is not None):
            raise ValueError("Vitals require separate explicit consent.")
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
        if self.command in ("disconnect", "delete_data", "enable_vitals", "disable_vitals") and self.device_id is not None:
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
    vitals_enabled: bool = Field(default=False, strict=True)
    vitals_consent_version: str | None = None
    latest: HealthConnectDay | None = None
    timezone: str
    window_start: date
    window_end: date

    @model_validator(mode="after")
    def validate_state(self):
        if self.vitals_enabled and (
            not self.enabled or self.vitals_consent_version != HEALTH_VITALS_CONSENT_VERSION
        ):
            raise ValueError("Vitals require active sharing and separate consent.")
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
