import hashlib
import json
import re
from collections import Counter
from collections.abc import Callable
from dataclasses import dataclass
from datetime import UTC, date, datetime, time, timedelta
from typing import Any
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from app.models.snapshots import SnapshotGenerateRequest
from app.models.weekly_reviews import (
    WEEKLY_REVIEW_CONTRACT_VERSION,
    WeeklyFeedbackFacts,
    WeeklyFocusFacts,
    WeeklyHabitFacts,
    WeeklyRecoveryFacts,
    WeeklyReview,
    WeeklyReviewEvidenceRef,
    WeeklyReviewEvidenceWindow,
    WeeklyReviewFacts,
    WeeklyReviewGenerateRequest,
    WeeklyReviewHabitCadence,
    WeeklyReviewHabitState,
    WeeklyReviewProposal,
    WeeklyReviewProposalChange,
    WeeklyReviewProvenance,
    WeeklyReviewReadResponse,
    WeeklyTaskFacts,
)
from app.repositories.weekly_review_repository import (
    WeeklyReviewContext,
    WeeklyReviewProfile,
    WeeklyReviewRepository,
)
from app.services.snapshot_aggregator import SnapshotAggregator


@dataclass(frozen=True)
class _ReviewPeriod:
    period_key: str
    starts_on: date
    ends_on: date
    timezone_name: str
    timezone: ZoneInfo
    starts_at: datetime
    ends_at: datetime


@dataclass(frozen=True)
class _HabitReview:
    row: dict[str, Any]
    state: WeeklyReviewHabitState
    ownership: str
    stable: bool
    scheduled: int
    completed: int
    skipped: int
    known_non_recovery_skips: int
    recovery_day_outcomes: int
    missed: int
    recovery_open: int
    unknown: int
    feedback: Counter[str]
    evidence_refs: tuple[WeeklyReviewEvidenceRef, ...]


@dataclass(frozen=True)
class _ReviewBuild:
    data_quality: str
    narrative: str
    facts: WeeklyReviewFacts
    proposals: list[WeeklyReviewProposal]
    evidence_refs: list[WeeklyReviewEvidenceRef]
    limitations: list[str]


@dataclass(frozen=True)
class _ProposalCandidate:
    priority: int
    proposal: WeeklyReviewProposal


class WeeklyReviewPeriodError(ValueError):
    pass


