"""Uncommitted, owner/date-bound proposals; never a Daily Capture write payload."""

from datetime import date
from typing import Annotated, Literal
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, field_validator, model_validator

CAPTURE_DRAFT_CONTRACT_VERSION = "daily-capture-draft-v1"
Rating = Annotated[int, Field(ge=1, le=10)]
Signal = Annotated[int, Field(ge=0, le=2)]
Clock = Annotated[str, Field(pattern=r"^(?:[01]\d|2[0-3]):[0-5]\d$")]
Target = Annotated[int, Field(ge=300, le=720, multiple_of=15)]


class CaptureDraftRequest(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, frozen=True)
    contract_version: Literal["daily-capture-draft-v1"]
    request_id: UUID = Field(strict=False)
    branch: Literal["morning", "evening"]
    transcript: str = Field(min_length=1, max_length=4000, repr=False)

    @field_validator("transcript")
    @classmethod
    def nonblank(cls, value: str) -> str:
        if not value.strip() or "\x00" in value:
            raise ValueError("A nonblank transcript is required.")
        return value


class MorningDraftFields(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, frozen=True)
    sleep_start: Clock | None = None
    wake_time: Clock | None = None
    sleep_target_minutes: Target | None = None
    sleep_quality: Rating | None = None
    current_energy: Rating | None = None
    motivation: Signal | None = None


class EveningDraftFields(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, frozen=True)
    mood: Rating | None = None
    energy: Rating | None = None
    stress_intensity: Rating | None = None
    planned_sleep_time: Clock | None = None
    sleep_target_minutes: Target | None = None
    stress_source: Literal[
        "workload", "avoidable_pressure", "private_emotional",
        "physical_recovery", "external_environment",
    ] | None = None
    stress_controllability: Literal[
        "hardly_controllable", "partly_controllable", "mostly_controllable",
    ] | None = None
    reflection_note: str | None = Field(default=None, min_length=1, max_length=1000)
    specific_blocker: str | None = Field(default=None, min_length=1, max_length=280)
    sport: Signal | None = None
    social: Signal | None = None


class CaptureDraftResponse(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, frozen=True)
    contract_version: Literal["daily-capture-draft-v1"] = CAPTURE_DRAFT_CONTRACT_VERSION
    request_id: UUID
    owner_id: UUID
    entry_date: date
    timezone: str = Field(min_length=1, max_length=80)
    branch: Literal["morning", "evening"]
    fields: MorningDraftFields | EveningDraftFields
    evidence: dict[str, str] = Field(max_length=11, repr=False)

    @model_validator(mode="after")
    def valid_branch_and_evidence(self) -> "CaptureDraftResponse":
        expected = MorningDraftFields if self.branch == "morning" else EveningDraftFields
        if not isinstance(self.fields, expected):
            raise ValueError("Draft fields do not match the requested branch.")
        populated = {key for key, value in self.fields.model_dump().items() if value is not None}
        if set(self.evidence) != populated:
            raise ValueError("Each proposed value requires source evidence.")
        if any(not text.strip() or len(text) > 1000 for text in self.evidence.values()):
            raise ValueError("Draft source evidence is invalid.")
        return self
