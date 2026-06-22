from datetime import date, datetime, time, timedelta, timezone
from typing import Any, Protocol

from app.clients.supabase import SupabaseRestClient
from app.models.user_context import (
    BehavioralEventSignal,
    DailyLogSignal,
    SignalSummary,
    TaskSignal,
)


class UserContextRepository(Protocol):
    async def load_recent_context(
        self,
        *,
        user_id: str,
        window_days: int,
        today: date,
    ) -> SignalSummary:
        pass


class SupabaseUserContextRepository:
    def __init__(self, client: SupabaseRestClient) -> None:
        self._client = client

    async def load_recent_context(
        self,
        *,
        user_id: str,
        window_days: int,
        today: date,
    ) -> SignalSummary:
        start_date = today - timedelta(days=window_days - 1)
        start_datetime = datetime.combine(
            start_date,
            time.min,
            tzinfo=timezone.utc,
        )

        daily_logs = await self._client.select(
            "daily_logs",
            params={
                "select": (
                    "id,entry_date,sleep_hours,steps,activity_level,"
                    "focus_minutes,energy_level,stress_level"
                ),
                "user_id": f"eq.{user_id}",
                "entry_date": f"gte.{start_date.isoformat()}",
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
            daily_logs=[_daily_log_signal(row) for row in daily_logs],
            behavioral_events=[
                _behavioral_event_signal(row) for row in behavioral_events
            ],
            tasks=[_task_signal(row) for row in tasks],
        )


def _daily_log_signal(row: dict[str, Any]) -> DailyLogSignal:
    return DailyLogSignal(
        id=str(row["id"]),
        entry_date=date.fromisoformat(str(row["entry_date"])),
        sleep_hours=_optional_float(row.get("sleep_hours")),
        energy=_optional_float(row.get("energy_level")),
        stress=_optional_float(row.get("stress_level")),
        focus_minutes=_optional_int(row.get("focus_minutes")),
        steps=_optional_int(row.get("steps")),
        activity_level=_optional_float(row.get("activity_level")),
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