class WeeklyReviewService:
    """Builds one bounded deterministic review for the latest closed ISO week."""

    def __init__(
        self,
        *,
        repository: WeeklyReviewRepository,
        snapshot_aggregator: SnapshotAggregator,
        now_provider: Callable[[], datetime] | None = None,
    ) -> None:
        self._repository = repository
        self._snapshot_aggregator = snapshot_aggregator
        self._now_provider = now_provider or _utc_now

    async def get_latest(self, *, user_id: str) -> WeeklyReviewReadResponse:
        profile = await self._repository.get_profile(user_id=user_id)
        period = self._latest_period(profile=profile)
        return await self._read(
            user_id=user_id,
            profile=profile,
            period=period,
        )

    async def get_period(
        self,
        *,
        user_id: str,
        period_key: str,
    ) -> WeeklyReviewReadResponse:
        profile = await self._repository.get_profile(user_id=user_id)
        period = self._latest_period(profile=profile)
        self._require_period(period=period, requested=period_key)
        return await self._read(
            user_id=user_id,
            profile=profile,
            period=period,
        )

    async def generate(
        self,
        *,
        user_id: str,
        request: WeeklyReviewGenerateRequest,
    ) -> WeeklyReviewReadResponse:
        profile = await self._repository.get_profile(user_id=user_id)
        period = self._latest_period(profile=profile)
        self._require_period(period=period, requested=request.period_key)
        if not profile.onboarded:
            return _not_ready(period)

        context = await self._load_context(user_id=user_id, period=period)
        current = await self._response_for_context(
            user_id=user_id,
            period=period,
            context=context,
        )
        if not _has_review_evidence(context):
            # Preserve a previously generated review as stale when all of its
            # source facts were removed. Hiding it as not-ready would erase the
            # exact correction the source fingerprint is meant to expose.
            return current
        if not request.force and current.freshness == "current":
            return current

        snapshot = await self._snapshot_aggregator.generate_snapshot(
            user_id=user_id,
            request=SnapshotGenerateRequest(
                scope="weekly",
                target_date=period.ends_on,
                window_days=7,
            ),
        )
        # Owner facts may change while the backend snapshot is being refreshed.
        # Re-read once so persisted review facts and their fingerprint agree.
        context = await self._load_context(user_id=user_id, period=period)
        if not _has_review_evidence(context):
            return await self._response_for_context(
                user_id=user_id,
                period=period,
                context=context,
            )
        fingerprint = _source_fingerprint(period=period, context=context)
        built = _build_review(
            period=period,
            context=context,
        )
        generated_at = self._now_provider()
        if generated_at.tzinfo is None:
            raise ValueError("Weekly review generation time must be timezone-aware.")
        review = await self._repository.persist_weekly_review(
            user_id=user_id,
            period_key=period.period_key,
            row={
                "user_id": user_id,
                "period_key": period.period_key,
                "week_start": period.starts_on.isoformat(),
                "week_end": period.ends_on.isoformat(),
                "timezone": period.timezone_name,
                "data_quality": built.data_quality,
                "narrative": built.narrative,
                "facts": built.facts.model_dump(mode="json"),
                "proposals": [
                    proposal.model_dump(mode="json")
                    for proposal in built.proposals
                ],
                "evidence_refs": [
                    evidence.model_dump(mode="json")
                    for evidence in built.evidence_refs
                ],
                "provenance": WeeklyReviewProvenance(
                    engine="deterministic",
                    contract_version="weekly-review-v1",
                    source_snapshot_id=snapshot.snapshot_id,
                    source_snapshot_generated_at=snapshot.generated_at,
                    evidence_window=WeeklyReviewEvidenceWindow(
                        starts_on=period.starts_on,
                        ends_on=period.ends_on,
                        days=7,
                    ),
                    source_fingerprint=fingerprint,
                    baseline="none",
                    limitations=built.limitations,
                    llm_used=False,
                ).model_dump(mode="json"),
                "source_fingerprint": fingerprint,
                "generated_at": generated_at.isoformat(),
                "updated_at": generated_at.isoformat(),
            },
        )
        return _response(
            period=period,
            freshness="current",
            stale_reasons=[],
            review=review,
        )

    async def _read(
        self,
        *,
        user_id: str,
        profile: WeeklyReviewProfile,
        period: _ReviewPeriod,
    ) -> WeeklyReviewReadResponse:
        if not profile.onboarded:
            return _not_ready(period)
        context = await self._load_context(user_id=user_id, period=period)
        return await self._response_for_context(
            user_id=user_id,
            period=period,
            context=context,
        )

    async def _response_for_context(
        self,
        *,
        user_id: str,
        period: _ReviewPeriod,
        context: WeeklyReviewContext,
    ) -> WeeklyReviewReadResponse:
        review = await self._repository.get_weekly_review(
            user_id=user_id,
            period_key=period.period_key,
        )
        if review is None:
            if not _has_review_evidence(context):
                return _not_ready(period)
            return _response(
                period=period,
                freshness="missing",
                stale_reasons=[],
                review=None,
            )
        fingerprint = _source_fingerprint(period=period, context=context)
        snapshot = await self._repository.get_weekly_snapshot(
            user_id=user_id,
            period_key=period.period_key,
        )
        stale_reasons = _stale_reasons(
            review=review,
            period=period,
            fingerprint=fingerprint,
            snapshot=snapshot,
        )
        return _response(
            period=period,
            freshness="stale" if stale_reasons else "current",
            stale_reasons=stale_reasons,
            review=review,
        )

    async def _load_context(
        self,
        *,
        user_id: str,
        period: _ReviewPeriod,
    ) -> WeeklyReviewContext:
        return await self._repository.load_context(
            user_id=user_id,
            starts_on=period.starts_on,
            ends_on=period.ends_on,
            starts_at=period.starts_at,
            ends_at=period.ends_at,
        )

    def _latest_period(self, *, profile: WeeklyReviewProfile) -> _ReviewPeriod:
        try:
            timezone = ZoneInfo(profile.timezone)
        except ZoneInfoNotFoundError as exc:
            raise ValueError("Profile timezone is invalid.") from exc
        now = self._now_provider()
        if now.tzinfo is None:
            raise ValueError("Weekly review clock must be timezone-aware.")
        local_today = now.astimezone(timezone).date()
        current_week_start = local_today - timedelta(days=local_today.isoweekday() - 1)
        ends_on = current_week_start - timedelta(days=1)
        starts_on = ends_on - timedelta(days=6)
        starts_at = datetime.combine(starts_on, time.min, tzinfo=timezone).astimezone(UTC)
        ends_at = datetime.combine(
            ends_on + timedelta(days=1),
            time.min,
            tzinfo=timezone,
        ).astimezone(UTC)
        return _ReviewPeriod(
            period_key=_period_key(starts_on),
            starts_on=starts_on,
            ends_on=ends_on,
            timezone_name=profile.timezone,
            timezone=timezone,
            starts_at=starts_at,
            ends_at=ends_at,
        )

    @staticmethod
    def _require_period(*, period: _ReviewPeriod, requested: str) -> None:
        if requested != period.period_key:
            raise WeeklyReviewPeriodError(
                "Only the latest completed profile-local ISO week is available.",
            )


