"""Secret-safe local runner for scheduled daily preparation."""

from __future__ import annotations

import argparse
import ipaddress
import json
import math
import os
import signal
import sys
import threading
import urllib.parse
import urllib.request
from collections.abc import Callable, Mapping, Sequence
from contextlib import contextmanager
from dataclasses import dataclass, field
from types import FrameType
from typing import Any, Protocol
from uuid import UUID


_ENDPOINT_PATH = "/v1/scheduled/daily-refresh"
_DEFAULT_BASE_URL = "http://127.0.0.1:8000"
_DEFAULT_INTERVAL_SECONDS = 900.0
_DEFAULT_TIMEOUT_SECONDS = 20.0
_MAX_PROFILE_IDS = 20
_MAX_RESPONSE_BYTES = 1_048_576

_EXIT_OK = 0
_EXIT_RUN_FAILED = 1
_EXIT_CONFIGURATION_ERROR = 2


class _Response(Protocol):
    def __enter__(self) -> _Response: ...

    def __exit__(self, *args: object) -> None: ...

    def read(self, amount: int = -1) -> bytes: ...

    def getcode(self) -> int: ...


Transport = Callable[[urllib.request.Request, float], _Response]
Output = Callable[[str], None]
Wait = Callable[[float], bool]


@dataclass(frozen=True, slots=True)
class RunnerConfig:
    """Validated inputs for one local runner process."""

    endpoint_url: str
    token: str = field(repr=False)
    profile_ids: tuple[str, ...] = ()
    timeout_seconds: float = _DEFAULT_TIMEOUT_SECONDS
    interval_seconds: float = _DEFAULT_INTERVAL_SECONDS

    def __post_init__(self) -> None:
        _validate_endpoint_url(self.endpoint_url)
        if (
            not isinstance(self.token, str)
            or not self.token
            or self.token != self.token.strip()
        ):
            raise RunnerConfigurationError("scheduler token is invalid")
        object.__setattr__(self, "profile_ids", _parse_profile_ids(self.profile_ids))
        _validate_seconds(self.timeout_seconds, name="timeout")
        _validate_seconds(self.interval_seconds, name="interval")


@dataclass(frozen=True, slots=True)
class RunSummary:
    """Non-identifying aggregate fields from the scheduler response."""

    processed: int
    succeeded: int
    failed: int


class RunnerConfigurationError(ValueError):
    """Raised before any request when local runner configuration is unsafe."""


class RunnerRequestError(RuntimeError):
    """Sanitized request or response failure safe to classify in output."""

    def __init__(self, category: str) -> None:
        super().__init__(category)
        self.category = category


class _SafeArgumentParser(argparse.ArgumentParser):
    def error(self, message: str) -> None:
        del message
        raise RunnerConfigurationError("invalid command arguments")


class _NoRedirectHandler(urllib.request.HTTPRedirectHandler):
    def redirect_request(
        self,
        request: urllib.request.Request,
        file_pointer: Any,
        code: int,
        message: str,
        headers: Any,
        new_url: str,
    ) -> None:
        del request, file_pointer, code, message, headers, new_url
        return None


def _default_transport(
    request: urllib.request.Request,
    timeout_seconds: float,
) -> _Response:
    # A local operational token must not be forwarded through environment proxy
    # settings or across a redirect.
    opener = urllib.request.build_opener(
        urllib.request.ProxyHandler({}),
        _NoRedirectHandler(),
    )
    return opener.open(request, timeout=timeout_seconds)


def _build_endpoint_url(base_url: str) -> str:
    value = base_url.strip()
    if not value:
        raise RunnerConfigurationError("base URL is required")

    parsed = _parse_loopback_url(value)
    if parsed.path not in {"", "/"}:
        raise RunnerConfigurationError("base URL must not contain a path")

    return urllib.parse.urlunsplit(
        (parsed.scheme, parsed.netloc, _ENDPOINT_PATH, "", ""),
    )


def _validate_endpoint_url(endpoint_url: str) -> None:
    if not isinstance(endpoint_url, str):
        raise RunnerConfigurationError("endpoint URL is invalid")
    value = endpoint_url.strip()
    if not value or value != endpoint_url:
        raise RunnerConfigurationError("endpoint URL is invalid")
    parsed = _parse_loopback_url(value)
    if parsed.path != _ENDPOINT_PATH:
        raise RunnerConfigurationError("endpoint path is invalid")


