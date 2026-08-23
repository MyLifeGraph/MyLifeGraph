from dataclasses import dataclass
from datetime import datetime
import re
from typing import Any, Protocol

import httpx

from app.clients.supabase import SupabaseResponseTooLargeError, SupabaseRestClient
from app.models.account import ACCOUNT_DELETION_STATUS_CONTRACT_VERSION
from app.owner_data_catalog import OwnerDataSource


AccountExportTable = OwnerDataSource


class AccountPersistenceError(RuntimeError):
    """A sanitized persistence failure at the account boundary."""


class AccountNotFoundError(RuntimeError):
    pass


class AccountDeletionOutcomeUnknownError(RuntimeError):
    pass


class AccountProfileUpdateOutcomeUnknownError(RuntimeError):
    pass


class AccountPreparationBudgetUpdateOutcomeUnknownError(RuntimeError):
    pass


class AccountParticipationOutcomeUnknownError(RuntimeError):
    pass


class AccountExportSourceTooLargeError(RuntimeError):
    pass


class AccountSettingConflictError(RuntimeError):
    pass


@dataclass(frozen=True)
class StoredPreparationBudget:
    minutes: int | None
    revision: int
    updated_at: datetime
    replayed: bool


@dataclass(frozen=True)
class StoredTimezone:
    timezone: str
    revision: int
    updated_at: datetime
    replayed: bool


@dataclass(frozen=True)
class StoredPilotParticipation:
    notice_version: str
    accepted_at: datetime
    replayed: bool


@dataclass(frozen=True)
class StoredDeletionIntent:
    deletion_id: str
    user_id: str
    state: str
    accepted_at: datetime
    journal_object_key: str | None
    journal_payload_sha256: str | None
    completed_at: datetime | None
    replayed: bool


@dataclass(frozen=True)
class StoredDeletionRecoveryStatus:
    pending_count: int
    oldest_pending_at: datetime | None


class AccountRepository(Protocol):
    async def accept_pilot_participation(
        self,
        *,
        user_id: str,
        notice_version: str,
    ) -> StoredPilotParticipation | None:
        pass

    async def update_timezone(
        self,
        *,
        user_id: str,
        request_id: str,
        request_fingerprint: str,
        expected_revision: int,
        timezone: str,
        now: datetime,
    ) -> StoredTimezone | None:
        pass

    async def update_preparation_budget(
        self,
        *,
        user_id: str,
        request_id: str,
        request_fingerprint: str,
        expected_revision: int,
        minutes: int | None,
        now: datetime,
    ) -> StoredPreparationBudget | None:
        pass

    async def list_export_rows(
        self,
        *,
        user_id: str,
        table: AccountExportTable,
        after_cursor: str | None,
        not_after: str,
        limit: int,
        max_response_bytes: int,
    ) -> list[dict[str, Any]]:
        pass

    async def get_export_watermark(
        self,
        *,
        user_id: str,
        table: AccountExportTable,
        max_response_bytes: int,
    ) -> str | None:
        pass

    async def delete_account(
        self,
        *,
        user_id: str,
        confirmation: str,
    ) -> None:
        pass

    async def prepare_account_deletion(
        self,
        *,
        user_id: str,
        deletion_id: str,
        confirmation: str,
    ) -> StoredDeletionIntent | None: ...

    async def accept_account_deletion_journal(
        self,
        *,
        user_id: str,
        deletion_id: str,
        accepted_at: datetime,
        journal_object_key: str,
        journal_payload_sha256: str,
        journaled_at: datetime,
    ) -> StoredDeletionIntent: ...

    async def mark_account_deletion_appending(
        self,
        *,
        user_id: str,
        deletion_id: str,
    ) -> StoredDeletionIntent: ...

    async def complete_account_deletion(
        self,
        *,
        user_id: str,
        deletion_id: str,
        confirmation: str,
        completed_at: datetime,
    ) -> StoredDeletionIntent: ...

    async def list_pending_account_deletions(
        self,
        *,
        limit: int,
    ) -> list[StoredDeletionIntent]: ...

    async def account_deletion_pending(self, *, user_id: str) -> bool: ...

    async def get_account_deletion_intent(
        self,
        *,
        user_id: str,
    ) -> StoredDeletionIntent | None: ...

    async def account_deletion_recovery_status(
        self,
    ) -> StoredDeletionRecoveryStatus: ...