def _build_review(
    *,
    period: _ReviewPeriod,
    context: WeeklyReviewContext,
) -> _ReviewBuild:
    daily_modes, daily_evidence = _daily_modes(period=period, rows=context.daily_snapshots)
    task_facts, task_evidence = _task_facts(period=period, context=context)
    habit_facts, habit_reviews, habit_evidence = _habit_facts(
        period=period,
        habits=context.habits,
        logs=context.habit_logs,
        feedback=context.feedback,
        daily_modes=daily_modes,
    )
    focus_facts, focus_evidence = _focus_facts(
        period=period,
        rows=context.focus_sessions,
    )
    feedback_facts, feedback_evidence = _feedback_facts(context.feedback)
    recovery_days = sum(mode == "recover" for mode in daily_modes.values())
    recovery_facts = WeeklyRecoveryFacts(
        observed_days=len(daily_modes),
        recovery_days=recovery_days,
    )
    facts = WeeklyReviewFacts(
        tasks=task_facts,
        habits=habit_facts,
        focus=focus_facts,
        recovery=recovery_facts,
        feedback=feedback_facts,
    )
    proposals = _proposals(
        period=period,
        habit_reviews=habit_reviews,
        observed_daily_state_days=len(daily_modes),
    )
    evidence = _dedupe_evidence(
        [
            *task_evidence,
            *habit_evidence,
            *focus_evidence,
            *daily_evidence,
            *feedback_evidence,
            *(ref for proposal in proposals for ref in proposal.evidence_refs),
        ],
        limit=40,
    )
    limitations = ["task_history_is_current_state_projection"] if context.tasks else []
    if len(daily_modes) < 7:
        limitations.append("daily_state_days_missing")
    if habit_facts.changed_definitions:
        limitations.append("habit_definitions_changed_in_or_after_window")
    if any(review.recovery_day_outcomes for review in habit_reviews):
        limitations.append("explicit_habit_outcomes_overlap_recovery_days")
    if any(review.state.cadence.kind == "weekly_target" for review in habit_reviews):
        limitations.append("weekly_target_recovery_allocation_is_conservative")
    data_quality = (
        "insufficient"
        if not proposals and len(daily_modes) < 3 and not context.habit_logs
        else "sufficient"
        if len(daily_modes) == 7 and habit_facts.changed_definitions == 0
        else "partial"
    )
    narrative = _narrative(facts=facts, proposal_count=len(proposals))
    return _ReviewBuild(
        data_quality=data_quality,
        narrative=narrative,
        facts=facts,
        proposals=proposals,
        evidence_refs=evidence,
        limitations=limitations[:10],
    )


def _task_facts(
    *,
    period: _ReviewPeriod,
    context: WeeklyReviewContext,
) -> tuple[WeeklyTaskFacts, list[WeeklyReviewEvidenceRef]]:
    goal_ids = {str(row["id"]) for row in context.goals if row.get("id") is not None}
    completed = carried = overdue = cancelled = goal_linked = 0
    evidence: list[WeeklyReviewEvidenceRef] = []
    for row in context.tasks:
        row_id = _row_id(row)
        status = row.get("status")
        if status == "done" and _instant_in_period(row.get("completed_at"), period):
            completed += 1
            evidence.append(_evidence("tasks", row_id, "completed_at"))
            metadata = row.get("metadata")
            goal_id = metadata.get("goal_id") if isinstance(metadata, dict) else None
            if isinstance(goal_id, str) and goal_id in goal_ids:
                goal_linked += 1
                evidence.append(_evidence("goals", goal_id, "id"))
        elif status in {"todo", "in_progress"} and _before_period_end(
            row.get("created_at"),
            period,
        ):
            carried += 1
            evidence.append(_evidence("tasks", row_id, "status"))
            deadline = _date_in_timezone(row.get("deadline"), period.timezone)
            if deadline is not None and deadline <= period.ends_on:
                overdue += 1
                evidence.append(_evidence("tasks", row_id, "deadline"))
        elif status == "cancelled" and _instant_in_period(
            row.get("cancelled_at"),
            period,
        ):
            cancelled += 1
            evidence.append(_evidence("tasks", row_id, "cancelled_at"))
    return (
        WeeklyTaskFacts(
            completed=completed,
            carried=carried,
            overdue_carried=overdue,
            cancelled=cancelled,
            goal_linked_completed=goal_linked,
        ),
        evidence,
    )


