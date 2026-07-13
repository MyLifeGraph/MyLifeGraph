import asyncio
import hashlib
from collections.abc import Callable
from datetime import UTC, datetime, timedelta
from uuid import UUID
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from app.core.config import Settings
from app.models.coach import (
    COACH_CAPABILITIES_CONTRACT_VERSION,
    COACH_CONTEXT_VERSION,
    COACH_HISTORY_CONTRACT_VERSION,
    COACH_MAX_SELECTED_MEMORIES,
    COACH_MEMORY_SELECTION_CONTRACT_VERSION,
    COACH_PROMPT_VERSION,
    COACH_RESPONSE_CONTRACT_VERSION,
    CoachCapabilitiesResponse,
    CoachErrorDetail,
    CoachHistoryDeleteResponse,
    CoachHistoryResponse,
    CoachHistoryTurn,
    CoachLimits,
    CoachMemory,
    CoachMemorySelectionResponse,
    CoachRequest,
    CoachResponse,
)
from app.providers.base import CoachProvider, CoachProviderError
from app.repositories.coach_context_repository import CoachContextRepository
from app.repositories.coach_repository import (
    CoachPersistenceConflict,
    CoachPersistenceRateLimited,
    CoachRepository,
)
from app.services.coach_context import CoachContextService
from app.services.coach_prompt import build_coach_prompt
from app.services.coach_safety import (
    force_missing_state_uncertainty,
    post_provider_safety,
    pre_provider_safety,
)


_HISTORY_LIMIT = 50
_CLAIM_LEASE_BUFFER_SECONDS = 60


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


