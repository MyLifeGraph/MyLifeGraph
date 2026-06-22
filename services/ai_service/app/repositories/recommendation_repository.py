from datetime import datetime
from typing import Any, Protocol

from app.clients.supabase import SupabaseRestClient
from app.models.recommendation_candidates import VerifiedRecommendation
from app.models.recommendations import (
    RecommendationItem,
    RecommendationMetadata,
)


class RecommendationRepository(Protocol):
    async def list_active_recommendations(
        self,
        *,
        user_id: str,
    ) -> list[RecommendationItem]:
        pass

    async def list_active_fingerprints_for_user(
        self,
        *,
        user_id: str,
    ) -> set[str]:
        pass

    async def persist_recommendations(
        self,
        *,
        user_id: str,
        recommendations: list[VerifiedRecommendation],
    ) -> list[RecommendationItem]:
        pass


class SupabaseRecommendationRepository:
    def __init__(self, client: SupabaseRestClient) -> None:
        self._client = client

    async def list_active_recommendations(
        self,
        *,
        user_id: str,
    ) -> list[RecommendationItem]:
        rows = await self._client.select(
            "recommendations",
            params={
                "select": (
                    "id,title,reason,action_label,category,priority,"
                    "confidence,generated_at,metadata,status"
                ),
                "user_id": f"eq.{user_id}",
                "status": "in.(new,accepted)",
                "order": "generated_at.desc",
                "limit": "20",
            },
        )
        return [_recommendation_item(row) for row in rows]

    async def list_active_fingerprints_for_user(
        self,
        *,
        user_id: str,
    ) -> set[str]:
        rows = await self._client.select(
            "recommendations",
            params={
                "select": "metadata",
                "user_id": f"eq.{user_id}",
                "status": "in.(new,accepted)",
                "order": "generated_at.desc",
            },
        )
        return {
            fingerprint
            for row in rows
            if (fingerprint := _metadata_fingerprint(row.get("metadata")))
        }

    async def persist_recommendations(
        self,
        *,
        user_id: str,
        recommendations: list[VerifiedRecommendation],
    ) -> list[RecommendationItem]:
        rows = [
            _insert_row(user_id=user_id, recommendation=recommendation)
            for recommendation in recommendations
        ]
        inserted = await self._client.insert("recommendations", rows=rows)
        return [_recommendation_item(row) for row in inserted]


def active_fingerprints(items: list[RecommendationItem]) -> set[str]:
    return {
        item.metadata.fingerprint
        for item in items
        if item.metadata.fingerprint
    }


def _metadata_fingerprint(metadata: Any) -> str:
    if not isinstance(metadata, dict):
        return ""
    fingerprint = metadata.get("fingerprint")
    return fingerprint if isinstance(fingerprint, str) else ""


def _insert_row(
    *,
    user_id: str,
    recommendation: VerifiedRecommendation,
) -> dict[str, Any]:
    candidate = recommendation.candidate
    return {
        "user_id": user_id,
        "title": candidate.title,
        "reason": candidate.reason,
        "action_label": candidate.action_label,
        "category": candidate.category,
        "priority": candidate.priority,
        "confidence": candidate.confidence,
        "status": "new",
        "metadata": {
            "rule_id": candidate.rule_id,
            "fingerprint": recommendation.fingerprint,
            "evidence_refs": [
                evidence_ref.as_metadata()
                for evidence_ref in candidate.evidence_refs
            ],
            "period_key": candidate.period_key,
            "source_engine_version": candidate.source_engine_version,
            "invalidation_dependencies": candidate.invalidation_dependencies,
            "deterministic_scores": candidate.deterministic_scores.as_metadata(),
            "model": None,
        },
    }


def _recommendation_item(row: dict[str, Any]) -> RecommendationItem:
    metadata = row.get("metadata")
    metadata = metadata if isinstance(metadata, dict) else {}
    return RecommendationItem(
        id=str(row["id"]),
        title=str(row["title"]),
        reason=str(row["reason"]),
        action_label=str(row["action_label"]),
        category=row["category"],
        priority=row.get("priority") or "medium",
        confidence=float(row["confidence"]),
        generated_at=_parse_datetime(str(row["generated_at"])),
        metadata=RecommendationMetadata(
            rule_id=str(metadata.get("rule_id") or ""),
            fingerprint=str(metadata.get("fingerprint") or ""),
            evidence_refs=list(metadata.get("evidence_refs") or []),
            period_key=str(metadata.get("period_key") or ""),
            source_engine_version=str(metadata.get("source_engine_version") or ""),
            invalidation_dependencies=list(
                metadata.get("invalidation_dependencies") or [],
            ),
            deterministic_scores=dict(metadata.get("deterministic_scores") or {}),
            model=metadata.get("model"),
        ),
    )


def _parse_datetime(value: str) -> datetime:
    normalized = value.replace("Z", "+00:00")
    return datetime.fromisoformat(normalized)
