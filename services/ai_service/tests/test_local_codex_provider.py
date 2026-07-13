import asyncio
import json
import os
import sys
import time
from pathlib import Path

import pytest

from app.core.config import Settings
from app.providers.base import CoachProviderError
from app.providers.local_codex import (
    LocalCodexCoachProvider,
    ProcessResult,
    _mapped_failure,
    _mapped_process_failure,
    _parse_event_stream,
    _reject_unsafe_event_line,
    run_bounded_process,
)


GLOBAL_HELP = b" ".join(
    [
        b"--ask-for-approval",
        b"--disable",
        b"--strict-config",
        b"--sandbox",
        b"--cd",
    ],
)
EXEC_HELP = b" ".join(
    [
        b"--ephemeral",
        b"--ignore-user-config",
        b"--ignore-rules",
        b"--skip-git-repo-check",
        b"--output-schema",
        b"--output-last-message",
        b"--json",
    ],
)
FEATURES = b"""shell_tool stable true
unified_exec stable true
apps stable true
browser_use stable true
goals stable true
memories experimental false
auth_elicitation stable true
remote_plugin stable true
skill_mcp_dependency_install stable true
old_tool removed false
"""
VALID_FINAL = json.dumps(
    {
        "reply": "bounded",
        "uncertainty": {"level": "medium", "reason": "bounded"},
        "staged_suggestion": None,
        "safety": {"classification": "normal"},
    },
    separators=(",", ":"),
)


def test_output_schema_uses_supported_nullable_union() -> None:
    schema_path = (
        Path(__file__).resolve().parents[1]
        / "app"
        / "providers"
        / "schemas"
        / "coach_model_output_v1.json"
    )
    schema = json.loads(schema_path.read_text())

    suggestion = schema["properties"]["staged_suggestion"]
    assert "anyOf" in suggestion
    assert "oneOf" not in suggestion


class Runner:
    def __init__(self, *, reported_model="gpt-5.5") -> None:
        self.calls = []
        self.reported_model = reported_model
        self.response_cwd = None
        self.response_cwd_mode = None

    async def __call__(self, argv, **kwargs):
        self.calls.append((list(argv), kwargs))
        if argv[-1] == "--help" and argv[-2] == "exec":
            return ProcessResult(0, EXEC_HELP, b"")
        if argv[-1] == "--help":
            return ProcessResult(0, GLOBAL_HELP, b"")
        if argv[-2:] == ["features", "list"]:
            return ProcessResult(0, FEATURES, b"")
        if argv[-2:] == ["login", "status"]:
            return ProcessResult(0, b"Logged in using ChatGPT", b"")

        self.response_cwd = kwargs["cwd"]
        self.response_cwd_mode = os.stat(kwargs["cwd"]).st_mode & 0o777
        output_index = argv.index("--output-last-message") + 1
        output_path = Path(argv[output_index])
        final = json.dumps(
            {
                "reply": "Take one bounded step.",
                "uncertainty": {"level": "medium", "reason": "Bounded context."},
                "staged_suggestion": None,
                "safety": {"classification": "normal"},
            },
            separators=(",", ":"),
        )
        output_path.write_text(final, encoding="utf-8")
        events = "\n".join(
            [
                json.dumps({"type": "thread.started", "thread_id": "redacted"}),
                json.dumps({"type": "turn.started", "model": self.reported_model}),
                json.dumps(
                    {
                        "type": "item.completed",
                        "item": {"id": "one", "type": "agent_message", "text": final},
                    },
                ),
                json.dumps({"type": "turn.completed", "usage": {}}),
            ],
        )
        return ProcessResult(0, events.encode(), b"harmless warning")


