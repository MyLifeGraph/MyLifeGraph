import asyncio
from datetime import date, datetime, timedelta, timezone

import pytest

from app.models.recommendation_candidates import (
    DeterministicScores,
    RecommendationCandidate,
    VerifiedRecommendation,
)
from app.models.recommendations import RecommendationItem, RecommendationMetadata
from app.models.user_context import DailyLogSignal, EvidenceRef, SignalSummary
from app.repositories.recommendation_repository import SupabaseRecommendationRepository
from app.repositories.user_context_repository import SupabaseUserContextRepository
from app.services.recommendation_engine import RecommendationEngine, current_period_key
from app.services.recommendation_fingerprint import build_recommendation_fingerprint


TODAY = date(2026, 6, 22)
PERIOD_KEY = current_period_key(TODAY)
NOW = datetime(2026, 6, 22, 12, tzinfo=timezone.utc)


class FakeSupabaseClient:
    def __init__(
        self,
        *,
        daily_rows: list[dict] | None = None,
        profile_timezone: str = "Europe/Berlin",
    ) -> None:
        self.daily_rows = daily_rows
        self.profile_timezone = profile_timezone
        self.select_calls = []
        self.insert_calls = []
        self.rpc_calls = []

    async def select(self, table: str, *, params: dict[str, str]):
        self.select_calls.append((table, params))
        if table == "daily_logs":
            return (
                self.daily_rows
                if self.daily_rows is not None
                else [
                    {
                        "id": "log-1",
                        "entry_date": TODAY.isoformat(),
                        "sleep_hours": 5.5,
                        "steps": 2000,
                        "activity_level": 1,
                        "focus_minutes": 25,
                        "energy_level": 3,
                        "stress_level": 8,
                    },
                ]
            )
        if table == "behavioral_events":
            return [
                {
                    "id": "event-1",
                    "event_type": "context_switch",
                    "source": "app",
                    "occurred_at": NOW.isoformat(),
                },
            ]
        if table == "focus_sessions":
            return []
        if table == "profiles":
            return [{"timezone": self.profile_timezone}]
        if table == "tasks":
            return [
                {
                    "id": "task-1",
                    "deadline": NOW.isoformat(),
                    "status": "todo",
                    "priority": "high",
                    "metadata": {},
                },
            ]
        if table == "user_state_snapshots":
            return [
                {
                    "id": "snapshot-1",
                    "scope": "onboarding",
                    "period_key": "onboarding:2026-06-22",
                    "summary": {
                        "primary_focus_areas": ["focus"],
                        "goals": ["Protect focus time"],
                        "friction_points": ["Too many context switches"],
                    },
                    "signals": {},
                    "generated_at": NOW.isoformat(),
                },
            ]
        if table == "recommendations":
            return []
        raise AssertionError(f"Unexpected table: {table}")

    async def insert(self, table: str, *, rows: list[dict]):
        self.insert_calls.append((table, rows))
        return [
            {
                **row,
                "id": f"recommendation-{index}",
                "generated_at": NOW.isoformat(),
            }
            for index, row in enumerate(rows, start=1)
        ]

    async def rpc(self, function: str, *, params: dict):
        self.rpc_calls.append((function, params))
        return {
            "contract_version": "recommendation-refresh-v2",
            "archived_count": 0,
            "inserted_count": len(params["p_rows"]),
            "refreshed_at": params["p_refreshed_at"],
        }


class FakeUserContextRepository:
    async def get_profile_timezone(self, *, user_id: str) -> str:
        return "UTC"

    async def load_recent_context(
        self,
        *,
        user_id: str,
        window_days: int,
        today: date,
        timezone_name: str = "UTC",
    ) -> SignalSummary:
        return SignalSummary(
            user_id=user_id,
            period_key=current_period_key(today),
            today=today,
            daily_logs=[
                DailyLogSignal(
                    id="log-1",
                    entry_date=today,
                    sleep_quality=3,
                ),
                DailyLogSignal(
                    id="log-2",
                    entry_date=today - timedelta(days=1),
                    sleep_target_deviation_minutes=-90,
                ),
            ],
        )


