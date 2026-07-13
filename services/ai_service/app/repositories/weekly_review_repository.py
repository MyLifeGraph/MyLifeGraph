from dataclasses import dataclass
from datetime import date, datetime, timedelta
from typing import Any, Protocol

from app.clients.supabase import SupabaseRestClient
from app.models.weekly_reviews import (
    WeeklyReview,
    WeeklyReviewEvidenceRef,
    WeeklyReviewFacts,
    WeeklyReviewProposal,
    WeeklyReviewProvenance,
)


@dataclass(frozen=True)
class WeeklyReviewProfile:
    timezone: str
    onboarded: bool


@dataclass(frozen=True)
class WeeklyReviewContext:
    tasks: list[dict[str, Any]]
    goals: list[dict[str, Any]]
    habits: list[dict[str, Any]]
    habit_logs: list[dict[str, Any]]
    focus_sessions: list[dict[str, Any]]
    daily_snapshots: list[dict[str, Any]]
    feedback: list[dict[str, Any]]


class WeeklyReviewRepository(Protocol):
    async def get_profile(self, *, user_id: str) -> WeeklyReviewProfile:
        pass

    async def get_weekly_review(
        self,
        *,
        user_id: str,
        period_key: str,
    ) -> WeeklyReview | None:
        pass

    async def get_weekly_snapshot(
        self,
        *,
        user_id: str,
        period_key: str,
    ) -> dict[str, Any] | None:
        pass

    async def load_context(
        self,
        *,
        user_id: str,
        starts_on: date,
        ends_on: date,
        starts_at: datetime,
        ends_at: datetime,
    ) -> WeeklyReviewContext:
        pass

    async def persist_weekly_review(
        self,
        *,
        user_id: str,
        period_key: str,
        row: dict[str, Any],
    ) -> WeeklyReview:
        pass


