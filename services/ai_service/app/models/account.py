from datetime import datetime
from typing import Any, Literal
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, field_validator, model_validator

from app.owner_data_catalog import (
    ACCOUNT_EXPORT_OMITTED_TABLES,
    ACCOUNT_EXPORT_SANITIZED_TABLES,
    ACCOUNT_EXPORT_TABLE_NAMES,
)

ACCOUNT_EXPORT_CONTRACT_VERSION = "account-export-v6"
PILOT_PARTICIPATION_CONTRACT_VERSION = "pilot-participation-v1"
PILOT_PARTICIPATION_NOTICE_VERSION = "pilot-participation-notice-v1"
PILOT_PARTICIPATION_GATE_CONTRACT_VERSION = "pilot-participation-gate-v1"
ACCOUNT_DELETION_CONTRACT_VERSION = "account-deletion-v2"
ACCOUNT_DELETION_STATUS_CONTRACT_VERSION = "account-deletion-status-v2"
ACCOUNT_DELETION_RECOVERY_CONTRACT_VERSION = "account-deletion-recovery-v2"
ACCOUNT_EXPORT_MAX_ROWS_PER_TABLE = 10_000
ACCOUNT_EXPORT_MAX_TOTAL_ROWS = 50_000
ACCOUNT_EXPORT_MAX_JSON_BYTES = 8 * 1024 * 1024
DAILY_PREPARATION_BUDGET_MINUTES_MIN = 25
DAILY_PREPARATION_BUDGET_MINUTES_MAX = 480


class PilotParticipationRequest(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, frozen=True)

    contract_version: Literal["pilot-participation-v1"]
    notice_version: Literal["pilot-participation-notice-v1"]
    confirmed_18_or_older: Literal[True]


class PilotParticipationResponse(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, frozen=True)

    contract_version: Literal["pilot-participation-v1"]
    notice_version: Literal["pilot-participation-notice-v1"]
    accepted_at: datetime
    replayed: bool

    @model_validator(mode="after")
    def validate_timestamp(self) -> "PilotParticipationResponse":
        if self.accepted_at.tzinfo is None:
            raise ValueError("accepted_at must be timezone-aware")
        return self


class AccountProfileUpdateRequest(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, frozen=True)

    contract_version: Literal["account-profile-update-v2"]
    request_id: UUID = Field(strict=False)
    expected_revision: int = Field(ge=1)
    timezone: str = Field(min_length=1, max_length=100)

    @field_validator("timezone")
    @classmethod
    def require_exact_timezone_text(cls, value: str) -> str:
        if value != value.strip():
            raise ValueError("timezone must not contain surrounding whitespace")
        return value


class AccountProfileResponse(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, frozen=True)

    contract_version: Literal["account-profile-v2"]
    timezone: str = Field(min_length=1, max_length=100)
    revision: int = Field(ge=2)
    updated_at: datetime
    replayed: bool

    @model_validator(mode="after")
    def validate_timestamp(self) -> "AccountProfileResponse":
        if self.updated_at.tzinfo is None:
            raise ValueError("updated_at must be timezone-aware")
        return self


class AccountPreparationBudgetUpdateRequest(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, frozen=True)

    contract_version: Literal["account-preparation-budget-update-v2"]
    request_id: UUID = Field(strict=False)
    expected_revision: int = Field(ge=1)
    daily_preparation_budget_minutes: int | None = Field(
        ge=DAILY_PREPARATION_BUDGET_MINUTES_MIN,
        le=DAILY_PREPARATION_BUDGET_MINUTES_MAX,
    )

    @field_validator("daily_preparation_budget_minutes")
    @classmethod
    def require_five_minute_increment(cls, value: int | None) -> int | None:
        if value is not None and value % 5 != 0:
            raise ValueError(
                "daily_preparation_budget_minutes must use five-minute increments",
            )
        return value


