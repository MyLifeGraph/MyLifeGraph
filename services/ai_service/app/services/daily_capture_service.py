import hashlib
import json
import re
from collections.abc import Callable
from datetime import UTC, date, datetime
from typing import Any

from app.models.daily_capture import (
    DailyCaptureBranch,
    DailyCaptureWriteRequest,
    DailyCaptureWriteResponse,
)
from app.repositories.daily_capture_repository import DailyCaptureRepository


class InvalidDailyCaptureError(ValueError):
    pass


_EVENING_REQUIRED = {
    "branch_version",
    "capture_kind",
    "entry_date",
    "capture_id",
    "captured_at",
    "mood",
    "energy",
    "stress_intensity",
    "stress_intensity_label",
    "planned_sleep_time",
    "sleep_target_minutes",
}
_EVENING_OPTIONAL = {
    "stress_source",
    "stress_controllability",
    "focus_band",
    "tomorrow_priority",
    "reflection_note",
    "specific_blocker",
}
_MORNING_REQUIRED = {
    "branch_version",
    "capture_kind",
    "entry_date",
    "capture_id",
    "captured_at",
    "sleep_hours",
    "sleep_quality",
    "current_energy",
    "day_shape",
    "estimated_sleep_started_at",
    "woke_at",
    "estimated_sleep_minutes",
    "sleep_target_minutes",
}
_MORNING_OPTIONAL = {"source_evening_capture_id"}
_CLOCK = re.compile(r"^(?:[01]\d|2[0-3]):[0-5]\d$")


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
    required = _MORNING_REQUIRED if branch == "morning" else _EVENING_REQUIRED
    optional = _MORNING_OPTIONAL if branch == "morning" else _EVENING_OPTIONAL
    if set(capture) - required - optional or not required.issubset(capture):
        raise InvalidDailyCaptureError(
            f"The complete Daily Capture {branch} branch is required.",
        )
    if (
        capture.get("branch_version") != "daily-capture-v4"
        or capture.get("capture_kind") != branch
        or capture.get("entry_date") != entry_date.isoformat()
        or not isinstance(capture.get("capture_id"), str)
        or not 1 <= len(capture["capture_id"].strip()) <= 160
    ):
        raise InvalidDailyCaptureError("Daily Capture identity is invalid.")
    captured_at = _aware_datetime(capture.get("captured_at"), "captured_at")
    if captured_at is None:
        raise InvalidDailyCaptureError("Daily Capture timestamp is invalid.")
    if branch == "evening":
        for field in ("mood", "energy", "stress_intensity"):
            _rating(capture.get(field), field)
        if not isinstance(capture.get("stress_intensity_label"), str):
            raise InvalidDailyCaptureError("Stress label is invalid.")
        if (
            not isinstance(capture.get("planned_sleep_time"), str)
            or _CLOCK.fullmatch(capture["planned_sleep_time"]) is None
        ):
            raise InvalidDailyCaptureError("Planned sleep time is invalid.")
    else:
        _rating(capture.get("sleep_quality"), "sleep_quality")
        _rating(capture.get("current_energy"), "current_energy")
        start = _aware_datetime(
            capture.get("estimated_sleep_started_at"),
            "estimated_sleep_started_at",
        )
        end = _aware_datetime(capture.get("woke_at"), "woke_at")
        minutes = capture.get("estimated_sleep_minutes")
        if (
            start is None
            or end is None
            or type(minutes) is not int
            or minutes != int((end - start).total_seconds() // 60)
            or minutes < 1
            or minutes > 16 * 60
        ):
            raise InvalidDailyCaptureError("Estimated sleep interval is invalid.")
        sleep_hours = capture.get("sleep_hours")
        if (
            not isinstance(sleep_hours, (int, float))
            or isinstance(sleep_hours, bool)
            or abs(float(sleep_hours) - minutes / 60) > 0.0001
        ):
            raise InvalidDailyCaptureError("Estimated sleep duration is invalid.")
    target = capture.get("sleep_target_minutes")
    if type(target) is not int or target < 300 or target > 720 or target % 15:
        raise InvalidDailyCaptureError("Sleep target is invalid.")


def _rating(value: object, field: str) -> None:
    if type(value) is not int or value < 0 or value > 10:
        raise InvalidDailyCaptureError(f"{field} must be between 0 and 10.")


def _aware_datetime(value: object, field: str) -> datetime | None:
    if not isinstance(value, str):
        return None
    try:
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError as exc:
        raise InvalidDailyCaptureError(f"{field} is invalid.") from exc
    return parsed if parsed.tzinfo is not None else None


def _fingerprint(payload: dict[str, Any]) -> str:
    encoded = json.dumps(
        payload,
        ensure_ascii=False,
        sort_keys=True,
        separators=(",", ":"),
    ).encode("utf-8")
    return hashlib.sha256(encoded).hexdigest()
