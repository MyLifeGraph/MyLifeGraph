import asyncio
from dataclasses import dataclass
from datetime import date, datetime
from decimal import Decimal
from math import isfinite
from typing import Any, Protocol
from uuid import UUID

import httpx

from app.clients.supabase import (
    SupabaseResponseTooLargeError,
    SupabaseRestClient,
)


class CoachEvidencePersistenceError(RuntimeError):
    pass


class CoachEvidenceNotFound(CoachEvidencePersistenceError):
    pass


@dataclass(frozen=True)
class EvidenceRows:
    rows: list[dict[str, Any]]
    available_count: int
    partial: bool


@dataclass(frozen=True)
class CoachEvidenceRows:
    daily_logs: EvidenceRows
    focus_sessions: EvidenceRows
    reflections: EvidenceRows
    habit_outcomes: EvidenceRows
    weekly_reviews: EvidenceRows
    task_lifecycle: EvidenceRows


@dataclass(frozen=True)
class FocusOptionRows:
    sessions: list[dict[str, Any]]
    more_available: bool


class CoachEvidenceRepository(Protocol):
    async def load_evidence(
        self,
        *,
        user_id: str,
        starts_at: datetime | None,
        ends_at: datetime,
        local_starts_on: date | None,
        local_ends_on: date,
    ) -> CoachEvidenceRows: ...

    async def load_focus_options(
        self,
        *,
        user_id: str,
        limit: int = 10,
    ) -> FocusOptionRows: ...

    async def load_selected_focus(
        self,
        *,
        user_id: str,
        focus_session_id: UUID,
    ) -> dict[str, Any] | None: ...


