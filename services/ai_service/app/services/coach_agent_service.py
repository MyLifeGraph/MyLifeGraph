import asyncio
import hashlib
import json
import logging
from contextlib import asynccontextmanager
from collections.abc import Callable
from dataclasses import dataclass
from datetime import date, datetime, timedelta
from pathlib import Path
from typing import Any
from uuid import UUID, uuid5

from app.coach_turn_lifecycle import (
    COACH_HISTORY_LIMIT,
    CoachClaimResult,
    CoachServiceError,
    CoachTurnLifecycle,
    CoachPersistenceRateLimited,
    utc_now,
)
from app.core.config import Settings
from app.models.coach import (
    COACH_AGENT_CONTEXT_VERSION,
    COACH_AGENT_PROMPT_VERSION,
    COACH_AGENT_REQUESTS_PER_LOCAL_DAY,
    COACH_AGENT_TIMEOUT_SECONDS,
    COACH_CAPABILITIES_V5_CONTRACT_VERSION,
    COACH_HISTORY_V4_CONTRACT_VERSION,
    COACH_OPERATOR_REQUESTS_PER_LOCAL_DAY,
    COACH_OPERATOR_REQUESTS_PER_UTC_DAY,
    COACH_RESPONSE_V3_CONTRACT_VERSION,
    COACH_RESPONSE_V4_CONTRACT_VERSION,
    CoachAgentCapabilitiesResponse,
    CoachAgentEvidence,
    CoachAgentHistoryResponse,
    CoachAgentHistoryTurn,
    CoachAgentLimits,
    CoachAgentModelOutput,
    CoachAgentRequest,
    CoachAgentResponse,
    CoachAgentTrace,
    CoachAgentTraceStep,
    CoachErrorDetail,
    CoachHistoryDeleteResponse,
    CoachModelOutput,
)
from app.providers.base import (
    CoachActivityCallback,
    CoachProvider,
    CoachProviderError,
    ReservableCoachProvider,
)
from app.providers.cloud_byok import CloudByokCoachProvider
from app.repositories.coach_context_repository import CoachContextRepository
from app.repositories.coach_repository import CoachRepository
from app.services.coach_agent_prompt import build_coach_agent_prompt
from app.services.coach_safety import (
    CoachSafetyDecision,
    post_provider_safety,
    pre_provider_safety,
)
from app.services.coach_snapshot import (
    CoachSnapshotCleanupError,
    CoachSnapshotService,
    CoachSnapshotTooLargeError,
    PreparedCoachSnapshot,
)


_LEASE_SECONDS = COACH_AGENT_TIMEOUT_SECONDS + 60
_CAPABILITY_SLOT_TIMEOUT_SECONDS = 1
_CAPABILITY_PROBE_TIMEOUT_SECONDS = 15
_TURN_ADMISSION_TIMEOUT_SECONDS = 1
_OPERATOR_DISPATCH_NAMESPACE = UUID("96bcaa7b-cb52-4d87-9c9e-02b62a3db87e")
_LOGGER = logging.getLogger(__name__)


@dataclass(slots=True)
class PreparedCoachTurn:
    """One-use, service-owned result of pre-stream Coach admission."""

    owner: object
    user_id: str
    request_id: UUID
    message_fingerprint: str
    local_date: date | None
    identity: tuple[str, str, str | None, str]
    safety: CoachSafetyDecision
    semaphore: asyncio.Semaphore
    slot_acquired: bool
    reservation_provider: ReservableCoachProvider | None = None
    reservation_id: UUID | None = None
    dispatch_id: UUID | None = None
    terminal_replay: CoachAgentResponse | None = None
    consumed: bool = False

    def consume(
        self, *, owner: object, user_id: str, request: CoachAgentRequest
    ) -> None:
        if self.owner is not owner or self.consumed:
            raise RuntimeError("Coach turn preparation is invalid or already consumed.")
        if (
            self.user_id != user_id
            or self.request_id != request.request_id
            or self.message_fingerprint
            != hashlib.sha256(request.message.encode("utf-8")).hexdigest()
        ):
            raise RuntimeError("Coach turn preparation does not match the request.")
        self.consumed = True

    @asynccontextmanager
    async def provider_scope(self):
        if not self.slot_acquired and self.reservation_id is None:
            raise RuntimeError("Provider work requires an admitted Coach slot.")
        yield

    async def release(self) -> None:
        if self.slot_acquired:
            self.slot_acquired = False
            self.semaphore.release()
        provider = self.reservation_provider
        reservation_id = self.reservation_id
        self.reservation_provider = None
        self.reservation_id = None
        if provider is not None and reservation_id is not None:
            await provider.release_reservation(reservation_id)


@dataclass(slots=True)
class _CoachUserActivity:
    blocked_users: set[str]
    active_tasks: dict[str, set[asyncio.Task[Any]]]


