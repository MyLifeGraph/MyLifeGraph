from collections.abc import Callable
from dataclasses import dataclass
from datetime import UTC, date, datetime
from typing import Any, Literal
from uuid import UUID
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from app.models.briefings import (
    DAILY_BRIEFING_CONTRACT_VERSION,
    BriefingAction,
    BriefingEvidenceRef,
    BriefingGenerateRequest,
    BriefingProvenance,
    BriefingReadResponse,
)
from app.models.executable_actions import ExecutableActionTarget
from app.models.snapshots import SnapshotGenerateRequest
from app.repositories.briefing_repository import BriefingContext, BriefingRepository
from app.services.snapshot_aggregator import SnapshotAggregator
from app.services.snapshot_daily_state import DAILY_STATE_CONTRACT_VERSION


@dataclass(frozen=True)
class _Candidate:
    action: BriefingAction
    score: int
    category: str


class BriefingService:
    """Build one deterministic daily decision from current executable facts."""

    def __init__(
        self,
        *,
        repository: BriefingRepository,
        snapshot_aggregator: SnapshotAggregator,
        now_provider: Callable[[], datetime] | None = None,
    ) -> None:
        self._repository = repository
        self._snapshot_aggregator = snapshot_aggregator
        self._now_provider = now_provider or _utc_now

    async def get_today(self, *, user_id: str) -> BriefingReadResponse:
        briefing_date = await self._briefing_date(user_id=user_id)
        briefing = await self._repository.get_daily_briefing(
            user_id=user_id,
            briefing_date=briefing_date,
        )
        if briefing is None:
            return _response(
                briefing_date=briefing_date,
                freshness="missing",
                stale_reasons=[],
                briefing=None,
            )
        snapshot = await self._repository.get_daily_snapshot(
            user_id=user_id,
            briefing_date=briefing_date,
        )
        stale_reasons = _stale_reasons(briefing=briefing, snapshot=snapshot)
        return _response(
            briefing_date=briefing_date,
            freshness="stale" if stale_reasons else "current",
            stale_reasons=stale_reasons,
            briefing=briefing,
        )

    async def generate_today(
        self,
        *,
        user_id: str,
        request: BriefingGenerateRequest,
    ) -> BriefingReadResponse:
        if not request.force:
            current = await self.get_today(user_id=user_id)
            if current.freshness == "current":
                return current
        briefing_date = await self._briefing_date(user_id=user_id)
        await self._snapshot_aggregator.generate_snapshot(
            user_id=user_id,
            request=SnapshotGenerateRequest(
                scope="daily",
                target_date=briefing_date,
                window_days=7,
            ),
        )
        context = await self._repository.load_context(
            user_id=user_id,
            briefing_date=briefing_date,
        )
        row = _build_briefing_row(
            user_id=user_id,
            briefing_date=briefing_date,
            context=context,
            generated_at=self._now_provider(),
        )
        briefing = await self._repository.persist_daily_briefing(
            user_id=user_id,
            briefing_date=briefing_date,
            row=row,
        )
        return _response(
            briefing_date=briefing_date,
            freshness="current",
            stale_reasons=[],
            briefing=briefing,
        )

    async def _briefing_date(self, *, user_id: str) -> date:
        timezone_name = await self._repository.get_profile_timezone(user_id=user_id)
        try:
            timezone = ZoneInfo(timezone_name)
        except ZoneInfoNotFoundError as exc:
            raise ValueError("Profile timezone is invalid.") from exc
        return self._now_provider().astimezone(timezone).date()


