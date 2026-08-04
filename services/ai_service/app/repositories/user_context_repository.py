from datetime import date, datetime, time, timedelta, timezone
from typing import Any, Protocol
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from app.clients.supabase import SupabaseRestClient
from app.models.user_context import (
    BehavioralEventSignal,
    DailyLogSignal,
    FocusSessionSignal,
    SignalSummary,
    TaskSignal,
)
from app.contracts.daily_capture_v4 import parse_daily_capture_sleep_episode


class UserContextRepository(Protocol):
    async def get_profile_timezone(self, *, user_id: str) -> str:
        pass

    async def load_recent_context(
        self,
        *,
        user_id: str,
        window_days: int,
        today: date,
        timezone_name: str = "UTC",
    ) -> SignalSummary:
        pass


class SupabaseUserContextRepository:
    def __init__(self, client: SupabaseRestClient) -> None:
        self._client = client

    async def get_profile_timezone(self, *, user_id: str) -> str:
        rows = await self._client.select(
            "profiles",
            params={
                "select": "timezone",
                "id": f"eq.{user_id}",
                "limit": "1",
            },
        )
        if len(rows) != 1:
            raise ValueError("Recommendation profile is unavailable.")
        timezone_name = str(rows[0].get("timezone") or "")
        try:
            ZoneInfo(timezone_name)
        except ZoneInfoNotFoundError as exc:
            raise ValueError("Recommendation profile timezone is invalid.") from exc
        return timezone_name

    async def load_recent_context(
        self,
        *,
        user_id: str,
        window_days: int,
        today: date,
        timezone_name: str = "UTC",
    ) -> SignalSummary:
        try:
            profile_timezone = ZoneInfo(timezone_name)
        except ZoneInfoNotFoundError as exc:
            raise ValueError("Recommendation profile timezone is invalid.") from exc
        start_date = today - timedelta(days=window_days - 1)
        start_datetime = datetime.combine(
            start_date,
            time.min,
            tzinfo=profile_timezone,
        ).astimezone(timezone.utc)

        daily_logs = await self._client.select(
            "daily_logs",
            params={
                "select": (
                    "id,entry_date,sleep_hours,steps,activity_level,"
                    "focus_minutes,energy_level,stress_level,metadata"
                ),
                "user_id": f"eq.{user_id}",
                "entry_date": f"gte.{start_date.isoformat()}",
                "and": f"(entry_date.lte.{today.isoformat()})",
                "order": "entry_date.desc",
                "limit": str(max(window_days, 1)),
            },
        )
        behavioral_events = await self._client.select(
            "behavioral_events",
            params={
                "select": "id,event_type,source,occurred_at",
                "user_id": f"eq.{user_id}",
                "occurred_at": f"gte.{start_datetime.isoformat()}",
                "order": "occurred_at.desc",
                "limit": "100",
            },
        )
        focus_sessions = await self._client.select(
            "focus_sessions",
            params={
                "select": (
                    "id,started_at,ended_at,planned_minutes,actual_minutes,status"
                ),
                "user_id": f"eq.{user_id}",
                "status": "in.(completed,abandoned)",
                "started_at": f"gte.{start_datetime.isoformat()}",
                "order": "started_at.desc",
                "limit": "200",
            },
        )
        tasks = await self._client.select(
            "tasks",
            params={
                "select": "id,deadline,status,priority,metadata",
                "user_id": f"eq.{user_id}",
                "order": "deadline.asc.nullslast,created_at.desc",
                "limit": "50",
            },
        )
        return SignalSummary(
            user_id=user_id,
            period_key=_current_period_key(today),
            today=today,
            timezone_name=timezone_name,
            daily_logs=_daily_log_signals_through(daily_logs, today=today),
            behavioral_events=[
                _behavioral_event_signal(row) for row in behavioral_events
            ],
            focus_sessions=[
                _focus_session_signal(row, profile_timezone=profile_timezone)
                for row in focus_sessions
            ],
            tasks=[_task_signal(row) for row in tasks],
            user_state_snapshots=[],
        )