def _habit_facts(
    *,
    period: _ReviewPeriod,
    habits: list[dict[str, Any]],
    logs: list[dict[str, Any]],
    feedback: list[dict[str, Any]],
    daily_modes: dict[date, str],
) -> tuple[WeeklyHabitFacts, list[_HabitReview], list[WeeklyReviewEvidenceRef]]:
    logs_by_habit: dict[str, list[dict[str, Any]]] = {}
    completed_total = skipped_total = 0
    evidence: list[WeeklyReviewEvidenceRef] = []
    for row in logs:
        habit_id = row.get("habit_id")
        if not isinstance(habit_id, str):
            continue
        logs_by_habit.setdefault(habit_id, []).append(row)
        if row.get("status") == "completed":
            completed_total += 1
            evidence.append(_evidence("habit_logs", _row_id(row), "status"))
        elif row.get("status") == "skipped":
            skipped_total += 1
            evidence.append(_evidence("habit_logs", _row_id(row), "status"))

    active = paused = archived = stable_count = changed_count = 0
    scheduled = missed = recovery_open = unknown = 0
    reviews: list[_HabitReview] = []
    for row in habits:
        state = _habit_state(row)
        if state is None:
            changed_count += 1
            continue
        lifecycle = state.lifecycle
        active += lifecycle == "active"
        paused += lifecycle == "paused"
        archived += lifecycle == "archived"
        updated_at = _aware_datetime(row.get("updated_at"))
        stable = updated_at is not None and updated_at < period.starts_at
        if stable:
            stable_count += 1
        else:
            changed_count += 1
        habit_id = _row_id(row)
        habit_logs = logs_by_habit.get(habit_id, [])
        habit_feedback = _habit_feedback(habit_id=habit_id, rows=feedback)
        review_evidence = [_evidence("habits", habit_id, "updated_at")]
        review_evidence.extend(
            _evidence("habit_logs", _row_id(item), "status")
            for item in habit_logs[:6]
            if item.get("status") in {"completed", "skipped"}
        )
        review_evidence.extend(
            _evidence("decision_feedback", _row_id(item), "feedback_type")
            for item in feedback
            if _feedback_matches_habit(item, habit_id)
        )
        habit_scheduled = habit_missed = habit_recovery = habit_unknown = 0
        habit_completed = sum(item.get("status") == "completed" for item in habit_logs)
        habit_skipped = sum(item.get("status") == "skipped" for item in habit_logs)
        known_non_recovery_skips = sum(
            item.get("status") == "skipped"
            and (entry_date := _strict_date(item.get("entry_date"))) is not None
            and daily_modes.get(entry_date) in {"push", "steady", "plan"}
            for item in habit_logs
        )
        recovery_day_outcomes = sum(
            item.get("status") in {"completed", "skipped"}
            and (entry_date := _strict_date(item.get("entry_date"))) is not None
            and daily_modes.get(entry_date) == "recover"
            for item in habit_logs
        )
        if stable and lifecycle == "active":
            outcomes = {
                parsed: item.get("status")
                for item in habit_logs
                if (parsed := _strict_date(item.get("entry_date"))) is not None
            }
            cadence = state.cadence
            if cadence.kind == "weekly_target":
                target = cadence.weekly_target or 0
                habit_scheduled = target
                remaining = max(target - habit_completed - habit_skipped, 0)
                if len(daily_modes) < 7:
                    habit_unknown = remaining
                else:
                    recovery_days = sum(
                        mode == "recover" and entry_date not in outcomes
                        for entry_date, mode in daily_modes.items()
                    )
                    habit_recovery = min(remaining, recovery_days)
                    habit_missed = remaining - habit_recovery
            else:
                for opportunity in _habit_opportunities(
                    period=period,
                    row=row,
                    cadence=cadence,
                ):
                    habit_scheduled += 1
                    outcome = outcomes.get(opportunity)
                    if outcome in {"completed", "skipped"}:
                        continue
                    mode = daily_modes.get(opportunity)
                    if mode is None:
                        habit_unknown += 1
                    elif mode == "recover":
                        habit_recovery += 1
                    else:
                        habit_missed += 1
        scheduled += habit_scheduled
        missed += habit_missed
        recovery_open += habit_recovery
        unknown += habit_unknown
        review = _HabitReview(
            row=row,
            state=state,
            ownership=_habit_ownership(row),
            stable=stable,
            scheduled=habit_scheduled,
            completed=habit_completed,
            skipped=habit_skipped,
            known_non_recovery_skips=known_non_recovery_skips,
            recovery_day_outcomes=recovery_day_outcomes,
            missed=habit_missed,
            recovery_open=habit_recovery,
            unknown=habit_unknown,
            feedback=habit_feedback,
            evidence_refs=tuple(_dedupe_evidence(review_evidence, limit=8)),
        )
        reviews.append(review)
        evidence.extend(review.evidence_refs)
    return (
        WeeklyHabitFacts(
            active=active,
            paused=paused,
            archived=archived,
            stable_definitions=stable_count,
            changed_definitions=changed_count,
            scheduled_opportunities=scheduled,
            completed=completed_total,
            skipped=skipped_total,
            missed=missed,
            recovery_open=recovery_open,
            unknown=unknown,
        ),
        reviews,
        evidence,
    )


def _focus_facts(
    *,
    period: _ReviewPeriod,
    rows: list[dict[str, Any]],
) -> tuple[WeeklyFocusFacts, list[WeeklyReviewEvidenceRef]]:
    counts: Counter[str] = Counter()
    actual_minutes = 0
    evidence: list[WeeklyReviewEvidenceRef] = []
    for row in rows:
        entry_date = _focus_entry_date(row)
        if entry_date is None or not period.starts_on <= entry_date <= period.ends_on:
            continue
        status = row.get("status")
        if status not in {"completed", "abandoned", "active"}:
            continue
        counts[str(status)] += 1
        value = row.get("actual_minutes")
        if isinstance(value, int) and not isinstance(value, bool) and value >= 0:
            actual_minutes += value
        evidence.append(_evidence("focus_sessions", _row_id(row), "status"))
    return (
        WeeklyFocusFacts(
            completed_sessions=counts["completed"],
            abandoned_sessions=counts["abandoned"],
            active_sessions=counts["active"],
            actual_minutes=actual_minutes,
        ),
        evidence,
    )


