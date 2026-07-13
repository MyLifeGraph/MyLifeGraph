import asyncio
import json
import os
import re
import shutil
import signal
import tempfile
import time
from collections.abc import Awaitable, Callable, Mapping
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from pydantic import ValidationError

from app.core.config import Settings
from app.models.coach import CoachModelOutput
from app.providers.base import (
    CoachProviderCapability,
    CoachProviderError,
    CoachProviderResult,
)


_MAX_STDIN_BYTES = 65_536
_MAX_STDOUT_BYTES = 262_144
_MAX_STDERR_BYTES = 32_768
_MAX_EVENTS = 128
_PREFLIGHT_TIMEOUT_SECONDS = 8
_READY_CAPABILITY_CACHE_SECONDS = 5.0
_UNAVAILABLE_CAPABILITY_CACHE_SECONDS = 1.0
_SCHEMA_PATH = (
    Path(__file__).resolve().parent / "schemas" / "coach_model_output_v1.json"
)

_ENV_ALLOWLIST = {
    "CODEX_HOME",
    "HOME",
    "PATH",
    "USER",
    "LOGNAME",
    "LANG",
    "LC_ALL",
    "SSL_CERT_FILE",
    "SSL_CERT_DIR",
}
_FORBIDDEN_EVENT_PARTS = {
    "approval",
    "browser",
    "command",
    "computer",
    "delegat",
    "exec",
    "file",
    "hook",
    "image",
    "mcp",
    "plugin",
    "search",
    "shell",
    "tool",
}
_ALLOWED_EVENT_TYPES = {
    "thread.started",
    "turn.started",
    "item.started",
    "item.completed",
    "turn.completed",
    "error",
}
_ALLOWED_CONTENT_ITEM_TYPES = {"reasoning", "agent_message"}
_NON_FATAL_ERROR_ITEM_TYPE = "error"


@dataclass(frozen=True)
class ProcessResult:
    returncode: int
    stdout: bytes
    stderr: bytes


@dataclass(frozen=True)
class _CapabilityCacheEntry:
    key: tuple[Any, ...]
    expires_at: float
    capability: CoachProviderCapability
    resolved_bin: str | None
    disabled_features: tuple[str, ...] | None


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
                raise stream_result
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