class AccountPreparationBudgetResponse(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, frozen=True)

    contract_version: Literal["account-preparation-budget-v2"]
    daily_preparation_budget_minutes: int | None = Field(
        ge=DAILY_PREPARATION_BUDGET_MINUTES_MIN,
        le=DAILY_PREPARATION_BUDGET_MINUTES_MAX,
    )
    revision: int = Field(ge=2)
    updated_at: datetime
    replayed: bool

    @model_validator(mode="after")
    def validate_timestamp(self) -> "AccountPreparationBudgetResponse":
        if self.updated_at.tzinfo is None:
            raise ValueError("updated_at must be timezone-aware")
        return self


class AccountDeleteRequest(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, frozen=True)

    contract_version: Literal["account-deletion-v2"]
    deletion_id: UUID = Field(strict=False)
    confirmation: Literal["DELETE"]


class AccountDeleteResponse(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, frozen=True)

    contract_version: Literal["account-deletion-v2"]
    deletion_id: UUID = Field(strict=False)
    state: Literal["deletion_pending", "completed"]
    accepted_at: datetime
    completed_at: datetime | None
    journal_durable: bool

    @model_validator(mode="after")
    def validate_state(self) -> "AccountDeleteResponse":
        if self.accepted_at.tzinfo is None:
            raise ValueError("accepted_at must be timezone-aware")
        if self.completed_at is not None and self.completed_at.tzinfo is None:
            raise ValueError("completed_at must be timezone-aware")
        if self.state == "completed" and (
            self.completed_at is None or not self.journal_durable
        ):
            raise ValueError("completed deletion requires journal and completion time")
        if self.state == "deletion_pending" and self.completed_at is not None:
            raise ValueError("pending deletion cannot have a completion time")
        return self


class AccountDeletionStatusResponse(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, frozen=True)

    contract_version: Literal["account-deletion-status-v2"]
    deletion: AccountDeleteResponse | None


class AccountExportLedgerPolicy(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, frozen=True)

    sanitized_tables: list[str]
    omitted_tables: dict[str, str]

    @model_validator(mode="after")
    def validate_exact_v6_policy(self) -> "AccountExportLedgerPolicy":
        if tuple(self.sanitized_tables) != ACCOUNT_EXPORT_SANITIZED_TABLES:
            raise ValueError("sanitized_tables must match the V6 ledger policy")
        if self.omitted_tables != ACCOUNT_EXPORT_OMITTED_TABLES:
            raise ValueError("omitted_tables must match the V6 ledger policy")
        return self


class AccountExportLimits(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, frozen=True)

    max_rows_per_table: int = Field(gt=0)
    max_total_rows: int = Field(gt=0)
    max_json_bytes: int = Field(gt=0)

    @model_validator(mode="after")
    def validate_exact_v6_limits(self) -> "AccountExportLimits":
        if (
            self.max_rows_per_table,
            self.max_total_rows,
            self.max_json_bytes,
        ) != (
            ACCOUNT_EXPORT_MAX_ROWS_PER_TABLE,
            ACCOUNT_EXPORT_MAX_TOTAL_ROWS,
            ACCOUNT_EXPORT_MAX_JSON_BYTES,
        ):
            raise ValueError("limits must match the account-export-v6 contract")
        return self


class AccountExportResponse(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, frozen=True)

    contract_version: Literal["account-export-v6"]
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
            raise ValueError("data must contain the exact V6 export table set")
        if set(self.record_counts) != expected_tables:
            raise ValueError("record_counts must contain the exact V6 table set")
        if any(
            self.record_counts[name] != len(rows) for name, rows in self.data.items()
        ):
            raise ValueError("record_counts must match exported row counts")
        if any(
            count > ACCOUNT_EXPORT_MAX_ROWS_PER_TABLE
            for count in self.record_counts.values()
        ):
            raise ValueError("record_counts exceed the V6 per-table bound")
        if sum(self.record_counts.values()) > ACCOUNT_EXPORT_MAX_TOTAL_ROWS:
            raise ValueError("record_counts exceed the V6 total bound")
        return self
