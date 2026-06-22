from datetime import date

from app.models.recommendations import (
    RecommendationGenerateRequest,
    RecommendationGenerateResponse,
    RecommendationListResponse,
)


def current_period_key(today: date | None = None) -> str:
    iso_year, iso_week, _ = (today or date.today()).isocalendar()
    return f"{iso_year}-W{iso_week:02d}"


class RecommendationEngine:
    """Placeholder service boundary for future ML-backed recommendations."""

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