class LocalCodexCoachProvider:
    def __init__(
        self,
        settings: Settings,
        *,
        runner: ProcessRunner = run_bounded_process,
        environ: Mapping[str, str] | None = None,
        executable_resolver: Callable[[str], str | None] = shutil.which,
        monotonic: Callable[[], float] = time.monotonic,
    ) -> None:
        self._settings = settings
        self._runner = runner
        self._environ = environ if environ is not None else os.environ
        self._executable_resolver = executable_resolver
        self._monotonic = monotonic
        self._resolved_bin: str | None = None
        self._disabled_features: tuple[str, ...] | None = None
        self._capability_cache: _CapabilityCacheEntry | None = None
        self._capability_task: asyncio.Task[CoachProviderCapability] | None = None
        self._capability_task_key: tuple[Any, ...] | None = None

    async def capability(self) -> CoachProviderCapability:
        unavailable = self._configuration_reason()
        if unavailable is not None:
            self.invalidate_capability()
            return self._capability(state="unavailable", reason_code=unavailable)

        resolved = self._resolve_executable()
        if resolved is None:
            self.invalidate_capability()
            return self._capability(state="unavailable", reason_code="missing_cli")

        cache_key = self._capability_cache_key(resolved)
        cached = self._capability_cache
        if (
            cached is not None
            and cached.key == cache_key
            and cached.expires_at > self._monotonic()
        ):
            self._apply_cached_capability(cached)
            return cached.capability

        loop = asyncio.get_running_loop()
        task = self._capability_task
        if (
            task is None
            or task.done()
            or task.get_loop() is not loop
            or self._capability_task_key != cache_key
        ):
            task = loop.create_task(
                self._probe_capability(resolved=resolved, cache_key=cache_key),
            )
            self._capability_task = task
            self._capability_task_key = cache_key
        try:
            return await task
        finally:
            if self._capability_task is task and task.done():
                self._capability_task = None
                self._capability_task_key = None

    async def _probe_capability(
        self,
        *,
        resolved: str,
        cache_key: tuple[Any, ...],
    ) -> CoachProviderCapability:
        model = self._configured_model()

        try:
            help_result = await self._preflight([resolved, "--help"])
            exec_help = await self._preflight([resolved, "exec", "--help"])
            if help_result.returncode != 0 or exec_help.returncode != 0:
                return self._cache_capability(
                    cache_key=cache_key,
                    state="unavailable",
                    reason_code="unsupported_cli",
                )
            if not _supports_hardened_argv(help_result.stdout, exec_help.stdout):
                return self._cache_capability(
                    cache_key=cache_key,
                    state="unavailable",
                    reason_code="tool_free_unavailable",
                )
            features_result = await self._preflight([resolved, "features", "list"])
            if features_result.returncode != 0:
                return self._cache_capability(
                    cache_key=cache_key,
                    state="unavailable",
                    reason_code="tool_free_unavailable",
                )
            disabled = _available_features(features_result.stdout)
            if not {"shell_tool", "unified_exec"}.issubset(disabled):
                return self._cache_capability(
                    cache_key=cache_key,
                    state="unavailable",
                    reason_code="tool_free_unavailable",
                )
            login_result = await self._preflight([resolved, "login", "status"])
        except (CoachProviderError, OSError):
            return self._cache_capability(
                cache_key=cache_key,
                state="unavailable",
                reason_code="provider_failure",
            )
        if login_result.returncode != 0:
            return self._cache_capability(
                cache_key=cache_key,
                state="unavailable",
                reason_code="not_logged_in",
            )
        if not _is_chatgpt_oauth_login(
            login_result.stdout + b"\n" + login_result.stderr,
        ):
            return self._cache_capability(
                cache_key=cache_key,
                state="unavailable",
                reason_code="unsupported_auth_mode",
            )

        self._resolved_bin = resolved
        self._disabled_features = tuple(sorted(disabled))
        capability = CoachProviderCapability(
            state="ready",
            provider="local_codex_oauth",
            provider_mode="local_development_only",
            model_requested=model,
            model_source="explicit" if model is not None else "cli_default",
            reason_code="ready",
        )
        self._capability_cache = _CapabilityCacheEntry(
            key=cache_key,
            expires_at=self._monotonic() + _READY_CAPABILITY_CACHE_SECONDS,
            capability=capability,
            resolved_bin=resolved,
            disabled_features=self._disabled_features,
        )
        return capability

    async def respond(self, *, prompt: str) -> CoachProviderResult:
        if self._resolved_bin is None or self._disabled_features is None:
            capability = await self.capability()
            if capability.state != "ready":
                raise CoachProviderError(
                    capability.reason_code,
                    "The local Coach provider is unavailable.",
                    retryable=capability.reason_code
                    in {"provider_failure", "not_logged_in"},
                )
        assert self._resolved_bin is not None
        assert self._disabled_features is not None

        workdir = tempfile.mkdtemp(prefix="mylifegraph-coach-")
        os.chmod(workdir, 0o700)
        try:
            argv = self._response_argv(workdir)
            final_path = Path(workdir) / "coach-output.json"
            final_path.touch(mode=0o600, exist_ok=False)
            result = await self._runner(
                argv,
                stdin=prompt.encode("utf-8"),
                cwd=workdir,
                env=self._child_environment(),
                timeout_seconds=self._settings.local_codex_timeout_seconds,
                stdout_line_validator=_reject_unsafe_event_line,
            )
            if result.returncode != 0:
                error = _mapped_process_failure(result.stdout, result.stderr)
                if error.code in {"not_logged_in", "provider_failure"}:
                    self.invalidate_capability()
                raise error
            if final_path.is_symlink() or not final_path.is_file():
                raise CoachProviderError(
                    "invalid_output",
                    "The local Coach provider returned no bounded final answer.",
                    retryable=True,
                )
            if final_path.stat().st_size > 16_384:
                raise CoachProviderError(
                    "invalid_output",
                    "The local Coach provider returned an oversized final answer.",
                    retryable=True,
                )
            final_output = final_path.read_bytes()
            parsed = _parse_event_stream(result.stdout, final_output=final_output)
            requested = self._configured_model()
            if (
                requested is not None
                and parsed.model_reported is not None
                and parsed.model_reported != requested
            ):
                raise CoachProviderError(
                    "unavailable_model",
                    "The local Coach provider reported a different model.",
                    retryable=False,
                )
            return parsed
        except FileNotFoundError as exc:
            self.invalidate_capability()
            raise CoachProviderError(
                "missing_cli",
                "The local Coach CLI is unavailable.",
                retryable=False,
            ) from exc
        except CoachProviderError as exc:
            if exc.code in {"not_logged_in", "provider_failure"}:
                self.invalidate_capability()
            raise
        finally:
            shutil.rmtree(workdir, ignore_errors=True)

    def invalidate_capability(self) -> None:
        """Forget local CLI readiness after auth/process state changes."""

        self._capability_cache = None
        self._clear_ready_state()

    def _clear_ready_state(self) -> None:
        self._resolved_bin = None
        self._disabled_features = None

    def _cache_capability(
        self,
        *,
        cache_key: tuple[Any, ...],
        state: str,
        reason_code: str,
    ) -> CoachProviderCapability:
        self._clear_ready_state()
        capability = self._capability(state=state, reason_code=reason_code)
        self._capability_cache = _CapabilityCacheEntry(
            key=cache_key,
            expires_at=self._monotonic() + _UNAVAILABLE_CAPABILITY_CACHE_SECONDS,
            capability=capability,
            resolved_bin=None,
            disabled_features=None,
        )
        return capability

    def _apply_cached_capability(self, cached: _CapabilityCacheEntry) -> None:
        self._resolved_bin = cached.resolved_bin
        self._disabled_features = cached.disabled_features

    def _capability_cache_key(self, resolved: str) -> tuple[Any, ...]:
        try:
            stat = os.stat(resolved)
            executable_fingerprint: tuple[int, int, int, int] | None = (
                stat.st_dev,
                stat.st_ino,
                stat.st_size,
                stat.st_mtime_ns,
            )
        except OSError:
            executable_fingerprint = None
        child_environment = self._child_environment()
        return (
            resolved,
            executable_fingerprint,
            self._configured_model(),
            child_environment.get("CODEX_HOME"),
            child_environment.get("HOME"),
            child_environment.get("PATH"),
        )

    def _configuration_reason(self) -> str | None:
        if self._settings.app_env != "development":
            return "development_only"
        if self._settings.use_mock_data:
            return "mock_data_enabled"
        if self._settings.coach_provider != "local_codex_oauth":
            return "provider_not_enabled"
        if not self._settings.local_codex_enabled:
            return "provider_not_enabled"
        if not (
            self._settings.supabase_url.strip()
            and self._settings.supabase_service_role_key.strip()
        ):
            return "persistence_unconfigured"
        return None

    def _resolve_executable(self) -> str | None:
        configured = self._settings.local_codex_bin.strip()
        if not configured or any(char in configured for char in "\x00\r\n"):
            return None
        if os.path.sep in configured:
            path = Path(configured).expanduser()
            if path.is_file() and os.access(path, os.X_OK):
                return str(path.resolve())
            return None
        return self._executable_resolver(configured)

    async def _preflight(self, argv: list[str]) -> ProcessResult:
        with tempfile.TemporaryDirectory(prefix="mylifegraph-coach-check-") as workdir:
            os.chmod(workdir, 0o700)
            return await self._runner(
                argv,
                stdin=b"",
                cwd=workdir,
                env=self._child_environment(),
                timeout_seconds=_PREFLIGHT_TIMEOUT_SECONDS,
                max_stdout_bytes=65_536,
                max_stderr_bytes=16_384,
            )

    def _response_argv(self, workdir: str) -> list[str]:
        assert self._resolved_bin is not None
        assert self._disabled_features is not None
        argv = [
            self._resolved_bin,
            "--ask-for-approval",
            "never",
            "--strict-config",
            "--sandbox",
            "read-only",
            "--cd",
            workdir,
        ]
        model = self._configured_model()
        if model is not None:
            argv.extend(["--model", model])
        for feature in self._disabled_features:
            argv.extend(["--disable", feature])
        argv.extend(
            [
                "exec",
                "--ephemeral",
                "--ignore-user-config",
                "--ignore-rules",
                "--skip-git-repo-check",
                "--output-schema",
                str(_SCHEMA_PATH),
                "--output-last-message",
                str(Path(workdir) / "coach-output.json"),
                "--json",
                "--color",
                "never",
                "-",
            ],
        )
        return argv

    def _configured_model(self) -> str | None:
        model = self._settings.local_codex_model.strip()
        return model or None

    def _child_environment(self) -> dict[str, str]:
        return {
            key: value
            for key, value in self._environ.items()
            if key in _ENV_ALLOWLIST
        }

    def _capability(
        self,
        *,
        state: str,
        reason_code: str,
    ) -> CoachProviderCapability:
        model = self._configured_model()
        return CoachProviderCapability(
            state=state,  # type: ignore[arg-type]
            provider="local_codex_oauth",
            provider_mode="local_development_only",
            model_requested=model,
            model_source="explicit" if model is not None else "cli_default",
            reason_code=reason_code,
        )


