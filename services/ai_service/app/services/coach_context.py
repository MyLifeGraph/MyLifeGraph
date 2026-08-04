import json
import re
from dataclasses import dataclass
from datetime import date
from typing import Any, Protocol

from app.models.briefings import BriefingReadResponse
from app.models.coach import (
    COACH_CONTEXT_BYTES,
    COACH_CONTEXT_V3_VERSION,
    CoachContextOptionsResponse,
    CoachRequest,
    CoachUsedContext,
)
from app.models.coach_evidence import CoachEvidenceDigest
from app.models.weekly_reviews import WeeklyReviewReadResponse
from app.repositories.coach_context_repository import (
    BoundedRows,
    CoachContextRepository,
    CoachSharedContext,
)


class BriefingReader(Protocol):
    async def get_for_date(
        self,
        *,
        user_id: str,
        briefing_date: date,
    ) -> BriefingReadResponse:
        pass


class WeeklyReviewReader(Protocol):
    async def get_latest(self, *, user_id: str) -> WeeklyReviewReadResponse:
        pass


class CoachEvidenceReader(Protocol):
    async def get_context_options(
        self,
        *,
        user_id: str,
        timezone: str,
    ) -> CoachContextOptionsResponse: ...

    async def build_patterns(
        self,
        *,
        user_id: str,
        timezone: str,
        horizon: str,
    ) -> CoachEvidenceDigest: ...

    async def build_focus(
        self,
        *,
        user_id: str,
        timezone: str,
        focus_session_id,
    ) -> CoachEvidenceDigest: ...

    async def build_review(
        self,
        *,
        user_id: str,
        timezone: str,
    ) -> CoachEvidenceDigest: ...


@dataclass(frozen=True)
class CoachContextPackage:
    serialized: str
    used_context: list[CoachUsedContext]
    daily_state_freshness: str
    daily_state_quality: str
    evidence_status: str = "not_applicable"

    @property
    def byte_count(self) -> int:
        return len(self.serialized.encode("utf-8"))


@dataclass(frozen=True)
class _Source:
    name: str
    available_count: int
    items: list[dict[str, Any]]
    freshness: str
    singleton: bool = False