def _feedback_facts(
    rows: list[dict[str, Any]],
) -> tuple[WeeklyFeedbackFacts, list[WeeklyReviewEvidenceRef]]:
    allowed = {"done", "later", "not_helpful", "too_much", "does_not_fit"}
    counts = Counter(
        str(row["feedback_type"])
        for row in rows
        if row.get("feedback_type") in allowed
    )
    evidence = [
        _evidence("decision_feedback", _row_id(row), "feedback_type")
        for row in rows
        if row.get("feedback_type") in allowed
    ]
    return (
        WeeklyFeedbackFacts(
            total=sum(counts.values()),
            done=counts["done"],
            later=counts["later"],
            not_helpful=counts["not_helpful"],
            too_much=counts["too_much"],
            does_not_fit=counts["does_not_fit"],
        ),
        evidence,
    )


def _daily_modes(
    *,
    period: _ReviewPeriod,
    rows: list[dict[str, Any]],
) -> tuple[dict[date, str], list[WeeklyReviewEvidenceRef]]:
    modes: dict[date, str] = {}
    evidence: list[WeeklyReviewEvidenceRef] = []
    for row in rows:
        period_date = _strict_date(row.get("period_key"))
        summary = row.get("summary")
        state = summary.get("daily_state") if isinstance(summary, dict) else None
        if (
            period_date is None
            or not period.starts_on <= period_date <= period.ends_on
            or not isinstance(state, dict)
            or state.get("contract_version") != "explainable-daily-state-v1"
            or state.get("target_date") != period_date.isoformat()
            or state.get("mode") not in {"push", "steady", "recover", "plan"}
            or state.get("data_quality")
            not in {"missing", "partial", "current", "stale"}
        ):
            continue
        modes[period_date] = str(state["mode"])
        evidence.append(
            _evidence("user_state_snapshots", _row_id(row), "summary.daily_state.mode"),
        )
    return modes, evidence


def _proposals(
    *,
    period: _ReviewPeriod,
    habit_reviews: list[_HabitReview],
    observed_daily_state_days: int,
) -> list[WeeklyReviewProposal]:
    candidates: list[_ProposalCandidate] = []
    for review in habit_reviews:
        if not review.stable:
            continue
        habit_id = _row_id(review.row)
        title = _bounded_title(review.row.get("title"))
        updated_at = _aware_datetime(review.row.get("updated_at"))
        if title is None or updated_at is None:
            continue
        mode = "direct_habit" if review.ownership == "manual" else "settings_setup"
        if review.feedback["does_not_fit"]:
            candidates.append(
                _proposal_candidate(
                    period=period,
                    review=review,
                    title=title,
                    updated_at=updated_at,
                    operation="replace",
                    application_mode="staged_only",
                    after=None,
                    priority=100,
                    reason_code="habit_does_not_fit",
                    reason=(
                        "You marked this habit as not fitting; review a replacement "
                        "without changing it automatically."
                    ),
                ),
            )
            continue
        if (
            review.state.lifecycle == "active"
            and review.completed == 0
            and review.recovery_open == 0
            and review.recovery_day_outcomes == 0
            and (
                review.known_non_recovery_skips >= 2
                or review.feedback["not_helpful"] > 0
            )
        ):
            candidates.append(
                _proposal_candidate(
                    period=period,
                    review=review,
                    title=title,
                    updated_at=updated_at,
                    operation="pause",
                    application_mode=mode,
                    after=WeeklyReviewHabitState(
                        lifecycle="paused",
                        cadence=review.state.cadence,
                    ),
                    priority=90,
                    reason_code="habit_explicitly_skipped_or_not_helpful",
                    reason="Explicit skips or feedback suggest pausing this habit for review.",
                ),
            )
            continue
        cadence = review.state.cadence
        if (
            review.state.lifecycle == "active"
            and cadence.kind == "weekly_target"
            and cadence.weekly_target is not None
            and cadence.weekly_target >= 2
            and observed_daily_state_days == 7
            and review.unknown == 0
            and review.feedback["too_much"] > 0
        ):
            candidates.append(
                _proposal_candidate(
                    period=period,
                    review=review,
                    title=title,
                    updated_at=updated_at,
                    operation="shrink",
                    application_mode=mode,
                    after=WeeklyReviewHabitState(
                        lifecycle="active",
                        cadence=WeeklyReviewHabitCadence(
                            kind="weekly_target",
                            weekly_target=cadence.weekly_target - 1,
                            scheduled_weekdays=[],
                        ),
                    ),
                    priority=80 + min(review.feedback["too_much"], 5),
                    reason_code="habit_weekly_target_too_large",
                    reason=(
                        "A slightly smaller weekly target better matches the explicit "
                        "outcomes and feedback."
                    ),
                ),
            )
            continue
        negative = (
            review.feedback["not_helpful"]
            + review.feedback["too_much"]
            + review.feedback["does_not_fit"]
        )
        if (
            review.state.lifecycle == "active"
            and review.scheduled >= 3
            and review.unknown == 0
            and negative == 0
            and review.completed / review.scheduled >= 0.8
        ):
            candidates.append(
                _proposal_candidate(
                    period=period,
                    review=review,
                    title=title,
                    updated_at=updated_at,
                    operation="keep",
                    application_mode="none",
                    after=review.state,
                    priority=20,
                    reason_code="habit_consistently_completed",
                    reason=(
                        "The scheduled opportunities were completed consistently; "
                        "keeping this habit is reasonable."
                    ),
                ),
            )

    result: list[WeeklyReviewProposal] = []
    direct_selected = False
    for candidate in sorted(
        candidates,
        key=lambda item: (-item.priority, item.proposal.target_id, item.proposal.id),
    ):
        is_direct = candidate.proposal.application_mode == "direct_habit"
        if is_direct and direct_selected:
            continue
        result.append(candidate.proposal)
        direct_selected = direct_selected or is_direct
        if len(result) == 2:
            break
    return result


