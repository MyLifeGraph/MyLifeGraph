from app.providers.base import (
    CoachProviderCapability,
    CoachProviderError,
    CoachProviderResult,
)


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