class SupabaseAccountRepository:
    """Privileged account operations after bearer-token verification.

    Account deletion deliberately calls one database RPC. The RPC owns the
    transaction that removes restrict-linked focus history before deleting the
    Supabase Auth user and allowing the profile/product cascade to complete.
    """

    def __init__(self, client: SupabaseRestClient) -> None:
        self._client = client

    async def accept_pilot_participation(
        self,
        *,
        user_id: str,
        notice_version: str,
    ) -> StoredPilotParticipation | None:
        params = {
            "p_user_id": user_id,
            "p_notice_version": notice_version,
        }
        try:
            result = await self._client.rpc(
                "accept_pilot_participation_v1",
                params=params,
            )
        except httpx.HTTPStatusError as exc:
            if _response_error_code(exc.response) == "PT404":
                return None
            if exc.response.status_code < 500:
                raise AccountPersistenceError(
                    "Pilot participation persistence is unavailable.",
                ) from exc
            result = await self._replay_pilot_participation(params=params)
        except (httpx.HTTPError, ValueError):
            result = await self._replay_pilot_participation(params=params)
        return _stored_pilot_participation(
            result,
            expected_notice_version=notice_version,
        )

    async def _replay_pilot_participation(
        self,
        *,
        params: dict[str, Any],
    ) -> Any:
        try:
            return await self._client.rpc(
                "accept_pilot_participation_v1",
                params=params,
            )
        except (httpx.HTTPError, ValueError) as exc:
            raise AccountParticipationOutcomeUnknownError(
                "Pilot participation outcome could not be determined.",
            ) from exc

    async def update_timezone(
        self,
        *,
        user_id: str,
        request_id: str,
        request_fingerprint: str,
        expected_revision: int,
        timezone: str,
        now: datetime,
    ) -> StoredTimezone | None:
        params = {
            "p_user_id": user_id,
            "p_request_id": request_id,
            "p_request_fingerprint": request_fingerprint,
            "p_expected_revision": expected_revision,
            "p_timezone": timezone,
            "p_now": now.isoformat(),
        }
        try:
            result = await self._client.rpc(
                "apply_account_timezone_v2",
                params=params,
            )
        except httpx.HTTPStatusError as exc:
            code = _response_error_code(exc.response)
            if code == "PT404":
                return None
            if code == "PT409":
                raise AccountSettingConflictError(
                    "Account timezone changed. Reload before saving.",
                ) from exc
            if exc.response.status_code >= 500:
                result = await self._replay_account_setting(
                    function="apply_account_timezone_v2",
                    params=params,
                    outcome_error=AccountProfileUpdateOutcomeUnknownError,
                )
            else:
                raise AccountPersistenceError(
                    "Account profile persistence is unavailable.",
                ) from exc
        except (httpx.HTTPError, ValueError):
            result = await self._replay_account_setting(
                function="apply_account_timezone_v2",
                params=params,
                outcome_error=AccountProfileUpdateOutcomeUnknownError,
            )
        return _stored_timezone(result, expected_timezone=timezone)

    async def update_preparation_budget(
        self,
        *,
        user_id: str,
        request_id: str,
        request_fingerprint: str,
        expected_revision: int,
        minutes: int | None,
        now: datetime,
    ) -> StoredPreparationBudget | None:
        params = {
            "p_user_id": user_id,
            "p_request_id": request_id,
            "p_request_fingerprint": request_fingerprint,
            "p_expected_revision": expected_revision,
            "p_daily_preparation_budget_minutes": minutes,
            "p_now": now.isoformat(),
        }
        try:
            result = await self._client.rpc(
                "apply_account_preparation_budget_v2",
                params=params,
            )
        except httpx.HTTPStatusError as exc:
            code = _response_error_code(exc.response)
            if code == "PT404":
                return None
            if code == "PT409":
                raise AccountSettingConflictError(
                    "Preparation budget changed. Reload before saving.",
                ) from exc
            if exc.response.status_code >= 500:
                result = await self._replay_account_setting(
                    function="apply_account_preparation_budget_v2",
                    params=params,
                    outcome_error=(AccountPreparationBudgetUpdateOutcomeUnknownError),
                )
            else:
                raise AccountPersistenceError(
                    "Preparation budget persistence is unavailable.",
                ) from exc
        except (httpx.HTTPError, ValueError):
            result = await self._replay_account_setting(
                function="apply_account_preparation_budget_v2",
                params=params,
                outcome_error=AccountPreparationBudgetUpdateOutcomeUnknownError,
            )
        return _stored_preparation_budget(result, expected_minutes=minutes)

    async def _replay_account_setting(
        self,
        *,
        function: str,
        params: dict[str, Any],
        outcome_error: type[RuntimeError],
    ) -> Any:
        try:
            return await self._client.rpc(function, params=params)
        except httpx.HTTPStatusError as exc:
            code = _response_error_code(exc.response)
            if code == "PT409":
                raise AccountSettingConflictError(
                    "Account setting request conflicts with an earlier write.",
                ) from exc
            raise outcome_error(
                "Account setting update outcome could not be determined.",
            ) from exc
        except (httpx.HTTPError, ValueError) as exc:
            raise outcome_error(
                "Account setting update outcome could not be determined.",
            ) from exc

    async def list_export_rows(
        self,
        *,
        user_id: str,
        table: AccountExportTable,
        after_cursor: str | None,
        not_after: str,
        limit: int,
        max_response_bytes: int,
    ) -> list[dict[str, Any]]:
        params = {
            "select": table.select,
            table.owner_column: f"eq.{user_id}",
            "order": f"{table.cursor_column}.asc",
            table.watermark_column: f"lte.{not_after}",
            "limit": str(limit),
        }
        if after_cursor is not None:
            params[table.cursor_column] = f"gt.{after_cursor}"
        try:
            return await self._client.select(
                table.name,
                params=params,
                max_response_bytes=max_response_bytes,
            )
        except SupabaseResponseTooLargeError as exc:
            raise AccountExportSourceTooLargeError(
                "Account export source page exceeds the V2 byte bound.",
            ) from exc
        except (httpx.HTTPError, ValueError) as exc:
            raise AccountPersistenceError(
                "Account export persistence is unavailable.",
            ) from exc

    async def get_export_watermark(
        self,
        *,
        user_id: str,
        table: AccountExportTable,
        max_response_bytes: int,
    ) -> str | None:
        select_columns = ",".join(
            dict.fromkeys((table.owner_column, table.watermark_column)),
        )
        try:
            rows = await self._client.select(
                table.name,
                params={
                    "select": select_columns,
                    table.owner_column: f"eq.{user_id}",
                    "order": f"{table.watermark_column}.desc",
                    "limit": "1",
                },
                max_response_bytes=max_response_bytes,
            )
        except (SupabaseResponseTooLargeError, httpx.HTTPError, ValueError) as exc:
            raise AccountPersistenceError(
                "Account export persistence is unavailable.",
            ) from exc
        if not isinstance(rows, list) or len(rows) > 1:
            raise AccountPersistenceError(
                "Account export persistence returned an invalid watermark.",
            )
        if not rows:
            return None
        row = rows[0]
        if (
            not isinstance(row, dict)
            or not isinstance(row.get(table.owner_column), str)
            or row[table.owner_column] != user_id
            or not isinstance(row.get(table.watermark_column), str)
            or not row[table.watermark_column]
        ):
            raise AccountPersistenceError(
                "Account export persistence returned an invalid watermark.",
            )
        return row[table.watermark_column]

    async def delete_account(
        self,
        *,
        user_id: str,
        confirmation: str,
    ) -> None:
        try:
            result = await self._client.rpc(
                "delete_account_v1",
                params={
                    "p_user_id": user_id,
                    "p_confirmation": confirmation,
                },
            )
        except httpx.HTTPStatusError as exc:
            if exc.response.status_code < 500:
                raise AccountPersistenceError(
                    "Account deletion could not be completed.",
                ) from exc
            await self._replay_ambiguous_delete(
                user_id=user_id,
                confirmation=confirmation,
                ambiguous_error=exc,
            )
            return
        except (httpx.TransportError, ValueError) as exc:
            await self._replay_ambiguous_delete(
                user_id=user_id,
                confirmation=confirmation,
                ambiguous_error=exc,
            )
            return
        except httpx.HTTPError as exc:
            await self._replay_ambiguous_delete(
                user_id=user_id,
                confirmation=confirmation,
                ambiguous_error=exc,
            )
            return

        if not _is_exact_delete_result(result=result, user_id=user_id):
            await self._replay_ambiguous_delete(
                user_id=user_id,
                confirmation=confirmation,
                ambiguous_error=ValueError(
                    "Account deletion returned an invalid result.",
                ),
            )
            return

    async def _replay_ambiguous_delete(
        self,
        *,
        user_id: str,
        confirmation: str,
        ambiguous_error: Exception,
    ) -> None:
        # A plain profile SELECT cannot prove non-commit after a timeout: MVCC
        # can expose the previous committed row while the first RPC is still
        # running. The RPC is deliberately retry-safe, and its locks serialize
        # this replay behind the first transaction. A committed first attempt
        # therefore converges to the exact `not_found` result.
        try:
            replay = await self._client.rpc(
                "delete_account_v1",
                params={
                    "p_user_id": user_id,
                    "p_confirmation": confirmation,
                },
            )
        except (httpx.HTTPError, ValueError) as exc:
            raise AccountDeletionOutcomeUnknownError(
                "Account deletion outcome could not be determined.",
            ) from exc
        if _is_exact_delete_result(result=replay, user_id=user_id):
            return
        raise AccountDeletionOutcomeUnknownError(
            "Account deletion outcome could not be determined.",
        ) from ambiguous_error

    async def prepare_account_deletion(
        self,
        *,
        user_id: str,
        deletion_id: str,
        confirmation: str,
    ) -> StoredDeletionIntent | None:
        params = {
            "p_user_id": user_id,
            "p_deletion_id": deletion_id,
            "p_confirmation": confirmation,
        }
        try:
            result = await self._deletion_recovery_rpc(
                "prepare_account_deletion_v2",
                params=params,
            )
        except httpx.HTTPStatusError as exc:
            if _response_error_code(exc.response) == "PT404":
                return None
            raise AccountPersistenceError(
                "Account deletion preparation is unavailable.",
            ) from exc
        return _stored_deletion_intent(
            result,
            expected_user_id=user_id,
            expected_deletion_id=deletion_id,
        )

    async def accept_account_deletion_journal(
        self,
        *,
        user_id: str,
        deletion_id: str,
        accepted_at: datetime,
        journal_object_key: str,
        journal_payload_sha256: str,
        journaled_at: datetime,
    ) -> StoredDeletionIntent:
        result = await self._deletion_recovery_rpc(
            "accept_account_deletion_journal_v2",
            params={
                "p_user_id": user_id,
                "p_deletion_id": deletion_id,
                "p_accepted_at": accepted_at.isoformat(),
                "p_journal_object_key": journal_object_key,
                "p_journal_payload_sha256": journal_payload_sha256,
                "p_journaled_at": journaled_at.isoformat(),
            },
        )
        return _stored_deletion_intent(
            result,
            expected_user_id=user_id,
            expected_deletion_id=deletion_id,
        )

    async def mark_account_deletion_appending(
        self,
        *,
        user_id: str,
        deletion_id: str,
    ) -> StoredDeletionIntent:
        result = await self._deletion_recovery_rpc(
            "mark_account_deletion_appending_v2",
            params={
                "p_user_id": user_id,
                "p_deletion_id": deletion_id,
            },
        )
        return _stored_deletion_intent(
            result,
            expected_user_id=user_id,
            expected_deletion_id=deletion_id,
        )

    async def complete_account_deletion(
        self,
        *,
        user_id: str,
        deletion_id: str,
        confirmation: str,
        completed_at: datetime,
    ) -> StoredDeletionIntent:
        result = await self._deletion_recovery_rpc(
            "complete_account_deletion_v2",
            params={
                "p_user_id": user_id,
                "p_deletion_id": deletion_id,
                "p_confirmation": confirmation,
                "p_completed_at": completed_at.isoformat(),
            },
        )
        return _stored_deletion_intent(
            result,
            expected_user_id=user_id,
            expected_deletion_id=deletion_id,
        )

    async def list_pending_account_deletions(
        self,
        *,
        limit: int,
    ) -> list[StoredDeletionIntent]:
        try:
            result = await self._client.rpc(
                "list_pending_account_deletions_v2",
                params={"p_limit": limit},
            )
        except (httpx.HTTPError, ValueError) as exc:
            raise AccountPersistenceError(
                "Pending account deletions are unavailable.",
            ) from exc
        if (
            not isinstance(result, dict)
            or set(result) != {"contract_version", "intents"}
            or result.get("contract_version") != "account-deletion-reconcile-v2"
            or not isinstance(result.get("intents"), list)
            or len(result["intents"]) > limit
        ):
            raise AccountPersistenceError(
                "Pending account deletions returned an invalid result.",
            )
        return [
            _stored_deletion_intent(item)
            for item in result["intents"]
        ]

    async def account_deletion_pending(self, *, user_id: str) -> bool:
        try:
            result = await self._client.rpc(
                "get_account_deletion_pending_v2",
                params={"p_user_id": user_id},
            )
        except (httpx.HTTPError, ValueError) as exc:
            raise AccountPersistenceError(
                "Account deletion state is unavailable.",
            ) from exc
        if (
            not isinstance(result, dict)
            or set(result) != {"contract_version", "pending"}
            or result.get("contract_version") != "account-deletion-pending-v2"
            or type(result.get("pending")) is not bool
        ):
            raise AccountPersistenceError(
                "Account deletion state returned an invalid result.",
            )
        return result["pending"]

    async def get_account_deletion_intent(
        self,
        *,
        user_id: str,
    ) -> StoredDeletionIntent | None:
        try:
            result = await self._client.rpc(
                "get_account_deletion_intent_v2",
                params={"p_user_id": user_id},
            )
        except (httpx.HTTPError, ValueError) as exc:
            raise AccountPersistenceError(
                "Account deletion status is unavailable.",
            ) from exc
        if (
            not isinstance(result, dict)
            or set(result) != {"contract_version", "intent"}
            or result.get("contract_version")
            != ACCOUNT_DELETION_STATUS_CONTRACT_VERSION
        ):
            raise AccountPersistenceError(
                "Account deletion status returned an invalid result.",
            )
        intent = result["intent"]
        if intent is None:
            return None
        return _stored_deletion_intent(intent, expected_user_id=user_id)

    async def account_deletion_recovery_status(
        self,
    ) -> StoredDeletionRecoveryStatus:
        try:
            result = await self._client.account_deletion_recovery_status()
            oldest_value = result["oldest_pending_at"]
            oldest = (
                datetime.fromisoformat(oldest_value.replace("Z", "+00:00"))
                if isinstance(oldest_value, str)
                else None
            )
        except (httpx.HTTPError, ValueError, KeyError) as exc:
            raise AccountPersistenceError(
                "Account deletion recovery status is unavailable.",
            ) from exc
        if oldest is not None and oldest.tzinfo is None:
            raise AccountPersistenceError(
                "Account deletion recovery status returned an invalid time.",
            )
        return StoredDeletionRecoveryStatus(
            pending_count=result["pending_count"],
            oldest_pending_at=oldest,
        )

    async def _deletion_recovery_rpc(
        self,
        function: str,
        *,
        params: dict[str, Any],
    ) -> Any:
        try:
            return await self._client.rpc(function, params=params)
        except httpx.HTTPStatusError as exc:
            if exc.response.status_code < 500:
                raise
        except (httpx.HTTPError, ValueError):
            pass
        try:
            return await self._client.rpc(function, params=params)
        except (httpx.HTTPError, ValueError) as exc:
            raise AccountDeletionOutcomeUnknownError(
                "Account deletion recovery outcome could not be determined.",
            ) from exc