class CoachAgentService:
    def __init__(
        self,
        *,
        settings: Settings,
        repository: CoachRepository,
        context_repository: CoachContextRepository,
        snapshot_service: CoachSnapshotService,
        provider: CoachProvider,
        global_semaphore: asyncio.Semaphore,
        now_provider: Callable[[], datetime] | None = None,
        lifecycle: CoachTurnLifecycle | None = None,
        identity_override: tuple[str, str, str | None, str] | None = None,
        operator_provider: ReservableCoachProvider | None = None,
        pre_admission_error: CoachServiceError | None = None,
        user_activity: _CoachUserActivity | None = None,
    ) -> None:
        self._settings = settings
        self._repository = repository
        self._context_repository = context_repository
        self._snapshot_service = snapshot_service
        self._provider = provider
        self._global_semaphore = global_semaphore
        self._preparation_owner = object()
        self._lifecycle = lifecycle or CoachTurnLifecycle(
            repository=repository,
            profile_reader=context_repository,
            now_provider=now_provider or utc_now,
        )
        self._identity_override = identity_override
        self._operator_provider = operator_provider
        self._pre_admission_error = pre_admission_error
        self._user_activity = user_activity or _CoachUserActivity(set(), {})

    def with_request_provider(
        self,
        *,
        provider: CoachProvider,
        identity: tuple[str, str, str | None, str],
        pre_admission_error: CoachServiceError | None = None,
    ) -> "CoachAgentService":
        return CoachAgentService(
            settings=self._settings,
            repository=self._repository,
            context_repository=self._context_repository,
            snapshot_service=self._snapshot_service,
            provider=provider,
            global_semaphore=self._global_semaphore,
            lifecycle=self._lifecycle,
            identity_override=identity,
            operator_provider=self._operator_provider,
            pre_admission_error=pre_admission_error,
            user_activity=self._user_activity,
        )

    def for_operator_request(self) -> "CoachAgentService":
        pre_admission_error: CoachServiceError | None = None
        if (
            not self._settings.operator_codex_pilot_enabled
            or self._settings.normalized_app_env not in {"staging", "pilot"}
        ):
            pre_admission_error = CoachServiceError(
                "provider_disabled",
                "The shared pilot Coach provider is not enabled.",
                retryable=False,
                status_code=503,
            )
        elif self._operator_provider is None:
            pre_admission_error = CoachServiceError(
                "provider_unavailable",
                "The shared pilot Coach provider is unavailable.",
                retryable=True,
                status_code=503,
            )
        return self.with_request_provider(
            provider=self._operator_provider or self._provider,
            identity=(
                "operator_codex_pilot",
                "operator_subscription_pilot",
                self._settings.coach_operator_model,
                "explicit",
            ),
            pre_admission_error=pre_admission_error,
        )

    @property
    def requires_explicit_provider(self) -> bool:
        return self._settings.is_hosted_environment

    async def reconcile_startup(self) -> int:
        if not self._settings.operator_codex_pilot_enabled:
            return 0
        return await self._repository.reconcile_operator_dispatches(
            reconciled_at=self._lifecycle.now(),
        )

    async def block_user_and_cancel(self, *, user_id: str) -> None:
        self._user_activity.blocked_users.add(user_id)
        current = asyncio.current_task()
        tasks = [
            task
            for task in self._user_activity.active_tasks.get(user_id, set())
            if task is not current and not task.done()
        ]
        for task in tasks:
            task.cancel()
        if tasks:
            await asyncio.gather(*tasks, return_exceptions=True)

    def _require_user_not_blocked(self, user_id: str) -> None:
        if user_id in self._user_activity.blocked_users:
            raise CoachServiceError(
                "account_deletion_pending",
                "Coach is unavailable while account deletion is pending.",
                retryable=False,
                status_code=423,
            )

    def for_byok_request(
        self,
        *,
        provider_name: str | None,
        api_key: str | None,
    ) -> "CoachAgentService":
        if provider_name is None and api_key is None:
            return self
        if provider_name not in {"openai", "gemini"}:
            raise CoachServiceError(
                "invalid_provider_credentials",
                "A supported Coach provider and API key are required together.",
                retryable=False,
                status_code=422,
            )
        model = "gpt-5.6-terra" if provider_name == "openai" else "gemini-3.6-flash"
        pre_admission_error: CoachServiceError | None = None
        provider: CoachProvider = self._provider
        if not api_key or not api_key.strip():
            pre_admission_error = CoachServiceError(
                "invalid_provider_credentials",
                "A supported Coach provider and API key are required together.",
                retryable=False,
                status_code=422,
            )
        elif provider_name not in self._settings.coach_byok_providers:
            pre_admission_error = CoachServiceError(
                "provider_disabled",
                "The selected Coach provider is not enabled.",
                retryable=False,
                status_code=503,
            )
        else:
            provider = CloudByokCoachProvider(
                provider=provider_name,
                api_key=api_key,
                settings=self._settings,
            )
        return self.with_request_provider(
            provider=provider,
            identity=(provider_name, "user_supplied_key", model, "explicit"),
            pre_admission_error=pre_admission_error,
        )

    async def capabilities(
        self,
        *,
        user_id: str,
    ) -> CoachAgentCapabilitiesResponse:
        try:
            profile = await self._context_repository.get_profile(user_id=user_id)
        except Exception:
            return self._capabilities(
                state="unavailable",
                reason_code="persistence_unavailable",
                remaining=0,
            )
        self._lifecycle.require_authenticated_account(profile)
        try:
            if self._identity()[0] == "operator_codex_pilot":
                utc_date = self._lifecycle.now().date()
                used = await self._repository.count_operator_usage(
                    user_id=user_id,
                    utc_date=utc_date,
                )
                global_used = await self._repository.count_operator_dispatches(
                    utc_date=utc_date,
                )
            else:
                local_date = self._lifecycle.local_date(profile.timezone)
                used = await self._repository.count_usage(
                    user_id=user_id,
                    local_date=local_date,
                )
                global_used = None
            remaining = max(0, self._daily_limit - used)
        except Exception:
            return self._capabilities(
                state="unavailable",
                reason_code="persistence_unavailable",
                remaining=0,
                global_remaining=0
                if self._identity()[0] == "operator_codex_pilot"
                else None,
            )
        acquired = False
        try:
            async with asyncio.timeout(_CAPABILITY_SLOT_TIMEOUT_SECONDS):
                await self._global_semaphore.acquire()
            acquired = True
            async with asyncio.timeout(_CAPABILITY_PROBE_TIMEOUT_SECONDS):
                capability = await self._provider.capability()
        except TimeoutError:
            return self._capabilities(
                state="unavailable",
                reason_code="provider_busy" if not acquired else "provider_failure",
                remaining=remaining,
                global_remaining=self._global_remaining(global_used),
            )
        except Exception:
            return self._capabilities(
                state="unavailable",
                reason_code="provider_failure",
                remaining=remaining,
                global_remaining=self._global_remaining(global_used),
            )
        finally:
            if acquired:
                self._global_semaphore.release()
        if (
            capability.state == "ready"
            and capability.provider == "local_codex_oauth"
            and capability.model_requested != "gpt-5.5"
        ):
            return self._capabilities(
                state="unavailable",
                reason_code="unavailable_model",
                remaining=remaining,
                global_remaining=self._global_remaining(global_used),
            )
        return self._capabilities(
            state=capability.state,
            reason_code=capability.reason_code,
            remaining=remaining,
            global_remaining=self._global_remaining(global_used),
        )

    async def _probe_terminal_replay(
        self,
        *,
        user_id: str,
        request: CoachAgentRequest,
        message_fingerprint: str,
        identity: tuple[str, str, str | None, str],
        provider_dispatch_required: bool,
    ) -> CoachAgentResponse | None:
        async def operation() -> CoachClaimResult:
            result = await self._repository.probe_agent_terminal_replay(
                contract_version=request.contract_version,
                user_id=user_id,
                request_id=request.request_id,
                message_fingerprint=message_fingerprint,
                provider=identity[0],
                provider_mode=identity[1],
                model_requested=identity[2],
                model_source=identity[3],
                provider_dispatch_required=provider_dispatch_required,
            )
            return result or CoachClaimResult(
                state="pending",
                remaining_requests=0,
                response=None,
                error=None,
            )

        try:
            return await self._lifecycle.claim(
                operation(),
                response_type=CoachAgentResponse,
                status_for_code=_status_for_code,
                completed_mismatch_message=(
                    "The request id belongs to an older Coach contract."
                ),
                deleted_error=CoachErrorDetail(
                    code="history_deleted",
                    message="This Coach request history was deleted.",
                    retryable=False,
                ),
            )
        except CoachServiceError:
            raise
        except Exception as exc:
            raise CoachServiceError(
                "persistence_unavailable",
                "Coach could not verify exact request replay.",
                retryable=True,
                status_code=503,
            ) from exc

    async def prepare_turn(
        self,
        *,
        user_id: str,
        request: CoachAgentRequest,
    ) -> PreparedCoachTurn:
        self._require_user_not_blocked(user_id)
        identity = self._identity()
        profile = await self._lifecycle.eligible_profile(user_id=user_id)
        safety = pre_provider_safety(request.message, force_english=True)
        message_fingerprint = hashlib.sha256(
            request.message.encode("utf-8"),
        ).hexdigest()
        replay = await self._probe_terminal_replay(
            user_id=user_id,
            request=request,
            message_fingerprint=message_fingerprint,
            identity=identity,
            provider_dispatch_required=not safety.bypass_provider,
        )
        if replay is not None:
            return PreparedCoachTurn(
                owner=self._preparation_owner,
                user_id=user_id,
                request_id=request.request_id,
                message_fingerprint=message_fingerprint,
                local_date=None,
                identity=identity,
                safety=safety,
                semaphore=self._global_semaphore,
                slot_acquired=False,
                terminal_replay=replay,
            )
        if self._pre_admission_error is not None:
            raise self._pre_admission_error
        try:
            local_date = self._lifecycle.local_date(profile.timezone)
        except ValueError as exc:
            raise CoachServiceError(
                "context_failure",
                "Coach could not resolve the owner-scoped local date.",
                retryable=True,
                status_code=503,
            ) from exc
        slot_acquired = False
        reservation_provider: ReservableCoachProvider | None = None
        reservation_id: UUID | None = None
        dispatch_id: UUID | None = None
        if not safety.bypass_provider:
            if identity[0] == "operator_codex_pilot":
                if not isinstance(self._provider, ReservableCoachProvider):
                    raise CoachServiceError(
                        "provider_unavailable",
                        "The shared pilot Coach provider is unavailable.",
                        retryable=True,
                        status_code=503,
                    )
                reservation_provider = self._provider
                try:
                    global_used = await self._repository.count_operator_dispatches(
                        utc_date=self._lifecycle.now().date(),
                    )
                except Exception as exc:
                    raise CoachServiceError(
                        "persistence_unavailable",
                        "Coach could not verify the shared provider budget.",
                        retryable=True,
                        status_code=503,
                    ) from exc
                if global_used >= COACH_OPERATOR_REQUESTS_PER_UTC_DAY:
                    raise CoachServiceError(
                        "provider_limit",
                        "The shared pilot Coach limit has been reached for today.",
                        retryable=True,
                        status_code=429,
                    )
                try:
                    async with asyncio.timeout(_TURN_ADMISSION_TIMEOUT_SECONDS):
                        reservation_id = await reservation_provider.reserve()
                    dispatch_id = uuid5(
                        _OPERATOR_DISPATCH_NAMESPACE,
                        str(request.request_id),
                    )
                except TimeoutError as exc:
                    raise self._provider_busy_error() from exc
                except CoachProviderError as exc:
                    if exc.code == "provider_busy":
                        raise self._provider_busy_error() from exc
                    raise CoachServiceError(
                        _provider_error_code(exc.code),
                        _provider_error_message(exc.code),
                        retryable=exc.retryable,
                        status_code=_status_for_code(_provider_error_code(exc.code)),
                    ) from exc
            else:
                try:
                    async with asyncio.timeout(_TURN_ADMISSION_TIMEOUT_SECONDS):
                        await self._global_semaphore.acquire()
                    slot_acquired = True
                except TimeoutError as exc:
                    raise self._provider_busy_error() from exc
        return PreparedCoachTurn(
            owner=self._preparation_owner,
            user_id=user_id,
            request_id=request.request_id,
            message_fingerprint=message_fingerprint,
            local_date=local_date,
            identity=identity,
            safety=safety,
            semaphore=self._global_semaphore,
            slot_acquired=slot_acquired,
            reservation_provider=reservation_provider,
            reservation_id=reservation_id,
            dispatch_id=dispatch_id,
        )

    async def respond(
        self,
        *,
        user_id: str,
        request: CoachAgentRequest,
        activity_callback: CoachActivityCallback | None = None,
    ) -> CoachAgentResponse:
        prepared = await self.prepare_turn(user_id=user_id, request=request)
        return await self.respond_prepared(
            user_id=user_id,
            request=request,
            prepared=prepared,
            activity_callback=activity_callback,
        )

    async def respond_prepared(
        self,
        *,
        user_id: str,
        request: CoachAgentRequest,
        prepared: PreparedCoachTurn,
        activity_callback: CoachActivityCallback | None = None,
    ) -> CoachAgentResponse:
        task = asyncio.current_task()
        if task is None:
            await prepared.release()
            raise RuntimeError("Coach turn is missing its execution task.")
        active = self._user_activity.active_tasks.setdefault(user_id, set())
        active.add(task)
        try:
            try:
                self._require_user_not_blocked(user_id)
                prepared.consume(
                    owner=self._preparation_owner,
                    user_id=user_id,
                    request=request,
                )
            except Exception:
                await prepared.release()
                raise
            try:
                if prepared.terminal_replay is not None:
                    return prepared.terminal_replay
                return await self._respond_admitted(
                    user_id=user_id,
                    request=request,
                    prepared=prepared,
                    activity_callback=activity_callback,
                )
            finally:
                await asyncio.shield(prepared.release())
        finally:
            active.discard(task)
            if not active:
                self._user_activity.active_tasks.pop(user_id, None)

    async def _respond_admitted(
        self,
        *,
        user_id: str,
        request: CoachAgentRequest,
        prepared: PreparedCoachTurn,
        activity_callback: CoachActivityCallback | None,
    ) -> CoachAgentResponse:
        identity = prepared.identity
        local_date = prepared.local_date
        if local_date is None:
            raise RuntimeError("Non-replay Coach turn is missing its local date.")
        now = self._lifecycle.now()
        replay = await self._lifecycle.claim(
            self._repository.claim_agent_request(
                contract_version=request.contract_version,
                user_id=user_id,
                request_id=request.request_id,
                message_fingerprint=prepared.message_fingerprint,
                local_date=local_date,
                provider=identity[0],
                provider_mode=identity[1],
                model_requested=identity[2],
                model_source=identity[3],
                claimed_at=now,
                lease_expires_at=now + timedelta(seconds=_LEASE_SECONDS),
                daily_limit=self._daily_limit,
                provider_dispatch_required=not prepared.safety.bypass_provider,
            ),
            response_type=CoachAgentResponse,
            status_for_code=_status_for_code,
            completed_mismatch_message=(
                "The request id belongs to an older Coach contract."
            ),
            deleted_error=CoachErrorDetail(
                code="history_deleted",
                message="This Coach request history was deleted.",
                retryable=False,
            ),
        )
        if replay is not None:
            return replay

        snapshot: PreparedCoachSnapshot | None = None
        snapshot_source_bytes = 0
        provider_called = False
        prompt = ""
        failure_stage = "context"
        operator_dispatch_recorded = False
        operator_dispatch_finalized = False

        async def finalize_operator_dispatch(
            *,
            state: str,
            error_code: str | None,
        ) -> None:
            nonlocal operator_dispatch_finalized
            if not operator_dispatch_recorded or operator_dispatch_finalized:
                return
            dispatch_id = prepared.dispatch_id
            if dispatch_id is None:
                raise RuntimeError("Coach operator dispatch identity is missing.")
            try:
                await self._repository.finish_operator_dispatch(
                    dispatch_id=dispatch_id,
                    request_id=request.request_id,
                    state=state,
                    error_code=error_code,
                    terminal_at=self._lifecycle.now(),
                )
            except Exception:
                # Dispatch insertion already consumed the conservative global
                # budget. Do not replace the owner-visible terminal request
                # with an infrastructure error; startup reconciliation repairs
                # this private ledger without redispatching the provider.
                _LOGGER.warning(
                    "Coach operator dispatch terminalization deferred to reconciliation."
                )
                return
            operator_dispatch_finalized = True

        async def fail_request_and_finalize_dispatch(
            *,
            code: str,
            message: str,
            retryable: bool,
            provider_called_value: bool,
            prompt_bytes: int = 0,
            snapshot_bytes: int = 0,
        ) -> None:
            try:
                await self._fail_and_raise(
                    user_id=user_id,
                    request_id=request.request_id,
                    code=code,
                    message=message,
                    retryable=retryable,
                    provider_called=provider_called_value,
                    prompt_bytes=prompt_bytes,
                    snapshot_bytes=snapshot_bytes,
                )
            except CoachServiceError as exc:
                # Only terminalize the private dispatch after the owner-visible
                # failure write was confirmed. An ambiguous persistence result
                # stays `dispatched` for startup reconciliation, which can read
                # the durable request truth without ever redispatching Codex.
                if exc.detail.code == code:
                    await finalize_operator_dispatch(
                        state="failed",
                        error_code=code,
                    )
                raise
            raise AssertionError("Coach failure recording returned unexpectedly.")

        async def release_snapshot_or_fail() -> None:
            nonlocal snapshot
            current = snapshot
            snapshot = None
            if current is None:
                return
            try:
                # Verified cleanup is deliberately synchronous and bounded:
                # cancellation cannot interrupt removal once it starts.
                current.cleanup()
            except CoachSnapshotCleanupError:
                await fail_request_and_finalize_dispatch(
                    code="context_failure",
                    message=("Coach could not securely remove the private turn data."),
                    retryable=True,
                    provider_called_value=provider_called,
                    prompt_bytes=len(prompt.encode("utf-8")),
                    snapshot_bytes=snapshot_source_bytes,
                )

        try:
            async with asyncio.timeout(COACH_AGENT_TIMEOUT_SECONDS):
                safety = prepared.safety
                if safety.bypass_provider:
                    assert safety.output is not None
                    response = self._response(
                        request_id=request.request_id,
                        output=_agent_output(safety.output),
                        identity=identity,
                        request_contract_version=request.contract_version,
                        model_reported=None,
                        source="deterministic_safety",
                        provider_called=False,
                        snapshot=None,
                        trace=_empty_trace(),
                        evidence=[],
                    )
                    return await self._complete(
                        user_id=user_id,
                        request=request,
                        response=response,
                        prompt_bytes=0,
                        snapshot_bytes=0,
                    )

                failure_stage = "provider"
                async with prepared.provider_scope():
                    capability = await self._provider.capability()
                    if capability.state != "ready":
                        await self._fail_and_raise(
                            user_id=user_id,
                            request_id=request.request_id,
                            code=_provider_error_code(capability.reason_code),
                            message=_provider_error_message(
                                capability.reason_code,
                            ),
                            retryable=capability.reason_code
                            in {"provider_failure", "not_logged_in"},
                            provider_called=False,
                        )

                    # The same global slot bounds snapshot collection, local
                    # SQLite creation, and model execution. Queued turns cannot
                    # fan out 50k-row exports while provider capacity is full.
                    failure_stage = "context"
                    prompt = build_coach_agent_prompt(
                        message=request.message,
                        allow_python=identity[0] not in {"openai", "gemini"},
                    )
                    if activity_callback is not None:
                        await activity_callback("Preparing a private data snapshot …")
                    snapshot = await self._snapshot_service.create(user_id=user_id)
                    snapshot_source_bytes = snapshot.source_bytes
                    trace_path = snapshot.working_directory / "agent-trace.jsonl"
                    failure_stage = "provider"
                    if prepared.reservation_id is not None:
                        dispatch_id = prepared.dispatch_id
                        if dispatch_id is None:
                            raise RuntimeError(
                                "Coach operator dispatch identity is missing.",
                            )
                        try:
                            await self._repository.record_operator_dispatch(
                                dispatch_id=dispatch_id,
                                request_id=request.request_id,
                                user_id=user_id,
                                reservation_id=prepared.reservation_id,
                                dispatched_at=self._lifecycle.now(),
                                global_limit=COACH_OPERATOR_REQUESTS_PER_UTC_DAY,
                            )
                        except CoachPersistenceRateLimited:
                            await self._fail_and_raise(
                                user_id=user_id,
                                request_id=request.request_id,
                                code="provider_limit",
                                message=(
                                    "The shared pilot Coach limit has been reached "
                                    "for today."
                                ),
                                retryable=True,
                                provider_called=False,
                                prompt_bytes=len(prompt.encode("utf-8")),
                                snapshot_bytes=snapshot_source_bytes,
                            )
                        operator_dispatch_recorded = True
                    provider_called = True
                    if prepared.reservation_id is not None:
                        provider = prepared.reservation_provider
                        if provider is None:
                            raise RuntimeError("Coach reservation provider is missing.")
                        provider_result = await provider.respond_agent_reserved(
                            reservation_id=prepared.reservation_id,
                            prompt=prompt,
                            snapshot_path=snapshot.path,
                            trace_path=trace_path,
                            activity_callback=activity_callback,
                        )
                    else:
                        provider_result = await self._provider.respond_agent(
                            prompt=prompt,
                            snapshot_path=snapshot.path,
                            trace_path=trace_path,
                            activity_callback=activity_callback,
                        )
                legacy = CoachModelOutput(
                    reply=provider_result.output.reply,
                    uncertainty=provider_result.output.uncertainty,
                    staged_suggestion=None,
                    safety=provider_result.output.safety,
                )
                safety_result = post_provider_safety(
                    legacy,
                    message=request.message,
                    force_english=True,
                )
                output = _agent_output(safety_result.output)
                trace = _read_trace(trace_path)
                evidence = _evidence(snapshot=snapshot, trace=trace_path)
                source = (
                    "deterministic_safety"
                    if safety_result.replaced_with_deterministic_safety
                    else "model"
                )
                response = self._response(
                    request_id=request.request_id,
                    output=output,
                    identity=identity,
                    request_contract_version=request.contract_version,
                    model_reported=provider_result.model_reported,
                    source=source,
                    provider_called=True,
                    snapshot=snapshot,
                    trace=trace,
                    evidence=evidence,
                )
                response_snapshot_bytes = response.provenance.snapshot_bytes
                failure_stage = "context"
                await release_snapshot_or_fail()
                completed = await self._complete(
                    user_id=user_id,
                    request=request,
                    response=response,
                    prompt_bytes=len(prompt.encode("utf-8")),
                    snapshot_bytes=response_snapshot_bytes,
                )
                await finalize_operator_dispatch(state="completed", error_code=None)
                return completed
        except CoachSnapshotTooLargeError as exc:
            await fail_request_and_finalize_dispatch(
                code="snapshot_too_large",
                message=str(exc),
                retryable=False,
                provider_called_value=provider_called,
                prompt_bytes=len(prompt.encode("utf-8")),
                snapshot_bytes=snapshot_source_bytes,
            )
        except TimeoutError:
            await release_snapshot_or_fail()
            await fail_request_and_finalize_dispatch(
                code="provider_timeout",
                message="Coach analysis exceeded its 180-second turn limit.",
                retryable=True,
                provider_called_value=provider_called,
                prompt_bytes=len(prompt.encode("utf-8")),
                snapshot_bytes=snapshot_source_bytes,
            )
        except CoachProviderError as exc:
            await release_snapshot_or_fail()
            await fail_request_and_finalize_dispatch(
                code=_provider_error_code(exc.code),
                message=_provider_error_message(exc.code),
                retryable=exc.retryable,
                provider_called_value=provider_called,
                prompt_bytes=len(prompt.encode("utf-8")),
                snapshot_bytes=snapshot_source_bytes,
            )
        except asyncio.CancelledError:
            await release_snapshot_or_fail()
            await asyncio.shield(
                self._record_failure(
                    user_id=user_id,
                    request_id=request.request_id,
                    error=CoachErrorDetail(
                        code="interrupted",
                        message="The Coach analysis was cancelled.",
                        retryable=True,
                    ),
                    provider_called=provider_called,
                    prompt_bytes=len(prompt.encode("utf-8")),
                    snapshot_bytes=snapshot_source_bytes,
                ),
            )
            await asyncio.shield(
                finalize_operator_dispatch(
                    state="interrupted",
                    error_code="interrupted",
                ),
            )
            raise
        except CoachServiceError:
            raise
        except Exception as exc:
            provider_failure = failure_stage == "provider"
            await release_snapshot_or_fail()
            await fail_request_and_finalize_dispatch(
                code="provider_failure" if provider_failure else "context_failure",
                message=(
                    "The local Coach agent failed."
                    if provider_failure
                    else "Coach could not build the private data snapshot."
                ),
                retryable=True,
                provider_called_value=provider_called,
                prompt_bytes=len(prompt.encode("utf-8")),
                snapshot_bytes=snapshot_source_bytes,
            )
            raise AssertionError("unreachable") from exc
        finally:
            if snapshot is not None:
                await release_snapshot_or_fail()

    async def history(self, *, user_id: str) -> CoachAgentHistoryResponse:
        rows = await self._lifecycle.history_rows(
            user_id=user_id,
            load=lambda: self._repository.list_agent_history(
                user_id=user_id,
                limit=COACH_HISTORY_LIMIT,
            ),
        )
        return CoachAgentHistoryResponse(
            contract_version=COACH_HISTORY_V4_CONTRACT_VERSION,
            turns=[CoachAgentHistoryTurn.model_validate(row) for row in rows],
        )

    async def delete_history(self, *, user_id: str) -> CoachHistoryDeleteResponse:
        return await self._lifecycle.delete_history(user_id=user_id)

    async def _complete(
        self,
        *,
        user_id: str,
        request: CoachAgentRequest,
        response: CoachAgentResponse,
        prompt_bytes: int,
        snapshot_bytes: int,
    ) -> CoachAgentResponse:
        return await self._lifecycle.complete(
            self._repository.complete_agent_request(
                user_id=user_id,
                request_id=request.request_id,
                user_message=request.message,
                response=response,
                usage={
                    "provider_called": response.provenance.provider_called,
                    "prompt_bytes": prompt_bytes,
                    "context_bytes": snapshot_bytes,
                    "reply_codepoints": len(response.reply),
                },
                completed_at=self._lifecycle.now(),
            ),
        )

    async def _record_failure(
        self,
        *,
        user_id: str,
        request_id: UUID,
        error: CoachErrorDetail,
        provider_called: bool,
        prompt_bytes: int = 0,
        snapshot_bytes: int = 0,
    ) -> None:
        await self._lifecycle.record_failure(
            user_id=user_id,
            request_id=request_id,
            error=error,
            provider_called=provider_called,
            prompt_bytes=prompt_bytes,
            context_bytes=snapshot_bytes,
            require_confirmation=False,
        )

    async def _fail_and_raise(
        self,
        *,
        user_id: str,
        request_id: UUID,
        code: str,
        message: str,
        retryable: bool,
        provider_called: bool,
        prompt_bytes: int = 0,
        snapshot_bytes: int = 0,
    ) -> None:
        await self._lifecycle.fail_and_raise(
            user_id=user_id,
            request_id=request_id,
            error=CoachErrorDetail(
                code=code,
                message=message,
                retryable=retryable,
            ),
            provider_called=provider_called,
            prompt_bytes=prompt_bytes,
            context_bytes=snapshot_bytes,
            status_for_code=_status_for_code,
        )

    def _response(
        self,
        *,
        request_id: UUID,
        output: CoachAgentModelOutput,
        identity: tuple[str, str, str | None, str],
        request_contract_version: str,
        model_reported: str | None,
        source: str,
        provider_called: bool,
        snapshot: PreparedCoachSnapshot | None,
        trace: CoachAgentTrace,
        evidence: list[CoachAgentEvidence],
    ) -> CoachAgentResponse:
        fast_codex = identity[0] in {
            "local_codex_oauth",
            "operator_codex_pilot",
        }
        return CoachAgentResponse(
            contract_version=(
                COACH_RESPONSE_V4_CONTRACT_VERSION
                if request_contract_version == "coach-request-v4"
                else COACH_RESPONSE_V3_CONTRACT_VERSION
            ),
            request_id=request_id,
            reply=output.reply,
            uncertainty=output.uncertainty,
            safety=output.safety,
            evidence=evidence,
            agent_trace=trace,
            provenance={
                "source": source,
                "provider": identity[0],
                "provider_mode": identity[1],
                "model_requested": identity[2],
                "model_reported": model_reported,
                "model_source": identity[3],
                "prompt_version": COACH_AGENT_PROMPT_VERSION,
                "context_version": COACH_AGENT_CONTEXT_VERSION,
                "generated_at": self._lifecycle.now(),
                "provider_called": provider_called,
                "service_tier": "fast" if fast_codex else "not_applicable",
                "service_tier_status": (
                    "configured" if fast_codex else "not_applicable"
                ),
                "fast_mode": fast_codex,
                "snapshot_row_count": snapshot.row_count if snapshot else 0,
                "snapshot_bytes": snapshot.source_bytes if snapshot else 0,
            },
        )

    def _capabilities(
        self,
        *,
        state: str,
        reason_code: str,
        remaining: int,
        global_remaining: int | None = None,
    ) -> CoachAgentCapabilitiesResponse:
        identity = self._identity()
        fast_codex = identity[0] in {
            "local_codex_oauth",
            "operator_codex_pilot",
        }
        if identity[0] == "operator_codex_pilot" and global_remaining is None:
            global_remaining = 0
        return CoachAgentCapabilitiesResponse(
            contract_version=COACH_CAPABILITIES_V5_CONTRACT_VERSION,
            state=state,
            provider=identity[0],
            provider_mode=identity[1],
            model_requested=identity[2],
            model_source=identity[3],
            service_tier="fast" if fast_codex else "not_applicable",
            fast_mode=fast_codex,
            reason_code=reason_code,
            tools=(
                ["inspect_data", "query_data"]
                if identity[0] in {"openai", "gemini"}
                else ["inspect_data", "query_data", "run_python"]
            ),
            limits=CoachAgentLimits(
                message_codepoints=2_000,
                reply_codepoints=4_000,
                requests_per_local_day=self._daily_limit,
                request_period=(
                    "utc_day"
                    if identity[0] == "operator_codex_pilot"
                    else "profile_local_day"
                ),
                remaining_requests=remaining,
                global_requests_per_utc_day=(
                    COACH_OPERATOR_REQUESTS_PER_UTC_DAY
                    if identity[0] == "operator_codex_pilot"
                    else None
                ),
                global_remaining_requests=global_remaining,
                max_tool_calls=12,
                turn_timeout_seconds=180,
                sql_timeout_seconds=5,
                python_timeout_seconds=30,
                snapshot_max_rows=50_000,
                snapshot_max_bytes=8 * 1024 * 1024,
            ),
        )

    def _identity(self) -> tuple[str, str, str | None, str]:
        if self._identity_override is not None:
            return self._identity_override
        if self._settings.coach_provider == "local_codex_oauth":
            return (
                "local_codex_oauth",
                "local_development_only",
                self._settings.local_codex_model.strip() or None,
                "explicit",
            )
        if self._settings.coach_provider == "fake":
            return ("fake", "deterministic_test_only", None, "not_applicable")
        return ("disabled", "disabled", None, "not_applicable")

    @staticmethod
    def _global_remaining(global_used: int | None) -> int | None:
        if global_used is None:
            return None
        return max(0, COACH_OPERATOR_REQUESTS_PER_UTC_DAY - global_used)

    def _provider_busy_error(self) -> CoachServiceError:
        retry_after = min(
            30,
            max(5, self._settings.coach_operator_retry_after_seconds),
        )
        return CoachServiceError(
            "provider_busy",
            "The selected Coach provider is busy. Try again shortly.",
            retryable=True,
            status_code=429,
            response_headers={"Retry-After": str(retry_after)},
        )

    @property
    def _daily_limit(self) -> int:
        return (
            COACH_OPERATOR_REQUESTS_PER_LOCAL_DAY
            if self._identity()[0] == "operator_codex_pilot"
            else COACH_AGENT_REQUESTS_PER_LOCAL_DAY
        )