class SupabaseCoachEvidenceRepository:
    _PAGE_SIZE = 500
    _PAGE_MAX_RESPONSE_BYTES = 4 * 1024 * 1024
    _CAPS = {
        "daily_logs": 5_000,
        "focus_sessions": 20_000,
        "reflections": 20_000,
        "habit_outcomes": 30_000,
        "weekly_reviews": 2_000,
        "task_lifecycle_each": 10_000,
    }

    def __init__(self, client: SupabaseRestClient) -> None:
        self._client = client

    async def load_evidence(
        self,
        *,
        user_id: str,
        starts_at: datetime | None,
        ends_at: datetime,
        local_starts_on: date | None,
        local_ends_on: date,
    ) -> CoachEvidenceRows:
        timestamp_start = (
            [("started_at", f"gte.{starts_at.isoformat()}")]
            if starts_at is not None
            else []
        )
        local_start = (
            [("entry_date", f"gte.{local_starts_on.isoformat()}")]
            if local_starts_on is not None
            else []
        )
        review_start = (
            [("week_end", f"gte.{local_starts_on.isoformat()}")]
            if local_starts_on is not None
            else []
        )
        try:
            (
                daily,
                focus,
                habits,
                reviews,
                completed_tasks,
                cancelled_tasks,
            ) = await asyncio.gather(
                self._select_bounded(
                    "daily_logs",
                    params=[
                        (
                            "select",
                            "id,entry_date,sleep_hours,steps,activity_level,"
                            "mood_score,energy_level,stress_level,metadata",
                        ),
                        ("user_id", f"eq.{user_id}"),
                        *local_start,
                        ("entry_date", f"lte.{local_ends_on.isoformat()}"),
                        ("order", "entry_date.asc,id.asc"),
                    ],
                    cap=self._CAPS["daily_logs"],
                    sanitizer=_safe_daily_log,
                ),
                self._select_bounded(
                    "focus_sessions",
                    params=[
                        (
                            "select",
                            "id,status,started_at,ended_at,planned_minutes,"
                            "actual_minutes",
                        ),
                        ("user_id", f"eq.{user_id}"),
                        ("status", "in.(completed,abandoned)"),
                        *timestamp_start,
                        ("started_at", f"lt.{ends_at.isoformat()}"),
                        ("order", "started_at.asc,id.asc"),
                    ],
                    cap=self._CAPS["focus_sessions"],
                ),
                self._select_bounded(
                    "habit_logs",
                    params=[
                        ("select", "id,habit_id,entry_date,status"),
                        ("user_id", f"eq.{user_id}"),
                        *local_start,
                        ("entry_date", f"lte.{local_ends_on.isoformat()}"),
                        ("order", "entry_date.asc,id.asc"),
                    ],
                    cap=self._CAPS["habit_outcomes"],
                ),
                self._select_bounded(
                    "weekly_reviews",
                    params=[
                        (
                            "select",
                            "id,period_key,week_start,week_end,data_quality,facts,"
                            "source_fingerprint,generated_at",
                        ),
                        ("user_id", f"eq.{user_id}"),
                        *review_start,
                        ("week_start", f"lte.{local_ends_on.isoformat()}"),
                        ("order", "week_start.asc,id.asc"),
                    ],
                    cap=self._CAPS["weekly_reviews"],
                ),
                self._terminal_tasks(
                    user_id=user_id,
                    status="done",
                    timestamp_field="completed_at",
                    starts_at=starts_at,
                    ends_at=ends_at,
                ),
                self._terminal_tasks(
                    user_id=user_id,
                    status="cancelled",
                    timestamp_field="cancelled_at",
                    starts_at=starts_at,
                    ends_at=ends_at,
                ),
            )
            reflections = await self._reflections_for_sessions(
                user_id=user_id,
                sessions=focus,
            )
        except (
            httpx.HTTPError,
            SupabaseResponseTooLargeError,
            ValueError,
        ) as exc:
            raise CoachEvidencePersistenceError(
                "Coach evidence could not be loaded.",
            ) from exc
        task_rows = [*completed_tasks.rows, *cancelled_tasks.rows]
        task_rows.sort(
            key=lambda row: (
                str(row.get("completed_at") or row.get("cancelled_at") or ""),
                str(row.get("id") or ""),
            ),
        )
        task_partial = completed_tasks.partial or cancelled_tasks.partial
        task_count = completed_tasks.available_count + cancelled_tasks.available_count
        return CoachEvidenceRows(
            daily_logs=daily,
            focus_sessions=focus,
            reflections=reflections,
            habit_outcomes=habits,
            weekly_reviews=reviews,
            task_lifecycle=EvidenceRows(
                rows=task_rows,
                available_count=task_count,
                partial=task_partial,
            ),
        )

    async def _reflections_for_sessions(
        self,
        *,
        user_id: str,
        sessions: EvidenceRows,
    ) -> EvidenceRows:
        rows: list[dict[str, Any]] = []
        session_ids = [str(row.get("id")) for row in sessions.rows]
        for offset in range(0, len(session_ids), 100):
            batch = session_ids[offset : offset + 100]
            if not batch:
                continue
            page = await self._client.select(
                "focus_session_reflections",
                params={
                    "select": (
                        "focus_session_id,contract_version,focus_quality,"
                        "useful_progress,obstacles,created_at,updated_at"
                    ),
                    "user_id": f"eq.{user_id}",
                    "focus_session_id": f"in.({','.join(batch)})",
                    "order": "focus_session_id.asc",
                    "limit": str(len(batch)),
                },
                max_response_bytes=self._PAGE_MAX_RESPONSE_BYTES,
            )
            rows.extend(page)
        rows.sort(key=lambda row: str(row.get("focus_session_id") or ""))
        return EvidenceRows(
            rows=rows,
            available_count=len(rows),
            partial=sessions.partial,
        )

    async def load_focus_options(
        self,
        *,
        user_id: str,
        limit: int = 10,
    ) -> FocusOptionRows:
        try:
            sessions = await self._client.select(
                "focus_sessions",
                params={
                    "select": ("id,status,started_at,planned_minutes,actual_minutes"),
                    "user_id": f"eq.{user_id}",
                    "status": "in.(completed,abandoned)",
                    "order": "started_at.desc,id.asc",
                    "limit": str(limit + 1),
                },
            )
            visible = sessions[:limit]
            if visible:
                ids = ",".join(str(row.get("id")) for row in visible)
                reflections = await self._client.select(
                    "focus_session_reflections",
                    params={
                        "select": "focus_session_id",
                        "user_id": f"eq.{user_id}",
                        "focus_session_id": f"in.({ids})",
                        "limit": str(limit),
                    },
                )
            else:
                reflections = []
        except (httpx.HTTPError, ValueError) as exc:
            raise CoachEvidencePersistenceError(
                "Coach Focus options could not be loaded.",
            ) from exc
        reflected = {str(row.get("focus_session_id")) for row in reflections}
        return FocusOptionRows(
            sessions=[
                {**row, "has_reflection": str(row.get("id")) in reflected}
                for row in visible
            ],
            more_available=len(sessions) > limit,
        )

    async def load_selected_focus(
        self,
        *,
        user_id: str,
        focus_session_id: UUID,
    ) -> dict[str, Any] | None:
        try:
            sessions = await self._client.select(
                "focus_sessions",
                params={
                    "select": (
                        "id,status,started_at,ended_at,planned_minutes,actual_minutes"
                    ),
                    "user_id": f"eq.{user_id}",
                    "id": f"eq.{focus_session_id}",
                    "status": "in.(completed,abandoned)",
                    "limit": "1",
                },
            )
            if not sessions:
                return None
            reflections = await self._client.select(
                "focus_session_reflections",
                params={
                    "select": (
                        "focus_session_id,contract_version,focus_quality,"
                        "useful_progress,obstacles,created_at,updated_at"
                    ),
                    "user_id": f"eq.{user_id}",
                    "focus_session_id": f"eq.{focus_session_id}",
                    "limit": "1",
                },
            )
        except (httpx.HTTPError, ValueError) as exc:
            raise CoachEvidencePersistenceError(
                "Selected Coach Focus evidence could not be loaded.",
            ) from exc
        return {
            **sessions[0],
            "reflection": reflections[0] if reflections else None,
        }

    async def _terminal_tasks(
        self,
        *,
        user_id: str,
        status: str,
        timestamp_field: str,
        starts_at: datetime | None,
        ends_at: datetime,
    ) -> EvidenceRows:
        start = (
            [(timestamp_field, f"gte.{starts_at.isoformat()}")]
            if starts_at is not None
            else []
        )
        return await self._select_bounded(
            "tasks",
            params=[
                (
                    "select",
                    "id,status,completed_at,cancelled_at",
                ),
                ("user_id", f"eq.{user_id}"),
                ("status", f"eq.{status}"),
                *start,
                (timestamp_field, f"lt.{ends_at.isoformat()}"),
                ("order", f"{timestamp_field}.asc,id.asc"),
            ],
            cap=self._CAPS["task_lifecycle_each"],
        )

    async def _select_bounded(
        self,
        table: str,
        *,
        params: list[tuple[str, str]],
        cap: int,
        sanitizer=None,
    ) -> EvidenceRows:
        rows: list[dict[str, Any]] = []
        offset = 0
        examined = 0
        partial = False
        while examined <= cap:
            requested = min(self._PAGE_SIZE, cap + 1 - examined)
            page = await self._client.select(
                table,
                params=[
                    *params,
                    ("limit", str(requested)),
                    ("offset", str(offset)),
                ],
                max_response_bytes=self._PAGE_MAX_RESPONSE_BYTES,
            )
            offset += len(page)
            for raw in page:
                examined += 1
                if examined > cap:
                    partial = True
                    break
                row = sanitizer(raw) if sanitizer is not None else raw
                if row is not None:
                    rows.append(row)
            if partial or len(page) < requested:
                break
        available_count = len(rows)
        if partial:
            available_count = await self._client.count_exact(
                table,
                params=_count_params(params),
            )
            if available_count <= cap:
                raise ValueError(
                    "Supabase exact count contradicts the bounded row probe.",
                )
        return EvidenceRows(
            rows=rows,
            available_count=available_count,
            partial=partial,
        )