class CoachContextService:
    """Build a deterministic JSON-only context package from safe projections."""

    def __init__(
        self,
        *,
        repository: CoachContextRepository,
        briefing_reader: BriefingReader,
        weekly_review_reader: WeeklyReviewReader,
        evidence_reader: CoachEvidenceReader | None = None,
    ) -> None:
        self._repository = repository
        self._briefing_reader = briefing_reader
        self._weekly_review_reader = weekly_review_reader
        self._evidence_reader = evidence_reader

    async def context_options(
        self,
        *,
        user_id: str,
        timezone: str,
    ) -> CoachContextOptionsResponse:
        if self._evidence_reader is None:
            raise ValueError("Coach historical evidence is unavailable.")
        return await self._evidence_reader.get_context_options(
            user_id=user_id,
            timezone=timezone,
        )

    async def build(
        self,
        *,
        user_id: str,
        local_date: date,
        request: CoachRequest,
    ) -> CoachContextPackage:
        if not request.is_v2:
            return await self.build_today(
                user_id=user_id,
                local_date=local_date,
            )
        if request.context_scope == "today":
            return await self.build_today(
                user_id=user_id,
                local_date=local_date,
                context_version=COACH_CONTEXT_V3_VERSION,
            )
        if self._evidence_reader is None:
            raise ValueError("Coach historical evidence is unavailable.")
        shared = await self._repository.load_shared_context(user_id=user_id)
        if request.context_scope == "patterns":
            horizon = request.patterns_horizon
            assert horizon is not None
            evidence = await self._evidence_reader.build_patterns(
                user_id=user_id,
                timezone=shared.profile.timezone,
                horizon=horizon,
            )
        elif request.context_scope == "focus":
            focus_session_id = request.focus_session_id
            assert focus_session_id is not None
            evidence = await self._evidence_reader.build_focus(
                user_id=user_id,
                timezone=shared.profile.timezone,
                focus_session_id=focus_session_id,
            )
        else:
            evidence = await self._evidence_reader.build_review(
                user_id=user_id,
                timezone=shared.profile.timezone,
            )
        return _build_evidence_package(
            local_date=local_date,
            request=request,
            shared=shared,
            evidence=evidence,
        )

    async def build_today(
        self,
        *,
        user_id: str,
        local_date: date,
        context_version: str = "coach-context-v2",
    ) -> CoachContextPackage:
        # These three reads are deliberately side-effect free. The established
        # briefing/review readers own freshness instead of Coach reinterpreting it.
        raw = await self._repository.load_today_context(
            user_id=user_id,
            local_date=local_date.isoformat(),
        )
        briefing = await self._briefing_reader.get_for_date(
            user_id=user_id,
            briefing_date=local_date,
        )
        weekly = await self._weekly_review_reader.get_latest(user_id=user_id)

        snapshot, snapshot_freshness, state_quality = _safe_snapshot(
            raw.daily_snapshot,
            local_date=local_date,
        )
        profile = {
            "local_date": local_date.isoformat(),
            "timezone": _bounded_text(raw.profile.timezone, 100),
        }
        briefing_item = briefing.model_dump(mode="json") if briefing.briefing else None
        weekly_item = (
            weekly.model_dump(mode="json")
            if weekly.review is not None and weekly.freshness == "current"
            else None
        )

        sources = [
            _Source("profile", 1, [profile], "current", singleton=True),
            _Source(
                "daily_snapshot",
                1 if raw.daily_snapshot is not None else 0,
                [snapshot] if snapshot is not None else [],
                snapshot_freshness,
                singleton=True,
            ),
            _Source(
                "daily_briefing",
                1 if briefing.briefing is not None else 0,
                [briefing_item] if briefing_item is not None else [],
                briefing.freshness,
                singleton=True,
            ),
            _row_source("tasks", raw.tasks, _safe_task),
            _row_source("habits", raw.habits, _safe_habit),
            _row_source("focus_sessions", raw.focus_sessions, _safe_focus),
            _Source(
                "weekly_review",
                1 if weekly.review is not None else 0,
                [weekly_item] if weekly_item is not None else [],
                _weekly_freshness(weekly.freshness),
                singleton=True,
            ),
            _row_source("memories", raw.selected_memories, _safe_memory),
            _row_source(
                "coach_history",
                raw.history,
                lambda row: _safe_history(
                    row,
                    include_context_selection=(
                        context_version == COACH_CONTEXT_V3_VERSION
                    ),
                ),
            ),
        ]
        context, manifest = _fit_sources(
            local_date=local_date,
            sources=sources,
            context_version=context_version,
        )
        serialized = _canonical_json(context)
        if len(serialized.encode("utf-8")) > COACH_CONTEXT_BYTES:
            raise ValueError("Coach context exceeds its byte boundary.")
        return CoachContextPackage(
            serialized=serialized,
            used_context=manifest,
            daily_state_freshness=snapshot_freshness,
            daily_state_quality=state_quality,
            evidence_status="not_applicable",
        )


def _fit_sources(
    *,
    local_date: date,
    sources: list[_Source],
    context_version: str = "coach-context-v2",
) -> tuple[dict[str, Any], list[CoachUsedContext]]:
    context: dict[str, Any] = {
        "contract_version": context_version,
        "context_scope": "today",
        "local_date": local_date.isoformat(),
        "sources": {},
    }
    if context_version == "coach-context-v3":
        context["context_parameters"] = {}
    counts: dict[str, int] = {}
    for source in sources:
        included: list[dict[str, Any]] = []
        for item in source.items:
            candidate_value: Any = item if source.singleton else [*included, item]
            candidate_sources = {**context["sources"], source.name: candidate_value}
            candidate = {**context, "sources": candidate_sources}
            if len(_canonical_json(candidate).encode("utf-8")) > COACH_CONTEXT_BYTES:
                break
            included.append(item)
            context["sources"][source.name] = candidate_value
        if not included:
            context["sources"][source.name] = None if source.singleton else []
        counts[source.name] = len(included)
    manifest = [
        CoachUsedContext(
            source=source.name,
            available_count=source.available_count,
            included_count=counts[source.name],
            omitted_count=source.available_count - counts[source.name],
            freshness=source.freshness,
        )
        for source in sources
    ]
    return context, manifest