def _is_exact_delete_result(*, result: object, user_id: str) -> bool:
    if not isinstance(result, dict) or set(result) != {
        "deleted",
        "not_found",
        "user_id",
    }:
        return False
    if not isinstance(result["user_id"], str) or result["user_id"] != user_id:
        return False
    return (result["deleted"] is True and result["not_found"] is False) or (
        result["deleted"] is False and result["not_found"] is True
    )


def _stored_deletion_intent(
    result: object,
    *,
    expected_user_id: str | None = None,
    expected_deletion_id: str | None = None,
) -> StoredDeletionIntent:
    expected_keys = {
        "contract_version",
        "deletion_id",
        "user_id",
        "state",
        "accepted_at",
        "journal_object_key",
        "journal_payload_sha256",
        "completed_at",
        "replayed",
    }
    if (
        not isinstance(result, dict)
        or set(result) != expected_keys
        or result.get("contract_version") != "account-deletion-v2"
        or result.get("state") not in {
            "prepared",
            "appending",
            "accepted",
            "completed",
        }
        or not isinstance(result.get("deletion_id"), str)
        or not isinstance(result.get("user_id"), str)
        or not isinstance(result.get("accepted_at"), str)
        or type(result.get("replayed")) is not bool
        or (
            expected_user_id is not None
            and result.get("user_id") != expected_user_id
        )
        or (
            expected_deletion_id is not None
            and result.get("deletion_id") != expected_deletion_id
        )
    ):
        raise AccountDeletionOutcomeUnknownError(
            "Account deletion recovery returned an invalid result.",
        )
    try:
        accepted_at = datetime.fromisoformat(
            result["accepted_at"].replace("Z", "+00:00"),
        )
        completed_at = (
            datetime.fromisoformat(result["completed_at"].replace("Z", "+00:00"))
            if isinstance(result["completed_at"], str)
            else None
        )
    except ValueError as exc:
        raise AccountDeletionOutcomeUnknownError(
            "Account deletion recovery returned an invalid time.",
        ) from exc
    state = result["state"]
    journal_object_key = result["journal_object_key"]
    journal_payload_sha256 = result["journal_payload_sha256"]
    if (
        accepted_at.tzinfo is None
        or (completed_at is not None and completed_at.tzinfo is None)
        or (
            state in {"prepared", "appending"}
            and (
                journal_object_key is not None
                or journal_payload_sha256 is not None
                or completed_at is not None
            )
        )
        or (
            state in {"accepted", "completed"}
            and (
                not isinstance(journal_object_key, str)
                or not isinstance(journal_payload_sha256, str)
                or re.fullmatch(r"[0-9a-f]{64}", journal_payload_sha256) is None
            )
        )
        or (state == "accepted" and completed_at is not None)
        or (state == "completed" and completed_at is None)
    ):
        raise AccountDeletionOutcomeUnknownError(
            "Account deletion recovery returned an invalid state.",
        )
    return StoredDeletionIntent(
        deletion_id=result["deletion_id"],
        user_id=result["user_id"],
        state=state,
        accepted_at=accepted_at,
        journal_object_key=journal_object_key,
        journal_payload_sha256=journal_payload_sha256,
        completed_at=completed_at,
        replayed=result["replayed"],
    )


