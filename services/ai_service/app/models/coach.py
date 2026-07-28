from datetime import datetime
from typing import Any, Literal, Self
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, field_validator, model_validator


COACH_REQUEST_CONTRACT_VERSION = "coach-request-v1"
COACH_REQUEST_V2_CONTRACT_VERSION = "coach-request-v2"
COACH_RESPONSE_CONTRACT_VERSION = "coach-response-v1"
COACH_CAPABILITIES_CONTRACT_VERSION = "coach-capabilities-v1"
COACH_HISTORY_CONTRACT_VERSION = "coach-history-v1"
COACH_MEMORY_SELECTION_CONTRACT_VERSION = "coach-memory-selection-v1"
COACH_CONTEXT_OPTIONS_CONTRACT_VERSION = "coach-context-options-v1"
COACH_CONTEXT_VERSION = "coach-context-v2"
COACH_PROMPT_VERSION = "controlled-coach-prompt-v2"
COACH_CONTEXT_V3_VERSION = "coach-context-v3"
COACH_PROMPT_V3_VERSION = "controlled-coach-prompt-v3"

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
    "daily_capture",
    "focus_reflections",
    "habit_outcomes",
    "decision_feedback",
    "weekly_reviews",
    "task_lifecycle",
]
CoachContextScope = Literal["today", "patterns", "focus", "review"]
CoachPatternsHorizon = Literal["90_days", "1_year", "all_available"]


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

    contract_version: Literal["coach-request-v1", "coach-request-v2"]
    request_id: UUID = Field(strict=False)
    message: str
    context_scope: CoachContextScope
    context_parameters: dict[str, Any] | None = None

    @field_validator("message")
    @classmethod
    def normalize_message(cls, value: str) -> str:
        normalized = value.strip()
        if not normalized:
            raise ValueError("message cannot be blank")
        if len(normalized) > COACH_MESSAGE_CODEPOINTS:
            raise ValueError("message exceeds 2,000 Unicode code points")
        return normalized

    @model_validator(mode="after")
    def validate_context_selection(self) -> Self:
        parameters_supplied = "context_parameters" in self.model_fields_set
        if self.contract_version == COACH_REQUEST_CONTRACT_VERSION:
            if self.context_scope != "today" or parameters_supplied:
                raise ValueError("Coach request V1 supports only today's context")
            return self
        if not parameters_supplied or not isinstance(self.context_parameters, dict):
            raise ValueError("Coach request V2 requires context parameters")
        parameters = self.context_parameters
        if self.context_scope in {"today", "review"}:
            if parameters:
                raise ValueError("this Coach context accepts no parameters")
            return self
        if self.context_scope == "patterns":
            if set(parameters) != {"horizon"} or parameters.get("horizon") not in {
                "90_days",
                "1_year",
                "all_available",
            }:
                raise ValueError("Patterns requires one valid horizon")
            return self
        if set(parameters) != {"focus_session_id"}:
            raise ValueError("Focus requires one Focus session id")
        raw_id = parameters.get("focus_session_id")
        if not isinstance(raw_id, str):
            raise ValueError("Focus session id must be a UUID string")
        try:
            normalized = str(UUID(raw_id))
        except ValueError as exc:
            raise ValueError("Focus session id must be valid") from exc
        self.context_parameters = {"focus_session_id": normalized}
        return self

    @property
    def is_v2(self) -> bool:
        return self.contract_version == COACH_REQUEST_V2_CONTRACT_VERSION

    @property
    def patterns_horizon(self) -> CoachPatternsHorizon | None:
        if self.context_scope != "patterns" or self.context_parameters is None:
            return None
        return self.context_parameters["horizon"]

    @property
    def focus_session_id(self) -> UUID | None:
        if self.context_scope != "focus" or self.context_parameters is None:
            return None
        return UUID(self.context_parameters["focus_session_id"])


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
    prompt_version: Literal[
        "controlled-coach-prompt-v1",
        "controlled-coach-prompt-v2",
        "controlled-coach-prompt-v3",
    ]
    context_version: Literal[
        "coach-context-v1",
        "coach-context-v2",
        "coach-context-v3",
    ]
    generated_at: datetime = Field(strict=False)
    provider_called: bool

    @model_validator(mode="after")
    def validate_provenance(self) -> Self:
        if self.generated_at.tzinfo is None:
            raise ValueError("generated_at must be timezone-aware")
        if (
            self.prompt_version,
            self.context_version,
        ) not in {
            ("controlled-coach-prompt-v1", "coach-context-v1"),
            ("controlled-coach-prompt-v2", "coach-context-v2"),
            ("controlled-coach-prompt-v3", "coach-context-v3"),
        }:
            raise ValueError("Coach prompt and context versions must match")
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
    context_scope: CoachContextScope
    context_parameters: dict[str, Any]
    response: CoachResponse
    created_at: datetime = Field(strict=False)

    @model_validator(mode="after")
    def validate_turn(self) -> Self:
        if self.created_at.tzinfo is None:
            raise ValueError("created_at must be timezone-aware")
        if self.response.request_id != self.request_id:
            raise ValueError("history request identity is inconsistent")
        if self.context_scope in {"today", "review"}:
            if self.context_parameters:
                raise ValueError("history context parameters are inconsistent")
        elif self.context_scope == "patterns":
            if set(self.context_parameters) != {"horizon"} or (
                self.context_parameters.get("horizon")
                not in {"90_days", "1_year", "all_available"}
            ):
                raise ValueError("history Patterns parameters are inconsistent")
        elif set(self.context_parameters) != {"focus_session_id"}:
            raise ValueError("history Focus parameters are inconsistent")
        else:
            try:
                UUID(str(self.context_parameters["focus_session_id"]))
            except ValueError as exc:
                raise ValueError("history Focus id is invalid") from exc
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


class CoachFocusContextOption(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, frozen=True)

    focus_session_id: UUID = Field(strict=False)
    status: Literal["completed", "abandoned"]
    local_started_at: datetime = Field(strict=False)
    planned_minutes: int = Field(ge=5, le=240)
    actual_minutes: int = Field(ge=0, le=90 * 24 * 60)
    has_reflection: bool

    @model_validator(mode="after")
    def validate_timestamp(self) -> Self:
        if self.local_started_at.utcoffset() is None:
            raise ValueError("Focus option timestamp must be timezone-aware")
        return self


class CoachContextOptionsResponse(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, frozen=True)

    contract_version: Literal["coach-context-options-v1"]
    timezone: str = Field(min_length=1, max_length=100)
    personal_pattern_analysis_enabled: bool
    focus_options: list[CoachFocusContextOption] = Field(max_length=10)
    default_focus_session_id: UUID | None = Field(default=None, strict=False)
    more_focus_options_available: bool

    @model_validator(mode="after")
    def validate_default(self) -> Self:
        option_ids = {option.focus_session_id for option in self.focus_options}
        if (
            self.default_focus_session_id is not None
            and self.default_focus_session_id not in option_ids
        ):
            raise ValueError("default Focus option must be included")
        return self


def _nonblank(value: str, field_name: str) -> str:
    normalized = value.strip()
    if not normalized:
        raise ValueError(f"{field_name} cannot be blank")
    return normalized
