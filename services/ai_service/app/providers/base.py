from dataclasses import dataclass
from collections.abc import Awaitable, Callable
from pathlib import Path
from typing import Protocol, runtime_checkable
from uuid import UUID

from app.models.coach import (
    CoachAgentModelOutput,
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


@dataclass(frozen=True)
class CoachAgentProviderResult:
    output: CoachAgentModelOutput
    model_reported: str | None = None


CoachActivityCallback = Callable[[str], Awaitable[None]]


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

    async def respond_agent(
        self,
        *,
        prompt: str,
        snapshot_path: Path,
        trace_path: Path,
        activity_callback: CoachActivityCallback | None = None,
    ) -> CoachAgentProviderResult:
        pass


@runtime_checkable
class ReservableCoachProvider(Protocol):
    """Provider whose separate executor owns scarce turn admission."""

    async def capability(self) -> CoachProviderCapability:
        pass

    async def reserve(self) -> UUID:
        pass

    async def release_reservation(self, reservation_id: UUID) -> None:
        pass

    async def respond_agent_reserved(
        self,
        *,
        reservation_id: UUID,
        prompt: str,
        snapshot_path: Path,
        trace_path: Path,
        activity_callback: CoachActivityCallback | None = None,
    ) -> CoachAgentProviderResult:
        pass
