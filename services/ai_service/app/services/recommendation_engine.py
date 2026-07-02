from collections.abc import Callable
from dataclasses import replace
from datetime import date, datetime, timedelta, timezone

from app.models.recommendation_candidates import (
    DeterministicScores,
    RecommendationCandidate,
)
from app.models.recommendations import (
    RecommendationGenerateRequest,
    RecommendationGenerateResponse,
    RecommendationItem,
    RecommendationListResponse,
)
from app.models.user_context import EvidenceRef, SignalSummary
from app.repositories.recommendation_repository import (
    RecommendationRepository,
)
from app.repositories.user_context_repository import UserContextRepository
from app.services.recommendation_fingerprint import build_recommendation_fingerprint
from app.services.recommendation_rules import (
    FOCUS_PROTECTION_RULE_ID,
    HIGH_STRESS_LOW_ENERGY_RULE_ID,
    LOW_RECOVERY_SLEEP_RULE_ID,
    MOVEMENT_NUDGE_RULE_ID,
    PLANNING_RESET_RULE_ID,
)
from app.services.recommendation_verifier import RecommendationVerifier


def current_period_key(today: date | None = None) -> str:
    iso_year, iso_week, _ = (today or date.today()).isocalendar()
    return f"{iso_year}-W{iso_week:02d}"


