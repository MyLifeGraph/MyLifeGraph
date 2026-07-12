from dataclasses import dataclass
from datetime import date, datetime, timedelta
from typing import Any, Protocol

from app.clients.supabase import SupabaseRestClient
from app.models.briefings import (
    BriefingAction,
    BriefingEvidenceRef,
    BriefingProvenance,
    DailyBriefing,
)


@dataclass(frozen=True)
class BriefingContext:
    snapshot: dict[str, Any]
    tasks: list[dict[str, Any]]
    goals: list[dict[str, Any]]
    habits: list[dict[str, Any]]
    habit_logs: list[dict[str, Any]]
    recommendations: list[dict[str, Any]]


class BriefingRepository(Protocol):
    async def get_profile_timezone(self, *, user_id: str) -> str:
        pass

    async def get_daily_snapshot(
        self,
        *,
        user_id: str,
        briefing_date: date,
    ) -> dict[str, Any] | None:
        pass

    async def get_daily_briefing(
        self,
        *,
        user_id: str,
        briefing_date: date,
    ) -> DailyBriefing | None:
        pass

    async def load_context(
        self,
        *,
        user_id: str,
        briefing_date: date,
    ) -> BriefingContext:
        pass

    async def persist_daily_briefing(
        self,
        *,
        user_id: str,
        briefing_date: date,
        row: dict[str, Any],
    ) -> DailyBriefing:
        pass


class SupabaseBriefingRepository:
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
        if not rows:
            raise ValueError("Profile is unavailable for briefing generation.")
        timezone_name = rows[0].get("timezone")
        return timezone_name if isinstance(timezone_name, str) else "UTC"

    async def get_daily_snapshot(
        self,
        *,
        user_id: str,
        briefing_date: date,
    ) -> dict[str, Any] | None:
        rows = await self._client.select(
            "user_state_snapshots",
            params={
                "select": "id,period_key,summary,signals,generated_at,metadata",
                "user_id": f"eq.{user_id}",
                "scope": "eq.daily",
                "period_key": f"eq.{briefing_date.isoformat()}",
                "order": "generated_at.desc",
                "limit": "1",
            },
        )
        return rows[0] if rows else None

    async def get_daily_briefing(
        self,
        *,
        user_id: str,
        briefing_date: date,
    ) -> DailyBriefing | None:
        rows = await self._client.select(
            "daily_briefings",
            params={
                "select": "*",
                "user_id": f"eq.{user_id}",
                "briefing_date": f"eq.{briefing_date.isoformat()}",
                "limit": "1",
            },
        )
        return _daily_briefing(rows[0]) if rows else None

    async def load_context(
        self,
        *,
        user_id: str,
        briefing_date: date,
    ) -> BriefingContext:
        snapshot = await self.get_daily_snapshot(
            user_id=user_id,
            briefing_date=briefing_date,
        )
        if snapshot is None:
            raise ValueError("A daily snapshot is required for a briefing.")
        tasks = await self._client.select(
            "tasks",
            params={
                "select": (
                    "id,title,status,priority,deadline,estimated_minutes,"
                    "metadata,updated_at"
                ),
                "user_id": f"eq.{user_id}",
                "status": "in.(todo,in_progress)",
                "order": "deadline.asc.nullslast,updated_at.desc,id.asc",
                "limit": "200",
            },
        )
        goals = await self._client.select(
            "goals",
            params={
                "select": "id,title,status,due_date,metadata,updated_at",
                "user_id": f"eq.{user_id}",
                "status": "eq.active",
                "order": "updated_at.desc,id.asc",
                "limit": "100",
            },
        )
        habits = await self._client.select(
            "habits",
            params={
                "select": (
                    "id,title,frequency,target,active,metadata,updated_at"
                ),
                "user_id": f"eq.{user_id}",
                "active": "eq.true",
                "order": "updated_at.desc,id.asc",
                "limit": "200",
            },
        )
        week_start = briefing_date - timedelta(days=briefing_date.isoweekday() - 1)
        habit_logs = await self._client.select(
            "habit_logs",
            params=[
                ("select", "id,habit_id,entry_date,status,created_at"),
                ("user_id", f"eq.{user_id}"),
                ("entry_date", f"gte.{week_start.isoformat()}"),
                ("entry_date", f"lte.{briefing_date.isoformat()}"),
                ("order", "entry_date.desc,created_at.desc,id.asc"),
                ("limit", "1000"),
            ],
        )
        recommendations = await self._client.select(
            "recommendations",
            params={
                "select": (
                    "id,title,reason,category,priority,confidence,"
                    "generated_at,metadata,status"
                ),
                "user_id": f"eq.{user_id}",
                "status": "in.(new,accepted)",
                "order": "generated_at.desc,id.asc",
                "limit": "20",
            },
        )
        return BriefingContext(
            snapshot=snapshot,
            tasks=tasks,
            goals=goals,
            habits=habits,
            habit_logs=habit_logs,
            recommendations=recommendations,
        )

    async def persist_daily_briefing(
        self,
        *,
        user_id: str,
        briefing_date: date,
        row: dict[str, Any],
    ) -> DailyBriefing:
        upserted = await self._client.upsert(
            "daily_briefings",
            rows=[row],
            on_conflict="user_id,briefing_date",
        )
        if not upserted:
            raise ValueError("Briefing persistence returned no row.")
        return _daily_briefing(upserted[0])


def _daily_briefing(row: dict[str, Any]) -> DailyBriefing:
    primary = row.get("primary_action")
    support = row.get("support_actions")
    evidence = row.get("evidence_refs")
    provenance = row.get("provenance")
    metadata = row.get("metadata")
    if not isinstance(primary, dict):
        raise ValueError("Persisted briefing primary action is invalid.")
    if not isinstance(support, list) or not isinstance(evidence, list):
        raise ValueError("Persisted briefing action lists are invalid.")
    if not isinstance(provenance, dict) or not isinstance(metadata, dict):
        raise ValueError("Persisted briefing metadata is invalid.")
    return DailyBriefing(
        id=str(row["id"]),
        briefing_date=date.fromisoformat(str(row["briefing_date"])),
        mode=row["mode"],
        data_quality=row["data_quality"],
        capacity_minutes=row.get("capacity_minutes"),
        capacity_note=str(metadata["capacity_note"]),
        summary=str(row["summary"]),
        primary_action=BriefingAction.model_validate(primary, strict=True),
        support_actions=[
            BriefingAction.model_validate(item, strict=True) for item in support
        ],
        evidence_refs=[
            BriefingEvidenceRef.model_validate(item, strict=True)
            for item in evidence
        ],
        provenance=BriefingProvenance.model_validate(
            {
                **provenance,
                "source_snapshot_generated_at": _datetime(
                    provenance.get("source_snapshot_generated_at"),
                ),
            },
            strict=True,
        ),
        generated_at=_datetime(row["generated_at"]),
        updated_at=_datetime(row["updated_at"]),
    )


def _datetime(value: Any) -> datetime:
    if not isinstance(value, str):
        raise ValueError("Persisted briefing timestamp is invalid.")
    return datetime.fromisoformat(value.replace("Z", "+00:00"))