def _proposal_candidate(
    *,
    period: _ReviewPeriod,
    review: _HabitReview,
    title: str,
    updated_at: datetime,
    operation: str,
    application_mode: str,
    after: WeeklyReviewHabitState | None,
    priority: int,
    reason_code: str,
    reason: str,
) -> _ProposalCandidate:
    habit_id = _row_id(review.row)
    proposal = WeeklyReviewProposal.model_validate(
        {
            "id": f"weekly-review:{period.period_key}:habit:{habit_id}:{operation}",
            "operation": operation,
            "target_kind": "habit",
            "target_id": habit_id,
            "target_title": title,
            "ownership": review.ownership,
            "application_mode": application_mode,
            "expected_updated_at": updated_at,
            "reason_code": reason_code,
            "reason": reason,
            "evidence_refs": list(review.evidence_refs),
            "change": {
                "before": review.state,
                "after": after,
            },
        },
        strict=True,
    )
    return _ProposalCandidate(priority=priority, proposal=proposal)


def _habit_opportunities(
    *,
    period: _ReviewPeriod,
    row: dict[str, Any],
    cadence: WeeklyReviewHabitCadence,
) -> list[date]:
    metadata = row.get("metadata")
    started_on = (
        _strict_date(metadata.get("started_on"))
        if isinstance(metadata, dict)
        else None
    )
    current = max(period.starts_on, started_on or period.starts_on)
    opportunities: list[date] = []
    while current <= period.ends_on:
        if cadence.kind == "daily" or (
            cadence.kind == "weekdays"
            and current.isoweekday() in cadence.scheduled_weekdays
        ):
            opportunities.append(current)
        current += timedelta(days=1)
    return opportunities


def _habit_state(row: dict[str, Any]) -> WeeklyReviewHabitState | None:
    metadata = row.get("metadata") if isinstance(row.get("metadata"), dict) else {}
    setup_state = metadata.get("setup_state")
    lifecycle_value = metadata.get("lifecycle")
    if setup_state == "archived" or lifecycle_value == "archived":
        lifecycle = "archived"
    elif setup_state == "paused" or lifecycle_value == "paused" or row.get("active") is False:
        lifecycle = "paused"
    elif row.get("active") is True:
        lifecycle = "active"
    else:
        return None
    cadence_value = metadata.get("cadence")
    if cadence_value is not None and metadata.get("contract_version") != "habit-v1":
        return None
    try:
        if cadence_value == "weekdays":
            weekdays = metadata.get("scheduled_weekdays")
            cadence = WeeklyReviewHabitCadence(
                kind="weekdays",
                weekly_target=None,
                scheduled_weekdays=weekdays if isinstance(weekdays, list) else [],
            )
        elif cadence_value == "weekly_target" or (
            cadence_value is None and row.get("frequency") == "weekly"
        ):
            target = row.get("target")
            cadence = WeeklyReviewHabitCadence(
                kind="weekly_target",
                weekly_target=(
                    target
                    if isinstance(target, int) and not isinstance(target, bool)
                    else None
                ),
                scheduled_weekdays=[],
            )
        elif cadence_value in {None, "daily"} and row.get("frequency") == "daily":
            cadence = WeeklyReviewHabitCadence(
                kind="daily",
                weekly_target=None,
                scheduled_weekdays=[],
            )
        else:
            return None
    except ValueError:
        return None
    return WeeklyReviewHabitState(lifecycle=lifecycle, cadence=cadence)


def _habit_ownership(row: dict[str, Any]) -> str:
    metadata = row.get("metadata")
    return (
        "setup"
        if isinstance(metadata, dict) and metadata.get("managed_by") == "setup"
        else "manual"
    )


def _habit_feedback(*, habit_id: str, rows: list[dict[str, Any]]) -> Counter[str]:
    return Counter(
        str(row["feedback_type"])
        for row in rows
        if _feedback_matches_habit(row, habit_id)
        and row.get("feedback_type")
        in {"done", "later", "not_helpful", "too_much", "does_not_fit"}
    )


