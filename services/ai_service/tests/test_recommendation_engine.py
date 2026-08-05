from datetime import date, datetime, timedelta, timezone

from app.models.recommendation_candidates import (
    DeterministicScores,
    RecommendationCandidate,
)
from app.models.user_context import (
    DailyLogSignal,
    EvidenceRef,
    FocusSessionSignal,
    SignalSummary,
    TaskSignal,
    UserStateSnapshotSignal,
)
from app.services.recommendation_engine import RecommendationEngine, current_period_key
from app.services.recommendation_fingerprint import build_recommendation_fingerprint
from app.services.recommendation_verifier import RecommendationVerifier


TODAY = date(2026, 6, 22)
PERIOD_KEY = current_period_key(TODAY)


def summary(
    *,
    daily_logs: list[DailyLogSignal] | None = None,
    focus_sessions: list[FocusSessionSignal] | None = None,
    tasks: list[TaskSignal] | None = None,
    user_state_snapshots: list[UserStateSnapshotSignal] | None = None,
) -> SignalSummary:
    return SignalSummary(
        user_id="user-test-123",
        period_key=PERIOD_KEY,
        today=TODAY,
        daily_logs=daily_logs or [],
        focus_sessions=focus_sessions or [],
        tasks=tasks or [],
        user_state_snapshots=user_state_snapshots or [],
    )


def daily_log(index: int, **kwargs) -> DailyLogSignal:
    return DailyLogSignal(
        id=f"log-{index}",
        entry_date=TODAY - timedelta(days=index),
        **kwargs,
    )


def focus_session(
    index: int,
    *,
    status: str,
    planned_minutes: int = 45,
    actual_minutes: int = 45,
) -> FocusSessionSignal:
    started_at = datetime(
        2026,
        6,
        22 - index,
        8,
        tzinfo=timezone.utc,
    )
    return FocusSessionSignal(
        id=f"focus-{index}",
        local_date=started_at.date(),
        started_at=started_at,
        ended_at=started_at + timedelta(minutes=actual_minutes),
        planned_minutes=planned_minutes,
        actual_minutes=actual_minutes,
        status=status,
    )


def onboarding_snapshot(**overrides) -> UserStateSnapshotSignal:
    values = {
        "id": "snapshot-1",
        "scope": "onboarding",
        "period_key": "onboarding:2026-06-22",
        "summary": {
            "best_energy_window": "morning",
            "existing_habit_count": 0,
            "active_habit_count": 0,
            "fixed_commitment_count": 0,
        },
        "signals": {},
        "generated_at": datetime(2026, 6, 22, tzinfo=timezone.utc),
    }
    values.update(overrides)
    return UserStateSnapshotSignal(**values)


def daily_state_snapshot() -> UserStateSnapshotSignal:
    return UserStateSnapshotSignal(
        id="daily-state-snapshot",
        scope="daily",
        period_key=TODAY.isoformat(),
        summary={
            "daily_state": {
                "contract_version": "explainable-daily-state-v2",
                "mode": "recover",
                "data_quality": "current",
                "risk_flags": ["low_sleep"],
            },
        },
        signals={"daily_state": {"engine": "deterministic"}},
        generated_at=datetime(2026, 6, 22, 8, tzinfo=timezone.utc),
    )


def test_onboarding_snapshot_does_not_create_recommendations() -> None:
    candidates = RecommendationEngine().generate_candidates(
        summary(user_state_snapshots=[onboarding_snapshot()]),
    )

    assert candidates == []


def test_daily_state_snapshot_does_not_change_recommendation_ranking() -> None:
    engine = RecommendationEngine()
    onboarding_only = engine.generate_candidates(
        summary(user_state_snapshots=[onboarding_snapshot()]),
    )
    with_daily_state = engine.generate_candidates(
        summary(
            user_state_snapshots=[daily_state_snapshot(), onboarding_snapshot()],
        ),
    )

    assert with_daily_state == onboarding_only


def test_two_abandons_among_three_terminal_sessions_create_focus_warning() -> None:
    candidates = RecommendationEngine().generate_candidates(
        summary(
            focus_sessions=[
                focus_session(0, status="abandoned", actual_minutes=5),
                focus_session(1, status="abandoned", actual_minutes=10),
                focus_session(
                    2,
                    status="completed",
                    planned_minutes=5,
                    actual_minutes=5,
                ),
            ],
        ),
    )

    focus = next(candidate for candidate in candidates if candidate.category == "focus")
    assert focus.rule_id == "focus_protection"
    assert len(focus.evidence_refs) == 3
    assert focus.reason.startswith("2 of 3 Focus sessions")
    assert all(ref.table == "focus_sessions" for ref in focus.evidence_refs)
    assert focus.fingerprint


