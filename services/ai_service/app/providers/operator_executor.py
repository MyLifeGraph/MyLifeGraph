"""FastAPI-side client for the separately sandboxed pilot Coach executor."""

from __future__ import annotations

import asyncio
import base64
import hashlib
from collections.abc import Awaitable, Callable
from datetime import UTC, datetime, timedelta
from pathlib import Path
from uuid import UUID

from pydantic import ValidationError

from app.coach_executor_protocol import (
    COACH_EXECUTOR_MAX_REQUEST_BYTES,
    COACH_EXECUTOR_MAX_RESPONSE_BYTES,
    COACH_EXECUTOR_MAX_SNAPSHOT_BYTES,
    COACH_EXECUTOR_MAX_TRACE_BYTES,
    COACH_EXECUTOR_PROTOCOL_VERSION,
    ExecutorProtocolError,
    ExecutorProtocolTimeout,
    bounded_text,
    decode_json_object,
    exact_object,
    read_frame,
    utc_datetime,
    write_frame,
)
from app.core.config import Settings
from app.models.coach import CoachAgentModelOutput
from app.providers.base import (
    CoachActivityCallback,
    CoachAgentProviderResult,
    CoachProviderCapability,
    CoachProviderError,
    CoachProviderResult,
)


_CONNECT_TIMEOUT_SECONDS = 2
_EXECUTE_RESPONSE_TIMEOUT_SECONDS = 185
_EXECUTE_DEADLINE_SECONDS = 185
_ERROR_CODES = {
    "provider_busy",
    "provider_failure",
    "provider_timeout",
    "provider_unavailable",
    "not_logged_in",
    "missing_cli",
    "unsupported_cli",
    "unsupported_auth_mode",
    "unavailable_model",
    "fast_mode_unavailable",
    "analysis_runtime_unavailable",
    "analysis_image_unavailable",
    "analysis_image_stale",
    "invalid_output",
    "tool_limit",
    "interrupted",
    "invalid_reservation",
}


