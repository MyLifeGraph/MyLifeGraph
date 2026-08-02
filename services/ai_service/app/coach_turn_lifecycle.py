from __future__ import annotations

from collections.abc import Awaitable, Callable
from dataclasses import dataclass
from datetime import UTC, date, datetime
from typing import Any, Literal, Protocol, TypeVar
from uuid import UUID
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from app.models.coach import (
    COACH_HISTORY_CONTRACT_VERSION,
    CoachAgentResponse,
    CoachErrorDetail,
    CoachHistoryDeleteResponse,
    CoachResponse,
)


COACH_HISTORY_LIMIT = 50

CoachClaimState = Literal[
    "pending",
    "completed",
    "failed",
    "deleted",
    "in_progress",
]
CoachTurnResponse = CoachResponse | CoachAgentResponse
ResponseT = TypeVar("ResponseT", CoachResponse, CoachAgentResponse)


class CoachPersistenceConflict(RuntimeError):
    pass


class CoachPersistenceRateLimited(RuntimeError):
    pass


class CoachServiceError(RuntimeError):
    def __init__(
        self,
        code: str,
        message: str,
        *,
        retryable: bool,
        status_code: int,
    ) -> None:
        super().__init__(message)
        self.detail = CoachErrorDetail(
            code=code,
            message=message,
            retryable=retryable,
        )
        self.status_code = status_code


@dataclass(frozen=True)
class CoachClaimResult:
    state: CoachClaimState
    remaining_requests: int
    response: CoachTurnResponse | None
    error: CoachErrorDetail | None


class _CoachProfile(Protocol):
    timezone: str

    @property
    def is_eligible_authenticated_account(self) -> bool:
        pass


class _CoachProfileReader(Protocol):
    async def get_profile(self, *, user_id: str) -> _CoachProfile:
        pass


class _CoachTurnRepository(Protocol):
    async def fail_request(
        self,
        *,
        user_id: str,
        request_id: UUID,
        error: CoachErrorDetail,
        usage: dict[str, Any],
        failed_at: datetime,
    ) -> CoachErrorDetail:
        pass

    async def delete_history(self, *, user_id: str, deleted_at: datetime) -> int:
        pass


