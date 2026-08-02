import hashlib
import json
from collections.abc import Callable
from dataclasses import dataclass
from datetime import UTC, datetime
from uuid import UUID
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from app.core.lossless_json import lossless_json_text
from app.models.account import (
    ACCOUNT_EXPORT_CONTRACT_VERSION,
    ACCOUNT_EXPORT_MAX_JSON_BYTES,
    ACCOUNT_EXPORT_MAX_ROWS_PER_TABLE,
    ACCOUNT_EXPORT_MAX_TOTAL_ROWS,
    ACCOUNT_EXPORT_OMITTED_TABLES,
    ACCOUNT_EXPORT_SANITIZED_TABLES,
    ACCOUNT_EXPORT_TABLE_NAMES,
    AccountExportLedgerPolicy,
    AccountExportLimits,
    AccountExportResponse,
    AccountPreparationBudgetResponse,
    AccountProfileResponse,
    DAILY_PREPARATION_BUDGET_MINUTES_MAX,
    DAILY_PREPARATION_BUDGET_MINUTES_MIN,
)
from app.owner_data_catalog import (
    ACCOUNT_EXPORT_TABLES,
    OWNER_DATA_PAGE_BYTE_CUSHION,
    OWNER_DATA_PAGE_SIZE,
    OWNER_DATA_WATERMARK_MAX_BYTES,
)
from app.repositories.account_repository import (
    AccountDeletionOutcomeUnknownError as AccountPersistenceDeletionOutcomeUnknown,
    AccountExportSourceTooLargeError as AccountPersistenceSourceTooLarge,
    AccountNotFoundError as AccountPersistenceNotFound,
    AccountPersistenceError,
    AccountPreparationBudgetUpdateOutcomeUnknownError as AccountPersistenceBudgetOutcomeUnknown,
    AccountProfileUpdateOutcomeUnknownError as AccountPersistenceProfileOutcomeUnknown,
    AccountRepository,
    AccountSettingConflictError as AccountPersistenceConflict,
)
from app.services.owner_data_reader import (
    OwnerDataInvalidCursorError,
    OwnerDataInvalidOwnerError,
    OwnerDataInvalidPageError,
    OwnerDataReadPolicy,
    OwnerDataReader,
    OwnerDataSerializedBytesExceededError,
    OwnerDataSourceRowsExceededError,
    OwnerDataTotalRowsExceededError,
)


ACCOUNT_EXPORT_PAGE_SIZE = OWNER_DATA_PAGE_SIZE
ACCOUNT_EXPORT_PAGE_BYTE_CUSHION = OWNER_DATA_PAGE_BYTE_CUSHION
ACCOUNT_EXPORT_WATERMARK_MAX_BYTES = OWNER_DATA_WATERMARK_MAX_BYTES


class InvalidAccountTimezoneError(ValueError):
    pass


class InvalidPreparationBudgetError(ValueError):
    pass


class AccountExportTooLargeError(RuntimeError):
    pass


class AccountNotFoundError(RuntimeError):
    pass


class AccountConflictError(RuntimeError):
    pass


class AccountOutcomeUnknownError(RuntimeError):
    pass


class AccountUnavailableError(RuntimeError):
    pass


@dataclass(frozen=True)
class PreparedAccountExport:
    envelope: AccountExportResponse
    content: bytes


ACCOUNT_EXPORT_LEDGER_POLICY = AccountExportLedgerPolicy(
    sanitized_tables=list(ACCOUNT_EXPORT_SANITIZED_TABLES),
    omitted_tables=dict(ACCOUNT_EXPORT_OMITTED_TABLES),
)


