import asyncio
import json
import os
import socket
import struct
import tempfile
from datetime import UTC, datetime, timedelta
from pathlib import Path
from uuid import UUID

import pytest

from app.coach_executor import (
    CoachExecutorReservations,
    CoachExecutorServer,
    _BusyError,
    _ReservationError,
    _assert_rootless_runtime,
)
from app.coach_executor_protocol import (
    COACH_EXECUTOR_MAX_REQUEST_BYTES,
    COACH_EXECUTOR_MAX_RESPONSE_BYTES,
    COACH_EXECUTOR_PROTOCOL_VERSION,
    ExecutorProtocolError,
    ExecutorProtocolTimeout,
    decode_json_object,
    encode_json_object,
    read_frame,
    write_frame,
)
from app.core.config import Settings
from app.models.coach import CoachAgentModelOutput
from app.providers.base import (
    CoachAgentProviderResult,
    CoachProviderCapability,
    CoachProviderError,
)
from app.providers.operator_executor import OperatorExecutorCoachProvider


NOW = datetime(2026, 8, 19, 20, tzinfo=UTC)


def _unix_socket_io_supported() -> bool:
    left = right = None
    try:
        left, right = socket.socketpair(socket.AF_UNIX, socket.SOCK_STREAM)
        left.sendall(b"x")
        return right.recv(1) == b"x"
    except OSError:
        return False
    finally:
        if left is not None:
            left.close()
        if right is not None:
            right.close()


_REQUIRES_UNIX_SOCKET_IO = pytest.mark.skipif(
    not _unix_socket_io_supported(),
    reason="the execution sandbox blocks Unix-socket I/O",
)


class ExecutorProvider:
    def __init__(self) -> None:
        self.calls = 0
        self.capability_calls = 0
        self.started = asyncio.Event()
        self.cancelled = asyncio.Event()
        self.block = False

    async def capability(self) -> CoachProviderCapability:
        self.capability_calls += 1
        return CoachProviderCapability(
            state="ready",
            provider="local_codex_oauth",
            provider_mode="local_development_only",
            model_requested="gpt-5.5",
            model_source="explicit",
            reason_code="ready",
        )

    async def respond_agent(
        self,
        *,
        prompt: str,
        snapshot_path: Path,
        trace_path: Path,
        activity_callback=None,
    ) -> CoachAgentProviderResult:
        del activity_callback
        assert prompt == "Bounded operator prompt"
        assert snapshot_path.read_bytes() == b"SQLite test snapshot"
        assert snapshot_path.stat().st_mode & 0o777 == 0o444
        self.calls += 1
        self.started.set()
        if self.block:
            try:
                await asyncio.Event().wait()
            except asyncio.CancelledError:
                self.cancelled.set()
                raise
        trace_path.write_text(
            json.dumps(
                {
                    "sequence": 1,
                    "tool": "inspect_data",
                    "status": "completed",
                    "summary": "Inspected the bounded snapshot.",
                    "row_count": None,
                    "duration_ms": 1,
                    "tables": [],
                },
            )
            + "\n",
            encoding="utf-8",
        )
        return CoachAgentProviderResult(
            output=CoachAgentModelOutput(
                reply="The bounded snapshot contains a test record.",
                uncertainty={
                    "level": "medium",
                    "reason": "This deterministic executor test is bounded.",
                },
                safety={"classification": "normal"},
            ),
            model_reported="gpt-5.5",
        )


def _settings(socket_path: str) -> Settings:
    return Settings(
        _env_file=None,
        APP_ENV="staging",
        USE_MOCK_DATA=False,
        OPERATOR_CODEX_PILOT_ENABLED=True,
        COACH_EXECUTOR_SOCKET_PATH=socket_path,
    )


async def _stream_pair():
    client_socket, server_socket = socket.socketpair(
        socket.AF_UNIX,
        socket.SOCK_STREAM,
    )
    client_socket.setblocking(False)
    server_socket.setblocking(False)
    client = await asyncio.open_connection(sock=client_socket)
    server = await asyncio.open_connection(sock=server_socket)
    return client, server