class CoachService:
    def __init__(
        self,
        *,
        settings: Settings,
        repository: CoachRepository,
        context_repository: CoachContextRepository,
        context_service: CoachContextService,
        provider: CoachProvider,
        global_semaphore: asyncio.Semaphore,
        now_provider: Callable[[], datetime] | None = None,
    ) -> None:
        self._settings = settings
        self._repository = repository
        self._context_repository = context_repository
        self._context_service = context_service
        self._provider = provider
        self._global_semaphore = global_semaphore
        self._now_provider = now_provider or _utc_now

    async def capabilities(self, *, user_id: str) -> CoachCapabilitiesResponse:
        limit = self._daily_limit
        try:
            profile = await self._context_repository.get_profile(user_id=user_id)
        except Exception:
            return self._unavailable_capabilities(
                reason_code="persistence_unavailable",
                remaining=0,
            )
        self._require_authenticated_account(profile)

        async with self._global_semaphore:
            capability = await self._provider.capability()
        remaining = limit
        if capability.state == "ready":
            try:
                local_date = self._local_date(profile.timezone)
                used = await self._repository.count_usage(
                    user_id=user_id,
                    local_date=local_date,
                )
                remaining = max(0, limit - used)
            except Exception:
                capability = capability.__class__(
                    state="unavailable",
                    provider=capability.provider,
                    provider_mode=capability.provider_mode,
                    model_requested=capability.model_requested,
                    model_source=capability.model_source,
                    reason_code="persistence_unavailable",
                )
                remaining = 0
        return CoachCapabilitiesResponse(
            contract_version=COACH_CAPABILITIES_CONTRACT_VERSION,
            state=capability.state,
            provider=capability.provider,
            provider_mode=capability.provider_mode,
            model_requested=capability.model_requested,
            model_source=capability.model_source,
            reason_code=capability.reason_code,
            limits=self._limits(remaining=remaining),
        )

    async def respond(self, *, user_id: str, request: CoachRequest) -> CoachResponse:
        identity = self._configured_identity()
        profile = await self._eligible_profile(user_id=user_id)
        try:
            local_date = self._local_date(profile.timezone)
        except ValueError as exc:
            raise CoachServiceError(
                "context_failure",
                "Coach could not resolve the owner-scoped local context.",
                retryable=True,
                status_code=503,
            ) from exc

        now = self._now()
        try:
            claim = await self._repository.claim_request(
                user_id=user_id,
                request_id=request.request_id,
                message_fingerprint=hashlib.sha256(
                    request.message.encode("utf-8"),
                ).hexdigest(),
                context_scope=request.context_scope,
                local_date=local_date,
                provider=identity[0],
                provider_mode=identity[1],
                model_requested=identity[2],
                model_source=identity[3],
                prompt_version=COACH_PROMPT_VERSION,
                context_version=COACH_CONTEXT_VERSION,
                claimed_at=now,
                lease_expires_at=now
                + timedelta(
                    seconds=(
                        self._settings.local_codex_timeout_seconds
                        + _CLAIM_LEASE_BUFFER_SECONDS
                    ),
                ),
                daily_limit=self._daily_limit,
            )
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

        if claim.state == "completed":
            assert claim.response is not None
            return claim.response
        if claim.state == "in_progress":
            raise CoachServiceError(
                "in_progress",
                "Another Coach request is already in progress.",
                retryable=True,
                status_code=409,
            )
        if claim.state in {"failed", "deleted"}:
            assert claim.error is not None
            raise _stored_failure(claim.error, deleted=claim.state == "deleted")

        safety = pre_provider_safety(request.message)
        if safety.bypass_provider:
            assert safety.output is not None
            response = self._response(
                request_id=request.request_id,
                output=safety.output,
                used_context=[],
                identity=identity,
                model_reported=None,
                source="deterministic_safety",
                provider_called=False,
            )
            return await self._complete(
                user_id=user_id,
                request=request,
                response=response,
                prompt_bytes=0,
                context_bytes=0,
            )

        async with self._global_semaphore:
            capability = await self._provider.capability()
        if capability.state != "ready":
            code = _capability_failure_code(capability.reason_code)
            await self._record_failure(
                user_id=user_id,
                request_id=request.request_id,
                error=CoachErrorDetail(
                    code=code,
                    message="The configured Coach provider is unavailable.",
                    retryable=code in {"provider_unavailable", "not_logged_in"},
                ),
                provider_called=False,
            )
            raise CoachServiceError(
                code,
                "The configured Coach provider is unavailable.",
                retryable=code in {"provider_unavailable", "not_logged_in"},
                status_code=503,
            )

        try:
            context = await self._context_service.build_today(
                user_id=user_id,
                local_date=local_date,
            )
            prompt = build_coach_prompt(message=request.message, context=context)
        except Exception as exc:
            error = CoachErrorDetail(
                code="context_failure",
                message="Coach could not build its bounded owner-scoped context.",
                retryable=True,
            )
            await self._record_failure(
                user_id=user_id,
                request_id=request.request_id,
                error=error,
                provider_called=False,
            )
            raise CoachServiceError(
                error.code,
                error.message,
                retryable=error.retryable,
                status_code=503,
            ) from exc

        provider_called = False
        try:
            async with self._global_semaphore:
                provider_called = True
                provider_result = await self._provider.respond(prompt=prompt)
            safety_result = post_provider_safety(
                provider_result.output,
                message=request.message,
            )
            output = force_missing_state_uncertainty(
                safety_result.output,
                daily_state_freshness=context.daily_state_freshness,
            )
        except CoachProviderError as exc:
            error = CoachErrorDetail(
                code=_provider_error_code(exc.code),
                message=_provider_error_message(exc.code),
                retryable=exc.retryable,
            )
            await self._record_failure(
                user_id=user_id,
                request_id=request.request_id,
                error=error,
                provider_called=provider_called,
                prompt_bytes=len(prompt.encode("utf-8")),
                context_bytes=context.byte_count,
            )
            raise CoachServiceError(
                error.code,
                error.message,
                retryable=error.retryable,
                status_code=_status_for_code(error.code),
            ) from exc
        except asyncio.CancelledError:
            error = CoachErrorDetail(
                code="interrupted",
                message="The Coach request was interrupted.",
                retryable=True,
            )
            await asyncio.shield(
                self._record_failure(
                    user_id=user_id,
                    request_id=request.request_id,
                    error=error,
                    provider_called=provider_called,
                    prompt_bytes=len(prompt.encode("utf-8")),
                    context_bytes=context.byte_count,
                ),
            )
            raise
        except Exception as exc:
            error = CoachErrorDetail(
                code="provider_failure",
                message="The local Coach provider failed.",
                retryable=True,
            )
            await self._record_failure(
                user_id=user_id,
                request_id=request.request_id,
                error=error,
                provider_called=provider_called,
                prompt_bytes=len(prompt.encode("utf-8")),
                context_bytes=context.byte_count,
            )
            raise CoachServiceError(
                error.code,
                error.message,
                retryable=True,
                status_code=503,
            ) from exc

        response = self._response(
            request_id=request.request_id,
            output=output,
            used_context=context.used_context,
            identity=identity,
            model_reported=provider_result.model_reported,
            source=(
                "deterministic_safety"
                if safety_result.replaced_with_deterministic_safety
                else "model"
            ),
            provider_called=True,
        )
        return await self._complete(
            user_id=user_id,
            request=request,
            response=response,
            prompt_bytes=len(prompt.encode("utf-8")),
            context_bytes=context.byte_count,
        )

    async def history(self, *, user_id: str) -> CoachHistoryResponse:
        await self._eligible_profile(user_id=user_id)
        rows = await self._repository.list_history(
            user_id=user_id,
            limit=_HISTORY_LIMIT,
        )
        return CoachHistoryResponse(
            contract_version=COACH_HISTORY_CONTRACT_VERSION,
            turns=[CoachHistoryTurn.model_validate(row) for row in rows],
        )

    async def delete_history(self, *, user_id: str) -> CoachHistoryDeleteResponse:
        await self._eligible_profile(user_id=user_id)
        try:
            await self._repository.delete_history(
                user_id=user_id,
                deleted_at=self._now(),
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

    async def memories(self, *, user_id: str) -> CoachMemorySelectionResponse:
        await self._eligible_profile(user_id=user_id)
        return await self._memory_selection_response(user_id=user_id)

    async def _memory_selection_response(
        self,
        *,
        user_id: str,
        include_memory_id: UUID | None = None,
    ) -> CoachMemorySelectionResponse:
        result = await self._repository.list_memories(
            user_id=user_id,
            include_memory_id=include_memory_id,
        )
        memories = [_memory_from_row(row) for row in result.rows]
        return CoachMemorySelectionResponse(
            contract_version=COACH_MEMORY_SELECTION_CONTRACT_VERSION,
            max_selected=COACH_MAX_SELECTED_MEMORIES,
            available_count=result.available_count,
            memories=memories,
        )

    async def set_memory_selection(
        self,
        *,
        user_id: str,
        memory_id: UUID,
        selected: bool,
    ) -> CoachMemorySelectionResponse:
        await self._eligible_profile(user_id=user_id)
        result = await self._repository.set_memory_selection(
            user_id=user_id,
            memory_id=memory_id,
            selected=selected,
            changed_at=self._now(),
        )
        if result["state"] == "not_found":
            raise CoachServiceError(
                "context_failure",
                "The memory is unavailable for Coach selection.",
                retryable=False,
                status_code=404,
            )
        if result["state"] == "limit_reached":
            raise CoachServiceError(
                "context_failure",
                "At most eight memories may be selected for Coach context.",
                retryable=False,
                status_code=409,
            )
        return await self._memory_selection_response(
            user_id=user_id,
            include_memory_id=memory_id,
        )

    async def _complete(
        self,
        *,
        user_id: str,
        request: CoachRequest,
        response: CoachResponse,
        prompt_bytes: int,
        context_bytes: int,
    ) -> CoachResponse:
        try:
            return await self._repository.complete_request(
                user_id=user_id,
                request_id=request.request_id,
                user_message=request.message,
                response=response,
                used_context=[
                    item.model_dump(mode="json") for item in response.used_context
                ],
                usage={
                    "provider_called": response.provenance.provider_called,
                    "prompt_bytes": prompt_bytes,
                    "context_bytes": context_bytes,
                    "reply_codepoints": len(response.reply),
                },
                completed_at=self._now(),
            )
        except CoachPersistenceConflict as exc:
            raise CoachServiceError(
                "request_conflict",
                "The Coach response conflicts with persisted request state.",
                retryable=False,
                status_code=409,
            ) from exc
        except Exception as exc:
            # The atomic completion may have committed before its response was
            # lost. Keep the request pending/terminal truth for same-id replay.
            raise CoachServiceError(
                "in_progress",
                "The Coach response could not be confirmed. Retry the same request id.",
                retryable=True,
                status_code=409,
            ) from exc

    async def _record_failure(
        self,
        *,
        user_id: str,
        request_id: UUID,
        error: CoachErrorDetail,
        provider_called: bool,
        prompt_bytes: int = 0,
        context_bytes: int = 0,
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
                failed_at=self._now(),
            )
        except Exception:
            # The atomic failure write may have committed before its response
            # was lost. Force an exact same-id replay so the client cannot
            # silently abandon the persisted or still-leased request identity.
            raise CoachServiceError(
                "in_progress",
                "The Coach failure could not be confirmed. Retry the same request id.",
                retryable=True,
                status_code=409,
            )

    def _response(
        self,
        *,
        request_id: UUID,
        output,
        used_context,
        identity: tuple[str, str, str | None, str],
        model_reported: str | None,
        source: str,
        provider_called: bool,
    ) -> CoachResponse:
        return CoachResponse(
            contract_version=COACH_RESPONSE_CONTRACT_VERSION,
            request_id=request_id,
            reply=output.reply,
            uncertainty=output.uncertainty,
            staged_suggestion=output.staged_suggestion,
            safety=output.safety,
            used_context=used_context,
            provenance={
                "source": source,
                "provider": identity[0],
                "provider_mode": identity[1],
                "model_requested": identity[2],
                "model_reported": model_reported,
                "model_source": identity[3],
                "prompt_version": COACH_PROMPT_VERSION,
                "context_version": COACH_CONTEXT_VERSION,
                "generated_at": self._now(),
                "provider_called": provider_called,
            },
        )

    def _configured_identity(self) -> tuple[str, str, str | None, str]:
        if self._settings.coach_provider == "local_codex_oauth":
            model = self._settings.local_codex_model.strip() or None
            return (
                "local_codex_oauth",
                "local_development_only",
                model,
                "explicit" if model is not None else "cli_default",
            )
        if self._settings.coach_provider == "fake":
            return ("fake", "deterministic_test_only", None, "not_applicable")
        return ("disabled", "disabled", None, "not_applicable")

    async def _eligible_profile(self, *, user_id: str):
        try:
            profile = await self._context_repository.get_profile(user_id=user_id)
        except Exception as exc:
            raise CoachServiceError(
                "context_failure",
                "Coach could not resolve the owner-scoped account profile.",
                retryable=True,
                status_code=503,
            ) from exc
        self._require_authenticated_account(profile)
        return profile

    @staticmethod
    def _require_authenticated_account(profile) -> None:
        if profile.is_eligible_authenticated_account:
            return
        raise CoachServiceError(
            "authenticated_account_required",
            "Coach requires a non-guest authenticated account.",
            retryable=False,
            status_code=403,
        )

    def _unavailable_capabilities(
        self,
        *,
        reason_code: str,
        remaining: int,
    ) -> CoachCapabilitiesResponse:
        identity = self._configured_identity()
        return CoachCapabilitiesResponse(
            contract_version=COACH_CAPABILITIES_CONTRACT_VERSION,
            state="unavailable",
            provider=identity[0],
            provider_mode=identity[1],
            model_requested=identity[2],
            model_source=identity[3],
            reason_code=reason_code,
            limits=self._limits(remaining=remaining),
        )

    def _limits(self, *, remaining: int) -> CoachLimits:
        return CoachLimits(
            message_codepoints=2_000,
            context_bytes=32_768,
            reply_codepoints=4_000,
            timeout_seconds=self._settings.local_codex_timeout_seconds,
            requests_per_local_day=self._daily_limit,
            remaining_requests=remaining,
        )

    @property
    def _daily_limit(self) -> int:
        return self._settings.local_codex_max_requests_per_user_per_day

    def _local_date(self, timezone_name: str):
        try:
            timezone = ZoneInfo(timezone_name)
        except ZoneInfoNotFoundError as exc:
            raise ValueError("Profile timezone is invalid.") from exc
        return self._now().astimezone(timezone).date()

    def _now(self) -> datetime:
        value = self._now_provider()
        if value.tzinfo is None:
            raise ValueError("Coach time must be timezone-aware.")
        return value.astimezone(UTC)


def _memory_from_row(row) -> CoachMemory:
    metadata = row.get("metadata")
    setup_owned = isinstance(metadata, dict) and (
        metadata.get("managed_by") == "setup" or metadata.get("source") == "intake-v1"
    )
    raw_content = row.get("content")
    if not isinstance(raw_content, str):
        raise ValueError("Coach memory content is invalid.")
    content = raw_content.strip()
    if not content:
        raise ValueError("Coach memory content is blank.")
    return CoachMemory(
        id=UUID(str(row.get("id"))),
        type=row.get("type"),
        title=str(row.get("title") or "").strip()[:160],
        content=content[:1_000],
        content_truncated=len(content) > 1_000,
        ownership="setup" if setup_owned else "manual",
        selected=row.get("selected_at") is not None,
        updated_at=_datetime(row.get("updated_at")),
    )


def _datetime(value) -> datetime:
    if not isinstance(value, str):
        raise ValueError("Coach timestamp is invalid.")
    parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    if parsed.tzinfo is None:
        raise ValueError("Coach timestamp lacks a timezone.")
    return parsed


def _stored_failure(error: CoachErrorDetail, *, deleted: bool) -> CoachServiceError:
    return CoachServiceError(
        error.code,
        error.message,
        retryable=False if deleted else error.retryable,
        status_code=410 if deleted else _status_for_code(error.code),
    )


def _capability_failure_code(reason: str) -> str:
    if reason == "provider_disabled":
        return "provider_disabled"
    if reason in {"missing_cli", "not_logged_in", "tool_free_unavailable"}:
        return reason
    return "provider_unavailable"


def _provider_error_code(code: str) -> str:
    allowed = {
        "provider_disabled",
        "provider_unavailable",
        "missing_cli",
        "not_logged_in",
        "unavailable_model",
        "account_limit",
        "timeout",
        "invalid_output",
        "unsafe_provider_event",
        "provider_failure",
        "context_failure",
        "tool_free_unavailable",
    }
    return code if code in allowed else "provider_failure"


def _provider_error_message(code: str) -> str:
    messages = {
        "missing_cli": "The local Codex CLI is unavailable.",
        "not_logged_in": "The local Codex CLI is not authenticated.",
        "unavailable_model": "The explicitly configured Coach model is unavailable.",
        "account_limit": "The local Codex account limit has been reached.",
        "timeout": "The local Coach provider timed out.",
        "invalid_output": "The local Coach provider returned an invalid answer.",
        "unsafe_provider_event": (
            "The local Coach provider attempted an unsupported operation."
        ),
        "tool_free_unavailable": (
            "The local CLI cannot establish a tool-free Coach invocation."
        ),
    }
    return messages.get(code, "The local Coach provider failed.")


def _status_for_code(code: str) -> int:
    if code == "account_limit":
        return 429
    if code == "timeout":
        return 504
    return 503


def _utc_now() -> datetime:
    return datetime.now(UTC)
