from pydantic import BaseModel, Field


class BehavioralSignal(BaseModel):
    signal_type: str = Field(examples=["sleep", "focus", "mood", "movement"])
    value: float
    occurred_at: str
    metadata: dict[str, str | int | float | bool] = Field(default_factory=dict)


class RecommendationRequest(BaseModel):
    user_id: str | None = None
    recent_signals: list[BehavioralSignal] = Field(default_factory=list)


class RecommendationResponse(BaseModel):
    id: str
    title: str
    reason: str
    action_label: str
    category: str
    confidence: float
