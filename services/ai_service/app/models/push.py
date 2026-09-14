from typing import Literal
from uuid import UUID

from pydantic import AwareDatetime, BaseModel, ConfigDict, Field, model_validator

PUSH_CONTRACT_VERSION = "android-push-v1"
PUSH_CONSENT_VERSION = "android-push-consent-v1"
_CLOCK = r"^([01][0-9]|2[0-3]):[0-5][0-9]$"


class PushSettings(BaseModel):
    model_config = ConfigDict(extra="forbid")
    enabled: bool = Field(strict=True)
    revision: int = Field(ge=0, strict=True)
    sleep: bool = Field(strict=True)
    deadlines: bool = Field(strict=True)
    patterns: bool = Field(strict=True)
    quiet_start: str = Field(pattern=_CLOCK)
    quiet_end: str = Field(pattern=_CLOCK)
    consent_version: Literal[PUSH_CONSENT_VERSION] | None = None
    consented_at: AwareDatetime | None = None

    @model_validator(mode="after")
    def require_consent(self):
        if self.enabled and (
            self.consent_version != PUSH_CONSENT_VERSION or self.consented_at is None
        ):
            raise ValueError("Enabled push requires explicit consent")
        return self


class PushState(BaseModel):
    model_config = ConfigDict(extra="forbid")
    contract_version: Literal[PUSH_CONTRACT_VERSION] = PUSH_CONTRACT_VERSION
    available: bool = False
    settings: PushSettings
    timezone: str
    device_id: UUID | None = None
    registration_id: UUID | None = None


class PushCommand(BaseModel):
    model_config = ConfigDict(extra="forbid")
    contract_version: Literal[PUSH_CONTRACT_VERSION]
    command: Literal["settings", "register", "unregister"]
    request_id: UUID
    expected_revision: int = Field(ge=0, strict=True)
    consent_version: Literal[PUSH_CONSENT_VERSION] | None = None
    enabled: bool | None = Field(default=None, strict=True)
    sleep: bool | None = Field(default=None, strict=True)
    deadlines: bool | None = Field(default=None, strict=True)
    patterns: bool | None = Field(default=None, strict=True)
    quiet_start: str | None = Field(default=None, pattern=_CLOCK)
    quiet_end: str | None = Field(default=None, pattern=_CLOCK)
    device_id: UUID | None = None
    registration_id: UUID | None = None
    token: str | None = Field(default=None, min_length=20, max_length=4096, repr=False)

    @model_validator(mode="after")
    def validate_command(self):
        config = (
            self.enabled,
            self.sleep,
            self.deadlines,
            self.patterns,
            self.quiet_start,
            self.quiet_end,
            self.consent_version,
        )
        if self.command == "settings":
            if any(value is None for value in config):
                raise ValueError("Complete explicit settings are required")
            if any(
                value is not None
                for value in (self.device_id, self.registration_id, self.token)
            ):
                raise ValueError("Settings do not register a device")
        else:
            if any(value is not None for value in config) or self.device_id is None:
                raise ValueError(
                    "Device command requires device identity, not settings"
                )
            if self.command == "register":
                if (
                    self.registration_id is None
                    or self.token is None
                    or any(c.isspace() for c in self.token)
                ):
                    raise ValueError("Complete device registration required")
            elif self.registration_id is not None or self.token is not None:
                raise ValueError("Unexpected unregistration payload")
        return self