def _feedback_matches_habit(row: dict[str, Any], habit_id: str) -> bool:
    action_id = row.get("action_id")
    return (
        row.get("action_kind") == "habit"
        and isinstance(action_id, str)
        and action_id.startswith(f"log_habit:{habit_id}:")
    )


def _source_fingerprint(
    *,
    period: _ReviewPeriod,
    context: WeeklyReviewContext,
) -> str:
    used_goal_ids = {
        str(metadata["goal_id"])
        for row in context.tasks
        if isinstance((metadata := row.get("metadata")), dict)
        and isinstance(metadata.get("goal_id"), str)
    }
    payload = {
        "period_key": period.period_key,
        "starts_on": period.starts_on.isoformat(),
        "ends_on": period.ends_on.isoformat(),
        "timezone": period.timezone_name,
        "tasks": [_fingerprint_task(row) for row in context.tasks],
        "goals": [
            {"id": row.get("id")}
            for row in context.goals
            if str(row.get("id")) in used_goal_ids
        ],
        "habits": [_fingerprint_habit(row) for row in context.habits],
        "habit_logs": [_fingerprint_habit_log(row) for row in context.habit_logs],
        "focus_sessions": [
            _fingerprint_focus(row)
            for row in context.focus_sessions
            if (
                (entry_date := _focus_entry_date(row)) is not None
                and period.starts_on <= entry_date <= period.ends_on
            )
        ],
        "daily_snapshots": [
            _fingerprint_daily_snapshot(row) for row in context.daily_snapshots
        ],
        "feedback": [_fingerprint_feedback(row) for row in context.feedback],
    }
    canonical = json.dumps(
        _canonical_source(payload),
        sort_keys=True,
        separators=(",", ":"),
        ensure_ascii=True,
    )
    return hashlib.sha256(canonical.encode("utf-8")).hexdigest()


def _fingerprint_task(row: dict[str, Any]) -> dict[str, Any]:
    metadata = row.get("metadata")
    return {
        "id": row.get("id"),
        "status": row.get("status"),
        "deadline": row.get("deadline"),
        "completed_at": row.get("completed_at"),
        "cancelled_at": row.get("cancelled_at"),
        "created_at": row.get("created_at"),
        "goal_id": metadata.get("goal_id") if isinstance(metadata, dict) else None,
    }


def _fingerprint_habit(row: dict[str, Any]) -> dict[str, Any]:
    metadata = row.get("metadata")
    metadata = metadata if isinstance(metadata, dict) else {}
    return {
        "id": row.get("id"),
        "title": row.get("title"),
        "frequency": row.get("frequency"),
        "target": row.get("target"),
        "active": row.get("active"),
        "created_at": row.get("created_at"),
        "updated_at": row.get("updated_at"),
        "metadata": {
            key: metadata.get(key)
            for key in (
                "cadence",
                "scheduled_weekdays",
                "lifecycle",
                "setup_state",
                "managed_by",
                "started_on",
                "contract_version",
            )
        },
    }


def _fingerprint_habit_log(row: dict[str, Any]) -> dict[str, Any]:
    return {
        "id": row.get("id"),
        "habit_id": row.get("habit_id"),
        "entry_date": row.get("entry_date"),
        "status": row.get("status"),
    }


def _fingerprint_focus(row: dict[str, Any]) -> dict[str, Any]:
    metadata = row.get("metadata")
    return {
        "id": row.get("id"),
        "status": row.get("status"),
        "actual_minutes": row.get("actual_minutes"),
        "started_at": row.get("started_at"),
        "entry_date": (
            metadata.get("entry_date") if isinstance(metadata, dict) else None
        ),
    }


def _fingerprint_daily_snapshot(row: dict[str, Any]) -> dict[str, Any]:
    summary = row.get("summary")
    state = summary.get("daily_state") if isinstance(summary, dict) else None
    normalized_state = None
    if isinstance(state, dict):
        normalized_state = {
            "contract_version": state.get("contract_version"),
            "target_date": state.get("target_date"),
            "mode": state.get("mode"),
            "data_quality": state.get("data_quality"),
        }
    return {
        "id": row.get("id"),
        "period_key": row.get("period_key"),
        "daily_state": normalized_state,
    }


def _fingerprint_feedback(row: dict[str, Any]) -> dict[str, Any]:
    return {
        "id": row.get("id"),
        "action_id": row.get("action_id"),
        "action_kind": row.get("action_kind"),
        "feedback_type": row.get("feedback_type"),
        "created_at": row.get("created_at"),
    }


def _canonical_source(value: Any) -> Any:
    if isinstance(value, dict):
        return {
            key: _canonical_source(item)
            for key, item in sorted(value.items())
            if key != "generated_at"
        }
    if isinstance(value, list):
        normalized = [_canonical_source(item) for item in value]
        return sorted(
            normalized,
            key=lambda item: json.dumps(item, sort_keys=True, separators=(",", ":")),
        )
    if isinstance(value, (date, datetime)):
        return value.isoformat()
    return value


