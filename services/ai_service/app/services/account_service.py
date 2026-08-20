import hashlib
import json
from collections.abc import Awaitable, Callable
from dataclasses import dataclass
from datetime import UTC, datetime
from uuid import UUID
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from app.account_deletion_journal import (
    DeletionJournalEnvelope,
    DeletionJournalError,
    DeletionJournalWriter,
    InMemoryDeletionJournalWriter,
)
from app.core.lossless_json import lossless_json_text
from app.models.account import (
    ACCOUNT_EXPORT_CONTRACT_VERSION,
    ACCOUNT_EXPORT_MAX_JSON_BYTES,
    ACCOUNT_EXPORT_MAX_ROWS_PER_TABLE,
    ACCOUNT_EXPORT_MAX_TOTAL_ROWS,
    ACCOUNT_EXPORT_OMITTED_TABLES,
    ACCOUNT_EXPORT_SANITIZED_TABLES,
    ACCOUNT_EXPORT_TABLE_NAMES,
    ACCOUNT_DELETION_STATUS_CONTRACT_VERSION,
    AccountDeleteResponse,
    AccountDeletionStatusResponse,
    AccountExportLedgerPolicy,
    AccountExportLimits,
    AccountExportResponse,
    AccountPreparationBudgetResponse,
    AccountProfileResponse,
    DAILY_PREPARATION_BUDGET_MINUTES_MAX,
    DAILY_PREPARATION_BUDGET_MINUTES_MIN,
    PILOT_PARTICIPATION_CONTRACT_VERSION,
    PILOT_PARTICIPATION_NOTICE_VERSION,
    PilotParticipationResponse,
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
    AccountParticipationOutcomeUnknownError as AccountPersistenceParticipationOutcomeUnknown,
    AccountProfileUpdateOutcomeUnknownError as AccountPersistenceProfileOutcomeUnknown,
    AccountRepository,
    AccountSettingConflictError as AccountPersistenceConflict,
    StoredDeletionIntent,
    StoredDeletionRecoveryStatus,
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


async def _no_account_deletion_barrier(_user_id: str) -> None:
    return None


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


@dataclass(frozen=True)
class AccountDeletionReconcileResult:
    examined: int
    completed: int
    failures: int
    pending_count: int | None
    oldest_pending_at: datetime | None


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
        deletion_journal: DeletionJournalWriter | None = None,
        before_account_deletion: Callable[[str], Awaitable[None]] | None = None,
    ) -> None:
        self._repository = repository
        self._owner_data_reader = OwnerDataReader(repository=repository)
        self._now = now or (lambda: datetime.now(UTC))
        self._deletion_journal = deletion_journal or InMemoryDeletionJournalWriter(
            now=self._now,
        )
        self._before_account_deletion = (
            before_account_deletion or _no_account_deletion_barrier
        )

    async def accept_pilot_participation(
        self,
        *,
        user_id: str,
        notice_version: str,
    ) -> PilotParticipationResponse:
        if notice_version != PILOT_PARTICIPATION_NOTICE_VERSION:
            raise ValueError("Unsupported pilot participation notice.")
        try:
            stored = await self._repository.accept_pilot_participation(
                user_id=user_id,
                notice_version=notice_version,
            )
        except AccountPersistenceParticipationOutcomeUnknown as exc:
            raise AccountOutcomeUnknownError(str(exc)) from exc
        except AccountPersistenceNotFound as exc:
            raise AccountNotFoundError(str(exc)) from exc
        except AccountPersistenceError as exc:
            raise AccountUnavailableError(
                "Pilot participation acceptance could not be recorded.",
            ) from exc
        if stored is None:
            raise AccountNotFoundError("Account profile is unavailable.")
        return PilotParticipationResponse(
            contract_version=PILOT_PARTICIPATION_CONTRACT_VERSION,
            notice_version=stored.notice_version,
            accepted_at=stored.accepted_at,
            replayed=stored.replayed,
        )

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
                "Account export exceeds the V6 JSON size bound.",
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
                f"Account export table {exc.source_name} exceeds the V3 row bound.",
            ) from exc
        except OwnerDataTotalRowsExceededError as exc:
            raise AccountExportTooLargeError(
                "Account export exceeds the V6 total row bound.",
            ) from exc
        except OwnerDataSerializedBytesExceededError as exc:
            raise AccountExportTooLargeError(
                "Account export exceeds the V6 JSON size bound.",
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
                "Account export exceeds the V6 JSON size bound.",
            )
        return PreparedAccountExport(envelope=envelope, content=content)

    async def delete_account(
        self,
        *,
        user_id: str,
        deletion_id: UUID,
        confirmation: str,
    ) -> AccountDeleteResponse:
        if confirmation != "DELETE":
            raise ValueError("Exact account deletion confirmation is required.")
        try:
            await self._before_account_deletion(user_id)
        except Exception as exc:
            raise AccountUnavailableError(
                "Account deletion could not stop active processing.",
            ) from exc
        try:
            intent = await self._repository.prepare_account_deletion(
                user_id=user_id,
                deletion_id=str(deletion_id),
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
        if intent is None:
            raise AccountNotFoundError("Account is unavailable.")
        return await self._advance_account_deletion(
            intent=intent,
            confirmation=confirmation,
        )

    async def account_deletion_status(
        self,
        *,
        user_id: str,
    ) -> AccountDeletionStatusResponse:
        try:
            intent = await self._repository.get_account_deletion_intent(
                user_id=user_id,
            )
        except AccountPersistenceError as exc:
            raise AccountUnavailableError(
                "Account deletion status is unavailable.",
            ) from exc
        return AccountDeletionStatusResponse(
            contract_version=ACCOUNT_DELETION_STATUS_CONTRACT_VERSION,
            deletion=(
                _deletion_response(
                    intent,
                    journal_durable=intent.state in {"accepted", "completed"},
                )
                if intent is not None
                else None
            ),
        )

    async def reconcile_account_deletions(
        self,
        *,
        limit: int = 100,
    ) -> AccountDeletionReconcileResult:
        try:
            intents = await self._repository.list_pending_account_deletions(
                limit=limit,
            )
        except (AccountPersistenceDeletionOutcomeUnknown, AccountPersistenceError):
            return AccountDeletionReconcileResult(
                examined=0,
                completed=0,
                failures=1,
                pending_count=None,
                oldest_pending_at=None,
            )
        completed = 0
        failures = 0
        for intent in intents:
            try:
                response = await self._advance_account_deletion(
                    intent=intent,
                    confirmation="DELETE",
                )
            except (
                AccountNotFoundError,
                AccountOutcomeUnknownError,
                AccountUnavailableError,
            ):
                failures += 1
                continue
            if response.state == "completed":
                completed += 1
            elif not response.journal_durable:
                failures += 1
        try:
            status: StoredDeletionRecoveryStatus = (
                await self._repository.account_deletion_recovery_status()
            )
        except AccountPersistenceError:
            failures += 1
            return AccountDeletionReconcileResult(
                examined=len(intents),
                completed=completed,
                failures=failures,
                pending_count=None,
                oldest_pending_at=None,
            )
        return AccountDeletionReconcileResult(
            examined=len(intents),
            completed=completed,
            failures=failures,
            pending_count=status.pending_count,
            oldest_pending_at=status.oldest_pending_at,
        )

    async def _advance_account_deletion(
        self,
        *,
        intent: StoredDeletionIntent,
        confirmation: str,
    ) -> AccountDeleteResponse:
        journal_durable = intent.state in {"accepted", "completed"}
        if intent.state == "prepared":
            try:
                intent = await self._repository.mark_account_deletion_appending(
                    user_id=intent.user_id,
                    deletion_id=intent.deletion_id,
                )
            except (AccountPersistenceDeletionOutcomeUnknown, AccountPersistenceError):
                return _deletion_response(intent, journal_durable=False)
        if intent.state == "appending":
            try:
                receipt = await self._deletion_journal.append(
                    DeletionJournalEnvelope(
                        deletion_id=intent.deletion_id,
                        user_id=intent.user_id,
                        accepted_at=intent.accepted_at,
                    ),
                )
                journal_durable = True
                intent = await self._repository.accept_account_deletion_journal(
                    user_id=intent.user_id,
                    deletion_id=intent.deletion_id,
                    accepted_at=intent.accepted_at,
                    journal_object_key=receipt.object_key,
                    journal_payload_sha256=receipt.payload_sha256,
                    journaled_at=receipt.journaled_at,
                )
            except DeletionJournalError:
                return _deletion_response(intent, journal_durable=False)
            except (AccountPersistenceDeletionOutcomeUnknown, AccountPersistenceError):
                return _deletion_response(intent, journal_durable=True)
        if intent.state == "accepted":
            try:
                intent = await self._repository.complete_account_deletion(
                    user_id=intent.user_id,
                    deletion_id=intent.deletion_id,
                    confirmation=confirmation,
                    completed_at=self._now(),
                )
            except (AccountPersistenceDeletionOutcomeUnknown, AccountPersistenceError):
                return _deletion_response(intent, journal_durable=True)
        return _deletion_response(intent, journal_durable=journal_durable)


def _deletion_response(
    intent: StoredDeletionIntent,
    *,
    journal_durable: bool,
) -> AccountDeleteResponse:
    return AccountDeleteResponse(
        contract_version="account-deletion-v2",
        deletion_id=UUID(intent.deletion_id),
        state=("completed" if intent.state == "completed" else "deletion_pending"),
        accepted_at=intent.accepted_at,
        completed_at=intent.completed_at,
        journal_durable=journal_durable or intent.state == "completed",
    )


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
