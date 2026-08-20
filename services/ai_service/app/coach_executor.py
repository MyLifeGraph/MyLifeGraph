"""Dedicated Unix-socket process for subscription-backed pilot Coach turns."""

from __future__ import annotations

import asyncio
import base64
import binascii
import hashlib
import hmac
import os
import re
import socket
import stat
import struct
import tempfile
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta
from pathlib import Path
from typing import Any
from uuid import UUID, uuid4

from app.coach_executor_protocol import (
    COACH_EXECUTOR_MAX_PROMPT_BYTES,
    COACH_EXECUTOR_MAX_REQUEST_BYTES,
    COACH_EXECUTOR_MAX_RESPONSE_BYTES,
    COACH_EXECUTOR_MAX_SNAPSHOT_BYTES,
    COACH_EXECUTOR_MAX_TRACE_BYTES,
    COACH_EXECUTOR_PROTOCOL_VERSION,
    COACH_EXECUTOR_RESERVATION_SECONDS,
    ExecutorProtocolError,
    bounded_text,
    decode_json_object,
    exact_object,
    read_frame,
    utc_datetime,
    write_frame,
)
from app.core.config import Settings
from app.providers.base import CoachAgentProviderResult, CoachProviderError
from app.providers.local_codex import LocalCodexCoachProvider


_PEER_CREDENTIALS = struct.Struct("3i")
_CONSUMED_RETENTION = timedelta(hours=1)
_MAX_CONSUMED_IDENTITIES = 256
_RELEASE_ANALYSIS_IMAGE_PATTERN = re.compile(
    r"^mylifegraph-coach-analysis:sha256-[0-9a-f]{64}$",
)
_FORBIDDEN_ENVIRONMENT_NAMES = {
    "DATABASE_URL",
    "GEMINI_API_KEY",
    "OPENAI_API_KEY",
    "SUPABASE_ACCESS_TOKEN",
    "SUPABASE_DB_PASSWORD",
    "PILOT_SUPABASE_PROJECT_REF",
    "SCHEDULED_REFRESH_TOKEN",
    "STAGING_SUPABASE_PROJECT_REF",
    "SUPABASE_ANON_KEY",
    "SUPABASE_PUBLISHABLE_KEY",
    "SUPABASE_SECRET_KEY",
    "SUPABASE_SERVICE_ROLE_KEY",
    "SUPABASE_URL",
}
_FORBIDDEN_ENVIRONMENT_PREFIXES = (
    "ACCOUNT_DELETION_JOURNAL_",
    "AWS_",
    "BACKUP_",
    "RESTIC_",
)
_CLIENT_ERROR_CODES = {
    "analysis_image_stale",
    "analysis_image_unavailable",
    "analysis_runtime_unavailable",
    "fast_mode_unavailable",
    "invalid_output",
    "missing_cli",
    "not_logged_in",
    "provider_failure",
    "provider_timeout",
    "tool_limit",
    "unavailable_model",
    "unsupported_auth_mode",
    "unsupported_cli",
}


@dataclass(slots=True)
class _Reservation:
    expires_at: datetime
    state: str = "reserved"
    task: asyncio.Task[CoachAgentProviderResult] | None = None


class _BusyError(RuntimeError):
    pass


class _ReservationError(RuntimeError):
    pass