class FakeRecommendationRepository:
    def __init__(
        self,
        existing_items: list[RecommendationItem] | None = None,
        *,
        accepted_item_ids: set[str] | None = None,
    ) -> None:
        self.items = list(existing_items or [])
        self.accepted_item_ids = set(accepted_item_ids or set())
        self.persisted = []
        self.list_user_ids = []
        self.fingerprint_user_ids = []
        self.replace_calls = []

    async def list_active_recommendations(self, *, user_id: str):
        self.list_user_ids.append(user_id)
        return list(self.items[:20])

    async def list_active_fingerprints_for_user(self, *, user_id: str):
        self.fingerprint_user_ids.append(user_id)
        return {
            item.metadata.fingerprint
            for item in self.items
            if item.id in self.accepted_item_ids
            if item.metadata.fingerprint
        }

    async def replace_new_recommendations(
        self,
        *,
        user_id: str,
        recommendations: list,
        refreshed_at: datetime,
    ):
        self.replace_calls.append((user_id, refreshed_at, list(recommendations)))
        self.persisted.extend(recommendations)
        accepted = [item for item in self.items if item.id in self.accepted_item_ids]
        inserted = [
            item_from_verified(
                recommendation,
                f"new-{index}",
                generated_at=refreshed_at,
            )
            for index, recommendation in enumerate(recommendations, start=1)
        ]
        self.items = [*inserted, *accepted]


def run(coro):
    return asyncio.run(coro)


def item_from_verified(recommendation, item_id: str, generated_at: datetime):
    candidate = recommendation.candidate
    return RecommendationItem(
        id=item_id,
        title=candidate.title,
        reason=candidate.reason,
        action_label=candidate.action_label,
        category=candidate.category,
        priority=candidate.priority,
        confidence=candidate.confidence,
        generated_at=generated_at,
        metadata=RecommendationMetadata(
            rule_id=candidate.rule_id,
            fingerprint=recommendation.fingerprint,
            evidence_refs=[
                evidence_ref.as_metadata() for evidence_ref in candidate.evidence_refs
            ],
            period_key=candidate.period_key,
            source_engine_version=candidate.source_engine_version,
            invalidation_dependencies=candidate.invalidation_dependencies,
            deterministic_scores=candidate.deterministic_scores.as_metadata(),
            model=None,
        ),
    )


def recommendation_item(
    *,
    item_id: str = "recommendation-existing",
    fingerprint: str = "fingerprint-current",
    generated_at: datetime = NOW,
    period_key: str = PERIOD_KEY,
) -> RecommendationItem:
    return RecommendationItem(
        id=item_id,
        title="Protect a sleep recovery window",
        reason="Recent sleep logs show repeated short nights.",
        action_label="Plan recovery time",
        category="recovery",
        priority="medium",
        confidence=0.72,
        generated_at=generated_at,
        metadata=RecommendationMetadata(
            rule_id="low_recovery_sleep",
            fingerprint=fingerprint,
            evidence_refs=[
                {"table": "daily_logs", "id": "log-1", "field": "sleep_hours"},
            ],
            period_key=period_key,
            source_engine_version="deterministic-v1",
            invalidation_dependencies=["daily_logs.sleep_hours"],
            deterministic_scores={"final": 0.72},
            model=None,
        ),
    )


def verified_recommendation() -> VerifiedRecommendation:
    evidence_refs = [
        EvidenceRef(table="daily_logs", id="log-1", field="sleep_hours"),
    ]
    candidate = RecommendationCandidate(
        user_id="user-test-123",
        rule_id="low_recovery_sleep",
        title="Protect a sleep recovery window",
        reason="Recent sleep logs show repeated short nights.",
        action_label="Plan recovery time",
        category="recovery",
        priority="medium",
        confidence=0.72,
        period_key=PERIOD_KEY,
        evidence_refs=evidence_refs,
        deterministic_scores=DeterministicScores(
            evidence_count=1,
            severity=0.5,
            recency=1,
            final=0.72,
        ),
        fingerprint=build_recommendation_fingerprint(
            rule_id="low_recovery_sleep",
            period_key=PERIOD_KEY,
            evidence_refs=evidence_refs,
        ),
    )
    return VerifiedRecommendation(
        candidate=candidate,
        fingerprint=candidate.fingerprint or "",
    )


