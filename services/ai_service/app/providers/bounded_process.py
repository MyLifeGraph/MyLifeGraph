import asyncio
import os
import signal
from collections.abc import Awaitable, Callable, Mapping
from dataclasses import dataclass

from app.providers.base import CoachProviderError


_MAX_STDIN_BYTES = 65_536
_MAX_STDOUT_BYTES = 262_144
_MAX_STDERR_BYTES = 32_768
_MAX_EVENTS = 128


@dataclass(frozen=True)
class ProcessResult:
    returncode: int
    stdout: bytes
    stderr: bytes


ProcessRunner = Callable[..., Awaitable[ProcessResult]]
StdoutLineValidator = Callable[[bytes], None]


class ProcessOutputLimitError(RuntimeError):
    pass


async def run_bounded_process(
    argv: list[str],
    *,
    stdin: bytes,
    cwd: str,
    env: Mapping[str, str],
    timeout_seconds: int,
    max_stdout_bytes: int = _MAX_STDOUT_BYTES,
    max_stderr_bytes: int = _MAX_STDERR_BYTES,
    stdout_line_validator: StdoutLineValidator | None = None,
) -> ProcessResult:
    """Run a fixed argv without a shell and bound both output streams."""

    if len(stdin) > _MAX_STDIN_BYTES:
        raise CoachProviderError(
            "context_too_large",
            "The bounded Coach prompt is too large.",
            retryable=False,
        )
    process = await asyncio.create_subprocess_exec(
        *argv,
        stdin=asyncio.subprocess.PIPE,
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.PIPE,
        cwd=cwd,
        env=dict(env),
        start_new_session=True,
    )
    assert process.stdin is not None
    assert process.stdout is not None
    assert process.stderr is not None

    async def read_bounded(
        stream: asyncio.StreamReader,
        limit: int,
        *,
        line_validator: StdoutLineValidator | None = None,
    ) -> bytes:
        chunks: list[bytes] = []
        pending_line = bytearray()
        validated_lines = 0
        size = 0

        def validate_line(line: bytes) -> None:
            nonlocal validated_lines
            if line_validator is None or not line:
                return
            validated_lines += 1
            if validated_lines > _MAX_EVENTS:
                raise CoachProviderError(
                    "invalid_output",
                    "The local Coach provider returned too many events.",
                    retryable=True,
                )
            line_validator(line)

        while True:
            chunk = await stream.read(8_192)
            if not chunk:
                if line_validator is not None and pending_line:
                    validate_line(bytes(pending_line).removesuffix(b"\r"))
                return b"".join(chunks)
            size += len(chunk)
            if size > limit:
                raise ProcessOutputLimitError
            chunks.append(chunk)
            if line_validator is None:
                continue
            pending_line.extend(chunk)
            while True:
                newline = pending_line.find(b"\n")
                if newline < 0:
                    break
                line = bytes(pending_line[:newline]).removesuffix(b"\r")
                del pending_line[: newline + 1]
                validate_line(line)

    stdout_task = asyncio.create_task(
        read_bounded(
            process.stdout,
            max_stdout_bytes,
            line_validator=stdout_line_validator,
        ),
    )
    stderr_task = asyncio.create_task(read_bounded(process.stderr, max_stderr_bytes))
    try:
        async with asyncio.timeout(timeout_seconds):
            process.stdin.write(stdin)
            await process.stdin.drain()
            process.stdin.close()
            await process.stdin.wait_closed()
            returncode, stdout, stderr = await asyncio.gather(
                process.wait(),
                stdout_task,
                stderr_task,
            )
    except TimeoutError as exc:
        await _terminate_process_group(process)
        raise CoachProviderError(
            "timeout",
            "The local Coach provider timed out.",
            retryable=True,
        ) from exc
    except ProcessOutputLimitError as exc:
        await _terminate_process_group(process)
        raise CoachProviderError(
            "invalid_output",
            "The local Coach provider returned too much data.",
            retryable=True,
        ) from exc
    except (BrokenPipeError, ConnectionResetError) as exc:
        await _terminate_process_group(process)
        stream_results = await asyncio.gather(
            stdout_task,
            stderr_task,
            return_exceptions=True,
        )
        for stream_result in stream_results:
            if isinstance(stream_result, CoachProviderError):
                raise stream_result from exc
            if isinstance(stream_result, ProcessOutputLimitError):
                raise CoachProviderError(
                    "invalid_output",
                    "The local Coach provider returned too much data.",
                    retryable=True,
                ) from stream_result
        raise CoachProviderError(
            "provider_failure",
            "The local Coach provider exited before accepting its input.",
            retryable=True,
        ) from exc
    except BaseException:
        await _terminate_process_group(process)
        raise
    finally:
        for task in (stdout_task, stderr_task):
            if not task.done():
                task.cancel()
        await asyncio.gather(stdout_task, stderr_task, return_exceptions=True)

    return ProcessResult(returncode=returncode, stdout=stdout, stderr=stderr)


async def _terminate_process_group(process: asyncio.subprocess.Process) -> None:
    if process.returncode is not None:
        await process.wait()
        return
    try:
        os.killpg(process.pid, signal.SIGTERM)
    except ProcessLookupError:
        pass
    try:
        await asyncio.wait_for(process.wait(), timeout=1)
        return
    except TimeoutError:
        pass
    try:
        os.killpg(process.pid, signal.SIGKILL)
    except ProcessLookupError:
        pass
    await process.wait()