class SupabaseWeeklyReviewRepository:
    def __init__(self, client: SupabaseRestClient) -> None:
        self._client = client

    async def get_profile(self, *, user_id: str) -> WeeklyReviewProfile:
        rows = await self._client.select(
            "profiles",
            params={
                "select": "timezone,onboarding_completed_at",
                "id": f"eq.{user_id}",
                "limit": "1",
            },
        )
        if not rows:
            raise ValueError("Profile is unavailable for weekly review.")
        timezone = rows[0].get("timezone")
        return WeeklyReviewProfile(
            timezone=timezone if isinstance(timezone, str) and timezone else "UTC",
            onboarded=rows[0].get("onboarding_completed_at") is not None,
        )

    async def get_weekly_review(
        self,
        *,
        user_id: str,
        period_key: str,
    ) -> WeeklyReview | None:
        rows = await self._client.select(
            "weekly_reviews",
            params={
                "select": "*",
                "user_id": f"eq.{user_id}",
                "period_key": f"eq.{period_key}",
                "limit": "1",
            },
        )
        return _weekly_review(rows[0]) if rows else None

    async def get_weekly_snapshot(
        self,
        *,
        user_id: str,
        period_key: str,
    ) -> dict[str, Any] | None:
        rows = await self._client.select(
            "user_state_snapshots",
            params={
                "select": "id,period_key,generated_at,metadata",
                "user_id": f"eq.{user_id}",
                "scope": "eq.weekly",
                "period_key": f"eq.{period_key}",
                "limit": "1",
            },
        )
        return rows[0] if rows else None

    async def load_context(
        self,
        *,
        user_id: str,
        starts_on: date,
        ends_on: date,
        starts_at: datetime,
        ends_at: datetime,
    ) -> WeeklyReviewContext:
        task_select = (
            "id,title,status,priority,deadline,completed_at,cancelled_at,"
            "metadata,created_at,updated_at"
        )
        open_tasks = await self._select_all_pages(
            "tasks",
            params=[
                ("select", task_select),
                ("user_id", f"eq.{user_id}"),
                ("status", "in.(todo,in_progress)"),
                ("created_at", f"lt.{ends_at.isoformat()}"),
                ("order", "created_at.asc,id.asc"),
            ],
        )
        completed_tasks = await self._select_all_pages(
            "tasks",
            params=[
                ("select", task_select),
                ("user_id", f"eq.{user_id}"),
                ("status", "eq.done"),
                ("completed_at", f"gte.{starts_at.isoformat()}"),
                ("completed_at", f"lt.{ends_at.isoformat()}"),
                ("order", "completed_at.asc,id.asc"),
            ],
        )
        cancelled_tasks = await self._select_all_pages(
            "tasks",
            params=[
                ("select", task_select),
                ("user_id", f"eq.{user_id}"),
                ("status", "eq.cancelled"),
                ("cancelled_at", f"gte.{starts_at.isoformat()}"),
                ("cancelled_at", f"lt.{ends_at.isoformat()}"),
                ("order", "cancelled_at.asc,id.asc"),
            ],
        )
        tasks = _dedupe_rows([*open_tasks, *completed_tasks, *cancelled_tasks])
        goals = await self._select_all_pages(
            "goals",
            params=[
                ("select", "id,title,status,metadata,created_at,updated_at"),
                ("user_id", f"eq.{user_id}"),
                ("created_at", f"lt.{ends_at.isoformat()}"),
                ("order", "created_at.asc,id.asc"),
            ],
        )
        habits = await self._select_all_pages(
            "habits",
            params=[
                (
                    "select",
                    "id,title,frequency,target,active,metadata,created_at,updated_at",
                ),
                ("user_id", f"eq.{user_id}"),
                ("created_at", f"lt.{ends_at.isoformat()}"),
                ("order", "created_at.asc,id.asc"),
            ],
        )
        habit_logs = await self._select_all_pages(
            "habit_logs",
            params=[
                (
                    "select",
                    "id,habit_id,entry_date,status,value,created_at,updated_at",
                ),
                ("user_id", f"eq.{user_id}"),
                ("entry_date", f"gte.{starts_on.isoformat()}"),
                ("entry_date", f"lte.{ends_on.isoformat()}"),
                ("order", "entry_date.asc,created_at.asc,id.asc"),
            ],
        )
        focus_sessions = await self._select_all_pages(
            "focus_sessions",
            params=[
                (
                    "select",
                    "id,status,started_at,ended_at,actual_minutes,task_id,habit_id,"
                    "metadata,created_at,updated_at",
                ),
                ("user_id", f"eq.{user_id}"),
                (
                    "started_at",
                    f"gte.{(starts_at - timedelta(days=1)).isoformat()}",
                ),
                (
                    "started_at",
                    f"lt.{(ends_at + timedelta(days=1)).isoformat()}",
                ),
                ("order", "started_at.asc,id.asc"),
            ],
        )
        daily_snapshots = await self._select_all_pages(
            "user_state_snapshots",
            params=[
                ("select", "id,period_key,summary,generated_at,metadata"),
                ("user_id", f"eq.{user_id}"),
                ("scope", "eq.daily"),
                ("period_key", f"gte.{starts_on.isoformat()}"),
                ("period_key", f"lte.{ends_on.isoformat()}"),
                ("order", "period_key.asc,id.asc"),
            ],
        )
        feedback = await self._select_all_pages(
            "decision_feedback",
            params=[
                (
                    "select",
                    "id,action_id,action_kind,feedback_type,context_mode,rule_key,"
                    "created_at",
                ),
                ("user_id", f"eq.{user_id}"),
                ("created_at", f"gte.{starts_at.isoformat()}"),
                ("created_at", f"lt.{ends_at.isoformat()}"),
                ("order", "created_at.asc,id.asc"),
            ],
        )
        return WeeklyReviewContext(
            tasks=tasks,
            goals=goals,
            habits=habits,
            habit_logs=habit_logs,
            focus_sessions=focus_sessions,
            daily_snapshots=daily_snapshots,
            feedback=feedback,
        )

    async def persist_weekly_review(
        self,
        *,
        user_id: str,
        period_key: str,
        row: dict[str, Any],
    ) -> WeeklyReview:
        rows = await self._client.upsert(
            "weekly_reviews",
            rows=[row],
            on_conflict="user_id,period_key",
        )
        if not rows:
            raise ValueError("Weekly review persistence returned no row.")
        return _weekly_review(rows[0])

    async def _select_all_pages(
        self,
        table: str,
        *,
        params: list[tuple[str, str]],
        page_size: int = 1000,
    ) -> list[dict[str, Any]]:
        rows: list[dict[str, Any]] = []
        offset = 0
        while True:
            page = await self._client.select(
                table,
                params=[
                    *params,
                    ("limit", str(page_size)),
                    ("offset", str(offset)),
                ],
            )
            rows.extend(page)
            if len(page) < page_size:
                return rows
            offset += len(page)