def _build_briefing_row(
    *,
    user_id: str,
    briefing_date: date,
    context: BriefingContext,
    generated_at: datetime,
) -> dict[str, Any]:
    snapshot = context.snapshot
    daily_state = _daily_state(snapshot=snapshot, briefing_date=briefing_date)
    mode = daily_state["mode"]
    data_quality = daily_state["data_quality"]
    candidates = _rank_candidates(
        context=context,
        briefing_date=briefing_date,
        mode=mode,
        data_quality=data_quality,
    )
    primary = candidates[0].action
    support = _support_actions(candidates[1:], primary=primary)
    evidence = _dedupe_evidence(
        [
            *_daily_state_evidence(daily_state),
            *primary.evidence_refs,
            *(ref for action in support for ref in action.evidence_refs),
        ],
        limit=20,
    )
    snapshot_generated_at = _parse_datetime(snapshot.get("generated_at"))
    provenance = BriefingProvenance(
        engine="deterministic",
        contract_version="daily-briefing-v1",
        daily_state_contract_version="explainable-daily-state-v1",
        executable_action_contract_version="executable-action-v1",
        source_snapshot_id=str(snapshot["id"]),
        source_snapshot_generated_at=snapshot_generated_at,
        baseline="none",
        llm_used=False,
    )
    capacity_note = _capacity_note(mode)
    return {
        "user_id": user_id,
        "briefing_date": briefing_date.isoformat(),
        "mode": mode,
        "capacity_minutes": None,
        "summary": _summary(mode=mode, primary=primary, data_quality=data_quality),
        "primary_action": primary.model_dump(mode="json", exclude_none=True),
        "support_actions": [
            action.model_dump(mode="json", exclude_none=True) for action in support
        ],
        "recommendation_ids": [
            action.recommendation_id
            for action in [primary, *support]
            if action.recommendation_id is not None
        ],
        "evidence_refs": [ref.model_dump(mode="json") for ref in evidence],
        "provenance": provenance.model_dump(mode="json"),
        "data_quality": data_quality,
        "metadata": {
            "contract_version": DAILY_BRIEFING_CONTRACT_VERSION,
            "capacity_note": capacity_note,
            "ranking_version": "deterministic-briefing-ranker-v1",
            "candidate_count": len(candidates),
        },
        "generated_at": generated_at.isoformat(),
        "updated_at": generated_at.isoformat(),
    }


def _daily_state(
    *,
    snapshot: dict[str, Any],
    briefing_date: date,
) -> dict[str, Any]:
    summary = snapshot.get("summary")
    state = summary.get("daily_state") if isinstance(summary, dict) else None
    if not isinstance(state, dict):
        raise ValueError("Daily snapshot has no valid daily state.")
    if state.get("contract_version") != DAILY_STATE_CONTRACT_VERSION:
        raise ValueError("Daily snapshot uses an unsupported daily state contract.")
    if state.get("target_date") != briefing_date.isoformat():
        raise ValueError("Daily snapshot target date does not match the briefing.")
    if state.get("mode") not in {"push", "steady", "recover", "plan"}:
        raise ValueError("Daily snapshot mode is invalid.")
    if state.get("data_quality") not in {"missing", "partial", "current", "stale"}:
        raise ValueError("Daily snapshot data quality is invalid.")
    return state


def _rank_candidates(
    *,
    context: BriefingContext,
    briefing_date: date,
    mode: str,
    data_quality: str,
) -> list[_Candidate]:
    candidates: list[_Candidate] = []
    if data_quality in {"missing", "stale", "partial"}:
        candidates.append(
            _capture_candidate(
                briefing_date=briefing_date,
                score={"missing": 1200, "stale": 1150, "partial": 520}[data_quality],
                reason=(
                    "Today's state is incomplete, so a short calibration is the "
                    "most reliable next step."
                ),
            ),
        )

    active_goal_ids = {
        str(row["id"])
        for row in context.goals
        if row.get("id") is not None and row.get("status") == "active"
    }
    recommendation_by_category = _recommendation_by_category(
        context.recommendations,
    )
    for task in context.tasks:
        candidate = _task_candidate(
            task=task,
            briefing_date=briefing_date,
            mode=mode,
            active_goal_ids=active_goal_ids,
            recommendation=recommendation_by_category.get(
                "planning" if mode == "plan" else "focus",
            ),
        )
        if candidate is not None:
            candidates.append(candidate)

    outcomes_by_habit = _habit_outcomes(context.habit_logs)
    for habit in context.habits:
        candidate = _habit_candidate(
            habit=habit,
            briefing_date=briefing_date,
            mode=mode,
            active_goal_ids=active_goal_ids,
            outcomes=outcomes_by_habit.get(str(habit.get("id")), []),
        )
        if candidate is not None:
            candidates.append(candidate)

    if not candidates:
        candidates.append(
            _capture_candidate(
                briefing_date=briefing_date,
                score=100,
                reason=(
                    "No open executable target is available, so updating your "
                    "calibration is the smallest useful next step."
                ),
            ),
        )
    return sorted(
        candidates,
        key=lambda item: (-item.score, item.category, item.action.target.id),
    )