class CoachExecutorReservations:
    """Single-process, one-use reservation authority with bounded leases."""

    def __init__(self) -> None:
        self._lock = asyncio.Lock()
        self._reservations: dict[UUID, _Reservation] = {}
        self._consumed: dict[UUID, datetime] = {}

    async def reserve(self, *, now: datetime) -> tuple[UUID, datetime]:
        async with self._lock:
            self._purge(now)
            if self._reservations:
                raise _BusyError
            reservation_id = uuid4()
            expires_at = now + timedelta(
                seconds=COACH_EXECUTOR_RESERVATION_SECONDS,
            )
            self._reservations[reservation_id] = _Reservation(expires_at=expires_at)
            return reservation_id, expires_at

    async def begin_execution(
        self,
        reservation_id: UUID,
        *,
        now: datetime,
        deadline: datetime,
    ) -> datetime:
        async with self._lock:
            self._purge(now)
            reservation = self._reservations.get(reservation_id)
            if (
                reservation is None
                or reservation.state != "reserved"
                or reservation_id in self._consumed
                or deadline <= now
                or deadline > reservation.expires_at
            ):
                raise _ReservationError
            reservation.state = "executing"
            return reservation.expires_at

    async def attach_task(
        self,
        reservation_id: UUID,
        task: asyncio.Task[CoachAgentProviderResult],
    ) -> None:
        async with self._lock:
            reservation = self._reservations.get(reservation_id)
            if reservation is None or reservation.state != "executing":
                task.cancel()
                raise _ReservationError
            reservation.task = task

    async def finish(self, reservation_id: UUID, *, now: datetime) -> None:
        async with self._lock:
            self._reservations.pop(reservation_id, None)
            self._remember_consumed(reservation_id, now)

    async def release(self, reservation_id: UUID, *, now: datetime) -> None:
        task: asyncio.Task[CoachAgentProviderResult] | None = None
        async with self._lock:
            self._purge(now)
            reservation = self._reservations.pop(reservation_id, None)
            if reservation is not None:
                task = reservation.task
                self._remember_consumed(reservation_id, now)
        if task is not None and not task.done():
            task.cancel()
            await asyncio.gather(task, return_exceptions=True)

    def _purge(self, now: datetime) -> None:
        for reservation_id, reservation in list(self._reservations.items()):
            if reservation.expires_at <= now and reservation.state == "reserved":
                self._reservations.pop(reservation_id, None)
                self._remember_consumed(reservation_id, now)
        cutoff = now - _CONSUMED_RETENTION
        self._consumed = {
            key: value for key, value in self._consumed.items() if value > cutoff
        }
        if len(self._consumed) > _MAX_CONSUMED_IDENTITIES:
            retained = sorted(
                self._consumed.items(),
                key=lambda item: item[1],
                reverse=True,
            )[:_MAX_CONSUMED_IDENTITIES]
            self._consumed = dict(retained)

    def _remember_consumed(self, reservation_id: UUID, now: datetime) -> None:
        self._consumed[reservation_id] = now