class CoachTurnLifecycle:
    """Shared persistence lifecycle around the separate Coach orchestrators."""

    def __init__(
        self,
        *,
        repository: _CoachTurnRepository,
        profile_reader: _CoachProfileReader,
        now_provider: Callable[[], datetime],
    ) -> None:
        self._repository = repository
        self._profile_reader = profile_reader
        self._now_provider = now_provider

    async def eligible_profile(self, *, user_id: str) -> _CoachProfile:
        try:
            profile = await self._profile_reader.get_profile(user_id=user_id)
        except Exception as exc:
            raise CoachServiceError(
                "context_failure",
                "Coach could not resolve the owner-scoped account profile.",
                retryable=True,
                status_code=503,
            ) from exc
        self.require_authenticated_account(profile)
        return profile

    @staticmethod
    def require_authenticated_account(profile: _CoachProfile) -> None:
        if profile.is_eligible_authenticated_account:
            return
        raise CoachServiceError(
            "authenticated_account_required",
            "Coach requires a non-guest authenticated account.",
            retryable=False,
            status_code=403,
        )

    async def claim(
        self,
        operation: Awaitable[CoachClaimResult],
        *,
        response_type: type[ResponseT],
        status_for_code: Callable[[str], int],
        completed_mismatch_message: str,
        deleted_error: CoachErrorDetail | None = None,
    ) -> ResponseT | None:
        try:
            claim = await operation
        except CoachPersistenceRateLimited as exc:
            raise CoachServiceError(
                "account_limit",
                "The local Coach request limit has been reached for today.",
                retryable=True,
                status_code=429,
            ) from exc
        except CoachPersistenceConflict as exc:
            raise CoachServiceError(
                "request_conflict",
                "The Coach request id conflicts with an earlier request.",
                retryable=False,
                status_code=409,
            ) from exc

        if claim.state == "pending":
            return None
        if claim.state == "completed":
            if not isinstance(claim.response, response_type):
                raise CoachServiceError(
                    "request_conflict",
                    completed_mismatch_message,
                    retryable=False,
                    status_code=409,
                )
            return claim.response
        if claim.state == "in_progress":
            raise CoachServiceError(
                "in_progress",
                "Another Coach request is already in progress.",
                retryable=True,
                status_code=409,
            )

        assert claim.error is not None
        error = (
            deleted_error if claim.state == "deleted" and deleted_error else claim.error
        )
        raise CoachServiceError(
            error.code,
            error.message,
            retryable=False if claim.state == "deleted" else error.retryable,
            status_code=410
            if claim.state == "deleted"
            else status_for_code(error.code),
        )

    async def complete(self, operation: Awaitable[ResponseT]) -> ResponseT:
        try:
            return await operation
        except CoachPersistenceConflict as exc:
            raise CoachServiceError(
                "request_conflict",
                "The Coach response conflicts with persisted request state.",
                retryable=False,
                status_code=409,
            ) from exc
        except Exception as exc:
            # The atomic completion may have committed before its response was
            # lost. Same-id replay must resolve the persisted terminal truth.
            raise CoachServiceError(
                "in_progress",
                "The Coach response could not be confirmed. Retry the same request id.",
                retryable=True,
                status_code=409,
            ) from exc

    async def record_failure(
        self,
        *,
        user_id: str,
        request_id: UUID,
        error: CoachErrorDetail,
        provider_called: bool,
        prompt_bytes: int = 0,
        context_bytes: int = 0,
        require_confirmation: bool,
    ) -> None:
        try:
            await self._repository.fail_request(
                user_id=user_id,
                request_id=request_id,
                error=error,
                usage={
                    "provider_called": provider_called,
                    "prompt_bytes": prompt_bytes,
                    "context_bytes": context_bytes,
                    "reply_codepoints": 0,
                },
                failed_at=self.now(),
            )
        except Exception as exc:
            if not require_confirmation:
                raise
            # The atomic failure write may have committed before its response
            # was lost. Force exact same-id replay instead of abandoning it.
            raise CoachServiceError(
                "in_progress",
                "The Coach failure could not be confirmed. Retry the same request id.",
                retryable=True,
                status_code=409,
            ) from exc

    async def fail_and_raise(
        self,
        *,
        user_id: str,
        request_id: UUID,
        error: CoachErrorDetail,
        provider_called: bool,
        status_for_code: Callable[[str], int],
        prompt_bytes: int = 0,
        context_bytes: int = 0,
    ) -> None:
        await self.record_failure(
            user_id=user_id,
            request_id=request_id,
            error=error,
            provider_called=provider_called,
            prompt_bytes=prompt_bytes,
            context_bytes=context_bytes,
            require_confirmation=True,
        )
        raise CoachServiceError(
            error.code,
            error.message,
            retryable=error.retryable,
            status_code=status_for_code(error.code),
        )

    async def history_rows(
        self,
        *,
        user_id: str,
        load: Callable[[], Awaitable[list[dict[str, Any]]]],
    ) -> list[dict[str, Any]]:
        await self.eligible_profile(user_id=user_id)
        return await load()

    async def delete_history(self, *, user_id: str) -> CoachHistoryDeleteResponse:
        await self.eligible_profile(user_id=user_id)
        try:
            await self._repository.delete_history(
                user_id=user_id,
                deleted_at=self.now(),
            )
        except CoachPersistenceConflict as exc:
            raise CoachServiceError(
                "in_progress",
                "Coach history cannot be deleted while a request is in progress.",
                retryable=True,
                status_code=409,
            ) from exc
        return CoachHistoryDeleteResponse(
            contract_version=COACH_HISTORY_CONTRACT_VERSION,
            deleted=True,
        )

    def local_date(self, timezone_name: str) -> date:
        try:
            timezone = ZoneInfo(timezone_name)
        except ZoneInfoNotFoundError as exc:
            raise ValueError("Profile timezone is invalid.") from exc
        return self.now().astimezone(timezone).date()

    def now(self) -> datetime:
        value = self._now_provider()
        if value.tzinfo is None:
            raise ValueError("Coach time must be timezone-aware.")
        return value.astimezone(UTC)


def utc_now() -> datetime:
    return datetime.now(UTC)