class RecommendationEngine:
    """Service boundary for recommendation reads and deterministic v1 candidates."""

    def __init__(
        self,
        *,
        user_context_repository: UserContextRepository | None = None,
        recommendation_repository: RecommendationRepository | None = None,
        verifier: RecommendationVerifier | None = None,
        today_provider: Callable[[], date] | None = None,
        now_provider: Callable[[], datetime] | None = None,
    ) -> None:
        self._user_context_repository = user_context_repository
        self._recommendation_repository = recommendation_repository
        self._verifier = verifier or RecommendationVerifier()
        self._today_provider = today_provider or date.today
        self._now_provider = now_provider or _utc_now

    async def list_recommendations(self, user_id: str) -> RecommendationListResponse:
        if self._recommendation_repository is None:
            raise RuntimeError("Recommendation repository is not configured.")
        items = await self._recommendation_repository.list_active_recommendations(
            user_id=user_id,
        )
        return _recommendation_response(
            items=items,
            current_period_key=current_period_key(self._today_provider()),
            now=self._now_provider(),
        )

    async def generate_recommendations(
        self,
        user_id: str,
        request: RecommendationGenerateRequest,
    ) -> RecommendationGenerateResponse:
        if (
            self._user_context_repository is None
            or self._recommendation_repository is None
        ):
            raise RuntimeError("Recommendation repositories are not configured.")

        today = self._today_provider()
        period_key = current_period_key(today)
        fingerprints = (
            await self._recommendation_repository.list_active_fingerprints_for_user(
                user_id=user_id,
            )
        )
        summary = await self._user_context_repository.load_recent_context(
            user_id=user_id,
            window_days=request.window_days,
            today=today,
        )
        verified = []
        for candidate in self.generate_candidates(summary):
            result = self._verifier.verify(
                candidate,
                expected_user_id=user_id,
                current_period_key=period_key,
                active_fingerprints=fingerprints,
            )
            if result.accepted and result.recommendation is not None:
                verified.append(result.recommendation)
                fingerprints.add(result.recommendation.fingerprint)

        if verified:
            await self._recommendation_repository.persist_recommendations(
                user_id=user_id,
                recommendations=verified,
            )

        current_items = (
            await self._recommendation_repository.list_active_recommendations(
                user_id=user_id,
            )
        )
        return _recommendation_response(
            items=current_items,
            current_period_key=period_key,
            now=self._now_provider(),
        )

    def generate_candidates(
        self,
        summary: SignalSummary,
    ) -> list[RecommendationCandidate]:
        candidates = [
            candidate
            for candidate in [
                *self._onboarding_snapshot_candidates(summary),
                self._low_recovery_sleep(summary),
                self._high_stress_low_energy(summary),
                self._focus_protection(summary),
                self._movement_nudge(summary),
                self._planning_reset(summary),
            ]
            if candidate is not None
        ]
        return sorted(
            candidates,
            key=lambda candidate: (
                {"critical": 3, "high": 2, "medium": 1, "low": 0}[candidate.priority],
                candidate.confidence,
                candidate.rule_id,
            ),
            reverse=True,
        )

    def _onboarding_snapshot_candidates(
        self,
        summary: SignalSummary,
    ) -> list[RecommendationCandidate]:
        snapshot = next(
            (
                snapshot
                for snapshot in summary.user_state_snapshots
                if snapshot.scope == "onboarding"
            ),
            None,
        )
        if snapshot is None:
            return []

        focus_areas = _string_set(snapshot.summary.get("primary_focus_areas"))
        goals = _string_list(snapshot.summary.get("goals"))
        friction_points = _string_list(snapshot.summary.get("friction_points"))
        friction_text = " ".join(friction_points).lower()
        candidates: list[RecommendationCandidate] = []

        if "focus" in focus_areas or _contains_any(
            friction_text,
            {"context", "switch", "interrupt", "distract", "focus"},
        ):
            candidates.append(
                self._candidate(
                    summary=summary,
                    rule_id=FOCUS_PROTECTION_RULE_ID,
                    title="Protect your first focus block",
                    reason=(
                        "Your intake points to focus as an early coaching area."
                    ),
                    action_label="Schedule focus block",
                    category="focus",
                    priority="medium",
                    evidence_refs=[
                        EvidenceRef(
                            table="user_state_snapshots",
                            id=snapshot.id,
                            field="summary.primary_focus_areas",
                        ),
                    ],
                    scores=_score(
                        evidence_count=1 + min(len(friction_points), 3),
                        severity=0.55,
                        recency=1,
                    ),
                    invalidation_dependencies=[
                        "user_state_snapshots.summary.primary_focus_areas",
                        "user_state_snapshots.summary.friction_points",
                    ],
                ),
            )

        if "planning" in focus_areas or _contains_any(
            friction_text,
            {"plan", "priorit", "overwhelm", "deadline", "too much"},
        ):
            candidates.append(
                self._candidate(
                    summary=summary,
                    rule_id=PLANNING_RESET_RULE_ID,
                    title="Set a simple first plan",
                    reason=(
                        "Your intake suggests a short planning pass would help "
                        "turn goals into next actions."
                    ),
                    action_label="Review priorities",
                    category="planning",
                    priority="medium",
                    evidence_refs=[
                        EvidenceRef(
                            table="user_state_snapshots",
                            id=snapshot.id,
                            field="summary.goals",
                        ),
                    ],
                    scores=_score(
                        evidence_count=max(1, min(len(goals), 3)),
                        severity=0.5,
                        recency=1,
                    ),
                    invalidation_dependencies=[
                        "user_state_snapshots.summary.goals",
                        "user_state_snapshots.summary.friction_points",
                    ],
                ),
            )

        if {"sleep", "stress", "energy"} & focus_areas:
            candidates.append(
                self._candidate(
                    summary=summary,
                    rule_id=LOW_RECOVERY_SLEEP_RULE_ID,
                    title="Protect a recovery window",
                    reason=(
                        "Your intake marked recovery-related signals as a "
                        "coaching focus."
                    ),
                    action_label="Plan recovery time",
                    category="recovery",
                    priority="medium",
                    evidence_refs=[
                        EvidenceRef(
                            table="user_state_snapshots",
                            id=snapshot.id,
                            field="summary.primary_focus_areas",
                        ),
                    ],
                    scores=_score(
                        evidence_count=len({"sleep", "stress", "energy"} & focus_areas),
                        severity=0.5,
                        recency=1,
                    ),
                    invalidation_dependencies=[
                        "user_state_snapshots.summary.primary_focus_areas",
                    ],
                ),
            )

        if "movement" in focus_areas:
            candidates.append(
                self._candidate(
                    summary=summary,
                    rule_id=MOVEMENT_NUDGE_RULE_ID,
                    title="Add a small movement reset",
                    reason="Your intake marked movement as a coaching focus.",
                    action_label="Take a short walk",
                    category="movement",
                    priority="low",
                    evidence_refs=[
                        EvidenceRef(
                            table="user_state_snapshots",
                            id=snapshot.id,
                            field="summary.primary_focus_areas",
                        ),
                    ],
                    scores=_score(
                        evidence_count=1,
                        severity=0.4,
                        recency=1,
                    ),
                    invalidation_dependencies=[
                        "user_state_snapshots.summary.primary_focus_areas",
                    ],
                ),
            )

        return candidates

    def _candidate(
        self,
        *,
        summary: SignalSummary,
        rule_id: str,
        title: str,
        reason: str,
        action_label: str,
        category: str,
        priority: str,
        evidence_refs: list[EvidenceRef],
        scores: DeterministicScores,
        invalidation_dependencies: list[str],
    ) -> RecommendationCandidate:
        candidate = RecommendationCandidate(
            user_id=summary.user_id,
            rule_id=rule_id,
            title=title,
            reason=reason,
            action_label=action_label,
            category=category,
            priority=priority,
            confidence=scores.final,
            period_key=summary.period_key,
            evidence_refs=evidence_refs,
            deterministic_scores=scores,
            invalidation_dependencies=invalidation_dependencies,
        )
        fingerprint = build_recommendation_fingerprint(
            rule_id=rule_id,
            period_key=summary.period_key,
            evidence_refs=evidence_refs,
            source_engine_version=candidate.source_engine_version,
        )
        return replace(candidate, fingerprint=fingerprint)

    def _low_recovery_sleep(
        self,
        summary: SignalSummary,
    ) -> RecommendationCandidate | None:
        threshold = 6.5
        low_sleep_logs = [
            log
            for log in summary.daily_logs
            if log.sleep_hours is not None and log.sleep_hours < threshold
        ]
        if len(low_sleep_logs) < 2:
            return None

        severity = _average(
            min((threshold - (log.sleep_hours or threshold)) / threshold, 1)
            for log in low_sleep_logs
        )
        evidence_refs = [
            EvidenceRef(table="daily_logs", id=log.id, field="sleep_hours")
            for log in low_sleep_logs
        ]
        scores = _score(
            evidence_count=len(evidence_refs),
            severity=severity,
            recency=_daily_log_recency(summary, low_sleep_logs),
        )
        return self._candidate(
            summary=summary,
            rule_id=LOW_RECOVERY_SLEEP_RULE_ID,
            title="Protect a sleep recovery window",
            reason="Recent sleep logs show repeated short nights.",
            action_label="Plan recovery time",
            category="recovery",
            priority="high" if len(evidence_refs) >= 3 else "medium",
            evidence_refs=evidence_refs,
            scores=scores,
            invalidation_dependencies=["daily_logs.sleep_hours"],
        )

    def _high_stress_low_energy(
        self,
        summary: SignalSummary,
    ) -> RecommendationCandidate | None:
        matching_logs = [
            log
            for log in summary.daily_logs
            if log.stress is not None
            and log.energy is not None
            and log.stress >= 7
            and log.energy <= 4
        ]
        measured_logs = [
            log
            for log in summary.daily_logs
            if log.stress is not None and log.energy is not None
        ]
        average_crosses_threshold = (
            len(measured_logs) >= 3
            and _average(log.stress or 0 for log in measured_logs) >= 7
            and _average(log.energy or 0 for log in measured_logs) <= 4
        )
        if len(matching_logs) < 3 and not average_crosses_threshold:
            return None

        evidence_logs = matching_logs if len(matching_logs) >= 3 else measured_logs
        average_stress = _average(log.stress or 0 for log in evidence_logs)
        average_energy = _average(log.energy or 0 for log in evidence_logs)
        severity = _clamp(((average_stress - 6) / 4 + (5 - average_energy) / 5) / 2)
        evidence_refs = [
            EvidenceRef(table="daily_logs", id=log.id, field="stress")
            for log in evidence_logs
        ] + [
            EvidenceRef(table="daily_logs", id=log.id, field="energy")
            for log in evidence_logs
        ]
        scores = _score(
            evidence_count=len(evidence_logs),
            severity=severity,
            recency=_daily_log_recency(summary, evidence_logs),
        )
        return self._candidate(
            summary=summary,
            rule_id=HIGH_STRESS_LOW_ENERGY_RULE_ID,
            title="Lower the load before adding more",
            reason="Recent check-ins show stress running high while energy is low.",
            action_label="Choose one recovery action",
            category="recovery",
            priority="high" if average_stress >= 8 else "medium",
            evidence_refs=evidence_refs,
            scores=scores,
            invalidation_dependencies=["daily_logs.stress", "daily_logs.energy"],
        )

    def _focus_protection(
        self,
        summary: SignalSummary,
    ) -> RecommendationCandidate | None:
        low_focus_logs = [
            log
            for log in summary.daily_logs
            if log.focus_minutes is not None and log.focus_minutes < 60
        ]
        switch_events = [
            event
            for event in summary.behavioral_events
            if event.event_type in {"context_switch", "interruption", "task_switch"}
        ]
        if len(low_focus_logs) < 2 and len(switch_events) < 3:
            return None

        evidence_refs = [
            EvidenceRef(table="daily_logs", id=log.id, field="focus_minutes")
            for log in low_focus_logs
        ] + [
            EvidenceRef(table="behavioral_events", id=event.id, field="event_type")
            for event in switch_events
        ]
        focus_severity = _average(
            (60 - min(log.focus_minutes or 60, 60)) / 60 for log in low_focus_logs
        )
        workload_pressure = _clamp(
            sum(
                task.workload_score
                for task in summary.tasks
                if task.status != "done"
            )
            / 10,
        )
        scores = _score(
            evidence_count=len(evidence_refs),
            severity=max(focus_severity, workload_pressure),
            recency=max(
                _daily_log_recency(summary, low_focus_logs),
                _event_recency(summary, switch_events),
            ),
        )
        priority = "high" if workload_pressure >= 0.8 else "medium"
        return self._candidate(
            summary=summary,
            rule_id=FOCUS_PROTECTION_RULE_ID,
            title="Protect a focus block",
            reason="Recent signals suggest focused time is getting squeezed.",
            action_label="Schedule focus block",
            category="focus",
            priority=priority,
            evidence_refs=evidence_refs,
            scores=scores,
            invalidation_dependencies=[
                "daily_logs.focus_minutes",
                "behavioral_events.event_type",
                "tasks.workload_score",
            ],
        )

    def _movement_nudge(
        self,
        summary: SignalSummary,
    ) -> RecommendationCandidate | None:
        low_movement_logs = [
            log
            for log in summary.daily_logs
            if (log.steps is not None and log.steps < 4000)
            or (log.activity_level is not None and log.activity_level <= 2)
        ]
        if len(low_movement_logs) < 3:
            return None

        severity = _average(
            max(
                (4000 - min(log.steps or 4000, 4000)) / 4000
                if log.steps is not None
                else 0,
                (3 - min(log.activity_level or 3, 3)) / 3
                if log.activity_level is not None
                else 0,
            )
            for log in low_movement_logs
        )
        evidence_refs = [
            EvidenceRef(
                table="daily_logs",
                id=log.id,
                field="steps" if log.steps is not None else "activity_level",
            )
            for log in low_movement_logs
        ]
        scores = _score(
            evidence_count=len(evidence_refs),
            severity=severity,
            recency=_daily_log_recency(summary, low_movement_logs),
        )
        return self._candidate(
            summary=summary,
            rule_id=MOVEMENT_NUDGE_RULE_ID,
            title="Add a small movement reset",
            reason="Recent activity signals are below your usual baseline.",
            action_label="Take a short walk",
            category="movement",
            priority="medium" if severity >= 0.5 else "low",
            evidence_refs=evidence_refs,
            scores=scores,
            invalidation_dependencies=["daily_logs.steps", "daily_logs.activity_level"],
        )

    def _planning_reset(
        self,
        summary: SignalSummary,
    ) -> RecommendationCandidate | None:
        overdue_tasks = [
            task for task in summary.tasks if task.is_overdue(summary.today)
        ]
        active_workload = sum(
            task.workload_score for task in summary.tasks if task.status != "done"
        )
        planning_events = [
            event
            for event in summary.behavioral_events
            if event.event_type in {"planning_friction", "missed_planning"}
        ]
        if not overdue_tasks and active_workload < 8 and len(planning_events) < 2:
            return None

        evidence_refs = [
            EvidenceRef(table="tasks", id=task.id, field="due_date")
            for task in overdue_tasks
        ] + [
            EvidenceRef(table="behavioral_events", id=event.id, field="event_type")
            for event in planning_events
        ]
        if active_workload >= 8 and not evidence_refs:
            evidence_refs = [
                EvidenceRef(table="tasks", id=task.id, field="workload_score")
                for task in summary.tasks
                if task.status != "done"
            ]
        severity = max(
            _clamp(len(overdue_tasks) / 3),
            _clamp(active_workload / 12),
            _clamp(len(planning_events) / 4),
        )
        scores = _score(
            evidence_count=len(evidence_refs),
            severity=severity,
            recency=max(
                _task_recency(summary, overdue_tasks),
                _event_recency(summary, planning_events),
                0.7 if active_workload >= 8 else 0,
            ),
        )
        return self._candidate(
            summary=summary,
            rule_id=PLANNING_RESET_RULE_ID,
            title="Reset the plan for this week",
            reason=(
                "Your current workload signals would benefit from a short "
                "planning pass."
            ),
            action_label="Review priorities",
            category="planning",
            priority="medium",
            evidence_refs=evidence_refs,
            scores=scores,
            invalidation_dependencies=[
                "tasks.due_date",
                "tasks.workload_score",
                "behavioral_events.event_type",
            ],
        )


