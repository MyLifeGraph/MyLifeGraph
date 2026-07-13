from datetime import datetime
from typing import Literal, Self
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, field_validator, model_validator


COACH_REQUEST_CONTRACT_VERSION = "coach-request-v1"
COACH_RESPONSE_CONTRACT_VERSION = "coach-response-v1"
COACH_CAPABILITIES_CONTRACT_VERSION = "coach-capabilities-v1"
COACH_HISTORY_CONTRACT_VERSION = "coach-history-v1"
COACH_MEMORY_SELECTION_CONTRACT_VERSION = "coach-memory-selection-v1"
COACH_CONTEXT_VERSION = "coach-context-v1"
COACH_PROMPT_VERSION = "controlled-coach-prompt-v1"

COACH_MESSAGE_CODEPOINTS = 2_000
COACH_CONTEXT_BYTES = 32_768
COACH_REPLY_CODEPOINTS = 4_000
COACH_MAX_SELECTED_MEMORIES = 8
COACH_MAX_HISTORY_TURNS = 6

CoachProviderName = Literal["disabled", "local_codex_oauth", "fake"]
CoachProviderMode = Literal[
    "disabled",
    "local_development_only",
    "deterministic_test_only",
]
CoachModelSource = Literal["explicit", "cli_default", "not_applicable"]
CoachCapabilityState = Literal["disabled", "unavailable", "ready"]
CoachFreshness = Literal["current", "stale", "missing", "not_applicable"]
CoachContextSource = Literal[
    "profile",
    "daily_snapshot",
    "daily_briefing",
    "goals",
    "tasks",
    "habits",
    "focus_sessions",
    "weekly_review",
    "memories",
    "coach_history",
]


class CoachErrorDetail(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, frozen=True)

    code: str = Field(min_length=1, max_length=64)
    message: str = Field(min_length=1, max_length=300)
    retryable: bool


class CoachLimits(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, frozen=True)

    message_codepoints: Literal[2000]
    context_bytes: Literal[32768]
    reply_codepoints: Literal[4000]
    timeout_seconds: int = Field(ge=5, le=120)
    requests_per_local_day: int = Field(ge=1, le=100)
    remaining_requests: int = Field(ge=0, le=100)


class CoachCapabilitiesResponse(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, frozen=True)

    contract_version: Literal["coach-capabilities-v1"]
    state: CoachCapabilityState
    provider: CoachProviderName
    provider_mode: CoachProviderMode
    model_requested: str | None = Field(default=None, max_length=100)
    model_source: CoachModelSource
    reason_code: str = Field(min_length=1, max_length=64)
    limits: CoachLimits


class CoachRequest(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True)

    contract_version: Literal["coach-request-v1"]
    request_id: UUID = Field(strict=False)
    message: str
    context_scope: Literal["today"]

    @field_validator("message")
    @classmethod
    def normalize_message(cls, value: str) -> str:
        normalized = value.strip()
        if not normalized:
            raise ValueError("message cannot be blank")
        if len(normalized) > COACH_MESSAGE_CODEPOINTS:
            raise ValueError("message exceeds 2,000 Unicode code points")
        return normalized


class CoachUncertainty(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, frozen=True)

    level: Literal["low", "medium", "high"]
    reason: str = Field(min_length=1, max_length=300)

    @field_validator("reason")
    @classmethod
    def normalize_reason(cls, value: str) -> str:
        return _nonblank(value, "uncertainty reason")


class CoachStagedSuggestion(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, frozen=True)

    title: str = Field(min_length=1, max_length=120)
    rationale: str = Field(min_length=1, max_length=500)

    @field_validator("title", "rationale")
    @classmethod
    def normalize_suggestion_text(cls, value: str) -> str:
        return _nonblank(value, "suggestion text")


class CoachSafety(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, frozen=True)

    classification: Literal["normal", "sensitive", "safety_redirect"]


class CoachUsedContext(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, frozen=True)

    source: CoachContextSource
    available_count: int = Field(ge=0)
    included_count: int = Field(ge=0)
    omitted_count: int = Field(ge=0)
    freshness: CoachFreshness

    @model_validator(mode="after")
    def validate_counts(self) -> Self:
        if self.included_count + self.omitted_count != self.available_count:
            raise ValueError("context counts must reconcile")
        return self