def _parse_loopback_url(value: str) -> urllib.parse.SplitResult:
    try:
        parsed = urllib.parse.urlsplit(value)
        port = parsed.port
    except ValueError as exc:
        raise RunnerConfigurationError("URL is invalid") from exc

    if parsed.scheme not in {"http", "https"}:
        raise RunnerConfigurationError("URL must use HTTP or HTTPS")
    if parsed.username is not None or parsed.password is not None:
        raise RunnerConfigurationError("URL must not contain credentials")
    if parsed.query or parsed.fragment:
        raise RunnerConfigurationError("URL must not contain query or fragment")
    if parsed.hostname is None or not _is_loopback_host(parsed.hostname):
        raise RunnerConfigurationError("URL host must be loopback-only")
    if port is not None and not 1 <= port <= 65_535:
        raise RunnerConfigurationError("URL port is invalid")
    return parsed


def _is_loopback_host(host: str) -> bool:
    normalized = host.rstrip(".").casefold()
    if normalized == "localhost":
        return True
    try:
        return ipaddress.ip_address(normalized).is_loopback
    except ValueError:
        return False


def _parse_profile_ids(values: Sequence[str]) -> tuple[str, ...]:
    if len(values) > _MAX_PROFILE_IDS:
        raise RunnerConfigurationError("at most 20 profile IDs are allowed")

    parsed: list[str] = []
    seen: set[str] = set()
    for value in values:
        try:
            profile_id = str(UUID(value))
        except (AttributeError, TypeError, ValueError) as exc:
            raise RunnerConfigurationError("profile IDs must be UUIDs") from exc
        if profile_id not in seen:
            parsed.append(profile_id)
            seen.add(profile_id)
    return tuple(parsed)


def _positive_seconds(value: str) -> float:
    try:
        parsed = float(value)
    except ValueError as exc:
        raise argparse.ArgumentTypeError("must be a number") from exc
    try:
        _validate_seconds(parsed, name="value")
    except RunnerConfigurationError as exc:
        raise argparse.ArgumentTypeError(
            "must be greater than 0 and at most 86400",
        ) from exc
    return parsed


def _validate_seconds(value: object, *, name: str) -> None:
    if (
        isinstance(value, bool)
        or not isinstance(value, (int, float))
        or not math.isfinite(value)
        or not 0 < value <= 86_400
    ):
        raise RunnerConfigurationError(f"{name} seconds are invalid")


def _build_parser() -> argparse.ArgumentParser:
    parser = _SafeArgumentParser(
        description="Run deterministic daily preparation against local FastAPI.",
    )
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument(
        "--once",
        action="store_true",
        help="run once and return a failure status when preparation fails (default)",
    )
    mode.add_argument(
        "--loop",
        action="store_true",
        help="run immediately, then continue at the configured interval",
    )
    parser.add_argument(
        "--base-url",
        default=None,
        help="loopback FastAPI base URL (default: http://127.0.0.1:8000)",
    )
    parser.add_argument(
        "--profile-id",
        action="append",
        default=[],
        metavar="UUID",
        help="restrict to an eligible profile; repeat at most 20 times",
    )
    parser.add_argument(
        "--timeout-seconds",
        type=_positive_seconds,
        default=_DEFAULT_TIMEOUT_SECONDS,
    )
    parser.add_argument(
        "--interval-seconds",
        type=_positive_seconds,
        default=_DEFAULT_INTERVAL_SECONDS,
    )
    return parser


def _config_from_args(
    args: argparse.Namespace,
    *,
    environ: Mapping[str, str],
) -> RunnerConfig:
    token = environ.get("SCHEDULED_REFRESH_TOKEN", "").strip()
    if not token:
        raise RunnerConfigurationError(
            "SCHEDULED_REFRESH_TOKEN must be set in the environment",
        )

    base_url = args.base_url
    if base_url is None:
        base_url = environ.get("LOCAL_DAILY_REFRESH_BASE_URL", _DEFAULT_BASE_URL)

    return RunnerConfig(
        endpoint_url=_build_endpoint_url(base_url),
        token=token,
        profile_ids=_parse_profile_ids(args.profile_id),
        timeout_seconds=args.timeout_seconds,
        interval_seconds=args.interval_seconds,
    )


def build_payload(profile_ids: Sequence[str] = ()) -> dict[str, object]:
    """Build the exact bounded scheduler request owned by this runner."""

    payload: dict[str, object] = {
        "window_days": 7,
        "limit": 100,
        "include_recommendations": False,
    }
    if profile_ids:
        payload["profile_ids"] = list(profile_ids)
    return payload


def _build_request(config: RunnerConfig) -> urllib.request.Request:
    body = json.dumps(
        build_payload(config.profile_ids),
        separators=(",", ":"),
        sort_keys=True,
    ).encode("utf-8")
    return urllib.request.Request(
        config.endpoint_url,
        data=body,
        headers={
            "Accept": "application/json",
            "Content-Type": "application/json",
            "X-Scheduled-Refresh-Token": config.token,
        },
        method="POST",
    )


