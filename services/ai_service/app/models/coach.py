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
COACH_REQUEST_V3_CONTRACT_VERSION = "coach-request-v3"
COACH_RESPONSE_V2_CONTRACT_VERSION = "coach-response-v2"
COACH_CAPABILITIES_V2_CONTRACT_VERSION = "coach-capabilities-v2"
COACH_HISTORY_V2_CONTRACT_VERSION = "coach-history-v2"
COACH_RESPONSE_V3_CONTRACT_VERSION = "coach-response-v3"
COACH_CAPABILITIES_V3_CONTRACT_VERSION = "coach-capabilities-v3"
COACH_HISTORY_V3_CONTRACT_VERSION = "coach-history-v3"
COACH_AGENT_PROMPT_VERSION = "free-coach-agent-prompt-v5"
COACH_AGENT_CONTEXT_VERSION = "personal-snapshot-v3"

COACH_MESSAGE_CODEPOINTS = 2_000
COACH_CONTEXT_BYTES = 32_768
COACH_REPLY_CODEPOINTS = 4_000
COACH_MAX_SELECTED_MEMORIES = 8
COACH_MAX_HISTORY_TURNS = 6
COACH_AGENT_MAX_TOOL_CALLS = 12
COACH_AGENT_TIMEOUT_SECONDS = 180
COACH_AGENT_REQUESTS_PER_LOCAL_DAY = 20
COACH_SNAPSHOT_MAX_ROWS = 50_000
COACH_SNAPSHOT_MAX_BYTES = 8 * 1024 * 1024