class CoachExecutorServer:
    def __init__(
        self,
        *,
        provider: LocalCodexCoachProvider,
        allowed_api_uid: int,
        reservations: CoachExecutorReservations | None = None,
    ) -> None:
        if allowed_api_uid <= 0:
            raise ValueError("The executor requires one explicit non-root API UID.")
        self._provider = provider
        self._allowed_api_uid = allowed_api_uid
        self._reservations = reservations or CoachExecutorReservations()

    async def handle_connection(
        self,
        reader: asyncio.StreamReader,
        writer: asyncio.StreamWriter,
    ) -> None:
        if self._peer_uid(writer) != self._allowed_api_uid:
            writer.close()
            try:
                await writer.wait_closed()
            except OSError:
                pass
            return
        response: dict[str, Any] | None = None
        try:
            raw = await read_frame(
                reader,
                max_bytes=COACH_EXECUTOR_MAX_REQUEST_BYTES,
            )
            request = decode_json_object(raw, label="executor request")
            response = await self._dispatch(request, reader=reader)
        except ExecutorProtocolError:
            response = self._error("invalid_request", retryable=False)
        except _BusyError:
            response = self._error("provider_busy", retryable=True)
        except _ReservationError:
            response = self._error("invalid_reservation", retryable=False)
        except CoachProviderError as exc:
            code = exc.code if exc.code in _CLIENT_ERROR_CODES else "provider_failure"
            response = self._error(code, retryable=exc.retryable)
        except asyncio.CancelledError:
            raise
        except Exception:
            response = self._error("provider_failure", retryable=True)
        try:
            if response is not None and not writer.is_closing():
                await write_frame(
                    writer,
                    response,
                    max_bytes=COACH_EXECUTOR_MAX_RESPONSE_BYTES,
                )
        except (ConnectionError, ExecutorProtocolError):
            pass
        finally:
            writer.close()
            try:
                await writer.wait_closed()
            except OSError:
                pass

    async def _dispatch(
        self,
        request: dict[str, Any],
        *,
        reader: asyncio.StreamReader,
    ) -> dict[str, Any] | None:
        operation = request.get("operation")
        if request.get("protocol_version") != COACH_EXECUTOR_PROTOCOL_VERSION:
            raise ExecutorProtocolError("Executor protocol version is invalid.")
        if operation == "capability":
            exact_object(
                request,
                keys={"protocol_version", "operation"},
                label="capability request",
            )
            capability = await self._provider.capability()
            return self._ok(
                "capability",
                state=capability.state,
                reason_code=capability.reason_code,
            )
        if operation == "reserve":
            exact_object(
                request,
                keys={"protocol_version", "operation"},
                label="reservation request",
            )
            reservation_id, expires_at = await self._reservations.reserve(
                now=datetime.now(UTC),
            )
            return self._ok(
                "reserve",
                reservation_id=str(reservation_id),
                expires_at=expires_at.isoformat(),
            )
        if operation == "release":
            payload = exact_object(
                request,
                keys={"protocol_version", "operation", "reservation_id"},
                label="release request",
            )
            reservation_id = self._uuid(payload["reservation_id"])
            await self._reservations.release(
                reservation_id,
                now=datetime.now(UTC),
            )
            return self._ok("release", released=True)
        if operation == "execute":
            return await self._execute(request, reader=reader)
        raise ExecutorProtocolError("Executor operation is unsupported.")

    async def _execute(
        self,
        request: dict[str, Any],
        *,
        reader: asyncio.StreamReader,
    ) -> dict[str, Any] | None:
        payload = exact_object(
            request,
            keys={
                "protocol_version",
                "operation",
                "reservation_id",
                "deadline",
                "prompt",
                "snapshot_sha256",
                "snapshot_base64",
            },
            label="execute request",
        )
        reservation_id = self._uuid(payload["reservation_id"])
        deadline = utc_datetime(payload["deadline"], label="execution deadline")
        now = datetime.now(UTC)
        prompt = bounded_text(
            payload["prompt"],
            label="executor prompt",
            max_bytes=COACH_EXECUTOR_MAX_PROMPT_BYTES,
        )
        snapshot = self._snapshot(payload)
        await self._reservations.begin_execution(
            reservation_id,
            now=now,
            deadline=deadline,
        )

        try:
            with tempfile.TemporaryDirectory(
                prefix="mylifegraph-executor-turn-",
            ) as workdir_text:
                workdir = Path(workdir_text)
                os.chmod(workdir, 0o700)
                snapshot_path = workdir / "personal.sqlite"
                self._write_private_file(snapshot_path, snapshot)
                trace_path = workdir / "agent-trace.jsonl"
                provider_task = asyncio.create_task(
                    self._provider.respond_agent(
                        prompt=prompt,
                        snapshot_path=snapshot_path,
                        trace_path=trace_path,
                    ),
                )
                await self._reservations.attach_task(reservation_id, provider_task)
                disconnected = asyncio.create_task(reader.read(1))
                try:
                    timeout_seconds = max(
                        0.001,
                        (deadline - datetime.now(UTC)).total_seconds(),
                    )
                    async with asyncio.timeout(timeout_seconds):
                        done, _ = await asyncio.wait(
                            {provider_task, disconnected},
                            return_when=asyncio.FIRST_COMPLETED,
                        )
                    if disconnected in done:
                        provider_task.cancel()
                        await asyncio.gather(provider_task, return_exceptions=True)
                        return None
                    disconnected.cancel()
                    await asyncio.gather(disconnected, return_exceptions=True)
                    result = await provider_task
                except TimeoutError as exc:
                    provider_task.cancel()
                    await asyncio.gather(provider_task, return_exceptions=True)
                    raise CoachProviderError(
                        "provider_timeout",
                        "The executor turn timed out.",
                        retryable=True,
                    ) from exc
                except asyncio.CancelledError:
                    provider_task.cancel()
                    await asyncio.gather(provider_task, return_exceptions=True)
                    raise
                finally:
                    if not disconnected.done():
                        disconnected.cancel()
                    await asyncio.gather(disconnected, return_exceptions=True)
                trace = self._read_trace(trace_path)
                return self._ok(
                    "execute",
                    output=result.output.model_dump(mode="json"),
                    model_reported=result.model_reported,
                    trace_jsonl=trace,
                )
        finally:
            await self._reservations.finish(
                reservation_id,
                now=datetime.now(UTC),
            )

    @staticmethod
    def _snapshot(payload: dict[str, Any]) -> bytes:
        digest = bounded_text(
            payload["snapshot_sha256"],
            label="snapshot digest",
            max_bytes=64,
        )
        if len(digest) != 64 or any(char not in "0123456789abcdef" for char in digest):
            raise ExecutorProtocolError("Snapshot digest is invalid.")
        encoded = bounded_text(
            payload["snapshot_base64"],
            label="snapshot payload",
            max_bytes=12 * 1024 * 1024,
        )
        try:
            snapshot = base64.b64decode(encoded, validate=True)
        except (binascii.Error, ValueError) as exc:
            raise ExecutorProtocolError("Snapshot payload is invalid.") from exc
        if not snapshot or len(snapshot) > COACH_EXECUTOR_MAX_SNAPSHOT_BYTES:
            raise ExecutorProtocolError("Snapshot payload exceeds its limit.")
        if not hmac.compare_digest(hashlib.sha256(snapshot).hexdigest(), digest):
            raise ExecutorProtocolError("Snapshot digest does not match.")
        return snapshot

    @staticmethod
    def _write_private_file(path: Path, value: bytes) -> None:
        flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL
        if hasattr(os, "O_NOFOLLOW"):
            flags |= os.O_NOFOLLOW
        descriptor = os.open(path, flags, 0o600)
        try:
            with os.fdopen(descriptor, "wb", closefd=False) as handle:
                handle.write(value)
                handle.flush()
                os.fsync(handle.fileno())
        finally:
            os.close(descriptor)
        # The rootless daemon can traverse only the executor-owned 0700 turn
        # directory. Inside the read-only bind mount, however, the fixed
        # container UID 65532 still needs read permission on this one file.
        os.chmod(path, 0o444)

    @staticmethod
    def _read_trace(path: Path) -> str:
        try:
            if path.is_symlink() or not path.is_file():
                raise OSError
            size = path.stat().st_size
            if size < 0 or size > COACH_EXECUTOR_MAX_TRACE_BYTES:
                raise OSError
            raw = path.read_bytes()
            if len(raw) != size:
                raise OSError
            return raw.decode("utf-8", errors="strict")
        except (OSError, UnicodeDecodeError) as exc:
            raise CoachProviderError(
                "invalid_output",
                "The executor returned an invalid trace.",
                retryable=True,
            ) from exc

    @staticmethod
    def _uuid(value: object) -> UUID:
        if not isinstance(value, str):
            raise ExecutorProtocolError("Reservation identity is invalid.")
        try:
            parsed = UUID(value)
        except ValueError as exc:
            raise ExecutorProtocolError("Reservation identity is invalid.") from exc
        if str(parsed) != value:
            raise ExecutorProtocolError("Reservation identity is not canonical.")
        return parsed

    @staticmethod
    def _peer_uid(writer: asyncio.StreamWriter) -> int | None:
        peer_socket = writer.get_extra_info("socket")
        if peer_socket is None or not hasattr(socket, "SO_PEERCRED"):
            return None
        try:
            raw = peer_socket.getsockopt(
                socket.SOL_SOCKET,
                socket.SO_PEERCRED,
                _PEER_CREDENTIALS.size,
            )
            _pid, uid, _gid = _PEER_CREDENTIALS.unpack(raw)
            return uid
        except OSError:
            return None

    @staticmethod
    def _ok(operation: str, **values: object) -> dict[str, Any]:
        return {
            "protocol_version": COACH_EXECUTOR_PROTOCOL_VERSION,
            "status": "ok",
            "operation": operation,
            **values,
        }

    @staticmethod
    def _error(code: str, *, retryable: bool) -> dict[str, Any]:
        return {
            "protocol_version": COACH_EXECUTOR_PROTOCOL_VERSION,
            "status": "error",
            "error": {"code": code, "retryable": retryable},
        }