def _supports_hardened_argv(help_stdout: bytes, exec_help_stdout: bytes) -> bool:
    global_help = help_stdout.decode("utf-8", errors="replace")
    exec_help = exec_help_stdout.decode("utf-8", errors="replace")
    return all(
        flag in global_help
        for flag in [
            "--ask-for-approval",
            "--disable",
            "--strict-config",
            "--sandbox",
            "--cd",
        ]
    ) and all(
        flag in exec_help
        for flag in [
            "--ephemeral",
            "--ignore-user-config",
            "--ignore-rules",
            "--skip-git-repo-check",
            "--output-schema",
            "--output-last-message",
            "--json",
        ]
    )


def _available_features(stdout: bytes) -> set[str]:
    features: set[str] = set()
    for line in stdout.decode("utf-8", errors="replace").splitlines():
        parts = line.split()
        if len(parts) < 3 or not re.fullmatch(r"[a-z][a-z0-9_]*", parts[0]):
            continue
        name, lifecycle = parts[0], parts[1]
        if lifecycle == "removed":
            continue
        features.add(name)
    return features


def _is_chatgpt_oauth_login(stdout: bytes) -> bool:
    """Accept only an explicit subscription/OAuth login status, without auth reads."""

    status = stdout.decode("utf-8", errors="replace").lower()
    if any(
        marker in status
        for marker in [
            "api key",
            "api-key",
            "api_key",
            "apikey",
            "access token",
            "access-token",
            "bearer token",
            "personal access token",
            "not logged in",
            "not authenticated",
            "login required",
            "logged out",
            "no active subscription",
            "inactive subscription",
        ]
    ):
        return False
    identifies_subscription_auth = any(
        marker in status for marker in ["chatgpt", "oauth", "subscription"]
    )
    confirms_active_login = any(
        marker in status for marker in ["logged in", "authenticated", "active"]
    )
    return identifies_subscription_auth and confirms_active_login