CoachProviderName = Literal["disabled", "local_codex_oauth", "fake", "openai", "gemini"]
CoachProviderMode = Literal[
    "disabled",
    "local_development_only",
    "deterministic_test_only",
    "user_supplied_key",
]
CoachModelSource = Literal["explicit", "cli_default", "not_applicable"]
CoachCapabilityState = Literal["disabled", "unavailable", "ready"]
CoachFreshness = Literal["current", "stale", "missing", "not_applicable"]
CoachContextSource = Literal[
    "profile",
    "daily_snapshot",
    "daily_briefing",
    "tasks",
    "habits",
    "focus_sessions",
    "weekly_review",
    "memories",
    "coach_history",
    "daily_capture",
    "focus_reflections",
    "habit_outcomes",
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
        normalized = _nonblank(value, "message")
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


class CoachAgentRequest(BaseModel):
    """The free-question request. Data scope is decided through read-only tools."""

    model_config = ConfigDict(extra="forbid", strict=True)

    contract_version: Literal["coach-request-v3"]
    request_id: UUID = Field(strict=False)
    message: str

    @field_validator("message")
    @classmethod
    def normalize_message(cls, value: str) -> str:
        normalized = _nonblank(value, "message")
        if len(normalized) > COACH_MESSAGE_CODEPOINTS:
            raise ValueError("message exceeds 2,000 Unicode code points")
        return normalized


class CoachAgentLimits(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, frozen=True)

    message_codepoints: Literal[2000]
    reply_codepoints: Literal[4000]
    requests_per_local_day: Literal[20]
    remaining_requests: int = Field(
        ge=0,
        le=COACH_AGENT_REQUESTS_PER_LOCAL_DAY,
    )
    max_tool_calls: Literal[12]
    turn_timeout_seconds: Literal[180]
    sql_timeout_seconds: Literal[5]
    python_timeout_seconds: Literal[30]
    snapshot_max_rows: Literal[50000]
    snapshot_max_bytes: Literal[8388608]


class CoachAgentCapabilitiesResponse(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, frozen=True)

    contract_version: Literal["coach-capabilities-v3"]
    state: CoachCapabilityState
    provider: CoachProviderName
    provider_mode: CoachProviderMode
    model_requested: str | None = Field(default=None, max_length=100)
    model_source: CoachModelSource
    service_tier: Literal["fast", "not_applicable"]
    fast_mode: bool
    reason_code: str = Field(min_length=1, max_length=64)
    tools: list[Literal["inspect_data", "query_data", "run_python"]]
    limits: CoachAgentLimits

    @model_validator(mode="after")
    def validate_provider_identity(self) -> Self:
        if self.provider == "local_codex_oauth":
            if (
                self.provider_mode != "local_development_only"
                or self.model_source != "explicit"
                or self.service_tier != "fast"
                or not self.fast_mode
            ):
                raise ValueError("local Coach capabilities require Fast mode")
            if self.state == "ready" and self.model_requested != "gpt-5.5":
                raise ValueError("a ready local Coach requires GPT-5.5")
        elif self.provider in {"openai", "gemini"}:
            expected_model = (
                "gpt-5.6-terra" if self.provider == "openai" else "gemini-3.6-flash"
            )
            if (
                self.provider_mode != "user_supplied_key"
                or self.model_requested != expected_model
                or self.model_source != "explicit"
                or self.service_tier != "not_applicable"
                or self.fast_mode
                or self.tools != ["inspect_data", "query_data"]
            ):
                raise ValueError("cloud BYOK Coach capability identity is invalid")
        elif self.provider == "fake":
            if (
                self.provider_mode != "deterministic_test_only"
                or self.model_requested is not None
                or self.model_source != "not_applicable"
                or self.service_tier != "not_applicable"
                or self.fast_mode
            ):
                raise ValueError("fake Coach capability identity is invalid")
        elif (
            self.provider_mode != "disabled"
            or self.model_requested is not None
            or self.model_source != "not_applicable"
            or self.service_tier != "not_applicable"
            or self.fast_mode
        ):
            raise ValueError("disabled Coach capability identity is invalid")
        if (self.state == "ready" and self.provider == "disabled") or (
            self.state == "disabled" and self.provider != "disabled"
        ):
            raise ValueError("Coach capability state and provider are inconsistent")
        return self


class CoachAgentEvidence(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, frozen=True)

    source: str = Field(min_length=1, max_length=80)
    record_count: int = Field(ge=0, le=COACH_SNAPSHOT_MAX_ROWS)
    period_start: str | None = Field(default=None, min_length=1, max_length=40)
    period_end: str | None = Field(default=None, min_length=1, max_length=40)

    @model_validator(mode="after")
    def validate_period(self) -> Self:
        if (self.period_start is None) != (self.period_end is None):
            raise ValueError("evidence periods must be complete or absent")
        return self


class CoachAgentTraceStep(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, frozen=True)

    sequence: int = Field(ge=1, le=COACH_AGENT_MAX_TOOL_CALLS)
    tool: Literal["inspect_data", "query_data", "run_python"]
    status: Literal["completed", "failed"]
    summary: str = Field(min_length=1, max_length=500)
    row_count: int | None = Field(default=None, ge=0)
    duration_ms: int = Field(ge=0, le=COACH_AGENT_TIMEOUT_SECONDS * 1_000)


class CoachAgentTrace(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, frozen=True)

    tool_call_count: int = Field(ge=0, le=COACH_AGENT_MAX_TOOL_CALLS)
    steps: list[CoachAgentTraceStep] = Field(max_length=COACH_AGENT_MAX_TOOL_CALLS)
    limitations: list[str] = Field(max_length=20)

    @model_validator(mode="after")
    def validate_trace(self) -> Self:
        if self.tool_call_count != len(self.steps):
            raise ValueError("tool count must match trace steps")
        if [step.sequence for step in self.steps] != list(
            range(1, len(self.steps) + 1),
        ):
            raise ValueError("trace steps must be contiguous")
        if any(not value.strip() or len(value) > 500 for value in self.limitations):
            raise ValueError("trace limitations must be bounded nonblank text")
        return self


class CoachAgentProvenance(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, frozen=True)

    source: Literal["model", "deterministic_safety"]
    provider: CoachProviderName
    provider_mode: CoachProviderMode
    model_requested: str | None = Field(default=None, max_length=100)
    model_reported: str | None = Field(default=None, max_length=100)
    model_source: CoachModelSource
    prompt_version: Literal["free-coach-agent-prompt-v4", "free-coach-agent-prompt-v5"]
    context_version: Literal["personal-snapshot-v3"]
    generated_at: datetime = Field(strict=False)
    provider_called: bool
    service_tier: Literal["fast", "not_applicable"]
    service_tier_status: Literal["configured", "not_applicable"]
    fast_mode: bool
    snapshot_row_count: int = Field(ge=0, le=COACH_SNAPSHOT_MAX_ROWS)
    snapshot_bytes: int = Field(ge=0, le=COACH_SNAPSHOT_MAX_BYTES)

    @model_validator(mode="after")
    def validate_provenance(self) -> Self:
        if self.generated_at.tzinfo is None:
            raise ValueError("generated_at must be timezone-aware")
        if (
            self.prompt_version
            not in {"free-coach-agent-prompt-v4", COACH_AGENT_PROMPT_VERSION}
            or self.context_version != COACH_AGENT_CONTEXT_VERSION
        ):
            raise ValueError("Coach prompt and snapshot versions must match")
        if self.source == "model" and not self.provider_called:
            raise ValueError("model responses must call a provider")
        if self.provider_called and self.provider == "disabled":
            raise ValueError("a disabled provider cannot have been called")
        if self.provider == "local_codex_oauth":
            if (
                self.provider_mode != "local_development_only"
                or self.service_tier != "fast"
                or self.service_tier_status != "configured"
                or not self.fast_mode
                or self.model_requested != "gpt-5.5"
                or self.model_reported not in {None, "gpt-5.5"}
                or self.model_source != "explicit"
            ):
                raise ValueError("local Codex agent must use configured Fast GPT-5.5")
        elif self.provider in {"openai", "gemini"}:
            expected_model = (
                "gpt-5.6-terra" if self.provider == "openai" else "gemini-3.6-flash"
            )
            if (
                self.provider_mode != "user_supplied_key"
                or self.model_requested != expected_model
                or self.model_reported not in {None, expected_model}
                or self.model_source != "explicit"
                or self.service_tier != "not_applicable"
                or self.service_tier_status != "not_applicable"
                or self.fast_mode
            ):
                raise ValueError("cloud BYOK Coach provenance is invalid")
        elif self.provider == "fake":
            if (
                self.provider_mode != "deterministic_test_only"
                or self.model_requested is not None
                or self.model_reported is not None
                or self.model_source != "not_applicable"
                or self.service_tier != "not_applicable"
                or self.service_tier_status != "not_applicable"
                or self.fast_mode
            ):
                raise ValueError("fake Coach provenance is invalid")
        elif (
            self.provider_mode != "disabled"
            or self.model_requested is not None
            or self.model_reported is not None
            or self.model_source != "not_applicable"
            or self.service_tier != "not_applicable"
            or self.service_tier_status != "not_applicable"
            or self.fast_mode
        ):
            raise ValueError("disabled Coach provenance is invalid")
        return self


class CoachAgentModelOutput(BaseModel):
    """The complete and only output fields trusted from the model."""

    model_config = ConfigDict(extra="forbid", strict=True, frozen=True)

    reply: str = Field(min_length=1, max_length=COACH_REPLY_CODEPOINTS)
    uncertainty: CoachUncertainty
    safety: CoachSafety

    @field_validator("reply")
    @classmethod
    def normalize_reply(cls, value: str) -> str:
        return _nonblank(value, "reply")


class CoachAgentResponse(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, frozen=True)

    contract_version: Literal["coach-response-v2", "coach-response-v3"]
    request_id: UUID = Field(strict=False)
    reply: str = Field(min_length=1, max_length=COACH_REPLY_CODEPOINTS)
    uncertainty: CoachUncertainty
    safety: CoachSafety
    evidence: list[CoachAgentEvidence] = Field(max_length=100)
    agent_trace: CoachAgentTrace
    provenance: CoachAgentProvenance

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


class CoachAgentHistoryTurn(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, frozen=True)

    request_id: UUID = Field(strict=False)
    message: str = Field(min_length=1, max_length=COACH_MESSAGE_CODEPOINTS)
    response: CoachResponse | CoachAgentResponse
    created_at: datetime = Field(strict=False)

    @model_validator(mode="after")
    def validate_turn(self) -> Self:
        if self.created_at.tzinfo is None:
            raise ValueError("created_at must be timezone-aware")
        if self.response.request_id != self.request_id:
            raise ValueError("history request identity is inconsistent")
        return self


class CoachAgentHistoryResponse(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, frozen=True)

    contract_version: Literal["coach-history-v3"]
    turns: list[CoachAgentHistoryTurn]


def _nonblank(value: str, field_name: str) -> str:
    normalized = value.strip()
    if not normalized:
        raise ValueError(f"{field_name} cannot be blank")
    try:
        normalized.encode("utf-8", errors="strict")
    except UnicodeEncodeError as exc:
        raise ValueError(
            f"{field_name} must contain valid Unicode scalar values",
        ) from exc
    return normalized