def _read_trace(path: Path) -> CoachAgentTrace:
    raw = _trace_rows(path)
    if len(raw) > 12:
        raise CoachProviderError(
            "tool_limit",
            "The local Coach agent exceeded the 12-call tool limit.",
            retryable=False,
        )
    steps: list[CoachAgentTraceStep] = []
    limitations = [
        "The snapshot contains app data only and cannot establish causality.",
    ]
    used_sql = False
    used_full_snapshot_python = False
    for index, row in enumerate(raw, start=1):
        tool = row.get("tool")
        status = row.get("status")
        if tool not in {"inspect_data", "query_data", "run_python"} or status not in {
            "completed",
            "failed",
        }:
            raise CoachProviderError(
                "invalid_output",
                "The Coach tool trace is invalid.",
                retryable=True,
            )
        if tool == "query_data" and isinstance(row.get("sql"), str):
            used_sql = status == "completed" or used_sql
            summary = f"Read-only SQL: {row['sql'][:460]}"
        elif tool == "run_python":
            used_full_snapshot_python = (
                status == "completed" and row.get("full_snapshot_access") is True
            ) or used_full_snapshot_python
            summary = (
                "Isolated Python analysis"
                f" ({int(row.get('python_codepoints') or 0)} code points)."
            )
        else:
            summary = str(row.get("summary") or f"Completed {tool}.")[:500]
        if status == "failed":
            limitations.append(summary)
        row_count = row.get("row_count")
        steps.append(
            CoachAgentTraceStep(
                sequence=index,
                tool=tool,
                status=status,
                summary=summary,
                row_count=(
                    row_count
                    if isinstance(row_count, int) and not isinstance(row_count, bool)
                    else None
                ),
                duration_ms=max(0, min(int(row.get("duration_ms") or 0), 180_000)),
            ),
        )
    if used_sql:
        limitations.append(
            "Evidence counts and periods describe full accessed snapshot "
            "sources; SQL step counts show returned rows.",
        )
    if used_full_snapshot_python:
        limitations.append(
            "Python had read-only access to the full personal snapshot; "
            "table-level attribution from arbitrary code is not trusted.",
        )
    return CoachAgentTrace(
        tool_call_count=len(steps),
        steps=steps,
        limitations=limitations,
    )