def test_hardened_argv_environment_stdin_and_cleanup() -> None:
    runner = Runner()
    provider = LocalCodexCoachProvider(
        _settings(),
        runner=runner,
        executable_resolver=lambda _: "/usr/bin/codex",
        environ={
            "HOME": "/home/test",
            "CODEX_HOME": "/home/test/.codex",
            "PATH": "/usr/bin",
            "SUPABASE_SERVICE_ROLE_KEY": "must-not-leak",
            "SCHEDULED_REFRESH_TOKEN": "must-not-leak",
        },
    )

    capability = asyncio.run(provider.capability())
    result = asyncio.run(provider.respond(prompt="synthetic private input"))

    assert capability.state == "ready"
    assert result.output.reply == "Take one bounded step."
    argv, kwargs = runner.calls[-1]
    exec_index = argv.index("exec")
    assert argv.index("--ask-for-approval") < exec_index
    assert argv[argv.index("--ask-for-approval") + 1] == "never"
    assert argv[argv.index("--sandbox") + 1] == "read-only"
    assert all(
        flag in argv
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
    disabled = {
        argv[index + 1]
        for index, value in enumerate(argv)
        if value == "--disable"
    }
    assert disabled == {
        "apps",
        "auth_elicitation",
        "browser_use",
        "goals",
        "memories",
        "remote_plugin",
        "shell_tool",
        "skill_mcp_dependency_install",
        "unified_exec",
    }
    assert "old_tool" not in disabled
    assert "synthetic private input" not in " ".join(argv)
    assert kwargs["stdin"] == b"synthetic private input"
    assert kwargs["env"] == {
        "HOME": "/home/test",
        "CODEX_HOME": "/home/test/.codex",
        "PATH": "/usr/bin",
    }
    assert runner.response_cwd_mode == 0o700
    assert runner.response_cwd is not None
    assert not Path(runner.response_cwd).exists()


def test_reported_model_mismatch_fails_without_fallback() -> None:
    runner = Runner(reported_model="another-model")
    provider = LocalCodexCoachProvider(
        _settings(),
        runner=runner,
        executable_resolver=lambda _: "/usr/bin/codex",
    )
    with pytest.raises(CoachProviderError) as caught:
        asyncio.run(provider.respond(prompt="synthetic input"))
    assert caught.value.code == "unavailable_model"


def test_missing_binary_login_and_hardening_fail_without_model_call() -> None:
    missing = LocalCodexCoachProvider(
        _settings(),
        runner=Runner(),
        executable_resolver=lambda _: None,
    )
    assert asyncio.run(missing.capability()).reason_code == "missing_cli"

    class LoginFailure(Runner):
        async def __call__(self, argv, **kwargs):
            if argv[-2:] == ["login", "status"]:
                return ProcessResult(1, b"", b"private diagnostic")
            return await super().__call__(argv, **kwargs)

    login = LocalCodexCoachProvider(
        _settings(),
        runner=LoginFailure(),
        executable_resolver=lambda _: "/usr/bin/codex",
    )
    assert asyncio.run(login.capability()).reason_code == "not_logged_in"

    class MissingFlag(Runner):
        async def __call__(self, argv, **kwargs):
            if argv[-1] == "--help" and argv[-2] == "exec":
                return ProcessResult(
                    0,
                    EXEC_HELP.replace(b"--output-last-message", b""),
                    b"",
                )
            return await super().__call__(argv, **kwargs)

    hardening = LocalCodexCoachProvider(
        _settings(),
        runner=MissingFlag(),
        executable_resolver=lambda _: "/usr/bin/codex",
    )
    assert asyncio.run(hardening.capability()).reason_code == "tool_free_unavailable"


@pytest.mark.parametrize(
    "status_output",
    [
        b"Logged in using an API key",
        b"Logged in using OPENAI_API_KEY for ChatGPT-labelled account",
        b"Logged in using access token",
        b"Logged in",
        b"ChatGPT",
        b"Not authenticated via OAuth",
        b"API key account with ChatGPT label",
    ],
)
def test_capability_rejects_non_oauth_and_ambiguous_login_modes(
    status_output: bytes,
) -> None:
    class LoginStatus(Runner):
        async def __call__(self, argv, **kwargs):
            if argv[-2:] == ["login", "status"]:
                return ProcessResult(0, status_output, b"")
            return await super().__call__(argv, **kwargs)

    provider = LocalCodexCoachProvider(
        _settings(),
        runner=LoginStatus(),
        executable_resolver=lambda _: "/usr/bin/codex",
    )

    capability = asyncio.run(provider.capability())

    assert capability.state == "unavailable"
    assert capability.reason_code == "unsupported_auth_mode"


@pytest.mark.parametrize(
    "status_output",
    [
        b"Logged in using ChatGPT",
        b"Authenticated via OAuth",
        b"Active ChatGPT subscription",
    ],
)
def test_capability_accepts_explicit_subscription_oauth_status(
    status_output: bytes,
) -> None:
    class LoginStatus(Runner):
        async def __call__(self, argv, **kwargs):
            if argv[-2:] == ["login", "status"]:
                return ProcessResult(0, status_output, b"")
            return await super().__call__(argv, **kwargs)

    provider = LocalCodexCoachProvider(
        _settings(),
        runner=LoginStatus(),
        executable_resolver=lambda _: "/usr/bin/codex",
    )

    assert asyncio.run(provider.capability()).state == "ready"


def test_capability_preflight_is_cached_coalesced_and_short_lived() -> None:
    clock = [100.0]

    class SlowRunner(Runner):
        async def __call__(self, argv, **kwargs):
            await asyncio.sleep(0.005)
            return await super().__call__(argv, **kwargs)

    runner = SlowRunner()
    provider = LocalCodexCoachProvider(
        _settings(),
        runner=runner,
        executable_resolver=lambda _: "/usr/bin/codex",
        monotonic=lambda: clock[0],
    )

    async def concurrent_capabilities():
        return await asyncio.gather(*(provider.capability() for _ in range(8)))

    first = asyncio.run(concurrent_capabilities())
    assert all(capability.state == "ready" for capability in first)
    assert len(runner.calls) == 4

    assert asyncio.run(provider.capability()).state == "ready"
    assert len(runner.calls) == 4

    clock[0] += 6
    assert asyncio.run(provider.capability()).state == "ready"
    assert len(runner.calls) == 8


def test_unavailable_auth_cache_rechecks_quickly_after_local_login_change() -> None:
    clock = [100.0]

    class ChangingLoginRunner(Runner):
        login_status = b"Logged in using an API key"

        async def __call__(self, argv, **kwargs):
            if argv[-2:] == ["login", "status"]:
                self.calls.append((list(argv), kwargs))
                return ProcessResult(0, self.login_status, b"")
            return await super().__call__(argv, **kwargs)

    runner = ChangingLoginRunner()
    provider = LocalCodexCoachProvider(
        _settings(),
        runner=runner,
        executable_resolver=lambda _: "/usr/bin/codex",
        monotonic=lambda: clock[0],
    )

    first = asyncio.run(provider.capability())
    assert first.reason_code == "unsupported_auth_mode"
    assert len(runner.calls) == 4

    runner.login_status = b"Logged in using ChatGPT"
    clock[0] += 0.5
    assert asyncio.run(provider.capability()).reason_code == "unsupported_auth_mode"
    assert len(runner.calls) == 4

    clock[0] += 0.6
    assert asyncio.run(provider.capability()).state == "ready"
    assert len(runner.calls) == 8


@pytest.mark.parametrize(
    ("stderr", "code"),
    [
        (b"model not found: private-model", "unavailable_model"),
        (b"account usage limit reached for private account", "account_limit"),
        (b"not logged in as private@example.com", "not_logged_in"),
        (b"unexpected /home/private/path token=secret", "provider_failure"),
    ],
)
def test_nonzero_diagnostics_map_to_sanitized_stable_errors(stderr, code) -> None:
    error = _mapped_failure(stderr)
    assert error.code == code
    assert "private" not in str(error).lower()
    assert "secret" not in str(error).lower()


@pytest.mark.parametrize(
    ("event", "code"),
    [
        (
            {"type": "error", "message": "Model gpt-5.5 is not supported"},
            "unavailable_model",
        ),
        (
            {
                "type": "turn.failed",
                "error": {"code": "usage_limit_reached", "message": "quota"},
            },
            "account_limit",
        ),
        (
            {"type": "error", "message": "private path without stable marker"},
            "provider_failure",
        ),
    ],
)
def test_nonzero_machine_events_are_classified_without_stderr_or_leak(
    event,
    code,
) -> None:
    stdout = (json.dumps(event) + "\n").encode()

    error = _mapped_process_failure(stdout, b"")

    assert error.code == code
    assert "private" not in str(error).lower()
    assert "gpt-5.5" not in str(error).lower()


@pytest.mark.parametrize(
    "event",
    [
        {"type": "tool.started", "tool": "shell"},
        {
            "type": "item.completed",
            "item": {"id": "x", "type": "command_execution", "text": "ls"},
        },
        {
            "type": "item.completed",
            "item": {
                "id": "x",
                "type": "agent_message",
                "text": "{}",
                "file_path": "/tmp/x",
            },
        },
        {
            "type": "item.completed",
            "item": {
                "id": "r",
                "type": "reasoning",
                "text": {"command": "whoami", "file_path": "/tmp/x"},
            },
        },
        {"type": "turn.completed", "usage": {"command": "whoami"}},
    ],
)
def test_tool_command_and_file_events_are_unsafe(event) -> None:
    with pytest.raises(CoachProviderError) as caught:
        _parse_event_stream(json.dumps(event).encode())
    assert caught.value.code == "unsafe_provider_event"


@pytest.mark.parametrize(
    "event",
    [
        {"type": "thread.started", "thread_id": 7},
        {"type": "thread.started", "thread_id": "x" * 201},
        {"type": "turn.started", "model": {}},
        {"type": "turn.started", "model": "   "},
        {"type": "turn.started", "model": "x" * 101},
    ],
)
def test_known_event_text_fields_reject_invalid_types_and_bounds(event) -> None:
    final = _valid_final()
    stream = b"\n".join([json.dumps(event).encode(), _agent_event(final)])
    with pytest.raises(CoachProviderError) as caught:
        _parse_event_stream(stream, final_output=final.encode())
    assert caught.value.code == "invalid_output"


@pytest.mark.parametrize("field", ["thread_id", "model"])
def test_known_event_fields_reject_nested_unsafe_shapes(field) -> None:
    event = {"type": "turn.started", field: {"command": "whoami"}}
    final = _valid_final()
    stream = b"\n".join([json.dumps(event).encode(), _agent_event(final)])
    with pytest.raises(CoachProviderError) as caught:
        _parse_event_stream(stream, final_output=final.encode())
    assert caught.value.code == "unsafe_provider_event"


def test_known_event_text_fields_allow_null_and_trim_reported_model() -> None:
    final = _valid_final()
    events = [
        {"type": "thread.started", "thread_id": None, "model": None},
        {"type": "turn.started", "model": "  gpt-5.5  "},
    ]
    stream = b"\n".join(
        [
            *(json.dumps(event).encode() for event in events),
            _agent_event(final),
            json.dumps({"type": "turn.completed", "usage": {}}).encode(),
        ],
    )

    result = _parse_event_stream(stream, final_output=final.encode())

    assert result.model_reported == "gpt-5.5"


def test_real_cli_lifecycle_allows_omitted_turn_started() -> None:
    final = _valid_final()
    stream = b"\n".join(
        [
            json.dumps(
                {"type": "thread.started", "thread_id": "redacted"},
            ).encode(),
            _agent_event(final),
            json.dumps({"type": "turn.completed", "usage": {}}).encode(),
        ],
    )

    result = _parse_event_stream(stream, final_output=final.encode())

    assert result.output.reply == "bounded"
    assert result.model_reported is None


def test_real_cli_non_fatal_error_items_are_ignored_before_success() -> None:
    final = _valid_final()
    events = [
        {"type": "thread.started", "thread_id": "redacted"},
        {
            "type": "item.completed",
            "item": {
                "id": "warning-one",
                "type": "error",
                "message": "A bounded non-fatal warning.",
            },
        },
        {
            "type": "item.completed",
            "item": {
                "id": "warning-two",
                "type": "error",
                "message": "Another bounded non-fatal warning.",
            },
        },
        {"type": "turn.started", "model": "gpt-5.5"},
    ]
    stream = b"\n".join(
        [
            *(json.dumps(event).encode() for event in events),
            _agent_event(final),
            json.dumps({"type": "turn.completed", "usage": {}}).encode(),
        ],
    )

    for event in events[1:3]:
        _reject_unsafe_event_line(json.dumps(event).encode())
    result = _parse_event_stream(stream, final_output=final.encode())

    assert result.output.reply == "bounded"
    assert result.model_reported == "gpt-5.5"


@pytest.mark.parametrize(
    "event",
    [
        {
            "type": "item.started",
            "item": {"id": "warning", "type": "error", "message": "bounded"},
        },
        {
            "type": "item.completed",
            "model": "gpt-5.5",
            "item": {"id": "warning", "type": "error", "message": "bounded"},
        },
        {
            "type": "item.completed",
            "item": {"type": "error", "message": "bounded"},
        },
        {
            "type": "item.completed",
            "item": {"id": None, "type": "error", "message": "bounded"},
        },
        {
            "type": "item.completed",
            "item": {"id": " ", "type": "error", "message": "bounded"},
        },
        {
            "type": "item.completed",
            "item": {"id": "x" * 201, "type": "error", "message": "bounded"},
        },
        {
            "type": "item.completed",
            "item": {"id": "warning", "type": "error", "message": None},
        },
        {
            "type": "item.completed",
            "item": {"id": "warning", "type": "error", "message": "  "},
        },
        {
            "type": "item.completed",
            "item": {"id": "warning", "type": "error", "message": "x" * 4_097},
        },
        {
            "type": "item.completed",
            "item": {
                "id": "warning",
                "type": "error",
                "message": "bounded",
                "text": "unexpected",
            },
        },
    ],
)
def test_non_fatal_error_item_requires_exact_bounded_completed_shape(event) -> None:
    final = _valid_final()
    stream = b"\n".join(
        [
            json.dumps(
                {"type": "thread.started", "thread_id": "redacted"},
            ).encode(),
            json.dumps(event).encode(),
            _agent_event(final),
            json.dumps({"type": "turn.completed", "usage": {}}).encode(),
        ],
    )

    with pytest.raises(CoachProviderError) as caught:
        _parse_event_stream(stream, final_output=final.encode())

    assert caught.value.code == "invalid_output"


@pytest.mark.parametrize(
    "events",
    [
        [
            {"type": "thread.started", "thread_id": "redacted"},
            {"type": "turn.started"},
            {"type": "turn.started"},
            {
                "type": "item.completed",
                "item": {
                    "id": "one",
                    "type": "agent_message",
                    "text": VALID_FINAL,
                },
            },
            {"type": "turn.completed", "usage": {}},
        ],
        [
            {"type": "thread.started", "thread_id": "redacted"},
            {
                "type": "item.completed",
                "item": {
                    "id": "one",
                    "type": "agent_message",
                    "text": VALID_FINAL,
                },
            },
            {"type": "turn.started"},
            {"type": "turn.completed", "usage": {}},
        ],
        [
            {"type": "thread.started", "thread_id": "redacted"},
            {
                "type": "item.completed",
                "item": {
                    "id": "one",
                    "type": "agent_message",
                    "text": VALID_FINAL,
                },
            },
            {"type": "turn.completed", "usage": {}},
            {"type": "turn.completed", "usage": {}},
        ],
    ],
)
def test_optional_turn_started_rejects_duplicates_and_out_of_order(events) -> None:
    with pytest.raises(CoachProviderError) as caught:
        _parse_event_stream(
            b"\n".join(json.dumps(event).encode() for event in events),
            final_output=VALID_FINAL.encode(),
        )

    assert caught.value.code == "invalid_output"


@pytest.mark.parametrize(
    "payload",
    [
        {
            "reply": None,
            "uncertainty": {"level": "medium", "reason": "bounded"},
            "staged_suggestion": None,
            "safety": {"classification": "normal"},
        },
        {
            "reply": 7,
            "uncertainty": {"level": "medium", "reason": "bounded"},
            "staged_suggestion": None,
            "safety": {"classification": "normal"},
        },
        {
            "reply": "x" * 4_001,
            "uncertainty": {"level": "medium", "reason": "bounded"},
            "staged_suggestion": None,
            "safety": {"classification": "normal"},
        },
        {
            "reply": "bounded",
            "uncertainty": {"level": "medium", "reason": "bounded"},
            "staged_suggestion": None,
            "safety": {"classification": "normal"},
            "unknown": True,
        },
    ],
)
def test_invalid_null_coerced_oversized_and_unknown_model_output(payload) -> None:
    final = json.dumps(payload, separators=(",", ":"))
    with pytest.raises(CoachProviderError) as caught:
        _parse_event_stream(_valid_stream(final), final_output=final.encode())
    assert caught.value.code == "invalid_output"


def test_truncated_json_and_final_file_mismatch_are_invalid() -> None:
    with pytest.raises(CoachProviderError) as truncated:
        _parse_event_stream(_valid_stream('{"reply":'))
    assert truncated.value.code == "invalid_output"

    valid = json.dumps(
        {
            "reply": "bounded",
            "uncertainty": {"level": "medium", "reason": "bounded"},
            "staged_suggestion": None,
            "safety": {"classification": "normal"},
        },
        separators=(",", ":"),
    )
    with pytest.raises(CoachProviderError) as mismatch:
        _parse_event_stream(_valid_stream(valid), final_output=b"{}")
    assert mismatch.value.code == "invalid_output"


@pytest.mark.parametrize(
    "events",
    [
        [
            {
                "type": "item.started",
                "item": {"id": "one", "type": "agent_message", "text": "{}"},
            },
        ],
        [
            {"type": "thread.started", "thread_id": "redacted"},
            {"type": "turn.started", "model": "gpt-5.5"},
            {
                "type": "item.completed",
                "item": {
                    "id": "one",
                    "type": "agent_message",
                    "text": VALID_FINAL,
                },
            },
        ],
        [
            {
                "type": "item.completed",
                "item": {
                    "id": "one",
                    "type": "agent_message",
                    "text": VALID_FINAL,
                },
            },
            {"type": "turn.completed", "usage": {}},
        ],
    ],
)
def test_event_stream_requires_complete_thread_turn_lifecycle(events) -> None:
    stdout = b"\n".join(json.dumps(event).encode() for event in events)

    with pytest.raises(CoachProviderError) as caught:
        _parse_event_stream(stdout, final_output=_valid_final().encode())

    assert caught.value.code == "invalid_output"


def test_error_event_is_terminal_even_if_a_valid_answer_follows() -> None:
    final = _valid_final()
    events = [
        {"type": "thread.started", "thread_id": "redacted"},
        {"type": "turn.started", "model": "gpt-5.5"},
        {"type": "error", "message": "model request failed"},
        json.loads(_agent_event(final)),
        {"type": "turn.completed", "usage": {}},
    ]

    with pytest.raises(CoachProviderError) as caught:
        _parse_event_stream(
            b"\n".join(json.dumps(event).encode() for event in events),
            final_output=final.encode(),
        )

    assert caught.value.code == "provider_failure"


def test_process_input_bound_and_timeout_terminate_without_diagnostic_leak() -> None:
    with pytest.raises(CoachProviderError) as oversized:
        asyncio.run(
            run_bounded_process(
                ["/bin/true"],
                stdin=b"x" * 65_537,
                cwd="/tmp",
                env={"PATH": "/usr/bin:/bin"},
                timeout_seconds=1,
            ),
        )
    assert oversized.value.code == "context_too_large"

    with pytest.raises(CoachProviderError) as output_limited:
        asyncio.run(
            run_bounded_process(
                ["/bin/sh", "-c", "printf 123456789"],
                stdin=b"",
                cwd="/tmp",
                env={"PATH": "/usr/bin:/bin"},
                timeout_seconds=1,
                max_stdout_bytes=4,
            ),
        )
    assert output_limited.value.code == "invalid_output"

    with pytest.raises(CoachProviderError) as timed_out:
        asyncio.run(
            run_bounded_process(
                ["/bin/sh", "-c", "sleep 10"],
                stdin=b"",
                cwd="/tmp",
                env={"PATH": "/usr/bin:/bin"},
                timeout_seconds=0.05,
            ),
        )
    assert timed_out.value.code == "timeout"


def test_process_cancellation_terminates_and_reaps_process_group() -> None:
    async def cancel():
        task = asyncio.create_task(
            run_bounded_process(
                ["/bin/sh", "-c", "sleep 10"],
                stdin=b"",
                cwd="/tmp",
                env={"PATH": "/usr/bin:/bin"},
                timeout_seconds=10,
            ),
        )
        await asyncio.sleep(0.02)
        task.cancel()
        with pytest.raises(asyncio.CancelledError):
            await task

    asyncio.run(cancel())


def test_process_timeout_covers_backpressured_stdin_write_and_close() -> None:
    with pytest.raises(CoachProviderError) as caught:
        asyncio.run(
            run_bounded_process(
                ["/bin/sh", "-c", "sleep 10"],
                stdin=b"x" * 65_536,
                cwd="/tmp",
                env={"PATH": "/usr/bin:/bin"},
                timeout_seconds=0.05,
            ),
        )
    assert caught.value.code == "timeout"


@pytest.mark.parametrize(
    ("event", "expected_code"),
    [
        ({"type": "tool.started", "tool": "shell"}, "unsafe_provider_event"),
        (
            {"type": "error", "message": "Model is not supported"},
            "unavailable_model",
        ),
    ],
)
def test_rejected_stream_event_terminates_process_before_normal_exit(
    event,
    expected_code,
) -> None:
    event_line = json.dumps(event)
    script = (
        "import sys,time; "
        f"sys.stdout.write({event_line!r} + '\\n'); sys.stdout.flush(); "
        "time.sleep(20)"
    )
    started = time.monotonic()

    with pytest.raises(CoachProviderError) as caught:
        asyncio.run(
            run_bounded_process(
                [sys.executable, "-c", script],
                stdin=b"synthetic input",
                cwd="/tmp",
                env={"PATH": os.environ.get("PATH", "")},
                timeout_seconds=10,
                stdout_line_validator=_reject_unsafe_event_line,
            ),
        )

    assert caught.value.code == expected_code
    assert time.monotonic() - started < 3


def _settings() -> Settings:
    return Settings(
        APP_ENV="development",
        USE_MOCK_DATA=False,
        SUPABASE_URL="http://127.0.0.1:54321",
        SUPABASE_SERVICE_ROLE_KEY="backend-only",
        COACH_PROVIDER="local_codex_oauth",
        LOCAL_CODEX_ENABLED=True,
        LOCAL_CODEX_BIN="codex",
        LOCAL_CODEX_MODEL="gpt-5.5",
    )


def _agent_event(final: str) -> bytes:
    return json.dumps(
        {
            "type": "item.completed",
            "item": {"id": "one", "type": "agent_message", "text": final},
        },
    ).encode()


def _valid_stream(final: str) -> bytes:
    return b"\n".join(
        [
            json.dumps(
                {"type": "thread.started", "thread_id": "redacted"},
            ).encode(),
            json.dumps({"type": "turn.started", "model": "gpt-5.5"}).encode(),
            _agent_event(final),
            json.dumps({"type": "turn.completed", "usage": {}}).encode(),
        ],
    )


def _valid_final() -> str:
    return VALID_FINAL