def _daily_log_signal(row: dict[str, Any]) -> DailyLogSignal:
    entry_date = date.fromisoformat(str(row["entry_date"]))
    metadata = row.get("metadata")
    metadata = metadata if isinstance(metadata, dict) else {}
    captures = (
        metadata.get("captures")
        if metadata.get("capture_version") in {"daily-capture-v4", "daily-capture-v5"}
        and isinstance(metadata.get("captures"), dict)
        else {}
    )
    parsed_sleep = parse_daily_capture_sleep_episode(
        captures.get("morning"),
        row_date=entry_date,
        container_version=metadata.get("capture_version"),
    ).value
    return DailyLogSignal(
        id=str(row["id"]),
        entry_date=entry_date,
        sleep_hours=(
            parsed_sleep.estimated_sleep_minutes / 60
            if parsed_sleep is not None
            else None
        ),
        sleep_quality=(
            parsed_sleep.sleep_quality if parsed_sleep is not None else None
        ),
        sleep_target_deviation_minutes=(
            parsed_sleep.target_deviation_minutes if parsed_sleep is not None else None
        ),
        energy=_optional_float(row.get("energy_level")),
        stress=_optional_float(row.get("stress_level")),
        focus_minutes=_optional_int(row.get("focus_minutes")),
        steps=_optional_int(row.get("steps")),
        activity_level=_optional_float(row.get("activity_level")),
    )


def _daily_log_signals_through(
    rows: list[dict[str, Any]],
    *,
    today: date,
) -> list[DailyLogSignal]:
    result: list[DailyLogSignal] = []
    for row in rows:
        entry_date = _optional_date(row.get("entry_date"))
        if entry_date is None or entry_date > today:
            continue
        result.append(_daily_log_signal(row))
    return result


def _focus_session_signal(
    row: dict[str, Any],
    *,
    profile_timezone: ZoneInfo,
) -> FocusSessionSignal:
    started_at = _parse_datetime(str(row["started_at"]))
    ended_at = _parse_datetime(str(row["ended_at"]))
    return FocusSessionSignal(
        id=str(row["id"]),
        local_date=started_at.astimezone(profile_timezone).date(),
        started_at=started_at,
        ended_at=ended_at,
        planned_minutes=int(row["planned_minutes"]),
        actual_minutes=int(row["actual_minutes"]),
        status=str(row["status"]),
    )


def _behavioral_event_signal(row: dict[str, Any]) -> BehavioralEventSignal:
    return BehavioralEventSignal(
        id=str(row["id"]),
        occurred_at=_parse_datetime(str(row["occurred_at"])),
        event_type=str(row["event_type"]),
        source=str(row["source"]) if row.get("source") is not None else None,
    )


def _task_signal(row: dict[str, Any]) -> TaskSignal:
    metadata = row.get("metadata")
    metadata = metadata if isinstance(metadata, dict) else {}
    return TaskSignal(
        id=str(row["id"]),
        due_date=_optional_date(row.get("deadline")),
        status=str(row.get("status") or "todo"),
        workload_score=_task_workload_score(
            priority=str(row.get("priority") or "medium"),
            metadata=metadata,
        ),
    )


def _task_workload_score(*, priority: str, metadata: dict[str, Any]) -> float:
    explicit_score = _optional_float(metadata.get("workload_score"))
    if explicit_score is not None:
        return explicit_score
    return {
        "critical": 5.0,
        "high": 4.0,
        "medium": 2.0,
        "low": 1.0,
    }.get(priority, 2.0)


def _current_period_key(today: date) -> str:
    iso_year, iso_week, _ = today.isocalendar()
    return f"{iso_year}-W{iso_week:02d}"


def _optional_date(value: Any) -> date | None:
    if value is None:
        return None
    raw = str(value)
    if not raw:
        return None
    return _parse_datetime(raw).date()


def _parse_datetime(value: str) -> datetime:
    normalized = value.replace("Z", "+00:00")
    return datetime.fromisoformat(normalized)


def _optional_float(value: Any) -> float | None:
    if value is None:
        return None
    return float(value)


def _optional_int(value: Any) -> int | None:
    if value is None:
        return None
    return int(value)