def _score(
    *,
    evidence_count: int,
    severity: float,
    recency: float,
) -> DeterministicScores:
    evidence_score = min(evidence_count / 4, 1)
    final = _clamp(0.45 * evidence_score + 0.35 * severity + 0.20 * recency)
    return DeterministicScores(
        evidence_count=float(evidence_count),
        severity=round(_clamp(severity), 4),
        recency=round(_clamp(recency), 4),
        final=round(final, 4),
    )


def _average(values) -> float:
    value_list = list(values)
    if not value_list:
        return 0
    return sum(value_list) / len(value_list)


def _string_list(value: object) -> list[str]:
    if not isinstance(value, list):
        return []
    return [item.strip() for item in value if isinstance(item, str) and item.strip()]


def _string_set(value: object) -> set[str]:
    return {item.lower() for item in _string_list(value)}


def _contains_any(value: str, needles: set[str]) -> bool:
    return any(needle in value for needle in needles)


def _clamp(value: float) -> float:
    return min(max(value, 0), 1)


def _daily_log_recency(summary: SignalSummary, logs) -> float:
    log_list = list(logs)
    if not log_list:
        return 0
    newest = max(log.entry_date for log in log_list)
    days_old = max((summary.today - newest).days, 0)
    return _clamp(1 - days_old / 7)