def _reject_unsafe_event_line(line: bytes) -> None:
    """Reject unsafe or terminal failure events while the process is running."""

    try:
        event = json.loads(line.decode("utf-8", errors="strict"))
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise CoachProviderError(
            "invalid_output",
            "The local Coach provider returned an invalid event.",
            retryable=True,
        ) from exc
    if not isinstance(event, dict):
        raise CoachProviderError(
            "invalid_output",
            "The local Coach provider returned an invalid event.",
            retryable=True,
        )
    _raise_if_unsafe_event(event)
    if event.get("type") in {"error", "turn.failed"}:
        raise _mapped_process_failure(line, b"")


def _raise_if_unsafe_event(event: Any) -> None:
    if isinstance(event, dict) and _has_unsafe_nested_shape(event):
        raise CoachProviderError(
            "unsafe_provider_event",
            "The local Coach provider attempted an unsupported operation.",
            retryable=False,
        )


def _parse_event_stream(
    stdout: bytes,
    *,
    final_output: bytes | None = None,
) -> CoachProviderResult:
    final_text: str | None = None
    model_reported: str | None = None
    seen_thread_started = False
    seen_turn_started = False
    seen_content_item_event = False
    seen_turn_completed = False
    try:
        lines = stdout.decode("utf-8", errors="strict").splitlines()
    except UnicodeDecodeError as exc:
        raise CoachProviderError(
            "invalid_output",
            "The local Coach provider returned invalid text encoding.",
            retryable=True,
        ) from exc
    if not lines or len(lines) > _MAX_EVENTS:
        raise CoachProviderError(
            "invalid_output",
            "The local Coach provider returned an invalid event stream.",
            retryable=True,
        )
    for line in lines:
        try:
            event = json.loads(line)
        except json.JSONDecodeError as exc:
            raise CoachProviderError(
                "invalid_output",
                "The local Coach provider returned invalid output.",
                retryable=True,
            ) from exc
        if not isinstance(event, dict):
            raise CoachProviderError(
                "invalid_output",
                "The local Coach provider returned an unexpected event.",
                retryable=True,
            )
        _raise_if_unsafe_event(event)
        extra_event_keys = set(event) - {
            "type",
            "thread_id",
            "item",
            "usage",
            "message",
            "model",
        }
        if extra_event_keys and any(
            any(part in key.lower() for part in _FORBIDDEN_EVENT_PARTS)
            for key in extra_event_keys
        ):
            raise CoachProviderError(
                "unsafe_provider_event",
                "The local Coach provider attempted an unsupported operation.",
                retryable=False,
            )
        if extra_event_keys:
            raise CoachProviderError(
                "invalid_output",
                "The local Coach provider returned an unexpected event.",
                retryable=True,
            )
        usage = event.get("usage")
        if usage is not None:
            if not isinstance(usage, dict):
                raise CoachProviderError(
                    "invalid_output",
                    "The local Coach provider returned invalid usage data.",
                    retryable=True,
                )
            if _has_unsafe_nested_shape(usage):
                raise CoachProviderError(
                    "unsafe_provider_event",
                    "The local Coach provider attempted an unsupported operation.",
                    retryable=False,
                )
        message = event.get("message")
        if message is not None and not isinstance(message, str):
            if _has_unsafe_nested_shape(message):
                raise CoachProviderError(
                    "unsafe_provider_event",
                    "The local Coach provider attempted an unsupported operation.",
                    retryable=False,
                )
            raise CoachProviderError(
                "invalid_output",
                "The local Coach provider returned invalid error data.",
                retryable=True,
            )
        event_type = event.get("type")
        if not isinstance(event_type, str):
            raise CoachProviderError(
                "invalid_output",
                "The local Coach provider returned an unsupported event.",
                retryable=True,
            )
        if any(part in event_type.lower() for part in _FORBIDDEN_EVENT_PARTS):
            raise CoachProviderError(
                "unsafe_provider_event",
                "The local Coach provider attempted an unsupported operation.",
                retryable=False,
            )
        if event_type in {"error", "turn.failed"}:
            raise _mapped_process_failure(line.encode("utf-8"), b"")
        if event_type not in _ALLOWED_EVENT_TYPES:
            raise CoachProviderError(
                "invalid_output",
                "The local Coach provider returned an unsupported event.",
                retryable=True,
            )
        if event_type == "thread.started":
            if (
                seen_thread_started
                or seen_turn_started
                or event.get("item") is not None
            ):
                raise CoachProviderError(
                    "invalid_output",
                    "The local Coach provider returned an invalid event sequence.",
                    retryable=True,
                )
            seen_thread_started = True
        elif event_type == "turn.started":
            if (
                not seen_thread_started
                or seen_turn_started
                or seen_content_item_event
                or seen_turn_completed
                or event.get("item") is not None
            ):
                raise CoachProviderError(
                    "invalid_output",
                    "The local Coach provider returned an invalid event sequence.",
                    retryable=True,
                )
            seen_turn_started = True
        elif event_type in {"item.started", "item.completed"}:
            if (
                not seen_thread_started
                or seen_turn_completed
                or event.get("item") is None
            ):
                raise CoachProviderError(
                    "invalid_output",
                    "The local Coach provider returned an invalid event sequence.",
                    retryable=True,
                )
        elif event_type == "turn.completed":
            if (
                not seen_thread_started
                or seen_turn_completed
                or event.get("item") is not None
            ):
                raise CoachProviderError(
                    "invalid_output",
                    "The local Coach provider returned an invalid event sequence.",
                    retryable=True,
                )
            seen_turn_completed = True
        _validated_event_text(
            event.get("thread_id"),
            field="thread_id",
            limit=200,
        )
        reported = _validated_event_text(
            event.get("model"),
            field="model",
            limit=100,
        )
        if reported is not None:
            model_reported = reported
        item = event.get("item")
        if item is None:
            continue
        if not isinstance(item, dict):
            raise CoachProviderError(
                "invalid_output",
                "The local Coach provider returned an invalid item.",
                retryable=True,
            )
        item_type = item.get("type")
        if not isinstance(item_type, str):
            raise CoachProviderError(
                "invalid_output",
                "The local Coach provider returned an invalid item.",
                retryable=True,
            )
        if any(part in item_type.lower() for part in _FORBIDDEN_EVENT_PARTS):
            raise CoachProviderError(
                "unsafe_provider_event",
                "The local Coach provider attempted an unsupported operation.",
                retryable=False,
            )
        if item_type == _NON_FATAL_ERROR_ITEM_TYPE:
            if event_type != "item.completed" or set(event) != {"type", "item"}:
                raise CoachProviderError(
                    "invalid_output",
                    "The local Coach provider returned an invalid non-fatal error item.",
                    retryable=True,
                )
            if set(item) != {"id", "type", "message"}:
                raise CoachProviderError(
                    "invalid_output",
                    "The local Coach provider returned an invalid non-fatal error item.",
                    retryable=True,
                )
            error_item_id = _validated_event_text(
                item.get("id"),
                field="item id",
                limit=200,
            )
            error_message = _validated_event_text(
                item.get("message"),
                field="non-fatal error item message",
                limit=4_096,
            )
            if error_item_id is None or error_message is None:
                raise CoachProviderError(
                    "invalid_output",
                    "The local Coach provider returned an invalid non-fatal error item.",
                    retryable=True,
                )
            continue
        if item_type not in _ALLOWED_CONTENT_ITEM_TYPES:
            raise CoachProviderError(
                "invalid_output",
                "The local Coach provider returned an unsupported item.",
                retryable=True,
            )
        if set(item) - {"id", "type", "text"} or _has_unsafe_nested_shape(item):
            raise CoachProviderError(
                "unsafe_provider_event",
                "The local Coach provider attempted an unsupported operation.",
                retryable=False,
            )
        item_text = item.get("text")
        if "text" in item and (
            not isinstance(item_text, str) or len(item_text) > 16_384
        ):
            raise CoachProviderError(
                "invalid_output",
                "The local Coach provider returned invalid item text.",
                retryable=True,
            )
        seen_content_item_event = True
        if item_type == "agent_message" and event_type == "item.completed":
            text = item_text
            if not isinstance(text, str) or final_text is not None:
                raise CoachProviderError(
                    "invalid_output",
                    "The local Coach provider returned an invalid final answer.",
                    retryable=True,
                )
            final_text = text
    if (
        final_text is None
        or not seen_thread_started
        or not seen_turn_completed
    ):
        raise CoachProviderError(
            "invalid_output",
            "The local Coach provider returned no final answer.",
            retryable=True,
        )
    if final_output is not None:
        try:
            final_file_text = final_output.decode("utf-8", errors="strict").strip()
        except UnicodeDecodeError as exc:
            raise CoachProviderError(
                "invalid_output",
                "The local Coach provider returned invalid text encoding.",
                retryable=True,
            ) from exc
        if final_file_text != final_text.strip():
            raise CoachProviderError(
                "invalid_output",
                "The local Coach provider final answer was inconsistent.",
                retryable=True,
            )
    try:
        payload: Any = json.loads(final_text)
        output = CoachModelOutput.model_validate(payload)
    except (json.JSONDecodeError, ValidationError) as exc:
        raise CoachProviderError(
            "invalid_output",
            "The local Coach provider returned an invalid answer.",
            retryable=True,
        ) from exc
    return CoachProviderResult(output=output, model_reported=model_reported)


