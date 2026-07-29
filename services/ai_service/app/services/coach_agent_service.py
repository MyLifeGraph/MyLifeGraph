import asyncio
import hashlib
import json
from collections.abc import Callable
from datetime import UTC, datetime, timedelta
from pathlib import Path
from typing import Any
from uuid import UUID
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from app.core.config import Settings
from app.models.coach import (
    COACH_AGENT_CONTEXT_VERSION,
    COACH_AGENT_PROMPT_VERSION,
    COACH_AGENT_REQUESTS_PER_LOCAL_DAY,
    COACH_AGENT_TIMEOUT_SECONDS,
    COACH_CAPABILITIES_V2_CONTRACT_VERSION,
    COACH_HISTORY_V2_CONTRACT_VERSION,
    COACH_RESPONSE_V2_CONTRACT_VERSION,
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
from app.providers.base import CoachActivityCallback, CoachProvider, CoachProviderError
from app.repositories.coach_context_repository import CoachContextRepository
from app.repositories.coach_repository import (
    CoachPersistenceConflict,
    CoachPersistenceRateLimited,
    CoachRepository,
)
from app.services.coach_agent_prompt import build_coach_agent_prompt
from app.services.coach_safety import post_provider_safety, pre_provider_safety
from app.services.coach_service import CoachServiceError
from app.services.coach_snapshot import (
    CoachSnapshotCleanupError,
    CoachSnapshotService,
    CoachSnapshotTooLargeError,
    PreparedCoachSnapshot,
)


_HISTORY_LIMIT = 50
_LEASE_SECONDS = COACH_AGENT_TIMEOUT_SECONDS + 60
_CAPABILITY_SLOT_TIMEOUT_SECONDS = 1
_CAPABILITY_PROBE_TIMEOUT_SECONDS = 15


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
    ) -> None:
        self._settings = settings
        self._repository = repository
        self._context_repository = context_repository
        self._snapshot_service = snapshot_service
        self._provider = provider
        self._global_semaphore = global_semaphore
        self._now_provider = now_provider or (lambda: datetime.now(UTC))

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
        self._require_authenticated_account(profile)
        try:
            used = await self._repository.count_usage(
                user_id=user_id,
                local_date=self._local_date(profile.timezone),
            )
            remaining = max(0, self._daily_limit - used)
        except Exception:
            return self._capabilities(
                state="unavailable",
                reason_code="persistence_unavailable",
                remaining=0,
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
            )
        except Exception:
            return self._capabilities(
                state="unavailable",
                reason_code="provider_failure",
                remaining=remaining,
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
            )
        return self._capabilities(
            state=capability.state,
            reason_code=capability.reason_code,
            remaining=remaining,
        )

    async def respond(
        self,
        *,
        user_id: str,
        request: CoachAgentRequest,
        activity_callback: CoachActivityCallback | None = None,
    ) -> CoachAgentResponse:
        identity = self._identity()
        profile = await self._eligible_profile(user_id=user_id)
        try:
            local_date = self._local_date(profile.timezone)
        except ValueError as exc:
            raise CoachServiceError(
                "context_failure",
                "Coach could not resolve the owner-scoped local date.",
                retryable=True,
                status_code=503,
            ) from exc
        now = self._now()
        try:
            claim = await self._repository.claim_agent_request(
                user_id=user_id,
                request_id=request.request_id,
                message_fingerprint=hashlib.sha256(
                    request.message.encode("utf-8"),
                ).hexdigest(),
                local_date=local_date,
                provider=identity[0],
                provider_mode=identity[1],
                model_requested=identity[2],
                model_source=identity[3],
                claimed_at=now,
                lease_expires_at=now + timedelta(seconds=_LEASE_SECONDS),
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
            if not isinstance(claim.response, CoachAgentResponse):
                raise CoachServiceError(
                    "request_conflict",
                    "The request id belongs to an older Coach contract.",
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
        if claim.state in {"failed", "deleted"}:
            assert claim.error is not None
            raise _stored_failure(claim.error, deleted=claim.state == "deleted")

        snapshot: PreparedCoachSnapshot | None = None
        snapshot_source_bytes = 0
        provider_called = False
        prompt = ""
        failure_stage = "context"

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
                await self._fail_and_raise(
                    user_id=user_id,
                    request_id=request.request_id,
                    code="context_failure",
                    message=(
                        "Coach could not securely remove the private turn data."
                    ),
                    retryable=True,
                    provider_called=provider_called,
                    prompt_bytes=len(prompt.encode("utf-8")),
                    snapshot_bytes=snapshot_source_bytes,
                )

        try:
            async with asyncio.timeout(COACH_AGENT_TIMEOUT_SECONDS):
                safety = pre_provider_safety(
                    request.message,
                    force_english=True,
                )
                if safety.bypass_provider:
                    assert safety.output is not None
                    response = self._response(
                        request_id=request.request_id,
                        output=_agent_output(safety.output),
                        identity=identity,
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
                async with self._global_semaphore:
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
                    prompt = build_coach_agent_prompt(message=request.message)
                    if activity_callback is not None:
                        await activity_callback("Preparing a private data snapshot …")
                    snapshot = await self._snapshot_service.create(user_id=user_id)
                    snapshot_source_bytes = snapshot.source_bytes
                    trace_path = snapshot.working_directory / "agent-trace.jsonl"
                    failure_stage = "provider"
                    provider_called = True
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
                return await self._complete(
                    user_id=user_id,
                    request=request,
                    response=response,
                    prompt_bytes=len(prompt.encode("utf-8")),
                    snapshot_bytes=response_snapshot_bytes,
                )
        except CoachSnapshotTooLargeError as exc:
            await self._fail_and_raise(
                user_id=user_id,
                request_id=request.request_id,
                code="snapshot_too_large",
                message=str(exc),
                retryable=False,
                provider_called=provider_called,
                prompt_bytes=len(prompt.encode("utf-8")),
                snapshot_bytes=snapshot_source_bytes,
            )
        except TimeoutError as exc:
            await release_snapshot_or_fail()
            await self._fail_and_raise(
                user_id=user_id,
                request_id=request.request_id,
                code="provider_timeout",
                message="Coach analysis exceeded its 180-second turn limit.",
                retryable=True,
                provider_called=provider_called,
                prompt_bytes=len(prompt.encode("utf-8")),
                snapshot_bytes=snapshot_source_bytes,
            )
        except CoachProviderError as exc:
            await release_snapshot_or_fail()
            await self._fail_and_raise(
                user_id=user_id,
                request_id=request.request_id,
                code=_provider_error_code(exc.code),
                message=_provider_error_message(exc.code),
                retryable=exc.retryable,
                provider_called=provider_called,
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
            raise
        except CoachServiceError:
            raise
        except Exception as exc:
            provider_failure = failure_stage == "provider"
            await release_snapshot_or_fail()
            await self._fail_and_raise(
                user_id=user_id,
                request_id=request.request_id,
                code="provider_failure" if provider_failure else "context_failure",
                message=(
                    "The local Coach agent failed."
                    if provider_failure
                    else "Coach could not build the private data snapshot."
                ),
                retryable=True,
                provider_called=provider_called,
                prompt_bytes=len(prompt.encode("utf-8")),
                snapshot_bytes=snapshot_source_bytes,
            )
            raise AssertionError("unreachable") from exc
        finally:
            if snapshot is not None:
                await release_snapshot_or_fail()

    async def history(self, *, user_id: str) -> CoachAgentHistoryResponse:
        await self._eligible_profile(user_id=user_id)
        rows = await self._repository.list_agent_history(
            user_id=user_id,
            limit=_HISTORY_LIMIT,
        )
        return CoachAgentHistoryResponse(
            contract_version=COACH_HISTORY_V2_CONTRACT_VERSION,
            turns=[CoachAgentHistoryTurn.model_validate(row) for row in rows],
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
            contract_version="coach-history-v1",
            deleted=True,
        )

    async def _complete(
        self,
        *,
        user_id: str,
        request: CoachAgentRequest,
        response: CoachAgentResponse,
        prompt_bytes: int,
        snapshot_bytes: int,
    ) -> CoachAgentResponse:
        try:
            return await self._repository.complete_agent_request(
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
        snapshot_bytes: int = 0,
    ) -> None:
        await self._repository.fail_request(
            user_id=user_id,
            request_id=request_id,
            error=error,
            usage={
                "provider_called": provider_called,
                "prompt_bytes": prompt_bytes,
                "context_bytes": snapshot_bytes,
                "reply_codepoints": 0,
            },
            failed_at=self._now(),
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
        error = CoachErrorDetail(
            code=code,
            message=message,
            retryable=retryable,
        )
        try:
            await self._record_failure(
                user_id=user_id,
                request_id=request_id,
                error=error,
                provider_called=provider_called,
                prompt_bytes=prompt_bytes,
                snapshot_bytes=snapshot_bytes,
            )
        except Exception as exc:
            raise CoachServiceError(
                "in_progress",
                "The Coach failure could not be confirmed. Retry the same request id.",
                retryable=True,
                status_code=409,
            ) from exc
        raise CoachServiceError(
            code,
            message,
            retryable=retryable,
            status_code=_status_for_code(code),
        )

    def _response(
        self,
        *,
        request_id: UUID,
        output: CoachAgentModelOutput,
        identity: tuple[str, str, str | None, str],
        model_reported: str | None,
        source: str,
        provider_called: bool,
        snapshot: PreparedCoachSnapshot | None,
        trace: CoachAgentTrace,
        evidence: list[CoachAgentEvidence],
    ) -> CoachAgentResponse:
        local_codex = identity[0] == "local_codex_oauth"
        return CoachAgentResponse(
            contract_version=COACH_RESPONSE_V2_CONTRACT_VERSION,
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
                "generated_at": self._now(),
                "provider_called": provider_called,
                "service_tier": "fast" if local_codex else "not_applicable",
                "service_tier_status": (
                    "configured" if local_codex else "not_applicable"
                ),
                "fast_mode": local_codex,
                "snapshot_row_count": snapshot.row_count if snapshot else 0,
                "snapshot_bytes": snapshot.source_bytes if snapshot else 0,
            },
        )

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

    def _capabilities(
        self,
        *,
        state: str,
        reason_code: str,
        remaining: int,
    ) -> CoachAgentCapabilitiesResponse:
        identity = self._identity()
        local_codex = identity[0] == "local_codex_oauth"
        return CoachAgentCapabilitiesResponse(
            contract_version=COACH_CAPABILITIES_V2_CONTRACT_VERSION,
            state=state,
            provider=identity[0],
            provider_mode=identity[1],
            model_requested=identity[2],
            model_source=identity[3],
            service_tier="fast" if local_codex else "not_applicable",
            fast_mode=local_codex,
            reason_code=reason_code,
            limits=CoachAgentLimits(
                message_codepoints=2_000,
                reply_codepoints=4_000,
                requests_per_local_day=self._daily_limit,
                remaining_requests=remaining,
                max_tool_calls=12,
                turn_timeout_seconds=180,
                sql_timeout_seconds=5,
                python_timeout_seconds=30,
                snapshot_max_rows=50_000,
                snapshot_max_bytes=8 * 1024 * 1024,
            ),
        )

    def _identity(self) -> tuple[str, str, str | None, str]:
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

    @property
    def _daily_limit(self) -> int:
        return COACH_AGENT_REQUESTS_PER_LOCAL_DAY

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
                status == "completed"
                and row.get("full_snapshot_access") is True
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
            row.get("tool") == "run_python"
            and row.get("full_snapshot_access") is True
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
            item.period_end
            for item in snapshot.coverage
            if item.period_end is not None
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
    }.get(code, "The local Coach provider failed.")


def _status_for_code(code: str) -> int:
    if code == "account_limit":
        return 429
    if code in {"request_conflict", "in_progress"}:
        return 409
    if code == "authenticated_account_required":
        return 403
    return 503


def _stored_failure(error: CoachErrorDetail, *, deleted: bool) -> CoachServiceError:
    code = "history_deleted" if deleted else error.code
    return CoachServiceError(
        code,
        (
            "This Coach request history was deleted."
            if deleted
            else error.message
        ),
        retryable=False if deleted else error.retryable,
        status_code=410 if deleted else _status_for_code(error.code),
    )
