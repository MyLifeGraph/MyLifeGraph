from datetime import date
from typing import Literal, Self

from pydantic import BaseModel, ConfigDict, Field, model_validator


class PlanningTimingProvenance(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, frozen=True)

    source: Literal["setup", "learned_personal_pattern"]
    window: Literal["05-09", "09-13", "13-18", "18-23"] | None = None
    evidence_count: int = Field(default=0, ge=0, le=10_000)
    evidence_starts_on: date | None = None
    evidence_ends_on: date | None = None
    evidence_fingerprint: str | None = Field(
        default=None,
        pattern=r"^[0-9a-f]{64}$",
    )
    fell_back_to_setup: bool = False
    warning: Literal["personal_patterns_unavailable"] | None = None

    @model_validator(mode="after")
    def validate_shape(self) -> Self:
        evidence = (
            self.window,
            self.evidence_starts_on,
            self.evidence_ends_on,
            self.evidence_fingerprint,
        )
        if self.source == "learned_personal_pattern":
            if (
                any(value is None for value in evidence)
                or self.evidence_count < 1
                or self.warning is not None
                or (
                    self.evidence_starts_on is not None
                    and self.evidence_ends_on is not None
                    and self.evidence_starts_on > self.evidence_ends_on
                )
            ):
                raise ValueError("learned planning timing provenance is incomplete")
        elif (
            any(value is not None for value in evidence)
            or self.evidence_count != 0
        ):
            raise ValueError("Setup planning timing cannot contain learned evidence")
        if self.warning is not None and not self.fell_back_to_setup:
            raise ValueError("planning timing warning requires Setup fallback")
        return self