def test_valid_sleep_quality_or_target_deviation_create_recovery_recommendation() -> None:
    candidates = RecommendationEngine().generate_candidates(
        summary(
            daily_logs=[
                daily_log(
                    0,
                    sleep_hours=7.5,
                    sleep_quality=4,
                    sleep_target_deviation_minutes=-30,
                    stress=8,
                    energy=3,
                ),
                daily_log(
                    1,
                    sleep_hours=6.5,
                    sleep_quality=7,
                    sleep_target_deviation_minutes=-90,
                    stress=8,
                    energy=3,
                ),
                daily_log(
                    2,
                    sleep_hours=7.0,
                    sleep_quality=8,
                    sleep_target_deviation_minutes=0,
                    stress=7,
                    energy=4,
                ),
            ],
        ),
    )

    recovery_rule_ids = {
        candidate.rule_id
        for candidate in candidates
        if candidate.category == "recovery"
    }
    assert "low_recovery_sleep" in recovery_rule_ids
    assert "high_stress_low_energy" in recovery_rule_ids


def test_sleep_evidence_names_each_days_strongest_trigger() -> None:
    candidate = next(
        candidate
        for candidate in RecommendationEngine().generate_candidates(
            summary(
                daily_logs=[
                    daily_log(
                        0,
                        sleep_quality=4,
                        sleep_target_deviation_minutes=-180,
                    ),
                    daily_log(
                        1,
                        sleep_quality=1,
                        sleep_target_deviation_minutes=-60,
                    ),
                ],
            ),
        )
        if candidate.rule_id == "low_recovery_sleep"
    )

    assert {
        evidence.id: evidence.field for evidence in candidate.evidence_refs
    } == {
        "log-0": "sleep_target_deviation_minutes",
        "log-1": "sleep_quality",
    }


def test_legacy_sleep_hours_alone_do_not_create_sleep_recommendation() -> None:
    candidates = RecommendationEngine().generate_candidates(
        summary(
            daily_logs=[
                daily_log(0, sleep_hours=4.0),
                daily_log(1, sleep_hours=4.5),
                daily_log(2, sleep_hours=5.0),
            ],
        ),
    )

    assert not any(
        candidate.rule_id == "low_recovery_sleep" for candidate in candidates
    )


def test_low_movement_creates_movement_recommendation() -> None:
    candidates = RecommendationEngine().generate_candidates(
        summary(
            daily_logs=[
                daily_log(0, steps=2500),
                daily_log(1, steps=3000),
                daily_log(2, activity_level=1),
            ],
        ),
    )

    movement = next(
        candidate for candidate in candidates if candidate.category == "movement"
    )
    assert movement.rule_id == "movement_nudge"
    assert movement.priority in {"low", "medium"}


def test_movement_evidence_names_each_days_strongest_trigger() -> None:
    movement = next(
        candidate
        for candidate in RecommendationEngine().generate_candidates(
            summary(
                daily_logs=[
                    daily_log(0, steps=3500, activity_level=0),
                    daily_log(1, steps=1000, activity_level=2),
                    daily_log(2, steps=2500, activity_level=2),
                ],
            ),
        )
        if candidate.rule_id == "movement_nudge"
    )

    assert {
        evidence.id: evidence.field for evidence in movement.evidence_refs
    } == {
        "log-0": "activity_level",
        "log-1": "steps",
        "log-2": "steps",
    }


def test_overdue_or_high_workload_creates_planning_recommendation() -> None:
    overdue_candidates = RecommendationEngine().generate_candidates(
        summary(
            tasks=[
                TaskSignal(
                    id="task-overdue",
                    due_date=TODAY - timedelta(days=1),
                ),
            ],
        ),
    )
    workload_candidates = RecommendationEngine().generate_candidates(
        summary(
            tasks=[
                TaskSignal(id="task-1", workload_score=4),
                TaskSignal(id="task-2", workload_score=4),
            ],
        ),
    )

    assert any(
        candidate.rule_id == "planning_reset" for candidate in overdue_candidates
    )
    assert any(
        candidate.rule_id == "planning_reset" for candidate in workload_candidates
    )