def _weekly_review(row: dict[str, Any]) -> WeeklyReview:
    facts = row.get("facts")
    proposals = row.get("proposals")
    evidence_refs = row.get("evidence_refs")
    provenance = row.get("provenance")
    if not isinstance(facts, dict):
        raise ValueError("Persisted weekly review facts are invalid.")
    if not isinstance(proposals, list) or not isinstance(evidence_refs, list):
        raise ValueError("Persisted weekly review lists are invalid.")
    if not isinstance(provenance, dict):
        raise ValueError("Persisted weekly review provenance is invalid.")
    if row.get("source_fingerprint") != provenance.get("source_fingerprint"):
        raise ValueError("Persisted weekly review fingerprint is inconsistent.")
    week_start = _date(row.get("week_start"))
    week_end = _date(row.get("week_end"))
    evidence_window = provenance.get("evidence_window")
    if not isinstance(evidence_window, dict) or (
        evidence_window.get("starts_on") != week_start.isoformat()
        or evidence_window.get("ends_on") != week_end.isoformat()
    ):
        raise ValueError("Persisted weekly review evidence window is inconsistent.")
    return WeeklyReview(
        id=str(row["id"]),
        data_quality=row["data_quality"],
        narrative=str(row["narrative"]),
        facts=WeeklyReviewFacts.model_validate(facts, strict=True),
        proposals=[_weekly_review_proposal(item) for item in proposals],
        evidence_refs=[
            WeeklyReviewEvidenceRef.model_validate(item, strict=True)
            for item in evidence_refs
        ],
        provenance=WeeklyReviewProvenance.model_validate(
            _weekly_review_provenance(provenance),
            strict=True,
        ),
        generated_at=_datetime(row["generated_at"]),
        updated_at=_datetime(row["updated_at"]),
    )


def _datetime(value: Any) -> datetime:
    if not isinstance(value, str):
        raise ValueError("Persisted weekly review timestamp is invalid.")
    parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    if parsed.tzinfo is None:
        raise ValueError("Persisted weekly review timestamp lacks timezone.")
    return parsed


def _date(value: Any) -> date:
    if not isinstance(value, str):
        raise ValueError("Persisted weekly review date is invalid.")
    return date.fromisoformat(value)


def _weekly_review_provenance(value: dict[str, Any]) -> dict[str, Any]:
    evidence_window = value.get("evidence_window")
    if not isinstance(evidence_window, dict):
        raise ValueError("Persisted weekly review evidence window is invalid.")
    return {
        **value,
        "source_snapshot_generated_at": _datetime(
            value.get("source_snapshot_generated_at"),
        ),
        "evidence_window": {
            **evidence_window,
            "starts_on": _date(evidence_window.get("starts_on")),
            "ends_on": _date(evidence_window.get("ends_on")),
        },
    }


def _weekly_review_proposal(value: Any) -> WeeklyReviewProposal:
    if not isinstance(value, dict):
        raise ValueError("Persisted weekly review proposal is invalid.")
    return WeeklyReviewProposal.model_validate(
        {
            **value,
            "expected_updated_at": _datetime(value.get("expected_updated_at")),
        },
        strict=True,
    )


def _dedupe_rows(rows: list[dict[str, Any]]) -> list[dict[str, Any]]:
    by_id: dict[str, dict[str, Any]] = {}
    for row in rows:
        row_id = row.get("id")
        if row_id is not None:
            by_id[str(row_id)] = row
    return [by_id[key] for key in sorted(by_id)]
