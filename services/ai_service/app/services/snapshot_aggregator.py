import re
from collections import Counter
from collections.abc import Callable, Iterable
from datetime import UTC, date, datetime, timedelta
from typing import Any

from app.models.snapshots import (
    SnapshotGenerateRequest,
    SnapshotGenerateResponse,
    SnapshotScope,
)
from app.repositories.snapshot_repository import SnapshotInputRows, SnapshotRepository
from app.services.planning_availability import recurring_commitment_applies_on
from app.services.snapshot_daily_state import (
    DAILY_STATE_CONTRACT_VERSION,
    DAILY_STATE_LOOKBACK_DAYS,
    DailyStateResult,
    build_snapshot_daily_state,
)


class SnapshotAggregator:
    """Builds compact deterministic user-state snapshots from recent signals."""

    def __init__(
        self,
        *,
        repository: SnapshotRepository,
        today_provider: Callable[[], date] | None = None,
        now_provider: Callable[[], datetime] | None = None,
    ) -> None:
        self._repository = repository
        self._today_provider = today_provider or date.today
        self._now_provider = now_provider or _utc_now

    async def generate_snapshot(
        self,
        *,
        user_id: str,
        request: SnapshotGenerateRequest,
    ) -> SnapshotGenerateResponse:
        target_date = request.target_date or self._today_provider()
        period_key = _period_key(scope=request.scope, target_date=target_date)
        load_window_days = max(request.window_days, DAILY_STATE_LOOKBACK_DAYS)
        loaded_inputs = await self._repository.load_snapshot_inputs(
            user_id=user_id,
            target_date=target_date,
            window_days=load_window_days,
        )
        inputs = _filter_window(
            inputs=loaded_inputs,
            target_date=target_date,
            window_days=request.window_days,
        )
        state_inputs = _filter_window(
            inputs=loaded_inputs,
            target_date=target_date,
            window_days=DAILY_STATE_LOOKBACK_DAYS,
        )
        generated_at = self._now_provider()
        daily_state = build_snapshot_daily_state(
            daily_logs=state_inputs.daily_logs,
            tasks=state_inputs.tasks,
            goals=state_inputs.goals,
            target_date=target_date,
            generated_at=generated_at,
        )
        summary = _build_summary(
            scope=request.scope,
            period_key=period_key,
            target_date=target_date,
            window_days=request.window_days,
            inputs=inputs,
            daily_state=daily_state,
        )
        signals = _build_signals(inputs, daily_state=daily_state)
        row = await self._repository.persist_user_state_snapshot(
            user_id=user_id,
            scope=request.scope,
            period_key=period_key,
            row={
                "user_id": user_id,
                "scope": request.scope,
                "period_key": period_key,
                "summary": summary,
                "signals": signals,
                "source": "backend",
                "generated_at": generated_at.isoformat(),
                "metadata": {
                    "source": "snapshot-aggregator-v1",
                    "daily_state_contract_version": DAILY_STATE_CONTRACT_VERSION,
                    "window_days": request.window_days,
                    "state_lookback_days": DAILY_STATE_LOOKBACK_DAYS,
                    "target_date": target_date.isoformat(),
                },
            },
        )
        return SnapshotGenerateResponse(
            snapshot_id=str(row["id"]),
            scope=request.scope,
            period_key=period_key,
            generated_at=generated_at,
            summary=summary,
            signals=signals,
        )