async def _with_server(provider, operation, *, server_type=CoachExecutorServer):
    executor = server_type(
        provider=provider,
        allowed_api_uid=os.getuid(),
    )
    tasks: list[asyncio.Task[None]] = []

    async def connect():
        (
            (client_reader, client_writer),
            (server_reader, server_writer),
        ) = await _stream_pair()
        tasks.append(
            asyncio.create_task(
                executor.handle_connection(server_reader, server_writer),
            ),
        )
        return client_reader, client_writer

    client = OperatorExecutorCoachProvider(
        _settings("/tmp/unused-executor.sock"),
        connector=connect,
    )
    try:
        return await operation(client)
    finally:
        if tasks:
            await asyncio.gather(*tasks, return_exceptions=True)


def test_protocol_rejects_duplicate_keys_and_oversized_output() -> None:
    with pytest.raises(ExecutorProtocolError):
        decode_json_object(b'{"operation":"reserve","operation":"execute"}', label="x")
    with pytest.raises(ExecutorProtocolError):
        encode_json_object({"value": "x" * 20}, max_bytes=10)


def test_frame_timeout_remains_distinct_from_malformed_input() -> None:
    async def run() -> None:
        reader = asyncio.StreamReader()
        with pytest.raises(ExecutorProtocolTimeout):
            await read_frame(reader, max_bytes=32, timeout_seconds=0.001)

    asyncio.run(run())


def test_operator_client_maps_protocol_timeout_to_provider_timeout() -> None:
    class TimedOutClient(OperatorExecutorCoachProvider):
        async def _round_trip(self, request, *, response_timeout_seconds=5):
            del request, response_timeout_seconds
            raise ExecutorProtocolTimeout("bounded timeout")

    client = TimedOutClient(_settings("/tmp/unused-executor.sock"))
    with pytest.raises(CoachProviderError) as caught:
        asyncio.run(client.reserve())
    assert caught.value.code == "provider_timeout"
    assert caught.value.retryable is True


def test_operator_client_accepts_missing_reported_model_but_rejects_mismatch(
    tmp_path: Path,
) -> None:
    class ResultClient(OperatorExecutorCoachProvider):
        def __init__(self, model_reported) -> None:
            super().__init__(_settings("/tmp/unused-executor.sock"))
            self.model_reported = model_reported

        async def _round_trip(self, request, *, response_timeout_seconds=5):
            del request, response_timeout_seconds
            return {
                "protocol_version": COACH_EXECUTOR_PROTOCOL_VERSION,
                "status": "ok",
                "operation": "execute",
                "output": {
                    "reply": "Bounded response.",
                    "uncertainty": {
                        "level": "medium",
                        "reason": "The CLI did not report a model field.",
                    },
                    "safety": {"classification": "normal"},
                },
                "model_reported": self.model_reported,
                "trace_jsonl": "",
            }

    snapshot = tmp_path / "snapshot.sqlite"
    snapshot.write_bytes(b"bounded snapshot")
    trace = tmp_path / "trace.jsonl"
    result = asyncio.run(
        ResultClient(None).respond_agent_reserved(
            reservation_id=UUID("11111111-1111-4111-8111-111111111111"),
            prompt="prompt",
            snapshot_path=snapshot,
            trace_path=trace,
        ),
    )
    assert result.model_reported is None
    assert trace.read_bytes() == b""

    with pytest.raises(CoachProviderError) as caught:
        asyncio.run(
            ResultClient("other-model").respond_agent_reserved(
                reservation_id=UUID("22222222-2222-4222-8222-222222222222"),
                prompt="prompt",
                snapshot_path=snapshot,
                trace_path=trace,
            ),
        )
    assert caught.value.code == "unavailable_model"