def _build_evidence_package(
    *,
    local_date: date,
    request: CoachRequest,
    shared: CoachSharedContext,
    evidence: CoachEvidenceDigest,
) -> CoachContextPackage:
    context: dict[str, Any] = {
        "contract_version": "coach-context-v3",
        "context_scope": request.context_scope,
        "context_parameters": request.context_parameters,
        "local_date": local_date.isoformat(),
        "evidence": evidence.model_dump(mode="json"),
        "sources": {
            "profile": {
                "local_date": local_date.isoformat(),
                "timezone": _bounded_text(shared.profile.timezone, 100),
            },
            "memories": [],
            "coach_history": [],
        },
    }
    if len(_canonical_json(context).encode("utf-8")) > COACH_CONTEXT_BYTES:
        raise ValueError("Coach evidence exceeds its context byte boundary.")

    memory_items = [
        item
        for row in shared.selected_memories.rows
        if (item := _safe_memory(row)) is not None
    ]
    history_items = [
        item
        for row in shared.history.rows
        if (
            item := _safe_history(
                row,
                include_context_selection=True,
            )
        )
        is not None
    ]
    included_counts: dict[str, int] = {"memories": 0, "coach_history": 0}
    for source_name, items in (
        ("memories", memory_items),
        ("coach_history", history_items),
    ):
        for item in items:
            candidate = {
                **context,
                "sources": {
                    **context["sources"],
                    source_name: [*context["sources"][source_name], item],
                },
            }
            if len(_canonical_json(candidate).encode("utf-8")) > COACH_CONTEXT_BYTES:
                break
            context = candidate
            included_counts[source_name] += 1

    manifest = [
        CoachUsedContext(
            source="profile",
            available_count=1,
            included_count=1,
            omitted_count=0,
            freshness="current",
        ),
        *[
            CoachUsedContext(
                source=source.source,
                available_count=source.available_count,
                included_count=source.included_count,
                omitted_count=source.available_count - source.included_count,
                freshness=(
                    "current"
                    if source.included_count
                    else "not_applicable"
                ),
            )
            for source in evidence.sources
        ],
        CoachUsedContext(
            source="memories",
            available_count=shared.selected_memories.available_count,
            included_count=included_counts["memories"],
            omitted_count=(
                shared.selected_memories.available_count
                - included_counts["memories"]
            ),
            freshness=(
                "current"
                if shared.selected_memories.available_count
                else "not_applicable"
            ),
        ),
        CoachUsedContext(
            source="coach_history",
            available_count=shared.history.available_count,
            included_count=included_counts["coach_history"],
            omitted_count=(
                shared.history.available_count
                - included_counts["coach_history"]
            ),
            freshness=(
                "current"
                if shared.history.available_count
                else "not_applicable"
            ),
        ),
    ]
    serialized = _canonical_json(context)
    if len(serialized.encode("utf-8")) > COACH_CONTEXT_BYTES:
        raise ValueError("Coach context exceeds its byte boundary.")
    return CoachContextPackage(
        serialized=serialized,
        used_context=manifest,
        daily_state_freshness="not_applicable",
        daily_state_quality="not_applicable",
        evidence_status=(
            evidence.status
            if evidence.status != "available"
            or sum(source.included_count for source in evidence.sources) >= 3
            else "sparse"
        ),
    )


def _row_source(
    name: str,
    rows: BoundedRows,
    sanitizer,
) -> _Source:
    sanitized = [item for row in rows.rows if (item := sanitizer(row)) is not None]
    return _Source(
        name=name,
        available_count=rows.available_count,
        items=sanitized,
        freshness="current" if rows.available_count else "not_applicable",
    )


def _safe_snapshot(
    row: dict[str, Any] | None,
    *,
    local_date: date,
) -> tuple[dict[str, Any] | None, str, str]:
    if row is None:
        return None, "missing", "missing"
    summary = row.get("summary")
    daily_state = summary.get("daily_state") if isinstance(summary, dict) else None
    if not isinstance(daily_state, dict):
        return None, "stale", "missing"
    source_contract = daily_state.get("contract_version")
    if source_contract not in {
        "explainable-daily-state-v1",
        "explainable-daily-state-v2",
        "explainable-daily-state-v3",
    }:
        return None, "stale", "missing"
    target = daily_state.get("target_date")
    quality = daily_state.get("data_quality")
    if target != local_date.isoformat() or quality not in {
        "missing",
        "partial",
        "current",
        "stale",
    }:
        return None, "stale", "missing"
    freshness = (
        "stale"
        if quality == "stale"
        else ("missing" if quality == "missing" else "current")
    )
    mode = daily_state.get("mode")
    if mode not in {"push", "steady", "recover", "plan"}:
        return None, "stale", "missing"
    safe_state = {
        "contract_version": "explainable-daily-state-v3",
        "target_date": target,
        "mode": mode,
        "data_quality": quality,
        "freshness": _safe_capture_freshness(daily_state.get("freshness")),
        "context": _safe_daily_context(daily_state.get("context")),
        "risk_flags": _safe_daily_codes(
            daily_state.get("risk_flags"),
            source_contract=source_contract,
            limit=20,
        ),
        "reason_codes": _safe_daily_codes(
            daily_state.get("reason_codes"),
            source_contract=source_contract,
            limit=10,
        ),
        "reasons": _safe_daily_reasons(
            daily_state.get("reasons"),
            source_contract=source_contract,
        ),
        "load_guidance": (
            daily_state.get("load_guidance")
            if daily_state.get("load_guidance")
            in {"protect_focus", "maintain", "reduce", "simplify"}
            else None
        ),
        "provenance": _safe_daily_provenance(daily_state.get("provenance")),
    }
    return (
        {
            "id": _bounded_text(row.get("id"), 200),
            "period_key": target,
            "generated_at": row.get("generated_at"),
            "daily_state": safe_state,
        },
        freshness,
        str(quality),
    )