class OperatorExecutorCoachProvider:
    """No-secret API adapter; the executor owns Codex auth and containers."""

    def __init__(
        self,
        settings: Settings,
        *,
        connector: Callable[
            [], Awaitable[tuple[asyncio.StreamReader, asyncio.StreamWriter]]
        ]
        | None = None,
    ) -> None:
        self._settings = settings
        self._connector = connector

    async def capability(self) -> CoachProviderCapability:
        if (
            not self._settings.operator_codex_pilot_enabled
            or self._settings.normalized_app_env not in {"staging", "pilot"}
        ):
            return self._capability("unavailable", "provider_not_enabled")
        try:
            response = await self._round_trip(
                {
                    "protocol_version": COACH_EXECUTOR_PROTOCOL_VERSION,
                    "operation": "capability",
                },
            )
            self._raise_error(response)
            payload = exact_object(
                response,
                keys={
                    "protocol_version",
                    "status",
                    "operation",
                    "state",
                    "reason_code",
                },
                label="executor capability response",
            )
            if payload["status"] != "ok" or payload["operation"] != "capability":
                raise ExecutorProtocolError("Executor capability status is invalid.")
            state = payload["state"]
            if state not in {"ready", "unavailable"}:
                raise ExecutorProtocolError("Executor capability state is invalid.")
            reason = bounded_text(
                payload["reason_code"],
                label="executor reason code",
                max_bytes=64,
            )
            return self._capability(state, reason)
        except (OSError, ExecutorProtocolError, CoachProviderError, TimeoutError):
            return self._capability("unavailable", "provider_failure")

    async def reserve(self) -> UUID:
        response = await self._request_or_provider_error(
            {
                "protocol_version": COACH_EXECUTOR_PROTOCOL_VERSION,
                "operation": "reserve",
            },
        )
        self._raise_error(response)
        payload = exact_object(
            response,
            keys={
                "protocol_version",
                "status",
                "operation",
                "reservation_id",
                "expires_at",
            },
            label="executor reservation response",
        )
        if payload["status"] != "ok" or payload["operation"] != "reserve":
            raise self._protocol_failure()
        reservation_id = self._uuid(payload["reservation_id"])
        expires_at = utc_datetime(payload["expires_at"], label="reservation expiry")
        if expires_at <= datetime.now(UTC):
            raise self._protocol_failure()
        return reservation_id

    async def release_reservation(self, reservation_id: UUID) -> None:
        try:
            response = await self._round_trip(
                {
                    "protocol_version": COACH_EXECUTOR_PROTOCOL_VERSION,
                    "operation": "release",
                    "reservation_id": str(reservation_id),
                },
            )
            self._raise_error(response)
            payload = exact_object(
                response,
                keys={
                    "protocol_version",
                    "status",
                    "operation",
                    "released",
                },
                label="executor release response",
            )
            if (
                payload["status"] != "ok"
                or payload["operation"] != "release"
                or payload["released"] is not True
            ):
                raise ExecutorProtocolError("Executor release status is invalid.")
        except (OSError, TimeoutError, ExecutorProtocolError, CoachProviderError):
            # The executor lease is fail-safe bounded. Cleanup failure must not
            # replace an already persisted terminal Coach response.
            return

    async def respond(self, *, prompt: str) -> CoachProviderResult:
        del prompt
        raise CoachProviderError(
            "provider_unavailable",
            "The shared pilot provider supports reserved agent turns only.",
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
            "invalid_reservation",
            "The shared pilot provider requires an admitted reservation.",
            retryable=False,
        )

    async def respond_agent_reserved(
        self,
        *,
        reservation_id: UUID,
        prompt: str,
        snapshot_path: Path,
        trace_path: Path,
        activity_callback: CoachActivityCallback | None = None,
    ) -> CoachAgentProviderResult:
        snapshot = self._read_snapshot(snapshot_path)
        if activity_callback is not None:
            await activity_callback("Checking available personal data …")
            await activity_callback("Testing the data with isolated analysis …")
        deadline = datetime.now(UTC) + timedelta(seconds=_EXECUTE_DEADLINE_SECONDS)
        response = await self._request_or_provider_error(
            {
                "protocol_version": COACH_EXECUTOR_PROTOCOL_VERSION,
                "operation": "execute",
                "reservation_id": str(reservation_id),
                "deadline": deadline.isoformat(),
                "prompt": prompt,
                "snapshot_sha256": hashlib.sha256(snapshot).hexdigest(),
                "snapshot_base64": base64.b64encode(snapshot).decode("ascii"),
            },
            response_timeout_seconds=_EXECUTE_RESPONSE_TIMEOUT_SECONDS,
        )
        self._raise_error(response)
        payload = exact_object(
            response,
            keys={
                "protocol_version",
                "status",
                "operation",
                "output",
                "model_reported",
                "trace_jsonl",
            },
            label="executor result response",
        )
        if payload["status"] != "ok" or payload["operation"] != "execute":
            raise self._protocol_failure()
        model_reported = payload["model_reported"]
        if model_reported is not None:
            try:
                model_reported = bounded_text(
                    model_reported,
                    label="executor reported model",
                    max_bytes=100,
                )
            except ExecutorProtocolError as exc:
                raise self._protocol_failure() from exc
            if model_reported != self._settings.coach_operator_model:
                raise CoachProviderError(
                    "unavailable_model",
                    "The shared pilot provider reported a different model.",
                    retryable=False,
                )
        try:
            output = CoachAgentModelOutput.model_validate(payload["output"])
        except ValidationError as exc:
            raise self._protocol_failure() from exc
        trace = bounded_text(
            payload["trace_jsonl"],
            label="executor trace",
            max_bytes=COACH_EXECUTOR_MAX_TRACE_BYTES,
            allow_empty=True,
        ).encode("utf-8")
        self._write_trace(trace_path, trace)
        return CoachAgentProviderResult(
            output=output,
            model_reported=model_reported,
        )

    async def _request_or_provider_error(
        self,
        request: dict[str, object],
        *,
        response_timeout_seconds: float = 5,
    ) -> dict[str, object]:
        try:
            return await self._round_trip(
                request,
                response_timeout_seconds=response_timeout_seconds,
            )
        except (TimeoutError, ExecutorProtocolTimeout) as exc:
            raise CoachProviderError(
                "provider_timeout",
                "The shared pilot provider timed out.",
                retryable=True,
            ) from exc
        except (OSError, ExecutorProtocolError) as exc:
            raise CoachProviderError(
                "provider_failure",
                "The shared pilot provider is unavailable.",
                retryable=True,
            ) from exc

    async def _round_trip(
        self,
        request: dict[str, object],
        *,
        response_timeout_seconds: float = 5,
    ) -> dict[str, object]:
        try:
            async with asyncio.timeout(_CONNECT_TIMEOUT_SECONDS):
                if self._connector is None:
                    reader, writer = await asyncio.open_unix_connection(
                        self._settings.coach_executor_socket_path,
                    )
                else:
                    reader, writer = await self._connector()
        except TimeoutError:
            raise
        try:
            await write_frame(
                writer,
                request,
                max_bytes=COACH_EXECUTOR_MAX_REQUEST_BYTES,
            )
            raw = await read_frame(
                reader,
                max_bytes=COACH_EXECUTOR_MAX_RESPONSE_BYTES,
                timeout_seconds=response_timeout_seconds,
            )
            response = decode_json_object(raw, label="executor response")
            if response.get("protocol_version") != COACH_EXECUTOR_PROTOCOL_VERSION:
                raise ExecutorProtocolError("Executor protocol version is invalid.")
            return response
        finally:
            writer.close()
            try:
                await writer.wait_closed()
            except OSError:
                pass

    def _raise_error(self, response: dict[str, object]) -> None:
        if response.get("status") != "error":
            return
        payload = exact_object(
            response,
            keys={"protocol_version", "status", "error"},
            label="executor error response",
        )
        error = exact_object(
            payload["error"],
            keys={"code", "retryable"},
            label="executor error",
        )
        code = error["code"]
        retryable = error["retryable"]
        if code not in _ERROR_CODES or not isinstance(retryable, bool):
            raise self._protocol_failure()
        raise CoachProviderError(
            code,
            "The shared pilot Coach provider could not complete the request.",
            retryable=retryable,
        )

    def _read_snapshot(self, path: Path) -> bytes:
        try:
            if path.is_symlink() or not path.is_file():
                raise OSError
            size = path.stat().st_size
            if size <= 0 or size > COACH_EXECUTOR_MAX_SNAPSHOT_BYTES:
                raise OSError
            snapshot = path.read_bytes()
        except OSError as exc:
            raise CoachProviderError(
                "context_failure",
                "The private Coach snapshot is unavailable.",
                retryable=True,
            ) from exc
        if len(snapshot) != size:
            raise CoachProviderError(
                "context_failure",
                "The private Coach snapshot changed during transfer.",
                retryable=True,
            )
        return snapshot

    @staticmethod
    def _write_trace(path: Path, trace: bytes) -> None:
        try:
            if path.exists() or path.is_symlink():
                raise OSError
            with path.open("xb") as handle:
                handle.write(trace)
        except OSError as exc:
            raise CoachProviderError(
                "invalid_output",
                "The shared pilot provider trace could not be retained.",
                retryable=True,
            ) from exc

    @staticmethod
    def _uuid(value: object) -> UUID:
        try:
            parsed = UUID(str(value))
        except (ValueError, AttributeError) as exc:
            raise ExecutorProtocolError("Executor reservation id is invalid.") from exc
        if str(parsed) != value:
            raise ExecutorProtocolError("Executor reservation id is not canonical.")
        return parsed

    @staticmethod
    def _protocol_failure() -> CoachProviderError:
        return CoachProviderError(
            "provider_failure",
            "The shared pilot provider returned an invalid response.",
            retryable=True,
        )

    def _capability(self, state: str, reason_code: str) -> CoachProviderCapability:
        return CoachProviderCapability(
            state=state,
            provider="operator_codex_pilot",
            provider_mode="operator_subscription_pilot",
            model_requested=self._settings.coach_operator_model,
            model_source="explicit",
            reason_code=reason_code,
        )
