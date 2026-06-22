import asyncio
from datetime import date, datetime, timedelta, timezone

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
    def __init__(self) -> None:
        self.select_calls = []
        self.insert_calls = []

    async def select(self, table: str, *, params: dict[str, str]):
        self.select_calls.append((table, params))
        if table == "daily_logs":
            return [
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
        if table == "behavioral_events":
            return [
                {
                    "id": "event-1",
                    "event_type": "context_switch",
                    "source": "app",
                    "occurred_at": NOW.isoformat(),
                },
            ]
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


class FakeUserContextRepository:
    async def load_recent_context(
        self,
        *,
        user_id: str,
        window_days: int,
        today: date,
    ) -> SignalSummary:
        return SignalSummary(
            user_id=user_id,
            period_key=current_period_key(today),
            today=today,
            daily_logs=[
                DailyLogSignal(
                    id="log-1",
                    entry_date=today,
                    sleep_hours=5.5,
                ),
                DailyLogSignal(
                    id="log-2",
                    entry_date=today - timedelta(days=1),
                    sleep_hours=5.75,
                ),
            ],
        )


class FakeRecommendationRepository:
    def __init__(self, existing_items: list[RecommendationItem] | None = None) -> None:
        self.items = list(existing_items or [])
        self.persisted = []
        self.list_user_ids = []
        self.fingerprint_user_ids = []
        self.persist_user_ids = []

    async def list_active_recommendations(self, *, user_id: str):
        self.list_user_ids.append(user_id)
        return list(self.items[:20])

    async def list_active_fingerprints_for_user(self, *, user_id: str):
        self.fingerprint_user_ids.append(user_id)
        return {
            item.metadata.fingerprint
            for item in self.items
            if item.metadata.fingerprint
        }

    async def persist_recommendations(self, *, user_id: str, recommendations: list):
        self.persist_user_ids.append(user_id)
        self.persisted.extend(recommendations)
        inserted = [
            item_from_verified(recommendation, f"new-{index}", generated_at=NOW)
            for index, recommendation in enumerate(recommendations, start=1)
        ]
        self.items.extend(inserted)
        return inserted


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
                evidence_ref.as_metadata()
                for evidence_ref in candidate.evidence_refs
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
        "tasks",
    }
    assert all(
        params["user_id"] == "eq.user-test-123"
        for _, params in client.select_calls
    )


def test_recommendation_repository_scopes_reads_and_writes_to_user_id() -> None:
    client = FakeSupabaseClient()
    repository = SupabaseRecommendationRepository(client)

    run(repository.list_active_recommendations(user_id="user-test-123"))
    run(repository.list_active_fingerprints_for_user(user_id="user-test-123"))
    run(
        repository.persist_recommendations(
            user_id="user-test-123",
            recommendations=[verified_recommendation()],
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
                "status": "in.(new,accepted)",
                "order": "generated_at.desc",
            },
        ),
    ]
    assert client.insert_calls[0][0] == "recommendations"
    inserted_row = client.insert_calls[0][1][0]
    assert inserted_row["user_id"] == "user-test-123"
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

    assert repository.persist_user_ids == ["user-test-123"]
    assert repository.fingerprint_user_ids == ["user-test-123"]
    assert len(repository.persisted) == 1
    assert response.needs_generation is False
    assert response.items[0].metadata.model is None
    assert response.items[0].metadata.source_engine_version == "deterministic-v1"


def test_duplicate_fingerprints_reuse_existing_recommendation_without_insert() -> None:
    fingerprint = build_recommendation_fingerprint(
        rule_id="low_recovery_sleep",
        period_key=PERIOD_KEY,
        evidence_refs=[
            EvidenceRef(table="daily_logs", id="log-1", field="sleep_hours"),
            EvidenceRef(table="daily_logs", id="log-2", field="sleep_hours"),
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

    assert repository.persisted == []
    assert [item.id for item in response.items] == ["recommendation-existing"]
    assert response.needs_generation is False


def test_generate_dedupes_against_fingerprints_beyond_display_limit() -> None:
    duplicate_fingerprint = build_recommendation_fingerprint(
        rule_id="low_recovery_sleep",
        period_key=PERIOD_KEY,
        evidence_refs=[
            EvidenceRef(table="daily_logs", id="log-1", field="sleep_hours"),
            EvidenceRef(table="daily_logs", id="log-2", field="sleep_hours"),
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
    )

    response = run(
        engine(repository).generate_recommendations(
            user_id="user-test-123",
            request=type("Request", (), {"window_days": 28})(),
        ),
    )

    assert repository.persisted == []
    assert repository.fingerprint_user_ids == ["user-test-123"]
    assert len(response.items) == 20
    assert [item.id for item in response.items] == [
        f"display-{index}" for index in range(20)
    ]
    assert "duplicate-outside-display-limit" not in {
        item.id for item in response.items
    }


def test_get_returns_needs_generation_true_when_no_current_recommendations() -> None:
    response = run(
        engine(FakeRecommendationRepository()).list_recommendations(
            user_id="user-test-123",
        ),
    )

    assert response.needs_generation is True
    assert response.stale_reason == "missing"


def test_get_returns_needs_generation_false_when_current_recommendations_exist() -> None:
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