class AccountService:
    def __init__(
        self,
        *,
        repository: AccountRepository,
        now: Callable[[], datetime] | None = None,
    ) -> None:
        self._repository = repository
        self._owner_data_reader = OwnerDataReader(repository=repository)
        self._now = now or (lambda: datetime.now(UTC))

    async def update_timezone(
        self,
        *,
        user_id: str,
        request_id: UUID,
        expected_revision: int,
        timezone: str,
    ) -> AccountProfileResponse:
        _validate_timezone(timezone)
        now = self._now()
        fingerprint = _setting_fingerprint(
            {
                "contract_version": "account-profile-update-v2",
                "request_id": str(request_id),
                "expected_revision": expected_revision,
                "timezone": timezone,
            },
        )
        try:
            stored = await self._repository.update_timezone(
                user_id=user_id,
                request_id=str(request_id),
                request_fingerprint=fingerprint,
                expected_revision=expected_revision,
                timezone=timezone,
                now=now,
            )
        except AccountPersistenceConflict as exc:
            raise AccountConflictError(str(exc)) from exc
        except AccountPersistenceProfileOutcomeUnknown as exc:
            raise AccountOutcomeUnknownError(str(exc)) from exc
        except AccountPersistenceNotFound as exc:
            raise AccountNotFoundError(str(exc)) from exc
        except AccountPersistenceError as exc:
            raise AccountUnavailableError(
                "Account profile could not be updated.",
            ) from exc
        if stored is None:
            raise AccountNotFoundError("Account profile is unavailable.")
        return AccountProfileResponse(
            contract_version="account-profile-v2",
            timezone=stored.timezone,
            revision=stored.revision,
            updated_at=stored.updated_at,
            replayed=stored.replayed,
        )

    async def update_preparation_budget(
        self,
        *,
        user_id: str,
        request_id: UUID,
        expected_revision: int,
        minutes: int | None,
    ) -> AccountPreparationBudgetResponse:
        _validate_preparation_budget(minutes)
        now = self._now()
        fingerprint = _setting_fingerprint(
            {
                "contract_version": "account-preparation-budget-update-v2",
                "request_id": str(request_id),
                "expected_revision": expected_revision,
                "daily_preparation_budget_minutes": minutes,
            },
        )
        try:
            stored = await self._repository.update_preparation_budget(
                user_id=user_id,
                request_id=str(request_id),
                request_fingerprint=fingerprint,
                expected_revision=expected_revision,
                minutes=minutes,
                now=now,
            )
        except AccountPersistenceConflict as exc:
            raise AccountConflictError(str(exc)) from exc
        except AccountPersistenceBudgetOutcomeUnknown as exc:
            raise AccountOutcomeUnknownError(str(exc)) from exc
        except AccountPersistenceNotFound as exc:
            raise AccountNotFoundError(str(exc)) from exc
        except AccountPersistenceError as exc:
            raise AccountUnavailableError(
                "Preparation budget could not be updated.",
            ) from exc
        if stored is None:
            raise AccountNotFoundError("Account profile is unavailable.")
        return AccountPreparationBudgetResponse(
            contract_version="account-preparation-budget-v2",
            daily_preparation_budget_minutes=stored.minutes,
            revision=stored.revision,
            updated_at=stored.updated_at,
            replayed=stored.replayed,
        )

    async def export_account(self, *, user_id: str) -> PreparedAccountExport:
        _validate_export_configuration()
        exported_at = self._now()
        empty_data: dict[str, list[dict[str, object]]] = {
            name: [] for name in ACCOUNT_EXPORT_TABLE_NAMES
        }
        empty_response = AccountExportResponse(
            contract_version=ACCOUNT_EXPORT_CONTRACT_VERSION,
            exported_at=exported_at,
            data=empty_data,
            record_counts={name: 0 for name in ACCOUNT_EXPORT_TABLE_NAMES},
            ledger_policy=ACCOUNT_EXPORT_LEDGER_POLICY,
            limits=_export_limits(),
        )
        # Capture all table-local upper bounds before retaining any product
        # rows. Together with immutable keyset cursors this prevents offset
        # shifts and excludes normal inserts committed after each watermark.
        # This deliberately does not claim a cross-table transaction snapshot.
        try:
            collection = await self._owner_data_reader.collect(
                user_id=user_id,
                sources=ACCOUNT_EXPORT_TABLES,
                policy=OwnerDataReadPolicy(
                    page_size=ACCOUNT_EXPORT_PAGE_SIZE,
                    max_rows_per_source=ACCOUNT_EXPORT_MAX_ROWS_PER_TABLE,
                    max_total_rows=ACCOUNT_EXPORT_MAX_TOTAL_ROWS,
                    max_serialized_bytes=ACCOUNT_EXPORT_MAX_JSON_BYTES,
                    watermark_max_response_bytes=(ACCOUNT_EXPORT_WATERMARK_MAX_BYTES),
                ),
                initial_serialized_bytes=len(_compact_json_bytes(empty_response)),
                transform_row=lambda _source, row: row,
                serialized_row_growth=_account_export_row_growth,
                page_response_bytes=_account_export_page_response_bytes,
            )
        except AccountPersistenceSourceTooLarge as exc:
            raise AccountExportTooLargeError(
                "Account export exceeds the V2 JSON size bound.",
            ) from exc
        except AccountPersistenceError as exc:
            raise AccountUnavailableError(
                "Account export could not be generated.",
            ) from exc
        except OwnerDataInvalidPageError as exc:
            raise AccountUnavailableError(
                "Account export persistence returned an invalid page.",
            ) from exc
        except OwnerDataInvalidOwnerError as exc:
            raise AccountUnavailableError(
                "Account export persistence returned an invalid owner.",
            ) from exc
        except OwnerDataInvalidCursorError as exc:
            raise AccountUnavailableError(
                "Account export persistence returned an invalid cursor.",
            ) from exc
        except OwnerDataSourceRowsExceededError as exc:
            raise AccountExportTooLargeError(
                f"Account export table {exc.source_name} exceeds the V2 row bound.",
            ) from exc
        except OwnerDataTotalRowsExceededError as exc:
            raise AccountExportTooLargeError(
                "Account export exceeds the V2 total row bound.",
            ) from exc
        except OwnerDataSerializedBytesExceededError as exc:
            raise AccountExportTooLargeError(
                "Account export exceeds the V2 JSON size bound.",
            ) from exc

        data = collection.rows_by_source
        estimated_json_bytes = collection.serialized_bytes

        envelope = AccountExportResponse(
            contract_version=ACCOUNT_EXPORT_CONTRACT_VERSION,
            exported_at=exported_at,
            data=data,
            record_counts={name: len(rows) for name, rows in data.items()},
            ledger_policy=ACCOUNT_EXPORT_LEDGER_POLICY,
            limits=_export_limits(),
        )
        content = _compact_json_bytes(envelope)
        if (
            len(content) != estimated_json_bytes
            or len(content) > ACCOUNT_EXPORT_MAX_JSON_BYTES
        ):
            raise AccountExportTooLargeError(
                "Account export exceeds the V2 JSON size bound.",
            )
        return PreparedAccountExport(envelope=envelope, content=content)

    async def delete_account(
        self,
        *,
        user_id: str,
        confirmation: str,
    ) -> None:
        if confirmation != "DELETE":
            raise ValueError("Exact account deletion confirmation is required.")
        try:
            await self._repository.delete_account(
                user_id=user_id,
                confirmation=confirmation,
            )
        except AccountPersistenceNotFound as exc:
            raise AccountNotFoundError(str(exc)) from exc
        except AccountPersistenceDeletionOutcomeUnknown as exc:
            raise AccountOutcomeUnknownError(str(exc)) from exc
        except AccountPersistenceError as exc:
            raise AccountUnavailableError(
                "Account deletion could not be completed.",
            ) from exc


