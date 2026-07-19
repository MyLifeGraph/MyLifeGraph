from dataclasses import dataclass
from typing import Any, Protocol

import httpx

from app.clients.supabase import SupabaseResponseTooLargeError, SupabaseRestClient


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


class AccountExportSourceTooLargeError(RuntimeError):
    pass


@dataclass(frozen=True)
class AccountExportTable:
    name: str
    owner_column: str
    select: str
    cursor_column: str
    watermark_column: str


@dataclass(frozen=True)
class StoredPreparationBudget:
    minutes: int | None


class AccountRepository(Protocol):
    async def update_timezone(
        self,
        *,
        user_id: str,
        timezone: str,
    ) -> str | None:
        pass

    async def update_preparation_budget(
        self,
        *,
        user_id: str,
        minutes: int | None,
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


class SupabaseAccountRepository:
    """Privileged account operations after bearer-token verification.

    Account deletion deliberately calls one database RPC. The RPC owns the
    transaction that removes restrict-linked focus history before deleting the
    Supabase Auth user and allowing the profile/product cascade to complete.
    """

    def __init__(self, client: SupabaseRestClient) -> None:
        self._client = client

    async def update_timezone(
        self,
        *,
        user_id: str,
        timezone: str,
    ) -> str | None:
        try:
            rows = await self._client.update(
                "profiles",
                values={"timezone": timezone},
                params={
                    "id": f"eq.{user_id}",
                    "select": "timezone",
                },
            )
        except httpx.HTTPStatusError as exc:
            if exc.response.status_code >= 500:
                return await self._reconcile_ambiguous_timezone_update(
                    user_id=user_id,
                    timezone=timezone,
                    ambiguous_error=exc,
                )
            raise AccountPersistenceError(
                "Account profile persistence is unavailable.",
            ) from exc
        except (httpx.TransportError, ValueError) as exc:
            return await self._reconcile_ambiguous_timezone_update(
                user_id=user_id,
                timezone=timezone,
                ambiguous_error=exc,
            )
        except httpx.HTTPError as exc:
            return await self._reconcile_ambiguous_timezone_update(
                user_id=user_id,
                timezone=timezone,
                ambiguous_error=exc,
            )
        if rows == []:
            return None
        if not _is_exact_timezone_result(rows=rows, timezone=timezone):
            return await self._reconcile_ambiguous_timezone_update(
                user_id=user_id,
                timezone=timezone,
                ambiguous_error=ValueError(
                    "Account profile persistence returned an invalid result.",
                ),
            )
        return timezone

    async def update_preparation_budget(
        self,
        *,
        user_id: str,
        minutes: int | None,
    ) -> StoredPreparationBudget | None:
        try:
            result = await self._client.rpc(
                "set_daily_preparation_budget_v1",
                params={
                    "p_user_id": user_id,
                    "p_daily_preparation_budget_minutes": minutes,
                },
            )
        except httpx.HTTPStatusError as exc:
            if _response_error_code(exc.response) == "PT404":
                return None
            if exc.response.status_code < 500:
                raise AccountPersistenceError(
                    "Preparation budget persistence is unavailable.",
                ) from exc
            return await self._reconcile_ambiguous_preparation_budget_update(
                user_id=user_id,
                minutes=minutes,
                ambiguous_error=exc,
            )
        except (httpx.HTTPError, ValueError) as exc:
            return await self._reconcile_ambiguous_preparation_budget_update(
                user_id=user_id,
                minutes=minutes,
                ambiguous_error=exc,
            )
        if not _is_exact_preparation_budget_result(result=result, minutes=minutes):
            return await self._reconcile_ambiguous_preparation_budget_update(
                user_id=user_id,
                minutes=minutes,
                ambiguous_error=ValueError(
                    "Preparation budget persistence returned an invalid result.",
                ),
            )
        return StoredPreparationBudget(minutes=minutes)

    async def _reconcile_ambiguous_preparation_budget_update(
        self,
        *,
        user_id: str,
        minutes: int | None,
        ambiguous_error: Exception,
    ) -> StoredPreparationBudget | None:
        # The RPC takes the same owner lock as plan confirmation and setting the
        # same nullable value is idempotent. Replaying serializes behind a first
        # request that may still be committing.
        try:
            result = await self._client.rpc(
                "set_daily_preparation_budget_v1",
                params={
                    "p_user_id": user_id,
                    "p_daily_preparation_budget_minutes": minutes,
                },
            )
        except httpx.HTTPStatusError as exc:
            if _response_error_code(exc.response) == "PT404":
                return None
            if exc.response.status_code < 500:
                raise AccountPersistenceError(
                    "Preparation budget persistence is unavailable.",
                ) from exc
            return await self._read_ambiguous_preparation_budget_result(
                user_id=user_id,
                minutes=minutes,
                ambiguous_error=ambiguous_error,
            )
        except (httpx.HTTPError, ValueError):
            return await self._read_ambiguous_preparation_budget_result(
                user_id=user_id,
                minutes=minutes,
                ambiguous_error=ambiguous_error,
            )
        if _is_exact_preparation_budget_result(result=result, minutes=minutes):
            return StoredPreparationBudget(minutes=minutes)
        return await self._read_ambiguous_preparation_budget_result(
            user_id=user_id,
            minutes=minutes,
            ambiguous_error=ambiguous_error,
        )

    async def _read_ambiguous_preparation_budget_result(
        self,
        *,
        user_id: str,
        minutes: int | None,
        ambiguous_error: Exception,
    ) -> StoredPreparationBudget | None:
        try:
            rows = await self._client.select(
                "profiles",
                params={
                    "select": "daily_preparation_budget_minutes",
                    "id": f"eq.{user_id}",
                    "limit": "1",
                },
            )
        except (httpx.HTTPError, ValueError) as exc:
            raise AccountPreparationBudgetUpdateOutcomeUnknownError(
                "Preparation budget update outcome could not be determined.",
            ) from exc
        if rows == []:
            return None
        if _is_exact_preparation_budget_rows(rows=rows, minutes=minutes):
            return StoredPreparationBudget(minutes=minutes)
        raise AccountPreparationBudgetUpdateOutcomeUnknownError(
            "Preparation budget update outcome could not be determined.",
        ) from ambiguous_error

    async def _reconcile_ambiguous_timezone_update(
        self,
        *,
        user_id: str,
        timezone: str,
        ambiguous_error: Exception,
    ) -> str | None:
        # Replaying this exact PATCH is safe: setting a timezone is idempotent.
        # It also avoids treating an MVCC read of the pre-commit row as proof
        # that a timed-out first PATCH will not commit moments later.
        try:
            rows = await self._client.update(
                "profiles",
                values={"timezone": timezone},
                params={
                    "id": f"eq.{user_id}",
                    "select": "timezone",
                },
            )
        except (httpx.HTTPError, ValueError):
            return await self._read_ambiguous_timezone_result(
                user_id=user_id,
                timezone=timezone,
                ambiguous_error=ambiguous_error,
            )
        if rows == []:
            return None
        if _is_exact_timezone_result(rows=rows, timezone=timezone):
            return timezone
        return await self._read_ambiguous_timezone_result(
            user_id=user_id,
            timezone=timezone,
            ambiguous_error=ambiguous_error,
        )

    async def _read_ambiguous_timezone_result(
        self,
        *,
        user_id: str,
        timezone: str,
        ambiguous_error: Exception,
    ) -> str | None:
        try:
            profile_rows = await self._client.select(
                "profiles",
                params={
                    "select": "timezone",
                    "id": f"eq.{user_id}",
                    "limit": "1",
                },
            )
        except (httpx.HTTPError, ValueError) as exc:
            raise AccountProfileUpdateOutcomeUnknownError(
                "Account profile update outcome could not be determined.",
            ) from exc
        if not isinstance(profile_rows, list):
            raise AccountProfileUpdateOutcomeUnknownError(
                "Account profile update outcome could not be determined.",
            ) from ambiguous_error
        if profile_rows == []:
            return None
        if _is_exact_timezone_result(rows=profile_rows, timezone=timezone):
            return timezone
        raise AccountProfileUpdateOutcomeUnknownError(
            "Account profile update outcome could not be determined.",
        ) from ambiguous_error

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
                "Account export source page exceeds the V1 byte bound.",
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


def _is_exact_delete_result(*, result: object, user_id: str) -> bool:
    if not isinstance(result, dict) or set(result) != {
        "deleted",
        "not_found",
        "user_id",
    }:
        return False
    if not isinstance(result["user_id"], str) or result["user_id"] != user_id:
        return False
    return (
        result["deleted"] is True and result["not_found"] is False
    ) or (
        result["deleted"] is False and result["not_found"] is True
    )


def _is_exact_timezone_result(*, rows: object, timezone: str) -> bool:
    return (
        isinstance(rows, list)
        and len(rows) == 1
        and isinstance(rows[0], dict)
        and set(rows[0]) == {"timezone"}
        and rows[0]["timezone"] == timezone
    )


def _is_exact_preparation_budget_result(*, result: object, minutes: int | None) -> bool:
    return (
        isinstance(result, dict)
        and set(result) == {"daily_preparation_budget_minutes"}
        and result["daily_preparation_budget_minutes"] == minutes
        and (
            result["daily_preparation_budget_minutes"] is None
            or type(result["daily_preparation_budget_minutes"]) is int
        )
    )


def _is_exact_preparation_budget_rows(*, rows: object, minutes: int | None) -> bool:
    return (
        isinstance(rows, list)
        and len(rows) == 1
        and _is_exact_preparation_budget_result(result=rows[0], minutes=minutes)
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
