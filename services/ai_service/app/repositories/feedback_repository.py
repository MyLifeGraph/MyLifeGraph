from datetime import datetime
from typing import Any, Protocol
from uuid import UUID

from app.clients.supabase import SupabaseRestClient
from app.models.feedback import DecisionFeedback


class FeedbackRepository(Protocol):
    async def get_briefing(self, *, user_id: str, briefing_id: UUID) -> dict[str, Any] | None:
        pass

    async def get_recommendation(self, *, user_id: str, recommendation_id: str) -> dict[str, Any] | None:
        pass

    async def get_by_request(self, *, user_id: str, request_id: UUID) -> DecisionFeedback | None:
        pass

    async def insert(self, *, row: dict[str, Any]) -> DecisionFeedback:
        pass

    async def list_recent(self, *, user_id: str, since: datetime, limit: int = 200) -> list[DecisionFeedback]:
        pass

    async def delete(self, *, user_id: str, feedback_id: UUID) -> bool:
        pass


class SupabaseFeedbackRepository:
    def __init__(self, client: SupabaseRestClient) -> None:
        self._client = client

    async def get_briefing(self, *, user_id: str, briefing_id: UUID) -> dict[str, Any] | None:
        rows = await self._client.select(
            "daily_briefings",
            params={"select": "*", "user_id": f"eq.{user_id}", "id": f"eq.{briefing_id}", "limit": "1"},
        )
        return rows[0] if rows else None

    async def get_recommendation(self, *, user_id: str, recommendation_id: str) -> dict[str, Any] | None:
        rows = await self._client.select(
            "recommendations",
            params={"select": "id", "user_id": f"eq.{user_id}", "id": f"eq.{recommendation_id}", "limit": "1"},
        )
        return rows[0] if rows else None

    async def get_by_request(self, *, user_id: str, request_id: UUID) -> DecisionFeedback | None:
        rows = await self._client.select(
            "decision_feedback",
            params={"select": "*", "user_id": f"eq.{user_id}", "request_id": f"eq.{request_id}", "limit": "1"},
        )
        return _feedback(rows[0]) if rows else None

    async def insert(self, *, row: dict[str, Any]) -> DecisionFeedback:
        rows = await self._client.insert("decision_feedback", rows=[row])
        if not rows:
            raise ValueError("Feedback persistence returned no row.")
        return _feedback(rows[0])

    async def list_recent(self, *, user_id: str, since: datetime, limit: int = 200) -> list[DecisionFeedback]:
        rows = await self._client.select(
            "decision_feedback",
            params={
                "select": "*",
                "user_id": f"eq.{user_id}",
                "created_at": f"gte.{since.isoformat()}",
                "order": "created_at.desc,id.desc",
                "limit": str(limit),
            },
        )
        return [_feedback(row) for row in rows]

    async def delete(self, *, user_id: str, feedback_id: UUID) -> bool:
        rows = await self._client.delete(
            "decision_feedback",
            params={"user_id": f"eq.{user_id}", "id": f"eq.{feedback_id}"},
        )
        return bool(rows)


def _feedback(row: dict[str, Any]) -> DecisionFeedback:
    return DecisionFeedback.model_validate(
        {
            "id": UUID(str(row["id"])),
            "request_id": UUID(str(row["request_id"])),
            "briefing_id": UUID(str(row["briefing_id"])),
            "recommendation_id": UUID(str(row["recommendation_id"])) if row.get("recommendation_id") else None,
            "action_id": row["action_id"],
            "action_kind": row["action_kind"],
            "feedback_type": row["feedback_type"],
            "context_mode": row["context_mode"],
            "estimated_minutes": row.get("estimated_minutes"),
            "rule_key": row["rule_key"],
            "created_at": datetime.fromisoformat(str(row["created_at"]).replace("Z", "+00:00")),
        },
        strict=True,
    )