def _setting_fingerprint(payload: dict[str, object]) -> str:
    encoded = json.dumps(
        payload,
        ensure_ascii=False,
        sort_keys=True,
        separators=(",", ":"),
    ).encode("utf-8")
    return hashlib.sha256(encoded).hexdigest()


def _validate_timezone(value: str) -> None:
    if value in {"localtime", "posixrules"} or value.startswith(("posix/", "right/")):
        raise InvalidAccountTimezoneError("timezone must be a stable IANA name")
    try:
        zone = ZoneInfo(value)
    except (ZoneInfoNotFoundError, ValueError) as exc:
        raise InvalidAccountTimezoneError("timezone must be a valid IANA name") from exc
    if zone.key != value:
        raise InvalidAccountTimezoneError("timezone must be a valid IANA name")


def _validate_preparation_budget(value: int | None) -> None:
    if value is None:
        return
    if (
        type(value) is not int
        or value < DAILY_PREPARATION_BUDGET_MINUTES_MIN
        or value > DAILY_PREPARATION_BUDGET_MINUTES_MAX
        or value % 5 != 0
    ):
        raise InvalidPreparationBudgetError(
            "daily preparation budget must be 25 through 480 minutes "
            "in five-minute increments",
        )


def _validate_export_configuration() -> None:
    configured_tables = tuple(table.name for table in ACCOUNT_EXPORT_TABLES)
    if configured_tables != ACCOUNT_EXPORT_TABLE_NAMES:
        raise AccountUnavailableError(
            "Account export contract configuration is invalid.",
        )
    configured_sanitized = tuple(
        ACCOUNT_EXPORT_LEDGER_POLICY.sanitized_tables,
    )
    if (
        configured_sanitized != ACCOUNT_EXPORT_SANITIZED_TABLES
        or ACCOUNT_EXPORT_LEDGER_POLICY.omitted_tables != ACCOUNT_EXPORT_OMITTED_TABLES
    ):
        raise AccountUnavailableError(
            "Account export contract configuration is invalid.",
        )
    if (
        ACCOUNT_EXPORT_MAX_ROWS_PER_TABLE,
        ACCOUNT_EXPORT_MAX_TOTAL_ROWS,
        ACCOUNT_EXPORT_MAX_JSON_BYTES,
    ) != (10_000, 50_000, 8 * 1024 * 1024):
        raise AccountUnavailableError(
            "Account export contract configuration is invalid.",
        )


