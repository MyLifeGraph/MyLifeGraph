from dataclasses import dataclass, field
from datetime import date, datetime
from typing import Any


@dataclass(frozen=True)
class EvidenceRef:
    table: str
    id: str
    field: str

    def as_metadata(self) -> dict[str, str]:
        return {
            "table": self.table,
            "id": self.id,
            "field": self.field,
        }


@dataclass(frozen=True)
class DailyLogSignal:
    id: str
    entry_date: date
    sleep_hours: float | None = None
    energy: float | None = None
    stress: float | None = None
    focus_minutes: int | None = None
    steps: int | None = None
    activity_level: float | None = None


@dataclass(frozen=True)
class BehavioralEventSignal:
    id: str
    occurred_at: datetime
    event_type: str
    source: str | None = None


@dataclass(frozen=True)
class TaskSignal:
    id: str
    due_date: date | None = None
    status: str = "open"
    workload_score: float = 1.0

    def is_overdue(self, today: date) -> bool:
        return (
            self.status != "done"
            and self.due_date is not None
            and self.due_date < today
        )


@dataclass(frozen=True)
class UserStateSnapshotSignal:
    id: str
    scope: str
    period_key: str
    summary: dict[str, Any]
    signals: dict[str, Any]
    generated_at: datetime


@dataclass(frozen=True)
class SignalSummary:
    user_id: str
    period_key: str
    today: date
    daily_logs: list[DailyLogSignal] = field(default_factory=list)
    behavioral_events: list[BehavioralEventSignal] = field(default_factory=list)
    tasks: list[TaskSignal] = field(default_factory=list)
    user_state_snapshots: list[UserStateSnapshotSignal] = field(default_factory=list)