def engine(
    recommendation_repository: FakeRecommendationRepository,
) -> RecommendationEngine:
    return RecommendationEngine(
        user_context_repository=FakeUserContextRepository(),
        recommendation_repository=recommendation_repository,
        today_provider=lambda: TODAY,
        now_provider=lambda: NOW,
    )


def test_user_context_repository_scopes_every_read_to_explicit_user_id() -> None:
    client = FakeSupabaseClient()
    context = run(
        SupabaseUserContextRepository(client).load_recent_context(
            user_id="user-test-123",
            window_days=28,
            today=TODAY,
        ),
    )

    assert context.user_id == "user-test-123"
    assert {table for table, _ in client.select_calls} == {
        "daily_logs",
        "behavioral_events",
        "focus_sessions",
        "tasks",
    }
    assert all(
        params["user_id"] == "eq.user-test-123" for _, params in client.select_calls
    )


@pytest.mark.parametrize(
    ("container_version", "branch_version"),
    (
        ("daily-capture-v4", "daily-capture-v4"),
        ("daily-capture-v5", "daily-capture-v5"),
        ("daily-capture-v5", "daily-capture-v4"),
    ),
)
def test_recommendation_context_uses_shared_sleep_and_profile_timezone(
    container_version: str,
    branch_version: str,
) -> None:
    client = FakeSupabaseClient(
        daily_rows=[
            {
                "id": "log-v4",
                "entry_date": "2026-03-30",
                "sleep_hours": 2.0,
                "steps": None,
                "activity_level": None,
                "focus_minutes": None,
                "energy_level": None,
                "stress_level": None,
                "metadata": {
                    "capture_version": container_version,
                    "captures": {
                        "morning": {
                            "branch_version": branch_version,
                            **(
                                {"compatibility": True}
                                if branch_version != container_version
                                else {}
                            ),
                            "capture_kind": "morning",
                            "entry_date": "2026-03-30",
                            "capture_id": "morning-1",
                            "captured_at": "2026-03-30T06:45:00+02:00",
                            "estimated_sleep_started_at": "2026-03-29T23:00:00+02:00",
                            "woke_at": "2026-03-30T06:30:00+02:00",
                            "estimated_sleep_minutes": 450,
                            "sleep_target_minutes": 510,
                            "sleep_hours": 7.5,
                            "sleep_quality": 4,
                            "current_energy": 5,
                            **(
                                {"day_shape": "normal"}
                                if branch_version == "daily-capture-v4"
                                else {}
                            ),
                            "source_evening_capture_id": "evening-1",
                        },
                    },
                },
            },
        ],
    )
    repository = SupabaseUserContextRepository(client)

    timezone_name = run(
        repository.get_profile_timezone(user_id="user-test-123"),
    )
    context = run(
        repository.load_recent_context(
            user_id="user-test-123",
            window_days=2,
            today=date(2026, 3, 30),
            timezone_name=timezone_name,
        ),
    )

    assert timezone_name == "Europe/Berlin"
    assert context.timezone_name == "Europe/Berlin"
    sleep = context.daily_logs[0]
    assert sleep.sleep_hours == 7.5
    assert sleep.sleep_quality == 4
    assert sleep.sleep_target_deviation_minutes == -60
    focus_query = next(
        params for table, params in client.select_calls if table == "focus_sessions"
    )
    assert focus_query["started_at"] == "gte.2026-03-28T23:00:00+00:00"


def test_recommendation_context_excludes_future_daily_logs() -> None:
    client = FakeSupabaseClient(
        daily_rows=[
            {
                "id": "future-log",
                "entry_date": "2026-03-31",
                "sleep_hours": 4.0,
                "steps": 1000,
                "activity_level": 1,
                "focus_minutes": None,
                "energy_level": None,
                "stress_level": None,
                "metadata": {},
            },
            {
                "id": "today-log",
                "entry_date": "2026-03-30",
                "sleep_hours": None,
                "steps": 5000,
                "activity_level": 5,
                "focus_minutes": None,
                "energy_level": None,
                "stress_level": None,
                "metadata": {},
            },
        ],
    )

    context = run(
        SupabaseUserContextRepository(client).load_recent_context(
            user_id="user-test-123",
            window_days=2,
            today=date(2026, 3, 30),
            timezone_name="Europe/Berlin",
        ),
    )

    assert [log.id for log in context.daily_logs] == ["today-log"]
    query = next(
        params for table, params in client.select_calls if table == "daily_logs"
    )
    assert query["and"] == "(entry_date.lte.2026-03-30)"