class CoachProvenance(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, frozen=True)

    source: Literal["model", "deterministic_safety"]
    provider: CoachProviderName
    provider_mode: CoachProviderMode
    model_requested: str | None = Field(default=None, max_length=100)
    model_reported: str | None = Field(default=None, max_length=100)
    model_source: CoachModelSource
    prompt_version: Literal["controlled-coach-prompt-v1"]
    context_version: Literal["coach-context-v1"]
    generated_at: datetime = Field(strict=False)
    provider_called: bool

    @model_validator(mode="after")
    def validate_provenance(self) -> Self:
        if self.generated_at.tzinfo is None:
            raise ValueError("generated_at must be timezone-aware")
        if self.source == "model" and not self.provider_called:
            raise ValueError("model responses must call a provider")
        if self.provider_called and self.provider == "disabled":
            raise ValueError("a disabled provider cannot have been called")
        return self


class CoachResponse(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, frozen=True)

    contract_version: Literal["coach-response-v1"]
    request_id: UUID = Field(strict=False)
    reply: str = Field(min_length=1, max_length=COACH_REPLY_CODEPOINTS)
    uncertainty: CoachUncertainty
    staged_suggestion: CoachStagedSuggestion | None
    safety: CoachSafety
    used_context: list[CoachUsedContext] = Field(max_length=10)
    provenance: CoachProvenance

    @field_validator("reply")
    @classmethod
    def normalize_reply(cls, value: str) -> str:
        return _nonblank(value, "reply")

    @model_validator(mode="after")
    def validate_safety_provenance(self) -> Self:
        deterministic = self.provenance.source == "deterministic_safety"
        redirected = self.safety.classification == "safety_redirect"
        if deterministic != redirected:
            raise ValueError(
                "deterministic safety provenance requires a safety redirect",
            )
        return self


class CoachModelOutput(BaseModel):
    """The only fields the untrusted provider is allowed to produce."""

    model_config = ConfigDict(extra="forbid", strict=True, frozen=True)

    reply: str = Field(min_length=1, max_length=COACH_REPLY_CODEPOINTS)
    uncertainty: CoachUncertainty
    staged_suggestion: CoachStagedSuggestion | None
    safety: CoachSafety

    @field_validator("reply")
    @classmethod
    def normalize_reply(cls, value: str) -> str:
        return _nonblank(value, "reply")


class CoachHistoryTurn(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, frozen=True)

    request_id: UUID = Field(strict=False)
    message: str = Field(min_length=1, max_length=COACH_MESSAGE_CODEPOINTS)
    response: CoachResponse
    created_at: datetime = Field(strict=False)

    @model_validator(mode="after")
    def validate_turn(self) -> Self:
        if self.created_at.tzinfo is None:
            raise ValueError("created_at must be timezone-aware")
        if self.response.request_id != self.request_id:
            raise ValueError("history request identity is inconsistent")
        return self


class CoachHistoryResponse(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, frozen=True)

    contract_version: Literal["coach-history-v1"]
    turns: list[CoachHistoryTurn]


class CoachHistoryDeleteResponse(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, frozen=True)

    contract_version: Literal["coach-history-v1"]
    deleted: bool


class CoachMemorySelectionRequest(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True)

    selected: Literal[True]

    @field_validator("selected", mode="before")
    @classmethod
    def require_literal_boolean(cls, value: object) -> object:
        if value is not True:
            raise ValueError("selected must be the boolean true")
        return value


class CoachMemory(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, frozen=True)

    id: UUID
    type: Literal[
        "pattern",
        "preference",
        "goal",
        "habit",
        "recurring_problem",
        "recommendation",
    ]
    title: str = Field(min_length=1, max_length=160)
    content: str = Field(min_length=1, max_length=1_000)
    content_truncated: bool
    ownership: Literal["setup", "manual"]
    selected: bool
    updated_at: datetime

    @field_validator("title", "content")
    @classmethod
    def normalize_memory_text(cls, value: str) -> str:
        return _nonblank(value, "memory text")

    @model_validator(mode="after")
    def validate_timestamp(self) -> Self:
        if self.updated_at.tzinfo is None:
            raise ValueError("updated_at must be timezone-aware")
        return self


class CoachMemorySelectionResponse(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, frozen=True)

    contract_version: Literal["coach-memory-selection-v1"]
    max_selected: Literal[8]
    available_count: int = Field(ge=0)
    memories: list[CoachMemory]

    @model_validator(mode="after")
    def validate_selection(self) -> Self:
        if self.available_count < len(self.memories):
            raise ValueError("available memory count cannot be smaller than rows")
        if sum(memory.selected for memory in self.memories) > self.max_selected:
            raise ValueError("selected memory limit exceeded")
        return self


def _nonblank(value: str, field_name: str) -> str:
    normalized = value.strip()
    if not normalized:
        raise ValueError(f"{field_name} cannot be blank")
    return normalized
