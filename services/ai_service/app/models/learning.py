from datetime import datetime
from typing import Literal
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, model_validator


LEARNING_PREFERENCES_CONTRACT_VERSION = "learning-preferences-v1"
FOCUS_REFLECTION_CONTRACT_VERSION = "focus-reflection-v1"


class LearningPreferencesState(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, frozen=True)

    contract_version: Literal["learning-preferences-v1"]
    revision: int = Field(ge=0)
    focus_reflection_prompt_enabled: bool
    personal_pattern_analysis_enabled: bool
    learned_focus_planning_enabled: bool
    updated_at: datetime | None

    @model_validator(mode="after")
    def validate_dependency_and_timestamp(self) -> "LearningPreferencesState":
        if (
            self.learned_focus_planning_enabled
            and not self.personal_pattern_analysis_enabled
        ):
            raise ValueError("learned Focus planning requires pattern analysis")
        if self.updated_at is not None and self.updated_at.utcoffset() is None:
            raise ValueError("learning preference timestamp must be aware")
        return self


class LearningPreferencesUpdateRequest(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, frozen=True)

    request_id: UUID = Field(strict=False)
    expected_revision: int = Field(ge=0)
    focus_reflection_prompt_enabled: bool
    personal_pattern_analysis_enabled: bool
    learned_focus_planning_enabled: bool

    @model_validator(mode="after")
    def validate_dependency(self) -> "LearningPreferencesUpdateRequest":
        if (
            self.learned_focus_planning_enabled
            and not self.personal_pattern_analysis_enabled
        ):
            raise ValueError("learned Focus planning requires pattern analysis")
        return self


class LearningPreferencesUpdateResponse(LearningPreferencesState):
    replayed: bool


class FocusReflectionHistoryClearRequest(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, frozen=True)

    request_id: UUID = Field(strict=False)
    expected_revision: int = Field(ge=0)
    confirmation: Literal["CLEAR"]


class FocusReflectionHistoryClearResponse(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, frozen=True)

    contract_version: Literal["focus-reflection-v1"]
    revision: int = Field(ge=0)
    deleted_count: int = Field(ge=0)
    cleared_at: datetime
    replayed: bool

    @model_validator(mode="after")
    def validate_timestamp(self) -> "FocusReflectionHistoryClearResponse":
        if self.cleared_at.utcoffset() is None:
            raise ValueError("Focus reflection clear timestamp must be aware")
        return self