def test_recommendation_period_uses_profile_local_date() -> None:
    class LosAngelesContext(FakeUserContextRepository):
        async def get_profile_timezone(self, *, user_id: str) -> str:
            return "America/Los_Angeles"

    local_boundary_now = datetime(2026, 6, 22, 0, 30, tzinfo=timezone.utc)
    response = run(
        RecommendationEngine(
            user_context_repository=LosAngelesContext(),
            recommendation_repository=FakeRecommendationRepository(),
            now_provider=lambda: local_boundary_now,
        ).list_recommendations(user_id="user-test-123"),
    )

    assert response.period_key == "2026-W25"


def test_recommendation_repository_scopes_reads_and_atomic_refresh_to_user_id() -> None:
    client = FakeSupabaseClient()
    repository = SupabaseRecommendationRepository(client)

    run(repository.list_active_recommendations(user_id="user-test-123"))
    run(repository.list_active_fingerprints_for_user(user_id="user-test-123"))
    run(
        repository.replace_new_recommendations(
            user_id="user-test-123",
            recommendations=[verified_recommendation()],
            refreshed_at=NOW,
        ),
    )

    assert client.select_calls == [
        (
            "recommendations",
            {
                "select": (
                    "id,title,reason,action_label,category,priority,"
                    "confidence,generated_at,metadata,status"
                ),
                "user_id": "eq.user-test-123",
                "status": "in.(new,accepted)",
                "order": "generated_at.desc",
                "limit": "20",
            },
        ),
        (
            "recommendations",
            {
                "select": "metadata",
                "user_id": "eq.user-test-123",
                "status": "eq.accepted",
                "order": "generated_at.desc",
            },
        ),
    ]
    assert client.insert_calls == []
    assert client.rpc_calls[0][0] == "replace_current_recommendations_v2"
    rpc_params = client.rpc_calls[0][1]
    assert rpc_params["p_user_id"] == "user-test-123"
    assert rpc_params["p_refreshed_at"] == NOW.isoformat()
    inserted_row = rpc_params["p_rows"][0]
    assert inserted_row["metadata"] == {
        "rule_id": "low_recovery_sleep",
        "fingerprint": verified_recommendation().fingerprint,
        "evidence_refs": [
            {"table": "daily_logs", "id": "log-1", "field": "sleep_hours"},
        ],
        "period_key": PERIOD_KEY,
        "source_engine_version": "deterministic-v1",
        "invalidation_dependencies": [],
        "deterministic_scores": {
            "evidence_count": 1,
            "severity": 0.5,
            "recency": 1,
            "final": 0.72,
        },
        "model": None,
    }


def test_generate_flow_persists_only_verified_recommendations() -> None:
    repository = FakeRecommendationRepository()

    response = run(
        engine(repository).generate_recommendations(
            user_id="user-test-123",
            request=type("Request", (), {"window_days": 28})(),
        ),
    )

    assert [call[0] for call in repository.replace_calls] == ["user-test-123"]
    assert repository.replace_calls[0][1] == NOW
    assert repository.fingerprint_user_ids == ["user-test-123"]
    assert len(repository.persisted) == 1
    assert response.needs_generation is False
    assert response.items[0].metadata.model is None
    assert response.items[0].metadata.source_engine_version == "deterministic-v1"


def test_refresh_replaces_unhandled_new_card_even_when_fingerprint_matches() -> None:
    fingerprint = build_recommendation_fingerprint(
        rule_id="low_recovery_sleep",
        period_key=PERIOD_KEY,
        evidence_refs=[
            EvidenceRef(table="daily_logs", id="log-1", field="sleep_quality"),
            EvidenceRef(
                table="daily_logs",
                id="log-2",
                field="sleep_target_deviation_minutes",
            ),
        ],
    )
    repository = FakeRecommendationRepository(
        [recommendation_item(fingerprint=fingerprint)],
    )

    response = run(
        engine(repository).generate_recommendations(
            user_id="user-test-123",
            request=type("Request", (), {"window_days": 28})(),
        ),
    )

    assert len(repository.persisted) == 1
    assert [item.id for item in response.items] == ["new-1"]
    assert response.needs_generation is False