def _export_limits() -> AccountExportLimits:
    return AccountExportLimits(
        max_rows_per_table=ACCOUNT_EXPORT_MAX_ROWS_PER_TABLE,
        max_total_rows=ACCOUNT_EXPORT_MAX_TOTAL_ROWS,
        max_json_bytes=ACCOUNT_EXPORT_MAX_JSON_BYTES,
    )


def _account_export_row_growth(
    _source: object,
    current_source_rows: int,
    row: dict[str, object],
) -> int:
    row_bytes = len(_compact_json_bytes(row))
    separator_bytes = 1 if current_source_rows else 0
    old_count_digits = len(str(current_source_rows))
    new_count_digits = len(str(current_source_rows + 1))
    return row_bytes + separator_bytes + new_count_digits - old_count_digits


def _account_export_page_response_bytes(serialized_bytes: int) -> int:
    response_budget = ACCOUNT_EXPORT_MAX_JSON_BYTES - serialized_bytes
    return max(
        2,
        min(
            ACCOUNT_EXPORT_MAX_JSON_BYTES,
            response_budget + ACCOUNT_EXPORT_PAGE_BYTE_CUSHION,
        ),
    )


def _compact_json_bytes(value: AccountExportResponse | dict[str, object]) -> bytes:
    serializable = (
        value.model_dump(mode="python")
        if isinstance(value, AccountExportResponse)
        else value
    )
    try:
        return lossless_json_text(serializable).encode("utf-8")
    except (RecursionError, TypeError, ValueError) as exc:
        raise AccountUnavailableError(
            "Account export persistence returned invalid JSON data.",
        ) from exc