def _task_candidate(
    *,
    task: dict[str, Any],
    briefing_date: date,
    mode: str,
    active_goal_ids: set[str],
    recommendation: dict[str, Any] | None,
) -> _Candidate | None:
    task_id = _uuid_string(task.get("id"))
    title = _string(task.get("title"))
    if (
        task_id is None
        or title is None
        or len(title) > 200
    ):
        return None
    if task.get("status") not in {"todo", "in_progress"}:
        return None
    estimate = _bounded_int(task.get("estimated_minutes"), minimum=5, maximum=480)
    priority = str(task.get("priority") or "medium")
    deadline = _parse_optional_date(task.get("deadline"))
    metadata = task.get("metadata") if isinstance(task.get("metadata"), dict) else {}
    linked_goal = _string(metadata.get("goal_id"))
    goal_relevant = linked_goal in active_goal_ids if linked_goal else False

    score = {"low": 100, "medium": 180, "high": 270, "critical": 360}.get(
        priority,
        150,
    )
    if task.get("status") == "in_progress":
        score += 55
    if goal_relevant:
        score += 90
    if deadline is not None:
        days = (deadline - briefing_date).days
        score += 320 if days < 0 else 230 if days == 0 else 140 if days <= 3 else 20
    if estimate is not None:
        if mode == "recover":
            score += 100 if estimate <= 15 else 35 if estimate <= 30 else -220
        elif mode == "push":
            score += 90 if 25 <= estimate <= 120 else 20
        else:
            score += 70 if estimate <= 60 else 10
    if mode == "plan" and deadline is not None:
        score += 100
    if mode == "recover" and priority not in {"critical", "high"}:
        score -= 80
    if recommendation is not None:
        score += 20
    score += _recency_score(task.get("updated_at"), briefing_date=briefing_date)

    evidence = [BriefingEvidenceRef(table="tasks", id=task_id, field="status")]
    if deadline is not None:
        evidence.append(
            BriefingEvidenceRef(table="tasks", id=task_id, field="deadline"),
        )
    if goal_relevant and linked_goal is not None:
        evidence.append(
            BriefingEvidenceRef(table="goals", id=linked_goal, field="status"),
        )
    reason = _task_reason(
        priority=priority,
        deadline=deadline,
        briefing_date=briefing_date,
        estimate=estimate,
        goal_relevant=goal_relevant,
        mode=mode,
    )
    action = BriefingAction(
        target=ExecutableActionTarget(
            contract_version="executable-action-v1",
            id=f"open_task:{task_id}",
            kind="task",
            command="open_task",
            target_id=task_id,
            estimated_minutes=estimate,
            metadata={"source": "daily-briefing-v1"},
        ),
        title=title,
        reason=reason,
        recommendation_id=(
            str(recommendation["id"]) if recommendation is not None else None
        ),
        evidence_refs=evidence,
    )
    return _Candidate(action=action, score=score, category="task")


def _habit_candidate(
    *,
    habit: dict[str, Any],
    briefing_date: date,
    mode: str,
    active_goal_ids: set[str],
    outcomes: list[dict[str, Any]],
) -> _Candidate | None:
    habit_id = _uuid_string(habit.get("id"))
    title = _string(habit.get("title"))
    if (
        habit_id is None
        or title is None
        or len(title) > 200
        or habit.get("active") is not True
    ):
        return None
    metadata = habit.get("metadata") if isinstance(habit.get("metadata"), dict) else {}
    if metadata.get("lifecycle", "active") != "active":
        return None
    if metadata.get("setup_state") in {"candidate", "archived"}:
        return None
    if any(str(row.get("entry_date")) == briefing_date.isoformat() for row in outcomes):
        return None

    started_on = _parse_optional_date(metadata.get("started_on"))
    if started_on is not None and started_on > briefing_date:
        return None
    cadence = _habit_cadence(habit=habit, metadata=metadata)
    if cadence is None:
        return None
    cadence_kind, weekly_target, scheduled_weekdays = cadence
    if (
        cadence_kind == "weekdays"
        and briefing_date.isoweekday() not in scheduled_weekdays
    ):
        return None
    if cadence_kind == "weekly_target":
        completed = sum(row.get("status") == "completed" for row in outcomes)
        if completed >= weekly_target:
            return None

    linked_goal = _string(metadata.get("goal_id"))
    goal_relevant = linked_goal in active_goal_ids if linked_goal else False
    score = 210 + (80 if goal_relevant else 0)
    if mode == "recover":
        score += 160
    elif mode == "steady":
        score += 80
    elif mode == "push":
        score += 20
    score += _recency_score(habit.get("updated_at"), briefing_date=briefing_date)
    evidence = [
        BriefingEvidenceRef(table="habits", id=habit_id, field="metadata.cadence"),
    ]
    if goal_relevant and linked_goal is not None:
        evidence.append(
            BriefingEvidenceRef(table="goals", id=linked_goal, field="status"),
        )
    action = BriefingAction(
        target=ExecutableActionTarget(
            contract_version="executable-action-v1",
            id=f"log_habit:{habit_id}:{briefing_date.isoformat()}",
            kind="habit",
            command="log_habit",
            target_id=habit_id,
            metadata={
                "entry_date": briefing_date.isoformat(),
                "habit_outcome": "completed",
                "source": "daily-briefing-v1",
            },
        ),
        title=title,
        reason=(
            "This habit is still open today and fits a lower-load day."
            if mode == "recover"
            else "This scheduled habit is still open today."
        ),
        evidence_refs=evidence,
    )
    return _Candidate(action=action, score=score, category="habit")