def test_generate_dedupes_against_accepted_fingerprint_beyond_display_limit() -> None:
    duplicate_fingerprint = build_recommendation_fingerprint(
        rule_id="low_recovery_sleep",
        period_key=PERIOD_KEY,
        evidence_refs=[
            EvidenceRef(table="daily_logs", id="log-1", field="sleep_quality"),
            EvidenceRef(
                table="daily_logs",
                id="log-2",
                field="sleep_target_deviation_minutes",
            ),
        ],
    )
    display_items = [
        recommendation_item(
            item_id=f"display-{index}",
            fingerprint=f"display-fingerprint-{index}",
            generated_at=NOW - timedelta(minutes=index),
        )
        for index in range(20)
    ]
    repository = FakeRecommendationRepository(
        [
            *display_items,
            recommendation_item(
                item_id="duplicate-outside-display-limit",
                fingerprint=duplicate_fingerprint,
                generated_at=NOW - timedelta(days=2),
            ),
        ],
        accepted_item_ids={"duplicate-outside-display-limit"},
    )

    response = run(
        engine(repository).generate_recommendations(
            user_id="user-test-123",
            request=type("Request", (), {"window_days": 28})(),
        ),
    )

    assert repository.persisted == []
    assert repository.fingerprint_user_ids == ["user-test-123"]
    assert [item.id for item in response.items] == ["duplicate-outside-display-limit"]


def test_empty_verified_refresh_retires_previous_new_feed() -> None:
    repository = FakeRecommendationRepository(
        [recommendation_item(item_id="stale-new")],
    )
    context_repository = FakeUserContextRepository()

    async def empty_context(**kwargs):
        return SignalSummary(
            user_id=kwargs["user_id"],
            period_key=PERIOD_KEY,
            today=kwargs["today"],
        )

    context_repository.load_recent_context = empty_context  # type: ignore[method-assign]
    refresh_engine = RecommendationEngine(
        user_context_repository=context_repository,
        recommendation_repository=repository,
        today_provider=lambda: TODAY,
        now_provider=lambda: NOW,
    )

    response = run(
        refresh_engine.generate_recommendations(
            user_id="user-test-123",
            request=type("Request", (), {"window_days": 28})(),
        ),
    )

    assert repository.replace_calls
    assert repository.persisted == []
    assert repository.items == []
    assert response.items == []
    assert response.needs_generation is True


def test_get_returns_needs_generation_true_when_no_current_recommendations() -> None:
    response = run(
        engine(FakeRecommendationRepository()).list_recommendations(
            user_id="user-test-123",
        ),
    )

    assert response.needs_generation is True
    assert response.stale_reason == "missing"


def test_get_returns_current_recommendations_without_generation_needed() -> None:
    response = run(
        engine(
            FakeRecommendationRepository([recommendation_item()]),
        ).list_recommendations(user_id="user-test-123"),
    )

    assert response.needs_generation is False
    assert response.stale_reason is None


def test_get_returns_period_mismatch_for_stale_period() -> None:
    response = run(
        engine(
            FakeRecommendationRepository(
                [recommendation_item(period_key="2026-W25")],
            ),
        ).list_recommendations(user_id="user-test-123"),
    )

    assert response.needs_generation is True
    assert response.stale_reason == "period_mismatch"


def test_get_returns_older_than_7_days_for_old_recommendations() -> None:
    response = run(
        engine(
            FakeRecommendationRepository(
                [recommendation_item(generated_at=NOW - timedelta(days=8))],
            ),
        ).list_recommendations(user_id="user-test-123"),
    )

    assert response.needs_generation is True
    assert response.stale_reason == "older_than_7_days"


def test_no_llm_model_metadata_is_persisted() -> None:
    repository = FakeRecommendationRepository()

    run(
        engine(repository).generate_recommendations(
            user_id="user-test-123",
            request=type("Request", (), {"window_days": 28})(),
        ),
    )

    assert repository.items[0].metadata.model is None
    assert "model" not in repository.items[0].metadata.deterministic_scores