def _has_unsafe_nested_shape(value: Any) -> bool:
    if isinstance(value, dict):
        for key, nested in value.items():
            lowered = str(key).lower()
            if any(part in lowered for part in _FORBIDDEN_EVENT_PARTS):
                return True
            if key == "type" and isinstance(nested, str) and any(
                part in nested.lower() for part in _FORBIDDEN_EVENT_PARTS
            ):
                return True
            if (
                key != "text" or not isinstance(nested, str)
            ) and _has_unsafe_nested_shape(nested):
                return True
    elif isinstance(value, list):
        return any(_has_unsafe_nested_shape(item) for item in value)
    return False


def _validated_event_text(
    value: Any,
    *,
    field: str,
    limit: int,
) -> str | None:
    if value is None:
        return None
    if isinstance(value, str):
        normalized = value.strip()
        if normalized and len(normalized) <= limit:
            return normalized
    if _has_unsafe_nested_shape(value):
        raise CoachProviderError(
            "unsafe_provider_event",
            "The local Coach provider attempted an unsupported operation.",
            retryable=False,
        )
    raise CoachProviderError(
        "invalid_output",
        f"The local Coach provider returned an invalid {field}.",
        retryable=True,
    )


def _mapped_process_failure(stdout: bytes, stderr: bytes) -> CoachProviderError:
    """Classify bounded machine errors without exposing their raw content."""

    fragments: list[str] = []
    for line in stdout.splitlines()[:_MAX_EVENTS]:
        try:
            event = json.loads(line.decode("utf-8", errors="strict"))
        except (UnicodeDecodeError, json.JSONDecodeError):
            continue
        if not isinstance(event, dict) or event.get("type") not in {
            "error",
            "turn.failed",
        }:
            continue
        message = event.get("message")
        if isinstance(message, str):
            fragments.append(message[:4_096])
        error = event.get("error")
        if isinstance(error, str):
            fragments.append(error[:4_096])
        elif isinstance(error, dict):
            for key in ("code", "message", "type"):
                value = error.get(key)
                if isinstance(value, str):
                    fragments.append(value[:4_096])
    structured = "\n".join(fragments).encode("utf-8")
    return _mapped_failure(stderr + b"\n" + structured)