def _safe_capture_freshness(value: Any) -> dict[str, Any]:
    if not isinstance(value, dict):
        return {}
    result = {}
    for kind in ["evening", "morning", "legacy"]:
        raw = value.get(kind)
        if not isinstance(raw, dict) or raw.get("state") not in {
            "missing",
            "current",
            "stale",
        }:
            continue
        age = raw.get("age_days")
        result[kind] = {
            "state": raw.get("state"),
            "entry_date": _optional_bounded_text(raw.get("entry_date"), 10),
            "captured_at": _optional_bounded_text(raw.get("captured_at"), 40),
            "age_days": (
                age if isinstance(age, int) and not isinstance(age, bool) else None
            ),
        }
    return result


def _safe_daily_context(value: Any) -> dict[str, Any]:
    if not isinstance(value, dict):
        return {}
    stress = value.get("stress")
    safe_stress = {}
    if isinstance(stress, dict):
        intensity = stress.get("intensity")
        safe_stress = {
            "intensity": _safe_number(intensity),
            "intensity_label": _enum_or_none(
                stress.get("intensity_label"),
                {"low", "medium", "high"},
            ),
            "source": _enum_or_none(
                stress.get("source"),
                {
                    "workload",
                    "avoidable_pressure",
                    "private_emotional",
                    "physical_recovery",
                    "external_environment",
                },
            ),
            "controllability": _enum_or_none(
                stress.get("controllability"),
                {
                    "hardly_controllable",
                    "partly_controllable",
                    "mostly_controllable",
                },
            ),
        }
    return {
        "mood": _safe_number(value.get("mood")),
        "current_energy": _safe_number(value.get("current_energy")),
        "sleep_hours": _safe_number(value.get("sleep_hours")),
        "sleep_quality": _safe_rating(value.get("sleep_quality")),
        "stress": safe_stress,
        "focus_band": _enum_or_none(
            value.get("focus_band"),
            {
                "none",
                "under_30_minutes",
                "30_to_60_minutes",
                "1_to_2_hours",
                "over_2_hours",
            },
        ),
    }


def _safe_daily_reasons(
    value: Any,
    *,
    source_contract: Any,
) -> list[dict[str, str]]:
    if not isinstance(value, list):
        return []
    result = []
    for raw in value[:3]:
        if not isinstance(raw, dict):
            continue
        code = _safe_code(raw.get("code"), 100)
        if code is not None and not _retired_daily_code(
            code,
            source_contract=source_contract,
        ):
            result.append({"code": code})
    return result


def _safe_daily_codes(
    value: Any,
    *,
    source_contract: Any,
    limit: int,
) -> list[str]:
    return [
        code
        for code in _safe_code_list(value, limit, 100)
        if not _retired_daily_code(code, source_contract=source_contract)
    ]


def _retired_daily_code(code: str, *, source_contract: Any) -> bool:
    if "friction" in code or code in {
        "plan_unclear_priorities",
        "constrained_capacity",
    }:
        return True
    return (
        source_contract == "explainable-daily-state-v1"
        and code in {"overload", "plan_overload"}
    )


def _safe_daily_provenance(value: Any) -> dict[str, str]:
    if not isinstance(value, dict):
        return {}
    result = {}
    allowlists = {
        "kind": {"deterministic"},
        "basis": {"none", "explicit_capture", "legacy_numeric", "mixed"},
        "baseline": {"none"},
        "history_claim": {"current_state_only"},
    }
    for key, allowed in allowlists.items():
        if value.get(key) in allowed:
            result[key] = value[key]
    return result


def _safe_code_list(value: Any, count: int, length: int) -> list[str]:
    if not isinstance(value, list):
        return []
    return [
        text
        for raw in value[:count]
        if (text := _safe_code(raw, length)) is not None
    ]