def _stored_timezone(
    result: object,
    *,
    expected_timezone: str,
) -> StoredTimezone:
    expected_keys = {
        "contract_version",
        "timezone",
        "revision",
        "updated_at",
        "replayed",
    }
    if (
        not isinstance(result, dict)
        or set(result) != expected_keys
        or result.get("contract_version") != "account-profile-v2"
        or result.get("timezone") != expected_timezone
        or type(result.get("revision")) is not int
        or result["revision"] < 2
        or type(result.get("replayed")) is not bool
        or not isinstance(result.get("updated_at"), str)
    ):
        raise AccountProfileUpdateOutcomeUnknownError(
            "Account profile update outcome could not be determined.",
        )
    try:
        updated_at = datetime.fromisoformat(result["updated_at"].replace("Z", "+00:00"))
    except ValueError as exc:
        raise AccountProfileUpdateOutcomeUnknownError(
            "Account profile update outcome could not be determined.",
        ) from exc
    if updated_at.tzinfo is None:
        raise AccountProfileUpdateOutcomeUnknownError(
            "Account profile update outcome could not be determined.",
        )
    return StoredTimezone(
        timezone=expected_timezone,
        revision=result["revision"],
        updated_at=updated_at,
        replayed=result["replayed"],
    )


def _stored_pilot_participation(
    result: object,
    *,
    expected_notice_version: str,
) -> StoredPilotParticipation:
    expected_keys = {
        "contract_version",
        "notice_version",
        "accepted_at",
        "replayed",
    }
    if (
        not isinstance(result, dict)
        or set(result) != expected_keys
        or result.get("contract_version") != "pilot-participation-v1"
        or result.get("notice_version") != expected_notice_version
        or not isinstance(result.get("accepted_at"), str)
        or type(result.get("replayed")) is not bool
    ):
        raise AccountParticipationOutcomeUnknownError(
            "Pilot participation outcome could not be determined.",
        )
    try:
        accepted_at = datetime.fromisoformat(
            result["accepted_at"].replace("Z", "+00:00"),
        )
    except ValueError as exc:
        raise AccountParticipationOutcomeUnknownError(
            "Pilot participation outcome could not be determined.",
        ) from exc
    if accepted_at.tzinfo is None:
        raise AccountParticipationOutcomeUnknownError(
            "Pilot participation outcome could not be determined.",
        )
    return StoredPilotParticipation(
        notice_version=expected_notice_version,
        accepted_at=accepted_at,
        replayed=result["replayed"],
    )


