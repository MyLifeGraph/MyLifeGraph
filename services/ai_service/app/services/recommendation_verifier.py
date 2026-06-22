from dataclasses import dataclass

from app.models.recommendation_candidates import (
    RecommendationCandidate,
    VerifiedRecommendation,
)


ALLOWED_CATEGORIES = {"focus", "recovery", "movement", "planning"}
ALLOWED_PRIORITIES = {"low", "medium", "high", "critical"}


@dataclass(frozen=True)
class VerificationResult:
    recommendation: VerifiedRecommendation | None
    errors: list[str]

    @property
    def accepted(self) -> bool:
        return self.recommendation is not None and not self.errors


class RecommendationVerifier:
    def verify(
        self,
        candidate: RecommendationCandidate,
        *,
        expected_user_id: str | None = None,
        current_period_key: str | None = None,
        active_fingerprints: set[str] | None = None,
    ) -> VerificationResult:
        errors: list[str] = []

        if expected_user_id is not None and candidate.user_id != expected_user_id:
            errors.append("user_id_mismatch")
        if (
            current_period_key is not None
            and candidate.period_key != current_period_key
        ):
            errors.append("stale_period_key")
        if not candidate.rule_id.strip():
            errors.append("missing_rule_id")
        if candidate.category not in ALLOWED_CATEGORIES:
            errors.append("invalid_category")
        if candidate.priority not in ALLOWED_PRIORITIES:
            errors.append("invalid_priority")
        if not 0 <= candidate.confidence <= 1:
            errors.append("invalid_confidence")
        if not candidate.evidence_refs:
            errors.append("missing_evidence")
        if not candidate.title.strip():
            errors.append("missing_title")
        if not candidate.reason.strip():
            errors.append("missing_reason")
        if not candidate.action_label.strip():
            errors.append("missing_action_label")
        if not candidate.fingerprint:
            errors.append("missing_fingerprint")
        if candidate.model is not None or candidate.model_metadata:
            errors.append("unsupported_model_metadata")
        if (
            candidate.fingerprint
            and active_fingerprints is not None
            and candidate.fingerprint in active_fingerprints
        ):
            errors.append("duplicate_fingerprint")

        if errors:
            return VerificationResult(recommendation=None, errors=errors)

        return VerificationResult(
            recommendation=VerifiedRecommendation(
                candidate=candidate,
                fingerprint=candidate.fingerprint or "",
            ),
            errors=[],
        )