def _safe_number(value: Any) -> int | float | None:
    if isinstance(value, (int, float)) and not isinstance(value, bool):
        return value
    return None


def _safe_rating(value: Any) -> int | None:
    if isinstance(value, int) and not isinstance(value, bool) and 1 <= value <= 10:
        return value
    return None


def _optional_bounded_text(value: Any, limit: int) -> str | None:
    return None if value is None else _bounded_text(value, limit)


def _safe_code(value: Any, limit: int) -> str | None:
    text = _bounded_text(value, limit)
    return text if text is not None and re.fullmatch(r"[a-z0-9_.-]+", text) else None


def _enum_or_none(value: Any, allowed: set[str]) -> str | None:
    return value if isinstance(value, str) and value in allowed else None


def _safe_task(row: dict[str, Any]) -> dict[str, Any] | None:
    title = _bounded_text(row.get("title"), 200)
    identifier = _bounded_text(row.get("id"), 200)
    if title is None or identifier is None:
        return None
    return {
        "id": identifier,
        "title": title,
        "status": row.get("status"),
        "priority": row.get("priority"),
        "deadline": row.get("deadline"),
        "estimated_minutes": row.get("estimated_minutes"),
    }


def _safe_habit(row: dict[str, Any]) -> dict[str, Any] | None:
    title = _bounded_text(row.get("title"), 160)
    identifier = _bounded_text(row.get("id"), 200)
    if title is None or identifier is None:
        return None
    metadata = row.get("metadata")
    safe_metadata = {}
    if isinstance(metadata, dict):
        safe_metadata = {
            key: metadata.get(key)
            for key in [
                "contract_version",
                "cadence",
                "scheduled_weekdays",
                "lifecycle",
                "started_on",
            ]
            if key in metadata
        }
    return {
        "id": identifier,
        "title": title,
        "frequency": row.get("frequency"),
        "target": row.get("target"),
        "cadence": safe_metadata,
    }


def _safe_focus(row: dict[str, Any]) -> dict[str, Any] | None:
    identifier = _bounded_text(row.get("id"), 200)
    if identifier is None:
        return None
    return {
        "id": identifier,
        "status": row.get("status"),
        "task_id": row.get("task_id"),
        "habit_id": row.get("habit_id"),
        "planned_minutes": row.get("planned_minutes"),
        "actual_minutes": row.get("actual_minutes"),
        "started_at": row.get("started_at"),
        "ended_at": row.get("ended_at"),
    }


def _safe_memory(row: dict[str, Any]) -> dict[str, Any] | None:
    identifier = _bounded_text(row.get("id"), 200)
    title = _bounded_text(row.get("title"), 160)
    content = _bounded_text(row.get("content"), 1_000)
    if identifier is None or title is None or content is None:
        return None
    return {
        "id": identifier,
        "type": row.get("type"),
        "title": title,
        "content": content,
        "selected_at": row.get("selected_at"),
    }


def _safe_history(
    row: dict[str, Any],
    *,
    include_context_selection: bool = False,
) -> dict[str, Any] | None:
    request_id = _bounded_text(row.get("request_id"), 100)
    message = _bounded_text(row.get("message"), 600)
    response = row.get("response")
    if request_id is None or message is None or not isinstance(response, dict):
        return None
    reply = _bounded_text(response.get("reply"), 1_200)
    uncertainty = response.get("uncertainty")
    safety = response.get("safety")
    if (
        reply is None
        or not isinstance(uncertainty, dict)
        or not isinstance(safety, dict)
    ):
        return None
    result = {
        "request_id": request_id,
        "message": message,
        "reply": reply,
        "uncertainty": {
            "level": uncertainty.get("level"),
            "reason": _bounded_text(uncertainty.get("reason"), 300),
        },
        "safety": {"classification": safety.get("classification")},
        "completed_at": row.get("completed_at"),
    }
    if include_context_selection:
        result["context_scope"] = row.get("context_scope")
        result["context_parameters"] = row.get("context_parameters") or {}
    return result


def _weekly_freshness(value: str) -> str:
    if value == "not_ready":
        return "not_applicable"
    return value


def _bounded_text(value: Any, limit: int) -> str | None:
    if not isinstance(value, str):
        return None
    normalized = value.strip()
    if not normalized:
        return None
    return normalized[:limit]


def _canonical_json(value: Any) -> str:
    return json.dumps(
        value,
        ensure_ascii=False,
        separators=(",", ":"),
        sort_keys=True,
    )
