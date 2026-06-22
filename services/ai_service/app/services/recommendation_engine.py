from dataclasses import replace
from datetime import date

from app.models.recommendation_candidates import (
    DeterministicScores,
    RecommendationCandidate,
)
from app.models.recommendations import (
    RecommendationGenerateRequest,
    RecommendationGenerateResponse,
    RecommendationListResponse,
)
from app.models.user_context import EvidenceRef, SignalSummary
from app.services.recommendation_fingerprint import build_recommendation_fingerprint


def current_period_key(today: date | None = None) -> str:
    iso_year, iso_week, _ = (today or date.today()).isocalendar()
    return f"{iso_year}-W{iso_week:02d}"


class RecommendationEngine:
    """Service boundary for recommendation reads and deterministic v1 candidates."""

    async def list_recommendations(self, user_id: str) -> RecommendationListResponse:
        return RecommendationListResponse(
            items=[],
            needs_generation=True,
            generated_at=None,
            period_key=current_period_key(),
            stale_reason="missing",
        )

    async def generate_recommendations(
        self,
        user_id: str,
        request: RecommendationGenerateRequest,
    ) -> RecommendationGenerateResponse:
        return RecommendationGenerateResponse(
            items=[],
            needs_generation=True,
            generated_at=None,
            period_key=current_period_key(),
            stale_reason="missing",
        )

    def generate_candidates(
        self,
        summary: SignalSummary,
    ) -> list[RecommendationCandidate]:
        candidates = [
            candidate
            for candidate in [
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
            rule_id="low_recovery_sleep",
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
            rule_id="high_stress_low_energy",
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
            rule_id="focus_protection",
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
            rule_id="movement_nudge",
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
            rule_id="planning_reset",
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
