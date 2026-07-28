from collections.abc import Callable
from dataclasses import replace
from datetime import date, datetime, timedelta, timezone
from zoneinfo import ZoneInfo

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
from app.models.user_context import DailyLogSignal, EvidenceRef, SignalSummary
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
        self._today_provider = today_provider
        self._now_provider = now_provider or _utc_now

    async def list_recommendations(self, user_id: str) -> RecommendationListResponse:
        if self._recommendation_repository is None:
            raise RuntimeError("Recommendation repository is not configured.")
        today, _ = await self._profile_date(user_id)
        items = await self._recommendation_repository.list_active_recommendations(
            user_id=user_id,
        )
        return _recommendation_response(
            items=items,
            current_period_key=current_period_key(today),
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

        today, timezone_name = await self._profile_date(user_id)
        period_key = current_period_key(today)
        fingerprints = (
            await self._recommendation_repository.list_active_fingerprints_for_user(
                user_id=user_id,
            )
        )
        summary = await self._user_context_repository.load_recent_context(
            user_id=user_id,
            window_days=max(request.window_days, 14),
            today=today,
            timezone_name=timezone_name,
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

        await self._recommendation_repository.replace_new_recommendations(
            user_id=user_id,
            recommendations=verified,
            refreshed_at=self._now_provider(),
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

    async def _profile_date(self, user_id: str) -> tuple[date, str]:
        if self._today_provider is not None:
            return self._today_provider(), "UTC"
        if self._user_context_repository is None:
            raise RuntimeError("User context repository is not configured.")
        timezone_name = await self._user_context_repository.get_profile_timezone(
            user_id=user_id,
        )
        local_now = _ensure_aware(self._now_provider()).astimezone(
            ZoneInfo(timezone_name),
        )
        return local_now.date(), timezone_name

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
        low_recovery_logs = [
            log
            for log in summary.daily_logs
            if (
                log.sleep_quality is not None
                and log.sleep_quality <= 4
            )
            or (
                log.sleep_target_deviation_minutes is not None
                and log.sleep_target_deviation_minutes <= -60
            )
        ]
        if len(low_recovery_logs) < 2:
            return None

        severity = _average(
            max(
                _clamp(
                    (5 - log.sleep_quality) / 4
                    if log.sleep_quality is not None
                    else 0,
                ),
                _clamp(
                    -log.sleep_target_deviation_minutes / 180
                    if log.sleep_target_deviation_minutes is not None
                    else 0,
                ),
            )
            for log in low_recovery_logs
        )
        evidence_refs = [
            EvidenceRef(
                table="daily_logs",
                id=log.id,
                field=_strongest_sleep_trigger(log),
            )
            for log in low_recovery_logs
        ]
        scores = _score(
            evidence_count=len(evidence_refs),
            severity=severity,
            recency=_daily_log_recency(summary, low_recovery_logs),
        )
        return self._candidate(
            summary=summary,
            rule_id=LOW_RECOVERY_SLEEP_RULE_ID,
            title="Protect a sleep recovery window",
            reason=(
                "At least two recent mornings had sleep quality of 4/10 or "
                "lower, or estimated sleep at least 60 minutes below your "
                "stated target."
            ),
            action_label="Plan recovery time",
            category="recovery",
            priority="high" if len(evidence_refs) >= 3 else "medium",
            evidence_refs=evidence_refs,
            scores=scores,
            invalidation_dependencies=[
                "daily_logs.metadata.morning.sleep_quality",
                "daily_logs.metadata.morning.sleep_target_minutes",
                "daily_logs.metadata.morning.estimated_sleep_minutes",
            ],
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
        window_start = summary.today - timedelta(days=13)
        terminal_sessions = [
            session
            for session in summary.focus_sessions
            if window_start <= session.local_date <= summary.today
        ]
        abandoned_sessions = [
            session for session in terminal_sessions if session.status == "abandoned"
        ]
        if len(terminal_sessions) < 3 or len(abandoned_sessions) < 2:
            return None

        evidence_refs = [
            EvidenceRef(table="focus_sessions", id=session.id, field="status")
            for session in terminal_sessions
        ]
        abandonment_rate = len(abandoned_sessions) / len(terminal_sessions)
        scores = _score(
            evidence_count=len(evidence_refs),
            severity=abandonment_rate,
            recency=_focus_session_recency(summary, terminal_sessions),
        )
        priority = "high" if abandonment_rate >= 0.75 else "medium"
        return self._candidate(
            summary=summary,
            rule_id=FOCUS_PROTECTION_RULE_ID,
            title="Protect a focus block",
            reason=(
                f"{len(abandoned_sessions)} of {len(terminal_sessions)} Focus "
                "sessions in the last 14 days were abandoned."
            ),
            action_label="Schedule focus block",
            category="focus",
            priority=priority,
            evidence_refs=evidence_refs,
            scores=scores,
            invalidation_dependencies=["focus_sessions.status"],
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
                field=_strongest_movement_trigger(log),
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
            reason=(
                "At least three measured days had fewer than 4,000 steps or "
                "an activity rating of 2/10 or lower."
            ),
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
            task.workload_score for task in summary.tasks if task.is_active
        )
        planning_events = [
            event
            for event in summary.behavioral_events
            if event.event_type == "missed_planning"
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
                if task.is_active
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


def _strongest_sleep_trigger(log: DailyLogSignal) -> str:
    quality_severity = _clamp(
        (5 - log.sleep_quality) / 4
        if log.sleep_quality is not None and log.sleep_quality <= 4
        else 0,
    )
    shortfall_severity = _clamp(
        -log.sleep_target_deviation_minutes / 180
        if log.sleep_target_deviation_minutes is not None
        and log.sleep_target_deviation_minutes <= -60
        else 0,
    )
    return (
        "sleep_quality"
        if quality_severity >= shortfall_severity
        else "sleep_target_deviation_minutes"
    )


def _strongest_movement_trigger(log: DailyLogSignal) -> str:
    steps_severity = (
        (4000 - min(log.steps, 4000)) / 4000
        if log.steps is not None and log.steps < 4000
        else 0
    )
    activity_severity = (
        (3 - min(log.activity_level, 3)) / 3
        if log.activity_level is not None and log.activity_level <= 2
        else 0
    )
    return "steps" if steps_severity >= activity_severity else "activity_level"


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


def _focus_session_recency(summary: SignalSummary, sessions) -> float:
    session_list = list(sessions)
    if not session_list:
        return 0
    newest = max(session.local_date for session in session_list)
    days_old = max((summary.today - newest).days, 0)
    return _clamp(1 - days_old / 14)


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