def _build_summary(
    *,
    scope: SnapshotScope,
    period_key: str,
    target_date: date,
    window_days: int,
    inputs: SnapshotInputRows,
    daily_state: DailyStateResult,
) -> dict[str, Any]:
    start_date = target_date - timedelta(days=window_days - 1)
    logs = inputs.daily_logs
    latest_log_date = _latest_date(logs, "entry_date")
    days_since_latest = (
        (target_date - latest_log_date).days if latest_log_date is not None else None
    )

    average_energy = _average(_numeric(row.get("energy_level")) for row in logs)
    average_stress = _average(_numeric(row.get("stress_level")) for row in logs)
    average_sleep = _average(_numeric(row.get("sleep_hours")) for row in logs)
    average_mood = _average(_numeric(row.get("mood_score")) for row in logs)
    focus_values = [
        value
        for row in logs
        if (value := _integer(row.get("focus_minutes"))) is not None
    ]
    total_focus = sum(focus_values)
    total_steps = sum(_integer(row.get("steps")) or 0 for row in logs)
    average_activity = _average(
        _numeric(row.get("activity_level")) for row in logs
    )

    active_tasks = [
        row for row in inputs.tasks if str(row.get("status") or "") not in _DONE_TASKS
    ]
    overdue_tasks = [
        row
        for row in active_tasks
        if (due_date := _optional_date(row.get("deadline"))) is not None
        and due_date < target_date
    ]
    due_soon_tasks = [
        row
        for row in active_tasks
        if (due_date := _optional_date(row.get("deadline"))) is not None
        and target_date <= due_date <= target_date + timedelta(days=3)
    ]
    completed_tasks = [
        row for row in inputs.tasks if str(row.get("status") or "") == "done"
    ]
    active_goals = [
        row for row in inputs.goals if str(row.get("status") or "active") == "active"
    ]
    completed_goals = [
        row for row in inputs.goals if str(row.get("status") or "") == "completed"
    ]
    active_habits = [
        row for row in inputs.habits if bool(row.get("active", True)) is True
    ]
    habit_outcome_counts = _habit_outcome_counts(inputs.habit_logs)
    focus_session_summary = _focus_session_summary(inputs.focus_sessions)

    risk_flags = _risk_flags(
        days_since_latest=days_since_latest,
        average_energy=average_energy,
        average_stress=average_stress,
        average_sleep=average_sleep,
        total_focus=total_focus,
        focus_is_measured=bool(focus_values),
        overdue_task_count=len(overdue_tasks),
    )
    return {
        "scope": scope,
        "period_key": period_key,
        "target_date": target_date.isoformat(),
        "window": {
            "starts_on": start_date.isoformat(),
            "ends_on": target_date.isoformat(),
            "days": window_days,
        },
        "check_ins": {
            "count": len(logs),
            "latest_entry_date": (
                latest_log_date.isoformat() if latest_log_date is not None else None
            ),
            "days_since_latest": days_since_latest,
        },
        "energy": {
            "average": _round_or_none(average_energy),
            "latest": _latest_numeric(logs, "energy_level", "entry_date"),
        },
        "stress": {
            "average": _round_or_none(average_stress),
            "latest": _latest_numeric(logs, "stress_level", "entry_date"),
        },
        "sleep": {"average_hours": _round_or_none(average_sleep)},
        "mood": {"average_score": _round_or_none(average_mood)},
        "focus": {
            "total_minutes": total_focus,
            "measured_days": len(focus_values),
        },
        "movement": {
            "total_steps": total_steps,
            "average_activity_level": _round_or_none(average_activity),
        },
        "tasks": {
            "active": len(active_tasks),
            "overdue": len(overdue_tasks),
            "due_soon": len(due_soon_tasks),
            "completed": len(completed_tasks),
        },
        "goals": {
            "active": len(active_goals),
            "completed": len(completed_goals),
        },
        "habits": {
            "active": len(active_habits),
            "outcome_counts": habit_outcome_counts,
        },
        "focus_sessions": focus_session_summary,
        "schedule": {"fixed_commitment_count": len(inputs.schedule_items)},
        "memories": {
            "count": len(inputs.memory_entries),
            "top_types": _top_values(inputs.memory_entries, "type", limit=3),
        },
        "risk_flags": list(daily_state.risk_codes),
        "window_risk_flags": risk_flags,
        "recommended_next_focus": _next_focus(
            mode=daily_state.mode,
            data_quality=str(daily_state.summary["data_quality"]),
        ),
        "daily_state": daily_state.summary,
    }