def test_executor_rootless_socket_must_match_process_uid(monkeypatch) -> None:
    uid = os.getuid()
    expected_runtime = f"/run/user/{uid}"
    monkeypatch.setenv("XDG_RUNTIME_DIR", expected_runtime)
    settings = _settings("/tmp/unused-executor.sock").model_copy(
        update={
            "coach_analysis_docker_host": (f"unix://{expected_runtime}/docker.sock"),
            "coach_analysis_image": (
                "mylifegraph-coach-analysis:sha256-" + "a" * 64
            ),
            "local_codex_expected_version": "0.147.0",
        },
    )
    _assert_rootless_runtime(settings)

    monkeypatch.setenv("XDG_RUNTIME_DIR", "/run/user/999999")
    with pytest.raises(RuntimeError, match="XDG runtime"):
        _assert_rootless_runtime(settings)

    monkeypatch.setenv("XDG_RUNTIME_DIR", expected_runtime)
    with pytest.raises(RuntimeError, match="release-revision pinned"):
        _assert_rootless_runtime(
            settings.model_copy(
                update={"coach_analysis_image": "mylifegraph-coach-analysis:1"},
            ),
        )


def test_reservations_are_single_slot_one_use_and_expire() -> None:
    async def run() -> None:
        reservations = CoachExecutorReservations()
        reservation_id, expires_at = await reservations.reserve(now=NOW)
        assert expires_at == NOW + timedelta(seconds=240)
        with pytest.raises(_BusyError):
            await reservations.reserve(now=NOW)
        await reservations.begin_execution(
            reservation_id,
            now=NOW,
            deadline=NOW + timedelta(seconds=180),
        )
        await reservations.finish(reservation_id, now=NOW)
        with pytest.raises(_ReservationError):
            await reservations.begin_execution(
                reservation_id,
                now=NOW,
                deadline=NOW + timedelta(seconds=180),
            )
        replacement, _ = await reservations.reserve(now=NOW)
        await reservations.release(replacement, now=NOW)
        expired, _ = await reservations.reserve(now=NOW)
        assert expired != replacement
        newer, _ = await reservations.reserve(now=NOW + timedelta(seconds=241))
        assert newer != expired

    asyncio.run(run())


@_REQUIRES_UNIX_SOCKET_IO
def test_operator_client_executes_once_and_cannot_reuse_token() -> None:
    async def operation(client: OperatorExecutorCoachProvider) -> None:
        capability = await client.capability()
        assert capability.state == "ready"
        assert capability.provider == "operator_codex_pilot"
        reservation_id = await client.reserve()
        with pytest.raises(CoachProviderError) as busy:
            await client.reserve()
        assert busy.value.code == "provider_busy"
        with tempfile.TemporaryDirectory(prefix="coach-client-test-") as workdir:
            snapshot_path = Path(workdir) / "snapshot.sqlite"
            snapshot_path.write_bytes(b"SQLite test snapshot")
            trace_path = Path(workdir) / "trace.jsonl"
            result = await client.respond_agent_reserved(
                reservation_id=reservation_id,
                prompt="Bounded operator prompt",
                snapshot_path=snapshot_path,
                trace_path=trace_path,
            )
            assert result.model_reported == "gpt-5.5"
            assert result.output.reply.startswith("The bounded snapshot")
            assert json.loads(trace_path.read_text())["tool"] == "inspect_data"
            with pytest.raises(CoachProviderError) as reused:
                await client.respond_agent_reserved(
                    reservation_id=reservation_id,
                    prompt="Bounded operator prompt",
                    snapshot_path=snapshot_path,
                    trace_path=Path(workdir) / "second-trace.jsonl",
                )
            assert reused.value.code == "invalid_reservation"
        await client.release_reservation(reservation_id)

    provider = ExecutorProvider()
    asyncio.run(_with_server(provider, operation))
    assert provider.calls == 1