def _count_params(
    params: list[tuple[str, str]],
) -> list[tuple[str, str]]:
    return [
        ("select", "id"),
        *[
            (key, value)
            for key, value in params
            if key not in {"select", "order", "limit", "offset"}
        ],
    ]


def _safe_daily_log(row: dict[str, Any]) -> dict[str, Any]:
    metadata = row.get("metadata")
    captures = metadata.get("captures") if isinstance(metadata, dict) else None
    morning = captures.get("morning") if isinstance(captures, dict) else None
    capture_version = (
        metadata.get("capture_version") if isinstance(metadata, dict) else None
    )
    entry_date = row.get("entry_date")
    return {
        "entry_date": entry_date,
        "sleep_hours": _safe_number(row.get("sleep_hours"), 0, 16),
        "steps": _safe_integer(row.get("steps"), 0, 500_000),
        "activity_level": _safe_integer(row.get("activity_level"), 0, 10),
        "mood_score": _safe_integer(row.get("mood_score"), 0, 10),
        "energy_level": _safe_integer(row.get("energy_level"), 0, 10),
        "stress_level": _safe_integer(row.get("stress_level"), 0, 10),
        "sleep_quality": _safe_morning_sleep_quality(
            morning,
            entry_date=entry_date,
            container_version=capture_version,
        ),
    }


def _safe_morning_sleep_quality(
    value: Any,
    *,
    entry_date: Any,
    container_version: Any,
) -> int | None:
    if container_version == "daily-capture-v4":
        valid_branch = (
            isinstance(value, dict)
            and value.get("branch_version") == "daily-capture-v4"
            and value.get("compatibility") in {None, False}
        )
    elif container_version == "daily-capture-v5":
        valid_branch = isinstance(value, dict) and (
            (
                value.get("branch_version") == "daily-capture-v5"
                and value.get("compatibility") in {None, False}
                and "day_shape" not in value
            )
            or (
                value.get("branch_version") == "daily-capture-v4"
                and value.get("compatibility") is True
            )
        )
    else:
        valid_branch = False
    if (
        not isinstance(value, dict)
        or not isinstance(entry_date, str)
        or not valid_branch
        or value.get("capture_kind") != "morning"
        or value.get("entry_date") != entry_date
    ):
        return None
    return _safe_integer(value.get("sleep_quality"), 1, 10)


def _safe_number(value: Any, minimum: float, maximum: float) -> float | None:
    if isinstance(value, bool) or not isinstance(value, (int, float, Decimal)):
        return None
    numeric = float(value)
    return numeric if isfinite(numeric) and minimum <= numeric <= maximum else None


def _safe_integer(value: Any, minimum: int, maximum: int) -> int | None:
    numeric = _safe_number(value, minimum, maximum)
    if numeric is None or not numeric.is_integer():
        return None
    return int(numeric)
