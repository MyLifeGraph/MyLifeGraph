from app.core.config import Settings
from app.models.coach import CoachAgentModelOutput, CoachModelOutput
from app.providers.base import (
    CoachActivityCallback,
    CoachAgentProviderResult,
    CoachProviderCapability,
    CoachProviderError,
    CoachProviderResult,
)
from pathlib import Path


class FakeCoachProvider:
    """Explicit deterministic provider for tests and local browser E2E only."""

    def __init__(self, settings: Settings) -> None:
        self._settings = settings
        self.calls = 0

    async def capability(self) -> CoachProviderCapability:
        ready = (
            self._settings.app_env in {"development", "test"}
            and self._settings.coach_provider == "fake"
            and self._settings.coach_fake_provider_enabled
        )
        return CoachProviderCapability(
            state="ready" if ready else "unavailable",
            provider="fake",
            provider_mode="deterministic_test_only",
            model_requested=None,
            model_source="not_applicable",
            reason_code="ready" if ready else "fake_provider_not_enabled",
        )

    async def respond(self, *, prompt: str) -> CoachProviderResult:
        capability = await self.capability()
        if capability.state != "ready":
            raise CoachProviderError(
                "provider_unavailable",
                "The deterministic Coach test provider is unavailable.",
                retryable=False,
            )
        self.calls += 1
        return CoachProviderResult(
            output=CoachModelOutput(
                reply=(
                    "Your current plan already contains a clear next step. "
                    "Keep it small, then reassess your available capacity."
                ),
                uncertainty={
                    "level": "medium",
                    "reason": "This answer uses only the bounded current context.",
                },
                staged_suggestion={
                    "title": "Protect one small next step",
                    "rationale": (
                        "Review whether one deliberately small action fits the "
                        "capacity you have today."
                    ),
                },
                safety={"classification": "normal"},
            ),
        )

    async def respond_agent(
        self,
        *,
        prompt: str,
        snapshot_path: Path,
        trace_path: Path,
        activity_callback: CoachActivityCallback | None = None,
    ) -> CoachAgentProviderResult:
        del prompt, snapshot_path, trace_path
        capability = await self.capability()
        if capability.state != "ready":
            raise CoachProviderError(
                "provider_unavailable",
                "The deterministic Coach test provider is unavailable.",
                retryable=False,
            )
        self.calls += 1
        if activity_callback is not None:
            await activity_callback("Preparing a direct answer …")
        return CoachAgentProviderResult(
            output=CoachAgentModelOutput(
                reply=(
                    "I can answer freely from the personal data available in this "
                    "local test account. This deterministic reply does not call a "
                    "real model."
                ),
                uncertainty={
                    "level": "medium",
                    "reason": "This is deterministic test-provider output.",
                },
                safety={"classification": "normal"},
            ),
        )