def _post_refresh(config: RunnerConfig, transport: Transport) -> RunSummary:
    request = _build_request(config)
    try:
        with transport(request, config.timeout_seconds) as response:
            status = response.getcode()
            if (
                isinstance(status, bool)
                or not isinstance(status, int)
                or status < 200
                or status >= 300
            ):
                raise RunnerRequestError("http")
            body = response.read(_MAX_RESPONSE_BYTES + 1)
    except RunnerRequestError:
        raise
    except OSError as exc:
        raise RunnerRequestError("http") from exc

    if not isinstance(body, bytes) or len(body) > _MAX_RESPONSE_BYTES:
        raise RunnerRequestError("json")
    try:
        decoded = body.decode("utf-8")
        payload = json.loads(decoded)
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise RunnerRequestError("json") from exc
    return _parse_summary(payload)


def _parse_summary(payload: object) -> RunSummary:
    if not isinstance(payload, dict):
        raise RunnerRequestError("json")

    processed = _required_count(payload, "processed")
    succeeded = _required_count(payload, "succeeded")
    failed = _required_count(payload, "failed")
    if processed != succeeded + failed:
        raise RunnerRequestError("json")

    results = payload.get("results")
    if not isinstance(results, list) or len(results) != processed:
        raise RunnerRequestError("json")
    result_succeeded = 0
    result_failed = 0
    for result in results:
        if not isinstance(result, dict):
            raise RunnerRequestError("json")
        status = result.get("status")
        if status == "succeeded":
            result_succeeded += 1
        elif status == "failed":
            result_failed += 1
        else:
            raise RunnerRequestError("json")
    if result_succeeded != succeeded or result_failed != failed:
        raise RunnerRequestError("json")

    return RunSummary(
        processed=processed,
        succeeded=succeeded,
        failed=failed,
    )


def _required_count(payload: Mapping[str, object], key: str) -> int:
    value = payload.get(key)
    if isinstance(value, bool) or not isinstance(value, int) or value < 0:
        raise RunnerRequestError("json")
    return value


def _emit_summary(summary: RunSummary, output: Output) -> None:
    status = "ok" if summary.failed == 0 else "failed"
    output(
        "daily-refresh "
        f"status={status} processed={summary.processed} "
        f"succeeded={summary.succeeded} failed={summary.failed}",
    )


def _emit_error(category: str, output: Output) -> None:
    output(f"daily-refresh status=error category={category}")


def _print_output(message: str) -> None:
    print(message, flush=True)


def run_once(
    config: RunnerConfig,
    *,
    transport: Transport = _default_transport,
    output: Output = _print_output,
) -> int:
    """Run one refresh and return non-zero for request or per-user failure."""

    try:
        summary = _post_refresh(config, transport)
    except RunnerRequestError as exc:
        _emit_error(exc.category, output)
        return _EXIT_RUN_FAILED
    except Exception:
        _emit_error("internal", output)
        return _EXIT_RUN_FAILED

    _emit_summary(summary, output)
    if summary.failed:
        return _EXIT_RUN_FAILED
    return _EXIT_OK


def run_loop(
    config: RunnerConfig,
    *,
    stop_event: threading.Event,
    transport: Transport = _default_transport,
    output: Output = _print_output,
    wait: Wait | None = None,
) -> int:
    """Continue after failed iterations until a signal or caller requests stop."""

    wait_for_stop = wait or stop_event.wait
    while not stop_event.is_set():
        run_once(config, transport=transport, output=output)
        if stop_event.is_set() or wait_for_stop(config.interval_seconds):
            break
    return _EXIT_OK


@contextmanager
def _signal_handlers(stop_event: threading.Event):
    previous: dict[signal.Signals, Any] = {}

    def request_stop(signum: int, frame: FrameType | None) -> None:
        del signum, frame
        stop_event.set()

    if threading.current_thread() is threading.main_thread():
        for signum in (signal.SIGINT, signal.SIGTERM):
            previous[signum] = signal.getsignal(signum)
            signal.signal(signum, request_stop)
    try:
        yield
    finally:
        for signum, handler in previous.items():
            signal.signal(signum, handler)


def main(
    argv: Sequence[str] | None = None,
    *,
    environ: Mapping[str, str] | None = None,
    transport: Transport = _default_transport,
    output: Output = _print_output,
) -> int:
    parser = _build_parser()
    try:
        args = parser.parse_args(argv)
        config = _config_from_args(
            args,
            environ=os.environ if environ is None else environ,
        )
    except RunnerConfigurationError:
        _emit_error("configuration", output)
        return _EXIT_CONFIGURATION_ERROR

    if not args.loop:
        return run_once(config, transport=transport, output=output)

    stop_event = threading.Event()
    with _signal_handlers(stop_event):
        try:
            return run_loop(
                config,
                stop_event=stop_event,
                transport=transport,
                output=output,
            )
        except KeyboardInterrupt:
            stop_event.set()
            return _EXIT_OK


if __name__ == "__main__":
    sys.exit(main())