def _assert_secret_free_environment() -> None:
    present = sorted(
        name
        for name in os.environ
        if name in _FORBIDDEN_ENVIRONMENT_NAMES
        or name.startswith(_FORBIDDEN_ENVIRONMENT_PREFIXES)
    )
    if present:
        raise RuntimeError(
            "Executor environment contains forbidden application secrets."
        )


def _assert_rootless_runtime(settings: Settings) -> None:
    uid = os.getuid()
    expected_runtime_dir = f"/run/user/{uid}"
    expected_docker_host = f"unix://{expected_runtime_dir}/docker.sock"
    if os.environ.get("XDG_RUNTIME_DIR") != expected_runtime_dir:
        raise RuntimeError("Executor XDG runtime directory does not match its UID.")
    if settings.coach_analysis_docker_host != expected_docker_host:
        raise RuntimeError("Executor Docker host does not match its rootless UID.")
    if (
        _RELEASE_ANALYSIS_IMAGE_PATTERN.fullmatch(settings.coach_analysis_image)
        is None
    ):
        raise RuntimeError("Executor analysis image is not release-revision pinned.")
    if not settings.local_codex_expected_version:
        raise RuntimeError("Executor Codex CLI version is not pinned.")


def _systemd_socket() -> socket.socket | None:
    if os.environ.get("LISTEN_FDS") != "1":
        return None
    try:
        listen_pid = int(os.environ.get("LISTEN_PID", "0"))
    except ValueError:
        return None
    if listen_pid != os.getpid():
        return None
    inherited = socket.fromfd(3, socket.AF_UNIX, socket.SOCK_STREAM)
    inherited.setblocking(False)
    return inherited


