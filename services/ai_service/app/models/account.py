from datetime import datetime
from typing import Any, Literal

from pydantic import BaseModel, ConfigDict, Field, field_validator, model_validator


ACCOUNT_EXPORT_CONTRACT_VERSION = "account-export-v1"
ACCOUNT_EXPORT_TABLE_NAMES = (
    "profiles",
    "notification_preferences",
    "daily_logs",
    "behavioral_events",
    "lifestyle_entries",
    "tasks",
    "schedule_items",
    "notifications",
    "coach_messages",
    "memory_entries",
    "ai_insights",
    "recommendations",
    "skillset_profiles",
    "goals",
    "habits",
    "habit_logs",
    "focus_sessions",
    "intake_responses",
    "user_state_snapshots",
    "daily_briefings",
    "decision_feedback",
    "weekly_reviews",
    "calendar_connections",
    "calendar_imports",
    "calendar_events",
    "coach_requests",
    "coach_usage_events",
    "coach_memory_selections",
)
ACCOUNT_EXPORT_SANITIZED_TABLES = (
    "calendar_connections",
    "calendar_imports",
    "calendar_events",
    "coach_requests",
    "coach_usage_events",
)
ACCOUNT_EXPORT_OMITTED_TABLES = {
    "calendar_request_identities": "backend_only_anti_replay_ledger",
    "notification_action_requests": "backend_only_anti_replay_ledger",
}
ACCOUNT_EXPORT_MAX_ROWS_PER_TABLE = 10_000
ACCOUNT_EXPORT_MAX_TOTAL_ROWS = 50_000
ACCOUNT_EXPORT_MAX_JSON_BYTES = 8 * 1024 * 1024


class AccountProfileUpdateRequest(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, frozen=True)

    timezone: str = Field(min_length=1, max_length=100)

    @field_validator("timezone")
    @classmethod
    def require_exact_timezone_text(cls, value: str) -> str:
        if value != value.strip():
            raise ValueError("timezone must not contain surrounding whitespace")
        return value


class AccountProfileResponse(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, frozen=True)

    timezone: str = Field(min_length=1, max_length=100)


class AccountDeleteRequest(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, frozen=True)

    confirmation: Literal["DELETE"]


class AccountExportLedgerPolicy(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, frozen=True)

    sanitized_tables: list[str]
    omitted_tables: dict[str, str]

    @model_validator(mode="after")
    def validate_exact_v1_policy(self) -> "AccountExportLedgerPolicy":
        if tuple(self.sanitized_tables) != ACCOUNT_EXPORT_SANITIZED_TABLES:
            raise ValueError("sanitized_tables must match the V1 ledger policy")
        if self.omitted_tables != ACCOUNT_EXPORT_OMITTED_TABLES:
            raise ValueError("omitted_tables must match the V1 ledger policy")
        return self


class AccountExportLimits(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, frozen=True)

    max_rows_per_table: int = Field(gt=0)
    max_total_rows: int = Field(gt=0)
    max_json_bytes: int = Field(gt=0)

    @model_validator(mode="after")
    def validate_exact_v1_limits(self) -> "AccountExportLimits":
        if (
            self.max_rows_per_table,
            self.max_total_rows,
            self.max_json_bytes,
        ) != (
            ACCOUNT_EXPORT_MAX_ROWS_PER_TABLE,
            ACCOUNT_EXPORT_MAX_TOTAL_ROWS,
            ACCOUNT_EXPORT_MAX_JSON_BYTES,
        ):
            raise ValueError("limits must match the account-export-v1 contract")
        return self


class AccountExportResponse(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, frozen=True)

    contract_version: Literal["account-export-v1"]
    exported_at: datetime
    data: dict[str, list[dict[str, Any]]]
    record_counts: dict[str, int]
    ledger_policy: AccountExportLedgerPolicy
    limits: AccountExportLimits

    @model_validator(mode="after")
    def validate_export_shape(self) -> "AccountExportResponse":
        if self.exported_at.tzinfo is None:
            raise ValueError("exported_at must be timezone-aware")
        expected_tables = set(ACCOUNT_EXPORT_TABLE_NAMES)
        if set(self.data) != expected_tables:
            raise ValueError("data must contain the exact V1 export table set")
        if set(self.record_counts) != expected_tables:
            raise ValueError("record_counts must contain the exact V1 table set")
        if any(
            self.record_counts[name] != len(rows)
            for name, rows in self.data.items()
        ):
            raise ValueError("record_counts must match exported row counts")
        if any(
            count > ACCOUNT_EXPORT_MAX_ROWS_PER_TABLE
            for count in self.record_counts.values()
        ):
            raise ValueError("record_counts exceed the V1 per-table bound")
        if sum(self.record_counts.values()) > ACCOUNT_EXPORT_MAX_TOTAL_ROWS:
            raise ValueError("record_counts exceed the V1 total bound")
        return self