def _capture_candidate(
    *,
    briefing_date: date,
    score: int,
    reason: str,
) -> _Candidate:
    action = BriefingAction(
        target=ExecutableActionTarget(
            contract_version="executable-action-v1",
            id=f"open_capture:morning:{briefing_date.isoformat()}",
            kind="capture",
            command="open_capture",
            metadata={
                "entry_date": briefing_date.isoformat(),
                "route": "/morning-calibration",
                "source": "daily-briefing-v1",
            },
        ),
        title="Calibrate today's capacity",
        reason=reason,
        evidence_refs=[],
    )
    return _Candidate(action=action, score=score, category="capture")


def _support_actions(
    candidates: list[_Candidate],
    *,
    primary: BriefingAction,
) -> list[BriefingAction]:
    support: list[BriefingAction] = []
    seen_targets = {primary.target.id}
    for candidate in candidates:
        if candidate.action.target.id in seen_targets:
            continue
        support.append(candidate.action)
        seen_targets.add(candidate.action.target.id)
        if len(support) == 2:
            break
    return support


def _stale_reasons(*, briefing: Any, snapshot: dict[str, Any] | None) -> list[str]:
    if snapshot is None:
        return ["daily_snapshot_missing"]
    reasons: list[str] = []
    if briefing.provenance.source_snapshot_id != str(snapshot.get("id")):
        reasons.append("daily_snapshot_changed")
    try:
        generated_at = _parse_datetime(snapshot.get("generated_at"))
    except ValueError:
        reasons.append("daily_snapshot_invalid")
    else:
        if briefing.provenance.source_snapshot_generated_at != generated_at:
            reasons.append("daily_snapshot_refreshed")
    return reasons


def _response(
    *,
    briefing_date: date,
    freshness: Literal["missing", "current", "stale"],
    stale_reasons: list[str],
    briefing: Any,
) -> BriefingReadResponse:
    return BriefingReadResponse(
        contract_version="daily-briefing-v1",
        briefing_date=briefing_date,
        freshness=freshness,
        needs_generation=freshness != "current",
        stale_reasons=stale_reasons,
        briefing=briefing,
    )


def _recommendation_by_category(
    rows: list[dict[str, Any]],
) -> dict[str, dict[str, Any]]:
    result: dict[str, dict[str, Any]] = {}
    for row in rows:
        category = row.get("category")
        if isinstance(category, str) and category not in result and row.get("id"):
            result[category] = row
    return result


def _habit_outcomes(
    rows: list[dict[str, Any]],
) -> dict[str, list[dict[str, Any]]]:
    result: dict[str, list[dict[str, Any]]] = {}
    for row in rows:
        habit_id = _string(row.get("habit_id"))
        if habit_id is not None:
            result.setdefault(habit_id, []).append(row)
    return result


def _daily_state_evidence(state: dict[str, Any]) -> list[BriefingEvidenceRef]:
    refs: list[BriefingEvidenceRef] = []
    reasons = state.get("reasons")
    if not isinstance(reasons, list):
        return refs
    for reason in reasons:
        evidence = reason.get("evidence_refs") if isinstance(reason, dict) else None
        if not isinstance(evidence, list):
            continue
        for item in evidence:
            if not isinstance(item, dict):
                continue
            try:
                refs.append(BriefingEvidenceRef.model_validate(item, strict=True))
            except ValueError:
                continue
    return refs