async def _serve() -> None:
    _assert_secret_free_environment()
    settings = Settings(_env_file=None)
    if (
        not settings.operator_codex_pilot_enabled
        or settings.normalized_app_env not in {"staging", "pilot"}
        or settings.coach_executor_allowed_api_uid <= 0
    ):
        raise RuntimeError("Executor pilot configuration is disabled or incomplete.")
    _assert_rootless_runtime(settings)
    provider = LocalCodexCoachProvider(settings, operator_executor=True)
    executor = CoachExecutorServer(
        provider=provider,
        allowed_api_uid=settings.coach_executor_allowed_api_uid,
    )
    inherited = _systemd_socket()
    if inherited is not None:
        server = await asyncio.start_unix_server(
            executor.handle_connection,
            sock=inherited,
        )
    else:
        socket_path = Path(settings.coach_executor_socket_path)
        socket_path.parent.mkdir(mode=0o750, parents=True, exist_ok=True)
        if socket_path.exists() or socket_path.is_symlink():
            mode = socket_path.lstat().st_mode
            if not stat.S_ISSOCK(mode):
                raise RuntimeError("Executor socket path exists and is not a socket.")
            socket_path.unlink()
        server = await asyncio.start_unix_server(
            executor.handle_connection,
            path=str(socket_path),
        )
        os.chmod(socket_path, 0o660)
    async with server:
        await server.serve_forever()


def main() -> None:
    asyncio.run(_serve())


if __name__ == "__main__":
    main()