def _filter_window(
    *,
    inputs: SnapshotInputRows,
    target_date: date,
    window_days: int,
) -> SnapshotInputRows:
    start_date = target_date - timedelta(days=window_days - 1)
    return SnapshotInputRows(
        daily_logs=[
            row
            for row in inputs.daily_logs
            if _is_date_in_window(row.get("entry_date"), start_date, target_date)
        ],
        behavioral_events=[
            row
            for row in inputs.behavioral_events
            if _is_event_in_window(row, start_date, target_date)
        ],
        tasks=inputs.tasks,
        goals=inputs.goals,
        habits=inputs.habits,
        habit_logs=[
            row
            for row in inputs.habit_logs
            if _is_date_in_window(row.get("entry_date"), start_date, target_date)
        ],
        focus_sessions=[
            row
            for row in inputs.focus_sessions
            if _is_focus_session_in_window(row, start_date, target_date)
        ],
        schedule_items=[
            row
            for row in inputs.schedule_items
            if _recurring_schedule_occurs_in_window(
                row,
                start_date=start_date,
                target_date=target_date,
            )
        ],
        memory_entries=inputs.memory_entries,
    )


def _build_signals(
    inputs: SnapshotInputRows,
    *,
    daily_state: DailyStateResult,
) -> dict[str, Any]:
    evidence_refs = _evidence_refs(inputs)
    evidence_refs.extend(_daily_state_evidence_refs(daily_state.signals))
    return {
        "source": "snapshot_aggregator_v1",
        "input_counts": {
            "daily_logs": len(inputs.daily_logs),
            "behavioral_events": len(inputs.behavioral_events),
            "tasks": len(inputs.tasks),
            "goals": len(inputs.goals),
            "habits": len(inputs.habits),
            "habit_logs": len(inputs.habit_logs),
            "focus_sessions": len(inputs.focus_sessions),
            "schedule_items": len(inputs.schedule_items),
            "memory_entries": len(inputs.memory_entries),
        },
        "event_type_counts": _count_values(inputs.behavioral_events, "event_type"),
        "task_status_counts": _count_values(inputs.tasks, "status"),
        "goal_status_counts": _count_values(inputs.goals, "status"),
        "habit_outcome_counts": _habit_outcome_counts(inputs.habit_logs),
        "focus_session_status_counts": _focus_session_status_counts(
            inputs.focus_sessions,
        ),
        "evidence_refs": _dedupe_evidence_refs(evidence_refs)[:60],
        "daily_state": daily_state.signals,
    }


def _period_key(*, scope: SnapshotScope, target_date: date) -> str:
    if scope == "daily":
        return target_date.isoformat()
    iso_year, iso_week, _ = target_date.isocalendar()
    return f"{iso_year}-W{iso_week:02d}"


def _risk_flags(
    *,
    days_since_latest: int | None,
    average_energy: float | None,
    average_stress: float | None,
    average_sleep: float | None,
    total_focus: int,
    focus_is_measured: bool,
    overdue_task_count: int,
) -> list[str]:
    flags: list[str] = []
    if days_since_latest is None or days_since_latest > 2:
        flags.append("no_recent_check_in")
    if average_sleep is not None and average_sleep < 6.5:
        flags.append("low_sleep")
    if average_stress is not None and average_stress >= 7:
        flags.append("high_stress")
    if average_energy is not None and average_energy < 4:
        flags.append("low_energy")
    if overdue_task_count > 0:
        flags.append("overdue_tasks")
    if focus_is_measured and total_focus < 30:
        flags.append("low_focus_time")
    return flags


def _next_focus(*, mode: str, data_quality: str) -> str:
    if mode == "recover":
        return "recovery"
    if mode == "plan":
        return "planning"
    if mode == "push":
        return "focus"
    if data_quality in {"missing", "stale"}:
        return "consistency"
    return "maintain"