def test_terminal_tasks_do_not_create_planning_pressure() -> None:
    terminal_tasks = [
        TaskSignal(
            id=f"task-{status}",
            due_date=TODAY - timedelta(days=2),
            status=status,
            workload_score=5,
        )
        for status in ("done", "cancelled", "archived")
    ]

    candidates = RecommendationEngine().generate_candidates(
        summary(tasks=terminal_tasks),
    )

    assert not any(candidate.rule_id == "planning_reset" for candidate in candidates)
    assert all(not task.is_overdue(TODAY) for task in terminal_tasks)


def test_short_completed_sessions_and_terminal_tasks_do_not_create_focus_warning() -> None:
    candidates = RecommendationEngine().generate_candidates(
        summary(
            focus_sessions=[
                focus_session(
                    0,
                    status="completed",
                    planned_minutes=5,
                    actual_minutes=5,
                ),
                focus_session(
                    1,
                    status="completed",
                    planned_minutes=10,
                    actual_minutes=10,
                ),
                focus_session(
                    2,
                    status="completed",
                    planned_minutes=15,
                    actual_minutes=15,
                ),
            ],
            tasks=[
                TaskSignal(
                    id="task-cancelled",
                    status="cancelled",
                    workload_score=10,
                ),
                TaskSignal(
                    id="task-archived",
                    status="archived",
                    workload_score=10,
                ),
            ],
        ),
    )

    assert not any(candidate.category == "focus" for candidate in candidates)


def test_sparse_evidence_rejects_candidate_or_lowers_confidence() -> None:
    sparse_candidates = RecommendationEngine().generate_candidates(
        summary(daily_logs=[daily_log(0, sleep_quality=2)]),
    )
    stronger_candidates = RecommendationEngine().generate_candidates(
        summary(
            daily_logs=[
                daily_log(0, sleep_quality=2),
                daily_log(1, sleep_target_deviation_minutes=-90),
                daily_log(2, sleep_quality=4),
            ],
        ),
    )

    assert not sparse_candidates
    recovery = next(
        candidate
        for candidate in stronger_candidates
        if candidate.rule_id == "low_recovery_sleep"
    )
    assert recovery.confidence < 1


def test_candidates_are_ranked_by_priority_then_confidence() -> None:
    candidates = RecommendationEngine().generate_candidates(
        summary(
                daily_logs=[
                daily_log(0, sleep_quality=2),
                daily_log(1, sleep_target_deviation_minutes=-120),
                daily_log(2, sleep_quality=3),
            ],
        ),
    )

    assert candidates[0].priority == "high"
    assert candidates[0].rule_id == "low_recovery_sleep"


def test_movement_copy_states_fixed_measurement_thresholds() -> None:
    movement = next(
        candidate
        for candidate in RecommendationEngine().generate_candidates(
            summary(
                daily_logs=[
                    daily_log(0, steps=2500),
                    daily_log(1, steps=3000),
                    daily_log(2, activity_level=1),
                ],
            ),
        )
        if candidate.rule_id == "movement_nudge"
    )

    assert "4,000 steps" in movement.reason
    assert "2/10" in movement.reason
    assert "baseline" not in movement.reason.lower()


def test_duplicate_fingerprint_is_stable() -> None:
    evidence_refs = [
        EvidenceRef(table="daily_logs", id="log-2", field="sleep_hours"),
        EvidenceRef(table="daily_logs", id="log-1", field="sleep_hours"),
    ]

    first = build_recommendation_fingerprint(
        rule_id="low_recovery_sleep",
        period_key=PERIOD_KEY,
        evidence_refs=evidence_refs,
    )
    second = build_recommendation_fingerprint(
        rule_id="low_recovery_sleep",
        period_key=PERIOD_KEY,
        evidence_refs=list(reversed(evidence_refs)),
    )

    assert first == second
    assert first.startswith(f"deterministic-v1:low_recovery_sleep:{PERIOD_KEY}:")


