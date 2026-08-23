from datetime import date, datetime
from typing import Any, Protocol

import httpx

from app.clients.supabase import SupabaseRestClient


class DailyCapturePersistenceError(RuntimeError):
    pass


class DailyCaptureConflictError(RuntimeError):
    pass


class DailyCaptureRepository(Protocol):
    async def apply_branch(
        self,
        *,
        user_id: str,
        entry_date: date,
        branch: str,
        request_id: str,
        request_fingerprint: str,
        expected_capture: dict[str, str] | None,
        capture: dict[str, Any],
        now: datetime,
    ) -> dict[str, Any]:
        pass


class SupabaseDailyCaptureRepository:
    def __init__(self, client: SupabaseRestClient) -> None:
        self._client = client

    async def apply_branch(
        self,
        *,
        user_id: str,
        entry_date: date,
        branch: str,
        request_id: str,
        request_fingerprint: str,
        expected_capture: dict[str, str] | None,
        capture: dict[str, Any],
        now: datetime,
    ) -> dict[str, Any]:
        params = {
            "p_user_id": user_id,
            "p_entry_date": entry_date.isoformat(),
            "p_branch": branch,
            "p_request_id": request_id,
            "p_request_fingerprint": request_fingerprint,
            "p_expected_capture": expected_capture,
            "p_capture": capture,
            "p_now": now.isoformat(),
        }
        try:
            result = await self._client.rpc(
                "apply_daily_capture_branch_v1",
                params=params,
            )
        except httpx.HTTPStatusError as exc:
            if _error_code(exc.response) == "PT409":
                raise DailyCaptureConflictError(
                    "This capture changed. Reload before saving.",
                ) from exc
            if exc.response.status_code < 500:
                raise DailyCapturePersistenceError(
                    "Daily Capture could not be saved.",
                ) from exc
            result = await self._replay(params)
        except (httpx.HTTPError, ValueError):
            result = await self._replay(params)
        if not isinstance(result, dict):
            raise DailyCapturePersistenceError(
                "Daily Capture returned an invalid result.",
            )
        return result

    async def _replay(self, params: dict[str, Any]) -> Any:
        try:
            return await self._client.rpc(
                "apply_daily_capture_branch_v1",
                params=params,
            )
        except httpx.HTTPStatusError as exc:
            if _error_code(exc.response) == "PT409":
                raise DailyCaptureConflictError(
                    "This capture changed. Reload before saving.",
                ) from exc
            raise DailyCapturePersistenceError(
                "Daily Capture save outcome could not be determined.",
            ) from exc
        except (httpx.HTTPError, ValueError) as exc:
            raise DailyCapturePersistenceError(
                "Daily Capture save outcome could not be determined.",
            ) from exc


def _error_code(response: httpx.Response) -> str | None:
    try:
        payload = response.json()
    except ValueError:
        return None
    if not isinstance(payload, dict):
        return None
    value = payload.get("code")
    return value if isinstance(value, str) else None