def _daily_state_evidence_refs(signals: dict[str, Any]) -> list[dict[str, str]]:
    refs: list[dict[str, str]] = []
    provenance = signals.get("provenance")
    if isinstance(provenance, list):
        for item in provenance:
            if not isinstance(item, dict):
                continue
            table = item.get("table")
            row_id = item.get("id")
            if isinstance(table, str) and isinstance(row_id, str):
                refs.append({"table": table, "id": row_id})
    for key in ("risk_evidence", "reason_evidence"):
        groups = signals.get(key)
        if not isinstance(groups, dict):
            continue
        for values in groups.values():
            if not isinstance(values, list):
                continue
            refs.extend(
                {
                    "table": str(item["table"]),
                    "id": str(item["id"]),
                    "field": str(item["field"]),
                }
                for item in values
                if isinstance(item, dict)
                and item.get("table") is not None
                and item.get("id") is not None
                and item.get("field") is not None
            )
    return refs


def _dedupe_evidence_refs(
    refs: list[dict[str, str]],
) -> list[dict[str, str]]:
    seen: set[tuple[tuple[str, str], ...]] = set()
    result: list[dict[str, str]] = []
    for ref in refs:
        key = tuple(sorted(ref.items()))
        if key in seen:
            continue
        seen.add(key)
        result.append(ref)
    return result


def _evidence_refs(inputs: SnapshotInputRows) -> list[dict[str, str]]:
    refs: list[dict[str, str]] = []
    for table, rows in [
        ("daily_logs", inputs.daily_logs),
        ("behavioral_events", inputs.behavioral_events),
        ("tasks", inputs.tasks),
        ("goals", inputs.goals),
        ("habits", inputs.habits),
        ("habit_logs", inputs.habit_logs),
        ("focus_sessions", inputs.focus_sessions),
        ("schedule_items", inputs.schedule_items),
        ("memory_entries", inputs.memory_entries),
    ]:
        refs.extend(
            {"table": table, "id": str(row["id"])}
            for row in rows[:5]
            if row.get("id") is not None
        )
    return refs


def _habit_outcome_counts(rows: list[dict[str, Any]]) -> dict[str, int]:
    counts = Counter(_habit_outcome(row) for row in rows)
    return {
        "completed": counts["completed"],
        "skipped": counts["skipped"],
        "unknown": counts["unknown"],
    }


def _habit_outcome(row: dict[str, Any]) -> str:
    status = str(row.get("status") or "").strip().lower()
    if status in {"completed", "skipped"}:
        return status
    return "unknown"


def _focus_session_summary(rows: list[dict[str, Any]]) -> dict[str, Any]:
    status_counts = _focus_session_status_counts(rows)
    actual_minutes = 0
    completed_minutes = 0
    abandoned_minutes = 0
    planned_minutes = 0
    for row in rows:
        status = _focus_session_status(row)
        actual = _nonnegative_integer(row.get("actual_minutes"))
        planned = _nonnegative_integer(row.get("planned_minutes"))
        actual_minutes += actual or 0
        planned_minutes += planned or 0
        if status == "completed":
            completed_minutes += actual or 0
        elif status == "abandoned":
            abandoned_minutes += actual or 0
    return {
        "count": len(rows),
        "status_counts": status_counts,
        "planned_minutes": planned_minutes,
        "actual_minutes": actual_minutes,
        "completed_minutes": completed_minutes,
        "abandoned_minutes": abandoned_minutes,
    }


def _focus_session_status_counts(
    rows: list[dict[str, Any]],
) -> dict[str, int]:
    counts = Counter(_focus_session_status(row) for row in rows)
    return {
        "active": counts["active"],
        "completed": counts["completed"],
        "abandoned": counts["abandoned"],
        "unknown": counts["unknown"],
    }


def _focus_session_status(row: dict[str, Any]) -> str:
    status = str(row.get("status") or "").strip().lower()
    if status in {"active", "completed", "abandoned"}:
        return status
    return "unknown"


def _count_values(rows: list[dict[str, Any]], key: str) -> dict[str, int]:
    counts = Counter(
        str(value)
        for row in rows
        if (value := row.get(key)) is not None and str(value)
    )
    return dict(counts.most_common(8))