def valid_candidate(**overrides) -> RecommendationCandidate:
    evidence_refs = [EvidenceRef(table="daily_logs", id="log-1", field="sleep_hours")]
    fingerprint = build_recommendation_fingerprint(
        rule_id=overrides.get("rule_id", "low_recovery_sleep"),
        period_key=overrides.get("period_key", PERIOD_KEY),
        evidence_refs=overrides.get("evidence_refs", evidence_refs),
    )
    values = {
        "user_id": "user-test-123",
        "rule_id": "low_recovery_sleep",
        "title": "Protect a sleep recovery window",
        "reason": "Recent sleep logs show repeated short nights.",
        "action_label": "Plan recovery time",
        "category": "recovery",
        "priority": "medium",
        "confidence": 0.72,
        "period_key": PERIOD_KEY,
        "evidence_refs": evidence_refs,
        "deterministic_scores": DeterministicScores(
            evidence_count=1,
            severity=0.5,
            recency=1,
            final=0.72,
        ),
        "fingerprint": fingerprint,
    }
    values.update(overrides)
    return RecommendationCandidate(**values)


def test_verifier_rejects_missing_evidence() -> None:
    result = RecommendationVerifier().verify(
        valid_candidate(evidence_refs=[]),
        expected_user_id="user-test-123",
        current_period_key=PERIOD_KEY,
    )

    assert not result.accepted
    assert "missing_evidence" in result.errors


def test_verifier_rejects_invalid_rule_id() -> None:
    result = RecommendationVerifier().verify(
        valid_candidate(rule_id="future_rule"),
        expected_user_id="user-test-123",
        current_period_key=PERIOD_KEY,
    )

    assert not result.accepted
    assert "invalid_rule_id" in result.errors


def test_verifier_rejects_invalid_category() -> None:
    result = RecommendationVerifier().verify(
        valid_candidate(category="nutrition"),
        expected_user_id="user-test-123",
        current_period_key=PERIOD_KEY,
    )

    assert not result.accepted
    assert "invalid_category" in result.errors


def test_verifier_rejects_confidence_outside_zero_to_one() -> None:
    result = RecommendationVerifier().verify(
        valid_candidate(confidence=1.2),
        expected_user_id="user-test-123",
        current_period_key=PERIOD_KEY,
    )

    assert not result.accepted
    assert "invalid_confidence" in result.errors


def test_verifier_rejects_fingerprint_mismatch() -> None:
    result = RecommendationVerifier().verify(
        valid_candidate(fingerprint="deterministic-v1:wrong:2026-W26:bad"),
        expected_user_id="user-test-123",
        current_period_key=PERIOD_KEY,
    )

    assert not result.accepted
    assert "fingerprint_mismatch" in result.errors


def test_verifier_rejects_missing_fingerprint() -> None:
    result = RecommendationVerifier().verify(
        valid_candidate(fingerprint=None),
        expected_user_id="user-test-123",
        current_period_key=PERIOD_KEY,
    )

    assert not result.accepted
    assert "missing_fingerprint" in result.errors


def test_verifier_rejects_missing_title() -> None:
    result = RecommendationVerifier().verify(
        valid_candidate(title=" "),
        expected_user_id="user-test-123",
        current_period_key=PERIOD_KEY,
    )

    assert not result.accepted
    assert "missing_title" in result.errors


def test_verifier_rejects_missing_reason() -> None:
    result = RecommendationVerifier().verify(
        valid_candidate(reason=" "),
        expected_user_id="user-test-123",
        current_period_key=PERIOD_KEY,
    )

    assert not result.accepted
    assert "missing_reason" in result.errors


def test_verifier_rejects_missing_action_label() -> None:
    result = RecommendationVerifier().verify(
        valid_candidate(action_label=" "),
        expected_user_id="user-test-123",
        current_period_key=PERIOD_KEY,
    )

    assert not result.accepted
    assert "missing_action_label" in result.errors


def test_verifier_rejects_duplicate_active_fingerprint() -> None:
    candidate = valid_candidate()

    result = RecommendationVerifier().verify(
        candidate,
        expected_user_id="user-test-123",
        current_period_key=PERIOD_KEY,
        active_fingerprints={candidate.fingerprint or ""},
    )

    assert not result.accepted
    assert "duplicate_fingerprint" in result.errors


def test_verifier_rejects_stale_period_key() -> None:
    result = RecommendationVerifier().verify(
        valid_candidate(period_key="2026-W25"),
        expected_user_id="user-test-123",
        current_period_key=PERIOD_KEY,
    )

    assert not result.accepted
    assert "stale_period_key" in result.errors


def test_verifier_rejects_unsupported_model_metadata() -> None:
    result = RecommendationVerifier().verify(
        valid_candidate(model="future-model"),
        expected_user_id="user-test-123",
        current_period_key=PERIOD_KEY,
    )

    assert not result.accepted
    assert "unsupported_model_metadata" in result.errors