def _evidence(
    *,
    snapshot: PreparedCoachSnapshot,
    trace: Path,
) -> list[CoachAgentEvidence]:
    coverage = {item.table: item for item in snapshot.coverage}
    used: list[str] = []
    full_snapshot_python = False
    for row in _trace_rows(trace):
        if row.get("status") != "completed":
            continue
        full_snapshot_python = full_snapshot_python or (
            row.get("tool") == "run_python" and row.get("full_snapshot_access") is True
        )
        tables = row.get("tables")
        if isinstance(tables, list):
            for table in tables:
                if isinstance(table, str) and table not in used:
                    used.append(table)
    result = [
        CoachAgentEvidence(
            source=table,
            record_count=coverage[table].record_count,
            period_start=coverage[table].period_start,
            period_end=coverage[table].period_end,
        )
        for table in used
        if table in coverage
    ]
    if full_snapshot_python:
        periods_start = [
            item.period_start
            for item in snapshot.coverage
            if item.period_start is not None
        ]
        periods_end = [
            item.period_end for item in snapshot.coverage if item.period_end is not None
        ]
        result.append(
            CoachAgentEvidence(
                source="personal_snapshot",
                record_count=snapshot.row_count,
                period_start=min(periods_start) if periods_start else None,
                period_end=max(periods_end) if periods_end else None,
            ),
        )
    return result


