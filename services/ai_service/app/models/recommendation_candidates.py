from dataclasses import dataclass, field

from app.models.recommendations import RecommendationCategory, RecommendationPriority
from app.models.user_context import EvidenceRef


@dataclass(frozen=True)
class DeterministicScores:
    evidence_count: float
    severity: float
    recency: float
    final: float

    def as_metadata(self) -> dict[str, float]:
        return {
            "evidence_count": self.evidence_count,
            "severity": self.severity,
            "recency": self.recency,
            "final": self.final,
        }


@dataclass(frozen=True)
class RecommendationCandidate:
    user_id: str
    rule_id: str
    title: str
    reason: str
    action_label: str
    category: RecommendationCategory | str
    priority: RecommendationPriority | str
    confidence: float
    period_key: str
    evidence_refs: list[EvidenceRef]
    deterministic_scores: DeterministicScores
    invalidation_dependencies: list[str] = field(default_factory=list)
    fingerprint: str | None = None
    source_engine_version: str = "deterministic-v1"
    model: str | None = None
    model_metadata: dict[str, str] = field(default_factory=dict)


@dataclass(frozen=True)
class VerifiedRecommendation:
    candidate: RecommendationCandidate
    fingerprint: str