def _mapped_failure(stderr: bytes) -> CoachProviderError:
    diagnostic = stderr.decode("utf-8", errors="replace").lower()
    if any(
        marker in diagnostic
        for marker in [
            "not logged in",
            "login required",
            "authentication required",
            "unauthorized",
        ]
    ):
        return CoachProviderError(
            "not_logged_in",
            "The local Codex CLI is not authenticated.",
            retryable=False,
        )
    if any(
        marker in diagnostic
        for marker in [
            "model not found",
            "unknown model",
            "unsupported model",
            "model is not supported",
            "model does not exist",
            "model unavailable",
            "model_not_found",
            "unsupported_model",
        ]
    ) or re.search(
        r"\bmodel\b.{0,160}\b(?:not supported|not available|does not exist)\b",
        diagnostic,
        flags=re.DOTALL,
    ):
        return CoachProviderError(
            "unavailable_model",
            "The explicitly configured Coach model is unavailable.",
            retryable=False,
        )
    if any(
        marker in diagnostic
        for marker in ["rate limit", "usage limit", "account limit", "quota"]
    ):
        return CoachProviderError(
            "account_limit",
            "The local Codex account limit has been reached.",
            retryable=True,
        )
    return CoachProviderError(
        "provider_failure",
        "The local Coach provider failed.",
        retryable=True,
    )
