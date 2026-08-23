from app.providers.base import (
    CoachActivityCallback,
    CoachAgentProviderResult,
    CoachProviderCapability,
    CoachProviderError,
    CoachProviderResult,
)
from pathlib import Path


class DisabledCoachProvider:
    async def capability(self) -> CoachProviderCapability:
        return CoachProviderCapability(
            state="disabled",
            provider="disabled",
            provider_mode="disabled",
            model_requested=None,
            model_source="not_applicable",
            reason_code="provider_disabled",
        )

    async def respond(self, *, prompt: str) -> CoachProviderResult:
        raise CoachProviderError(
            "provider_disabled",
            "Coach is disabled.",
            retryable=False,
        )

    async def respond_agent(
        self,
        *,
        prompt: str,
        snapshot_path: Path,
        trace_path: Path,
        activity_callback: CoachActivityCallback | None = None,
    ) -> CoachAgentProviderResult:
        del prompt, snapshot_path, trace_path, activity_callback
        raise CoachProviderError(
            "provider_disabled",
            "Coach is disabled.",
            retryable=False,
        )