def _trace_rows(path: Path) -> list[dict[str, Any]]:
    try:
        lines = path.read_text(encoding="utf-8").splitlines()
    except FileNotFoundError:
        return []
    result: list[dict[str, Any]] = []
    for line in lines:
        try:
            row = json.loads(line)
        except json.JSONDecodeError as exc:
            raise CoachProviderError(
                "invalid_output",
                "The Coach tool trace is invalid.",
                retryable=True,
            ) from exc
        if not isinstance(row, dict):
            raise CoachProviderError(
                "invalid_output",
                "The Coach tool trace is invalid.",
                retryable=True,
            )
        result.append(row)
    return result


def _empty_trace() -> CoachAgentTrace:
    return CoachAgentTrace(
        tool_call_count=0,
        steps=[],
        limitations=[
            "No personal-data tool was needed for the deterministic safety response.",
        ],
    )


def _agent_output(value: CoachModelOutput) -> CoachAgentModelOutput:
    return CoachAgentModelOutput(
        reply=value.reply,
        uncertainty=value.uncertainty,
        safety=value.safety,
    )


def _provider_error_code(code: str) -> str:
    return {
        "not_logged_in": "not_logged_in",
        "unavailable_model": "unavailable_model",
        "fast_mode_unavailable": "fast_mode_unavailable",
        "timeout": "provider_timeout",
        "account_limit": "account_limit",
        "context_too_large": "snapshot_too_large",
        "tool_limit": "tool_limit",
        "invalid_output": "invalid_output",
    }.get(code, "provider_failure")


def _provider_error_message(code: str) -> str:
    return {
        "not_logged_in": "The local Codex CLI is not authenticated.",
        "unavailable_model": "The required gpt-5.5 model is unavailable.",
        "fast_mode_unavailable": "The required Codex Fast mode is unavailable.",
        "timeout": "Coach analysis exceeded its 180-second turn limit.",
        "account_limit": "The local Codex account limit has been reached.",
        "context_too_large": "Personal data exceeds the Coach snapshot limit.",
        "tool_limit": "Coach analysis exceeded the 12-call tool limit.",
        "invalid_output": "The Coach provider returned invalid output.",
    }.get(code, "The local Coach provider failed.")


def _status_for_code(code: str) -> int:
    if code in {"account_limit", "provider_limit"}:
        return 429
    if code in {"request_conflict", "in_progress"}:
        return 409
    if code == "authenticated_account_required":
        return 403
    return 503
