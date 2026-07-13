from dataclasses import dataclass
from typing import Protocol

from app.models.coach import (
    CoachCapabilityState,
    CoachModelOutput,
    CoachModelSource,
    CoachProviderMode,
    CoachProviderName,
)


@dataclass(frozen=True)
class CoachProviderCapability:
    state: CoachCapabilityState
    provider: CoachProviderName
    provider_mode: CoachProviderMode
    model_requested: str | None
    model_source: CoachModelSource
    reason_code: str


@dataclass(frozen=True)
class CoachProviderResult:
    output: CoachModelOutput
    model_reported: str | None = None


class CoachProviderError(RuntimeError):
    def __init__(
        self,
        code: str,
        message: str,
        *,
        retryable: bool,
    ) -> None:
        super().__init__(message)
        self.code = code
        self.retryable = retryable


class CoachProvider(Protocol):
    async def capability(self) -> CoachProviderCapability:
        pass

    async def respond(self, *, prompt: str) -> CoachProviderResult:
        pass
