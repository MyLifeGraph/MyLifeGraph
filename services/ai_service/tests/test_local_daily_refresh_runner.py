import json
import signal
import threading
import urllib.error
import urllib.request
from collections.abc import Callable
from typing import Any

import pytest

from app.ops import local_daily_refresh as runner


PROFILE_1 = "11111111-1111-4111-8111-111111111111"
PROFILE_2 = "22222222-2222-4222-8222-222222222222"
TOKEN = "secret-local-scheduler-token"


class FakeResponse:
    def __init__(self, payload: object, *, status: int = 200) -> None:
        if isinstance(payload, bytes):
            self._body = payload
        else:
            self._body = json.dumps(payload).encode("utf-8")
        self._status = status

    def __enter__(self) -> "FakeResponse":
        return self

    def __exit__(self, *args: object) -> None:
        return None

    def read(self, amount: int = -1) -> bytes:
        return self._body[:amount] if amount >= 0 else self._body

    def getcode(self) -> int:
        return self._status


def success_payload(*, processed: int = 0) -> dict[str, object]:
    return {
        "run_at": "2026-07-14T08:00:00Z",
        "target_date": None,
        "processed": processed,
        "succeeded": processed,
        "failed": 0,
        "results": [
            {"user_id": PROFILE_1, "status": "succeeded"}
            for _ in range(processed)
        ],
    }


def invoke(
    response: FakeResponse | Exception,
) -> tuple[
    Callable[[urllib.request.Request, float], FakeResponse],
    list[tuple[urllib.request.Request, float]],
]:
    calls: list[tuple[urllib.request.Request, float]] = []

    def transport(
        request: urllib.request.Request,
        timeout: float,
    ) -> FakeResponse:
        calls.append((request, timeout))
        if isinstance(response, Exception):
            raise response
        return response

    return transport, calls


def config(**overrides: Any) -> runner.RunnerConfig:
    values: dict[str, object] = {
        "endpoint_url": (
            "http://127.0.0.1:8000/v1/scheduled/daily-refresh"
        ),
        "token": TOKEN,
    }
    values.update(overrides)
    return runner.RunnerConfig(**values)


def test_once_posts_exact_safe_default_payload_and_environment_token() -> None:
    transport, calls = invoke(FakeResponse(success_payload()))
    output: list[str] = []

    exit_code = runner.main(
        ["--once"],
        environ={"SCHEDULED_REFRESH_TOKEN": TOKEN},
        transport=transport,
        output=output.append,
    )

    assert exit_code == 0
    assert len(calls) == 1
    request, timeout = calls[0]
    assert request.full_url == (
        "http://127.0.0.1:8000/v1/scheduled/daily-refresh"
    )
    assert request.get_method() == "POST"
    assert json.loads(request.data or b"") == {
        "window_days": 7,
        "limit": 100,
        "include_recommendations": False,
    }
    assert request.get_header("X-scheduled-refresh-token") == TOKEN
    assert request.get_header("Content-type") == "application/json"
    assert timeout == 20.0
    assert output == [
        "daily-refresh status=ok processed=0 succeeded=0 failed=0",
    ]


def test_profile_ids_are_canonical_bounded_and_sent_only_in_request() -> None:
    transport, calls = invoke(FakeResponse(success_payload(processed=2)))
    output: list[str] = []

    exit_code = runner.main(
        ["--profile-id", PROFILE_1.upper(), "--profile-id", PROFILE_2],
        environ={"SCHEDULED_REFRESH_TOKEN": TOKEN},
        transport=transport,
        output=output.append,
    )

    assert exit_code == 0
    payload = json.loads(calls[0][0].data or b"")
    assert payload == {
        "window_days": 7,
        "limit": 100,
        "include_recommendations": False,
        "profile_ids": [PROFILE_1, PROFILE_2],
    }
    combined_output = "\n".join(output)
    assert PROFILE_1 not in combined_output
    assert PROFILE_2 not in combined_output
    assert TOKEN not in combined_output


@pytest.mark.parametrize(
    "base_url",
    [
        "https://example.com",
        "http://10.0.0.10:8000",
        "http://127.0.0.1:8000/unexpected",
        "http://user:password@127.0.0.1:8000",
        "http://127.0.0.1:8000?next=https://example.com",
    ],
)
def test_non_loopback_or_ambiguous_base_urls_fail_before_request(
    base_url: str,
) -> None:
    transport, calls = invoke(FakeResponse(success_payload()))
    output: list[str] = []

    exit_code = runner.main(
        ["--base-url", base_url],
        environ={"SCHEDULED_REFRESH_TOKEN": TOKEN},
        transport=transport,
        output=output.append,
    )

    assert exit_code == 2
    assert calls == []
    assert output == ["daily-refresh status=error category=configuration"]
    assert base_url not in "\n".join(output)


@pytest.mark.parametrize(
    "base_url",
    [
        "http://localhost:8000",
        "http://localhost.:8000/",
        "http://127.42.0.1:8000",
        "http://[::1]:8000",
    ],
)
def test_explicit_loopback_hosts_are_allowed(base_url: str) -> None:
    transport, calls = invoke(FakeResponse(success_payload()))

    exit_code = runner.main(
        ["--base-url", base_url],
        environ={"SCHEDULED_REFRESH_TOKEN": TOKEN},
        transport=transport,
        output=lambda _: None,
    )

    assert exit_code == 0
    assert len(calls) == 1
    assert calls[0][0].full_url.endswith(
        "/v1/scheduled/daily-refresh",
    )