def _top_values(
    rows: list[dict[str, Any]],
    key: str,
    *,
    limit: int,
) -> list[str]:
    return [value for value, _ in Counter(_values(rows, key)).most_common(limit)]


def _values(rows: list[dict[str, Any]], key: str) -> Iterable[str]:
    for row in rows:
        value = row.get(key)
        if value is not None and str(value):
            yield str(value)


def _latest_date(rows: list[dict[str, Any]], key: str) -> date | None:
    dates = [_optional_date(row.get(key)) for row in rows]
    dates = [value for value in dates if value is not None]
    return max(dates) if dates else None


def _latest_numeric(
    rows: list[dict[str, Any]],
    numeric_key: str,
    date_key: str,
) -> float | None:
    dated_rows = [
        (parsed_date, row)
        for row in rows
        if (parsed_date := _optional_date(row.get(date_key))) is not None
    ]
    if not dated_rows:
        return None
    _, latest = max(dated_rows, key=lambda item: item[0])
    return _round_or_none(_numeric(latest.get(numeric_key)))


def _average(values: Iterable[float | None]) -> float | None:
    present = [value for value in values if value is not None]
    if not present:
        return None
    return sum(present) / len(present)


def _round_or_none(value: float | None) -> float | None:
    return round(value, 2) if value is not None else None


def _optional_date(value: Any) -> date | None:
    if value is None:
        return None
    raw = str(value)
    if not raw:
        return None
    if "T" in raw or " " in raw:
        parsed = datetime.fromisoformat(raw.replace("Z", "+00:00"))
        if parsed.tzinfo is not None:
            parsed = parsed.astimezone(UTC)
        return parsed.date()
    return date.fromisoformat(raw)


def _is_date_in_window(value: Any, start_date: date, target_date: date) -> bool:
    parsed = _optional_date(value)
    return parsed is not None and start_date <= parsed <= target_date


def _recurring_schedule_occurs_in_window(
    row: dict[str, Any],
    *,
    start_date: date,
    target_date: date,
) -> bool:
    weekday = row.get("weekday")
    if isinstance(weekday, bool) or not isinstance(weekday, int):
        return False
    cursor = start_date
    while cursor <= target_date:
        if (
            cursor.isoweekday() == weekday
            and recurring_commitment_applies_on(row, cursor)
        ):
            return True
        cursor += timedelta(days=1)
    return False


def _is_event_in_window(
    row: dict[str, Any],
    start_date: date,
    target_date: date,
) -> bool:
    metadata = row.get("metadata")
    if isinstance(metadata, dict) and metadata.get("entry_date") is not None:
        entry_date = _strict_calendar_date(metadata["entry_date"])
        if entry_date is not None:
            return start_date <= entry_date <= target_date
    return _is_date_in_window(row.get("occurred_at"), start_date, target_date)


def _is_focus_session_in_window(
    row: dict[str, Any],
    start_date: date,
    target_date: date,
) -> bool:
    metadata = row.get("metadata")
    if isinstance(metadata, dict) and metadata.get("entry_date") is not None:
        entry_date = _strict_calendar_date(metadata["entry_date"])
        if entry_date is not None:
            return start_date <= entry_date <= target_date
    return _is_date_in_window(row.get("started_at"), start_date, target_date)


def _strict_calendar_date(value: Any) -> date | None:
    if not isinstance(value, str) or re.fullmatch(r"\d{4}-\d{2}-\d{2}", value) is None:
        return None
    try:
        return date.fromisoformat(value)
    except ValueError:
        return None


def _numeric(value: Any) -> float | None:
    if value is None:
        return None
    return float(value)


def _integer(value: Any) -> int | None:
    if value is None:
        return None
    return int(value)


def _nonnegative_integer(value: Any) -> int | None:
    parsed = _integer(value)
    if parsed is None or parsed < 0:
        return None
    return parsed


def _utc_now() -> datetime:
    return datetime.now(tz=UTC)


_DONE_TASKS = {"done", "cancelled", "archived"}