@_REQUIRES_UNIX_SOCKET_IO
def test_client_disconnect_cancels_executor_work_and_releases_slot() -> None:
    async def operation(client: OperatorExecutorCoachProvider) -> None:
        reservation_id = await client.reserve()
        with tempfile.TemporaryDirectory(prefix="coach-cancel-test-") as workdir:
            snapshot_path = Path(workdir) / "snapshot.sqlite"
            snapshot_path.write_bytes(b"SQLite test snapshot")
            task = asyncio.create_task(
                client.respond_agent_reserved(
                    reservation_id=reservation_id,
                    prompt="Bounded operator prompt",
                    snapshot_path=snapshot_path,
                    trace_path=Path(workdir) / "trace.jsonl",
                ),
            )
            await provider.started.wait()
            task.cancel()
            await asyncio.gather(task, return_exceptions=True)
            await asyncio.wait_for(provider.cancelled.wait(), timeout=1)
            for _ in range(20):
                try:
                    replacement = await client.reserve()
                    break
                except CoachProviderError as exc:
                    assert exc.code == "provider_busy"
                    await asyncio.sleep(0)
            else:
                raise AssertionError("Executor slot was not released after disconnect.")
            await client.release_reservation(replacement)

    provider = ExecutorProvider()
    provider.block = True
    asyncio.run(_with_server(provider, operation))
    assert provider.capability_calls == 0


@_REQUIRES_UNIX_SOCKET_IO
def test_server_rejects_oversized_frame_before_provider_work() -> None:
    async def run() -> None:
        provider = ExecutorProvider()
        executor = CoachExecutorServer(
            provider=provider,
            allowed_api_uid=os.getuid(),
        )
        (reader, writer), (server_reader, server_writer) = await _stream_pair()
        task = asyncio.create_task(
            executor.handle_connection(server_reader, server_writer),
        )
        writer.write(
            struct.pack("!I", COACH_EXECUTOR_MAX_REQUEST_BYTES + 1),
        )
        await writer.drain()
        response = decode_json_object(
            await read_frame(
                reader,
                max_bytes=COACH_EXECUTOR_MAX_RESPONSE_BYTES,
            ),
            label="error response",
        )
        assert response["error"] == {
            "code": "invalid_request",
            "retryable": False,
        }
        writer.close()
        await writer.wait_closed()
        await task
        assert provider.calls == 0

    asyncio.run(run())


@_REQUIRES_UNIX_SOCKET_IO
def test_server_rejects_unauthorized_peer_before_reading_a_request() -> None:
    class DeniedExecutorServer(CoachExecutorServer):
        @staticmethod
        def _peer_uid(writer) -> int | None:
            del writer
            return os.getuid() + 1

    async def operation(client: OperatorExecutorCoachProvider) -> None:
        capability = await client.capability()
        assert capability.state == "unavailable"
        assert capability.reason_code == "provider_failure"

    provider = ExecutorProvider()
    asyncio.run(
        _with_server(
            provider,
            operation,
            server_type=DeniedExecutorServer,
        ),
    )
    assert provider.capability_calls == 0
    assert provider.calls == 0


@_REQUIRES_UNIX_SOCKET_IO
def test_frame_helpers_round_trip_one_exact_object() -> None:
    async def handle(reader, writer) -> None:
        request = decode_json_object(
            await read_frame(reader, max_bytes=1024),
            label="request",
        )
        await write_frame(writer, request, max_bytes=1024)
        writer.close()

    async def run() -> None:
        (reader, writer), (server_reader, server_writer) = await _stream_pair()
        task = asyncio.create_task(handle(server_reader, server_writer))
        payload = {
            "protocol_version": COACH_EXECUTOR_PROTOCOL_VERSION,
            "operation": "capability",
        }
        await write_frame(writer, payload, max_bytes=1024)
        echoed = decode_json_object(
            await read_frame(reader, max_bytes=1024),
            label="response",
        )
        assert echoed == payload
        writer.close()
        await writer.wait_closed()
        await task

    asyncio.run(run())