def _dedupe_evidence(
    refs: list[BriefingEvidenceRef],
    *,
    limit: int,
) -> list[BriefingEvidenceRef]:
    result: list[BriefingEvidenceRef] = []
    seen: set[tuple[str, str, str]] = set()
    for ref in refs:
        key = (ref.table, ref.id, ref.field)
        if key in seen:
            continue
        seen.add(key)
        result.append(ref)
        if len(result) == limit:
            break
    return result


def _task_reason(
    *,
    priority: str,
    deadline: date | None,
    briefing_date: date,
    estimate: int | None,
    goal_relevant: bool,
    mode: str,
) -> str:
    if deadline is not None and deadline < briefing_date:
        return "This open task is overdue and is the clearest pressure to reduce."
    if deadline == briefing_date:
        return "This open task is due today and should be handled before lower urgency work."
    if mode == "recover" and estimate is not None and estimate <= 30:
        return "This is a bounded open task that fits today's reduced load."
    if goal_relevant:
        return "This open task is linked to an active goal."
    if priority in {"critical", "high"}:
        return "This is one of the highest-priority open tasks."
    return "This open task is the strongest remaining executable option."


def _capacity_note(mode: str) -> str:
    return {
        "push": "Protect one focused block and keep the rest secondary.",
        "steady": "Choose one meaningful block and keep support work limited.",
        "recover": "Keep today's load small and protect recovery.",
        "plan": "Use one bounded action to reduce urgency or ambiguity.",
    }[mode]


def _summary(*, mode: str, primary: BriefingAction, data_quality: str) -> str:
    quality_prefix = (
        "Based on limited current data, "
        if data_quality in {"missing", "partial", "stale"}
        else ""
    )
    return f"{quality_prefix}{mode} mode: start with {primary.title}."


def _parse_optional_date(value: Any) -> date | None:
    if value is None:
        return None
    if not isinstance(value, str):
        return None
    try:
        return datetime.fromisoformat(value.replace("Z", "+00:00")).date()
    except ValueError:
        try:
            return date.fromisoformat(value)
        except ValueError:
            return None


def _habit_cadence(
    *,
    habit: dict[str, Any],
    metadata: dict[str, Any],
) -> tuple[str, int, frozenset[int]] | None:
    cadence = metadata.get("cadence")
    if cadence is not None and metadata.get("contract_version") != "habit-v1":
        return None
    if cadence == "weekdays":
        raw_weekdays = metadata.get("scheduled_weekdays")
        if not isinstance(raw_weekdays, list):
            return None
        weekdays = frozenset(
            day
            for day in raw_weekdays
            if isinstance(day, int) and not isinstance(day, bool) and 1 <= day <= 7
        )
        if len(weekdays) != len(raw_weekdays) or not weekdays:
            return None
        return ("weekdays", 1, weekdays)
    if cadence == "weekly_target" or (
        cadence is None and habit.get("frequency") == "weekly"
    ):
        target = _bounded_int(habit.get("target"), minimum=1, maximum=7)
        return ("weekly_target", target, frozenset()) if target is not None else None
    if cadence in {None, "daily"}:
        return ("daily", 1, frozenset())
    return None


def _recency_score(value: Any, *, briefing_date: date) -> int:
    updated_on = _parse_optional_date(value)
    if updated_on is None or updated_on > briefing_date:
        return 0
    age_days = (briefing_date - updated_on).days
    return 30 if age_days <= 1 else 15 if age_days <= 7 else 0


def _parse_datetime(value: Any) -> datetime:
    if not isinstance(value, str):
        raise ValueError("Snapshot timestamp is invalid.")
    parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    if parsed.tzinfo is None:
        raise ValueError("Snapshot timestamp must include a timezone.")
    return parsed


def _bounded_int(value: Any, *, minimum: int, maximum: int) -> int | None:
    if isinstance(value, bool) or not isinstance(value, int):
        return None
    return value if minimum <= value <= maximum else None


def _string(value: Any) -> str | None:
    if not isinstance(value, str):
        return None
    return value if value and value == value.strip() else None


def _uuid_string(value: Any) -> str | None:
    text = _string(value)
    if text is None:
        return None
    try:
        return str(UUID(text))
    except ValueError:
        return None


def _utc_now() -> datetime:
    return datetime.now(UTC)
