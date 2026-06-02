from app.models.recommendations import RecommendationRequest, RecommendationResponse


class RecommendationEngine:
    """Placeholder service boundary for future ML-backed recommendations."""

    async def preview(
        self,
        request: RecommendationRequest,
    ) -> list[RecommendationResponse]:
        return [
            RecommendationResponse(
                id="rec_focus_block",
                title="Protect a 90-minute focus block",
                reason="Your strongest mock signal points to morning focus.",
                action_label="Schedule block",
                category="focus",
                confidence=0.88,
            ),
            RecommendationResponse(
                id="rec_recovery",
                title="Create an earlier wind-down",
                reason="Recovery signals are weaker after late task switching.",
                action_label="Plan wind-down",
                category="recovery",
                confidence=0.79,
            ),
        ]