def _event_recency(summary: SignalSummary, events) -> float:
    event_list = list(events)
    if not event_list:
        return 0
    newest = max(event.occurred_at.date() for event in event_list)
    days_old = max((summary.today - newest).days, 0)
    return _clamp(1 - days_old / 7)


def _task_recency(summary: SignalSummary, tasks) -> float:
    task_list = [task for task in tasks if task.due_date is not None]
    if not task_list:
        return 0
    newest_due_date = max(task.due_date for task in task_list if task.due_date)
    days_old = max((summary.today - newest_due_date).days, 0)
    return _clamp(1 - days_old / 7)


def _recommendation_response(
    *,
    items: list[RecommendationItem],
    current_period_key: str,
    now: datetime,
) -> RecommendationListResponse:
    newest_generated_at = max((item.generated_at for item in items), default=None)
    stale_reason = _stale_reason(
        items=items,
        generated_at=newest_generated_at,
        current_period_key=current_period_key,
        now=now,
    )
    return RecommendationListResponse(
        items=items,
        needs_generation=stale_reason is not None,
        generated_at=newest_generated_at,
        period_key=current_period_key,
        stale_reason=stale_reason,
    )


def _stale_reason(
    *,
    items: list[RecommendationItem],
    generated_at: datetime | None,
    current_period_key: str,
    now: datetime,
) -> str | None:
    if not items or generated_at is None:
        return "missing"
    if any(item.metadata.period_key != current_period_key for item in items):
        return "period_mismatch"
    if _ensure_aware(now) - _ensure_aware(generated_at) > timedelta(days=7):
        return "older_than_7_days"
    return None


def _utc_now() -> datetime:
    return datetime.now(timezone.utc)


def _ensure_aware(value: datetime) -> datetime:
    if value.tzinfo is None:
        return value.replace(tzinfo=timezone.utc)
    return value