def _stored_preparation_budget(
    result: object,
    *,
    expected_minutes: int | None,
) -> StoredPreparationBudget:
    expected_keys = {
        "contract_version",
        "daily_preparation_budget_minutes",
        "revision",
        "updated_at",
        "replayed",
    }
    if (
        not isinstance(result, dict)
        or set(result) != expected_keys
        or result.get("contract_version") != "account-preparation-budget-v2"
        or result.get("daily_preparation_budget_minutes") != expected_minutes
        or type(result.get("revision")) is not int
        or result["revision"] < 2
        or type(result.get("replayed")) is not bool
        or not isinstance(result.get("updated_at"), str)
    ):
        raise AccountPreparationBudgetUpdateOutcomeUnknownError(
            "Preparation budget update outcome could not be determined.",
        )
    try:
        updated_at = datetime.fromisoformat(result["updated_at"].replace("Z", "+00:00"))
    except ValueError as exc:
        raise AccountPreparationBudgetUpdateOutcomeUnknownError(
            "Preparation budget update outcome could not be determined.",
        ) from exc
    if updated_at.tzinfo is None:
        raise AccountPreparationBudgetUpdateOutcomeUnknownError(
            "Preparation budget update outcome could not be determined.",
        )
    return StoredPreparationBudget(
        minutes=expected_minutes,
        revision=result["revision"],
        updated_at=updated_at,
        replayed=result["replayed"],
    )


def _response_error_code(response: httpx.Response) -> str | None:
    try:
        payload = response.json()
    except ValueError:
        return None
    if not isinstance(payload, dict):
        return None
    code = payload.get("code")
    return code if isinstance(code, str) else None
