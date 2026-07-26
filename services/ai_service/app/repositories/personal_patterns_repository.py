import asyncio
from datetime import date, datetime
from typing import Any, Protocol

import httpx

from app.clients.supabase import SupabaseRestClient


class PersonalPatternsPersistenceError(RuntimeError):
    pass


class PersonalPatternsNotFound(PersonalPatternsPersistenceError):
    pass


class PersonalPatternsRepository(Protocol):
    async def get_profile_timezone(self, *, user_id: str) -> str: ...

    async def load_evidence(
        self,
        *,
        user_id: str,
        starts_at: datetime,
        ends_at: datetime,
        local_starts_on: date,
        local_ends_on: date,
    ) -> tuple[
        list[dict[str, Any]],
        list[dict[str, Any]],
        list[dict[str, Any]],
    ]: ...


class SupabasePersonalPatternsRepository:
    _max_focus_rows = 10_000
    _max_reflection_rows = 10_000
    _max_daily_log_rows = 1_000

    def __init__(self, client: SupabaseRestClient) -> None:
        self._client = client

    async def get_profile_timezone(self, *, user_id: str) -> str:
        try:
            rows = await self._client.select(
                "profiles",
                params={
                    "select": "timezone",
                    "id": f"eq.{user_id}",
                    "limit": "1",
                },
            )
        except (httpx.HTTPError, ValueError) as exc:
            raise PersonalPatternsPersistenceError(
                "Personal pattern profile could not be loaded.",
            ) from exc
        if not rows:
            raise PersonalPatternsNotFound(
                "Personal pattern profile is unavailable.",
            )
        if len(rows) != 1 or not isinstance(rows[0].get("timezone"), str):
            raise PersonalPatternsPersistenceError(
                "Personal pattern profile is invalid.",
            )
        return rows[0]["timezone"]

    async def load_evidence(
        self,
        *,
        user_id: str,
        starts_at: datetime,
        ends_at: datetime,
        local_starts_on: date,
        local_ends_on: date,
    ) -> tuple[
        list[dict[str, Any]],
        list[dict[str, Any]],
        list[dict[str, Any]],
    ]:
        try:
            sessions, reflections, daily_logs = await asyncio.gather(
                self._client.select(
                    "focus_sessions",
                    params=[
                        (
                            "select",
                            "id,status,started_at,ended_at,planned_minutes,"
                            "actual_minutes",
                        ),
                        ("user_id", f"eq.{user_id}"),
                        ("status", "in.(completed,abandoned)"),
                        ("started_at", f"gte.{starts_at.isoformat()}"),
                        ("started_at", f"lt.{ends_at.isoformat()}"),
                        ("order", "started_at.asc,id.asc"),
                        ("limit", str(self._max_focus_rows + 1)),
                    ],
                ),
                self._client.select(
                    "focus_session_reflections",
                    params={
                        "select": (
                            "focus_session_id,contract_version,focus_quality,"
                            "useful_progress,obstacles,created_at,updated_at"
                        ),
                        "user_id": f"eq.{user_id}",
                        "created_at": f"gte.{starts_at.isoformat()}",
                        "order": "focus_session_id.asc",
                        "limit": str(self._max_reflection_rows + 1),
                    },
                ),
                self._client.select(
                    "daily_logs",
                    params={
                        "select": "id,entry_date,metadata",
                        "user_id": f"eq.{user_id}",
                        "entry_date": (
                            f"gte.{local_starts_on.isoformat()}"
                        ),
                        "and": (
                            f"(entry_date.lte.{local_ends_on.isoformat()})"
                        ),
                        "order": "entry_date.asc,id.asc",
                        "limit": str(self._max_daily_log_rows + 1),
                    },
                ),
            )
        except (httpx.HTTPError, ValueError) as exc:
            raise PersonalPatternsPersistenceError(
                "Personal pattern evidence could not be loaded.",
            ) from exc
        if (
            len(sessions) > self._max_focus_rows
            or len(reflections) > self._max_reflection_rows
            or len(daily_logs) > self._max_daily_log_rows
        ):
            raise PersonalPatternsPersistenceError(
                "Personal pattern evidence exceeds its bounded window.",
            )
        return sessions, reflections, daily_logs