def test_token_is_required_from_environment_and_has_no_cli_option() -> None:
    transport, calls = invoke(FakeResponse(success_payload()))
    output: list[str] = []

    exit_code = runner.main(
        [],
        environ={},
        transport=transport,
        output=output.append,
    )

    assert exit_code == 2
    assert calls == []
    assert output == ["daily-refresh status=error category=configuration"]
    output.clear()
    exit_code = runner.main(
        ["--token", TOKEN],
        environ={},
        transport=transport,
        output=output.append,
    )
    assert exit_code == 2
    assert output == ["daily-refresh status=error category=configuration"]
    assert TOKEN not in "\n".join(output)


def test_direct_runner_config_cannot_bypass_loopback_validation() -> None:
    with pytest.raises(runner.RunnerConfigurationError):
        config(endpoint_url="https://example.com/v1/scheduled/daily-refresh")


def test_runner_config_repr_never_contains_token() -> None:
    assert TOKEN not in repr(config())


@pytest.mark.parametrize(
    "profile_ids",
    [
        ["not-a-uuid"],
        [PROFILE_1] * 21,
    ],
)
def test_invalid_or_more_than_twenty_profile_ids_fail_before_request(
    profile_ids: list[str],
) -> None:
    args = [item for profile_id in profile_ids for item in ("--profile-id", profile_id)]
    transport, calls = invoke(FakeResponse(success_payload()))
    output: list[str] = []

    exit_code = runner.main(
        args,
        environ={"SCHEDULED_REFRESH_TOKEN": TOKEN},
        transport=transport,
        output=output.append,
    )

    assert exit_code == 2
    assert calls == []
    assert output == ["daily-refresh status=error category=configuration"]


def test_once_returns_nonzero_for_http_failure_without_leaking_detail() -> None:
    error = urllib.error.HTTPError(
        "http://127.0.0.1:8000/private-user-id",
        503,
        f"upstream included {TOKEN}",
        hdrs=None,
        fp=None,
    )
    transport, _ = invoke(error)
    output: list[str] = []

    exit_code = runner.run_once(
        config(),
        transport=transport,
        output=output.append,
    )

    assert exit_code == 1
    assert output == ["daily-refresh status=error category=http"]
    assert TOKEN not in "\n".join(output)
    assert "private-user-id" not in "\n".join(output)


@pytest.mark.parametrize(
    "body",
    [
        b"not-json",
        b"[]",
        json.dumps(
            {
                "processed": 1,
                "succeeded": 1,
                "failed": 0,
                "results": [],
            },
        ).encode("utf-8"),
    ],
)
def test_once_returns_nonzero_for_invalid_json_or_aggregate(body: bytes) -> None:
    transport, _ = invoke(FakeResponse(body))
    output: list[str] = []

    exit_code = runner.run_once(
        config(),
        transport=transport,
        output=output.append,
    )

    assert exit_code == 1
    assert output == ["daily-refresh status=error category=json"]
    assert body.decode("utf-8") not in "\n".join(output)


def test_once_returns_nonzero_and_only_aggregate_for_per_user_failure() -> None:
    payload = {
        "processed": 2,
        "succeeded": 1,
        "failed": 1,
        "results": [
            {"user_id": PROFILE_1, "status": "succeeded"},
            {
                "user_id": PROFILE_2,
                "status": "failed",
                "failed_stage": "briefing",
                "error": f"private {TOKEN}",
            },
        ],
    }
    transport, _ = invoke(FakeResponse(payload))
    output: list[str] = []

    exit_code = runner.run_once(
        config(),
        transport=transport,
        output=output.append,
    )

    assert exit_code == 1
    assert output == [
        "daily-refresh status=failed processed=2 succeeded=1 failed=1",
    ]
    assert PROFILE_1 not in output[0]
    assert PROFILE_2 not in output[0]
    assert TOKEN not in output[0]


def test_loop_continues_after_failure_until_stop_is_requested() -> None:
    responses: list[FakeResponse | Exception] = [
        urllib.error.URLError(f"private {TOKEN}"),
        FakeResponse(success_payload()),
    ]
    calls = 0

    def transport(
        request: urllib.request.Request,
        timeout: float,
    ) -> FakeResponse:
        nonlocal calls
        del request, timeout
        response = responses[calls]
        calls += 1
        if isinstance(response, Exception):
            raise response
        return response

    stop_event = threading.Event()
    waits: list[float] = []

    def wait(interval: float) -> bool:
        waits.append(interval)
        if len(waits) == 2:
            stop_event.set()
        return stop_event.is_set()

    output: list[str] = []
    exit_code = runner.run_loop(
        config(interval_seconds=3.0),
        stop_event=stop_event,
        transport=transport,
        output=output.append,
        wait=wait,
    )

    assert exit_code == 0
    assert calls == 2
    assert waits == [3.0, 3.0]
    assert output == [
        "daily-refresh status=error category=http",
        "daily-refresh status=ok processed=0 succeeded=0 failed=0",
    ]
    assert TOKEN not in "\n".join(output)


def test_signal_handler_requests_clean_stop_and_restores_handlers(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    installed: dict[signal.Signals, object] = {}
    restored: list[tuple[signal.Signals, object]] = []

    def fake_getsignal(signum: signal.Signals) -> str:
        return f"previous-{signum.name}"

    def fake_signal(signum: signal.Signals, handler: object) -> None:
        if callable(handler):
            installed[signum] = handler
        else:
            restored.append((signum, handler))

    monkeypatch.setattr(signal, "getsignal", fake_getsignal)
    monkeypatch.setattr(signal, "signal", fake_signal)
    stop_event = threading.Event()

    with runner._signal_handlers(stop_event):
        handler = installed[signal.SIGTERM]
        assert callable(handler)
        handler(signal.SIGTERM, None)
        assert stop_event.is_set()

    assert restored == [
        (signal.SIGINT, "previous-SIGINT"),
        (signal.SIGTERM, "previous-SIGTERM"),
    ]