def _stale_reasons(
    *,
    review: WeeklyReview,
    period: _ReviewPeriod,
    fingerprint: str,
    snapshot: dict[str, Any] | None,
) -> list[str]:
    reasons: list[str] = []
    provenance = review.provenance
    if provenance.source_fingerprint != fingerprint:
        reasons.append("source_facts_changed")
    if snapshot is None:
        reasons.append("source_snapshot_missing")
    else:
        generated_at = _aware_datetime(snapshot.get("generated_at"))
        if (
            str(snapshot.get("id")) != provenance.source_snapshot_id
            or generated_at != provenance.source_snapshot_generated_at
        ):
            reasons.append("source_snapshot_changed")
    return reasons[:8]


def _narrative(*, facts: WeeklyReviewFacts, proposal_count: int) -> str:
    return (
        f"This week records {facts.tasks.completed} completed and "
        f"{facts.tasks.carried} still-open tasks, {facts.habits.completed} completed "
        f"and {facts.habits.skipped} intentionally skipped habit outcomes, and "
        f"{facts.recovery.recovery_days} observed recovery days. "
        f"{proposal_count} bounded adaptation proposal"
        f"{' is' if proposal_count == 1 else 's are'} available."
    )


def _response(
    *,
    period: _ReviewPeriod,
    freshness: str,
    stale_reasons: list[str],
    review: WeeklyReview | None,
) -> WeeklyReviewReadResponse:
    return WeeklyReviewReadResponse.model_validate(
        {
            "contract_version": WEEKLY_REVIEW_CONTRACT_VERSION,
            "period_key": period.period_key,
            "starts_on": period.starts_on,
            "ends_on": period.ends_on,
            "timezone": period.timezone_name,
            "freshness": freshness,
            "needs_generation": freshness in {"missing", "stale"},
            "stale_reasons": stale_reasons,
            "review": review,
        },
        strict=True,
    )


def _not_ready(period: _ReviewPeriod) -> WeeklyReviewReadResponse:
    return _response(
        period=period,
        freshness="not_ready",
        stale_reasons=[],
        review=None,
    )


def _has_review_evidence(context: WeeklyReviewContext) -> bool:
    return any(
        (
            context.tasks,
            context.habits,
            context.habit_logs,
            context.focus_sessions,
            context.daily_snapshots,
            context.feedback,
        ),
    )


def _period_key(value: date) -> str:
    iso_year, iso_week, _ = value.isocalendar()
    return f"{iso_year}-W{iso_week:02d}"


def _focus_entry_date(row: dict[str, Any]) -> date | None:
    metadata = row.get("metadata")
    if isinstance(metadata, dict):
        parsed = _strict_date(metadata.get("entry_date"))
        if parsed is not None:
            return parsed
    started_at = _aware_datetime(row.get("started_at"))
    return started_at.astimezone(UTC).date() if started_at is not None else None


def _instant_in_period(value: Any, period: _ReviewPeriod) -> bool:
    parsed = _aware_datetime(value)
    return parsed is not None and period.starts_at <= parsed < period.ends_at


def _before_period_end(value: Any, period: _ReviewPeriod) -> bool:
    parsed = _aware_datetime(value)
    return parsed is not None and parsed < period.ends_at


def _date_in_timezone(value: Any, timezone: ZoneInfo) -> date | None:
    parsed = _aware_datetime(value)
    if parsed is not None:
        return parsed.astimezone(timezone).date()
    return _strict_date(value)


def _aware_datetime(value: Any) -> datetime | None:
    if isinstance(value, datetime):
        return value if value.tzinfo is not None else None
    if not isinstance(value, str):
        return None
    try:
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return None
    return parsed if parsed.tzinfo is not None else None


def _strict_date(value: Any) -> date | None:
    if not isinstance(value, str) or re.fullmatch(r"\d{4}-\d{2}-\d{2}", value) is None:
        return None
    try:
        return date.fromisoformat(value)
    except ValueError:
        return None


def _row_id(row: dict[str, Any]) -> str:
    value = row.get("id")
    return str(value) if value is not None else "missing"


def _bounded_title(value: Any) -> str | None:
    if not isinstance(value, str):
        return None
    title = value.strip()
    return title if 1 <= len(title) <= 160 else None


def _evidence(table: str, row_id: str, field: str) -> WeeklyReviewEvidenceRef:
    return WeeklyReviewEvidenceRef(table=table, id=row_id, field=field)


def _dedupe_evidence(
    rows: list[WeeklyReviewEvidenceRef],
    *,
    limit: int,
) -> list[WeeklyReviewEvidenceRef]:
    result: list[WeeklyReviewEvidenceRef] = []
    seen: set[tuple[str, str, str]] = set()
    for row in rows:
        key = (row.table, row.id, row.field)
        if key in seen:
            continue
        seen.add(key)
        result.append(row)
        if len(result) == limit:
            break
    return result


def _utc_now() -> datetime:
    return datetime.now(tz=UTC)
