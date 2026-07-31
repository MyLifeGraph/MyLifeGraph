import hashlib
import json
from collections.abc import Callable
from datetime import UTC, date, datetime
from typing import Any

from app.contracts.daily_capture_v4 import validate_daily_capture_v4_branch
from app.models.daily_capture import (
    DailyCaptureBranch,
    DailyCaptureWriteRequest,
    DailyCaptureWriteResponse,
)
from app.repositories.daily_capture_repository import DailyCaptureRepository
from app.repositories.daily_capture_repository import (
    DailyCaptureConflictError as DailyCapturePersistenceConflict,
)
from app.repositories.daily_capture_repository import (
    DailyCapturePersistenceError,
)


class InvalidDailyCaptureError(ValueError):
    pass


class DailyCaptureConflictError(RuntimeError):
    pass


class DailyCaptureUnavailableError(RuntimeError):
    pass


class DailyCaptureService:
    def __init__(
        self,
        *,
        repository: DailyCaptureRepository,
        now: Callable[[], datetime] | None = None,
    ) -> None:
        self._repository = repository
        self._now = now or (lambda: datetime.now(UTC))

    async def write_branch(
        self,
        *,
        user_id: str,
        entry_date: date,
        branch: DailyCaptureBranch,
        request: DailyCaptureWriteRequest,
    ) -> DailyCaptureWriteResponse:
        capture = dict(request.capture)
        _validate_capture(capture, entry_date=entry_date, branch=branch)
        expected = (
            None
            if request.expected_capture is None
            else {
                "capture_id": request.expected_capture.capture_id,
                "captured_at": request.expected_capture.captured_at.isoformat(),
            }
        )
        fingerprint = _fingerprint(
            {
                "contract_version": request.contract_version,
                "request_id": str(request.request_id),
                "entry_date": entry_date.isoformat(),
                "branch": branch,
                "expected_capture": expected,
                "capture": capture,
            },
        )
        try:
            result = await self._repository.apply_branch(
                user_id=user_id,
                entry_date=entry_date,
                branch=branch,
                request_id=str(request.request_id),
                request_fingerprint=fingerprint,
                expected_capture=expected,
                capture=capture,
                now=self._now(),
            )
        except DailyCapturePersistenceConflict as exc:
            raise DailyCaptureConflictError(str(exc)) from exc
        except DailyCapturePersistenceError as exc:
            raise DailyCaptureUnavailableError(
                "Daily Capture could not be saved.",
            ) from exc
        try:
            return DailyCaptureWriteResponse.model_validate(result)
        except ValueError as exc:
            raise InvalidDailyCaptureError(
                "Daily Capture returned an invalid saved state.",
            ) from exc


def _validate_capture(
    capture: dict[str, Any],
    *,
    entry_date: date,
    branch: DailyCaptureBranch,
) -> None:
    issues = validate_daily_capture_v4_branch(
        capture,
        row_date=entry_date,
        branch=branch,
    )
    if issues:
        raise InvalidDailyCaptureError(
            f"The complete Daily Capture {branch} branch is invalid.",
        )


def _fingerprint(payload: dict[str, Any]) -> str:
    encoded = json.dumps(
        payload,
        ensure_ascii=False,
        sort_keys=True,
        separators=(",", ":"),
    ).encode("utf-8")
    return hashlib.sha256(encoded).hexdigest()
