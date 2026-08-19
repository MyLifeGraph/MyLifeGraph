import asyncio
import json
import shutil
from pathlib import Path

import pytest

import app.providers.local_codex as local_codex_module
from app.core.config import Settings
from app.core.private_files import PrivateFileCleanupError
from app.providers.base import CoachProviderError
from app.providers.local_codex import (
    LocalCodexCoachProvider,
    ProcessResult,
    _expected_analysis_revision,
    _validate_agent_event_line,
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
fast_mode stable false
apps stable true
web_search stable false
collab stable false
"""


def _settings(**overrides) -> Settings:
    values = {
        "APP_ENV": "development",
        "USE_MOCK_DATA": False,
        "COACH_PROVIDER": "local_codex_oauth",
        "LOCAL_CODEX_ENABLED": True,
        "LOCAL_CODEX_BIN": "codex",
        "LOCAL_CODEX_MODEL": "gpt-5.5",
        "SUPABASE_URL": "http://127.0.0.1:54321",
        "SUPABASE_SECRET_KEY": "sb_secret_backend-secret",
        "SUPABASE_SERVICE_ROLE_KEY": "backend-secret",
        "COACH_ANALYSIS_DOCKER_BIN": "/usr/bin/docker",
        "COACH_ANALYSIS_IMAGE": "mylifegraph-coach-analysis:1",
    }
    values.update(overrides)
    return Settings(**values)


class AgentRunner:
    def __init__(
        self,
        *,
        features: bytes = FEATURES,
        model: str = "gpt-5.5",
        docker_available: bool = True,
        image_available: bool = True,
        image_revision: str | None = None,
    ):
        self.features = features
        self.model = model
        self.docker_available = docker_available
        self.image_available = image_available
        self.image_revision = image_revision or _expected_analysis_revision()
        self.calls: list[tuple[list[str], dict[str, object]]] = []

    async def __call__(self, argv, **kwargs) -> ProcessResult:
        self.calls.append((list(argv), kwargs))
        if argv[1:2] == ["version"]:
            return ProcessResult(
                0 if self.docker_available else 1,
                b"27.0.0" if self.docker_available else b"",
                b"",
            )
        if argv[1:3] == ["image", "inspect"]:
            if not self.image_available:
                return ProcessResult(1, b"", b"image missing")
            return ProcessResult(0, (self.image_revision or "").encode(), b"")
        if argv[1:3] == ["container", "rm"]:
            return ProcessResult(0, b"", b"")
        if argv[1:3] == ["container", "ls"]:
            return ProcessResult(0, b"", b"")
        if argv[-1] == "--help" and argv[-2] == "exec":
            return ProcessResult(0, EXEC_HELP, b"")
        if argv[-1] == "--help":
            return ProcessResult(0, GLOBAL_HELP, b"")
        if argv[-2:] == ["features", "list"]:
            return ProcessResult(0, self.features, b"")
        if argv[-2:] == ["login", "status"]:
            return ProcessResult(0, b"Logged in using ChatGPT subscription", b"")

        output = {
            "reply": "The available records do not support that premise.",
            "uncertainty": {
                "level": "medium",
                "reason": "Several periods contain no matching observations.",
            },
            "safety": {"classification": "normal"},
        }
        output_path = Path(argv[argv.index("--output-last-message") + 1])
        output_path.write_text(
            json.dumps(output, separators=(",", ":")),
            encoding="utf-8",
        )
        events = "\n".join(
            [
                json.dumps({"type": "thread.started", "thread_id": "redacted"}),
                json.dumps({"type": "turn.started", "model": self.model}),
                json.dumps(
                    {
                        "type": "item.completed",
                        "item": {
                            "id": "tool-1",
                            "type": "mcp_tool_call",
                            "server": "coach_data",
                            "tool": "query_data",
                            "status": "completed",
                        },
                    },
                ),
                json.dumps(
                    {
                        "type": "item.completed",
                        "item": {
                            "id": "answer-1",
                            "type": "agent_message",
                            "text": json.dumps(output, separators=(",", ":")),
                        },
                    },
                ),
                json.dumps({"type": "turn.completed", "usage": {}}),
            ],
        )
        validator = kwargs["stdout_line_validator"]
        for line in events.encode().splitlines():
            validator(line)
        return ProcessResult(0, events.encode(), b"")


def test_agent_invocation_requires_gpt55_fast_and_only_personal_data_mcp(
    tmp_path: Path,
) -> None:
    runner = AgentRunner()
    provider = LocalCodexCoachProvider(
        _settings(),
        runner=runner,
        executable_resolver=lambda _: "/usr/bin/codex",
        environ={
            "HOME": "/home/test",
            "CODEX_HOME": "/home/test/.codex",
            "PATH": "/usr/bin",
            "SUPABASE_SECRET_KEY": "must-not-leak",
            "SUPABASE_SERVICE_ROLE_KEY": "must-not-leak",
            "SCHEDULED_REFRESH_TOKEN": "must-not-leak",
            "OPENAI_API_KEY": "must-not-leak",
        },
    )
    snapshot = tmp_path / "personal.sqlite"
    snapshot.write_bytes(b"immutable snapshot")
    trace = tmp_path / "trace.jsonl"

    capability = asyncio.run(provider.capability())
    result = asyncio.run(
        provider.respond_agent(
            prompt="Answer this free question.",
            snapshot_path=snapshot,
            trace_path=trace,
        ),
    )

    assert capability.state == "ready"
    assert capability.model_requested == "gpt-5.5"
    assert result.output.reply.startswith("The available records")
    assert result.model_reported == "gpt-5.5"

    argv, options = runner.calls[-1]
    assert argv[argv.index("--model") + 1] == "gpt-5.5"
    configs = [
        argv[index + 1]
        for index, value in enumerate(argv)
        if value == "-c"
    ]
    assert 'service_tier="fast"' in configs
    assert "features.fast_mode=true" in configs
    assert "mcp_servers.coach_data.required=true" in configs
    assert (
        'mcp_servers.coach_data.enabled_tools='
        '["inspect_data","query_data","run_python"]'
    ) in configs
    assert (
        'mcp_servers.coach_data.default_tools_approval_mode="approve"'
        in configs
    )
    assert any(
        value.startswith("mcp_servers.coach_data.command=")
        for value in configs
    )
    assert any(
        value
        == "mcp_servers.coach_data.env.COACH_SNAPSHOT_PATH="
        + json.dumps(str(snapshot))
        for value in configs
    )
    assert any(
        value
        == "mcp_servers.coach_data.env.COACH_TRACE_PATH="
        + json.dumps(str(trace))
        for value in configs
    )
    mcp_home_values = [
        json.loads(value.split("=", 1)[1])
        for value in configs
        if value.startswith("mcp_servers.coach_data.env.HOME=")
    ]
    assert len(mcp_home_values) == 1
    assert mcp_home_values[0] != "/home/test"
    assert Path(mcp_home_values[0]).name == "mcp-home"
    assert not Path(mcp_home_values[0]).exists()
    assert (
        "mcp_servers.coach_data.env.CODEX_HOME="
        + json.dumps(mcp_home_values[0])
    ) in configs
    container_state = trace.with_name("coach-analysis-container.name")
    assert (
        "mcp_servers.coach_data.env.COACH_CONTAINER_STATE_PATH="
        + json.dumps(str(container_state))
    ) in configs
    assert not container_state.exists()
    assert not any(
        value.startswith("mcp_servers.") and ".coach_data" not in value
        for value in configs
    )
    disabled = {
        argv[index + 1]
        for index, value in enumerate(argv)
        if value == "--disable"
    }
    assert disabled == {
        "apps",
        "collab",
        "shell_tool",
        "unified_exec",
        "web_search",
    }
    assert "fast_mode" not in disabled
    assert argv[argv.index("--sandbox") + 1] == "read-only"
    assert "--ask-for-approval" in argv
    assert argv[argv.index("--ask-for-approval") + 1] == "never"
    assert "--ignore-user-config" in argv
    assert "--ignore-rules" in argv
    assert options["timeout_seconds"] == 180
    assert options["env"] == {
        "HOME": "/home/test",
        "CODEX_HOME": "/home/test/.codex",
        "PATH": "/usr/bin",
    }
    docker_calls = [
        call_options
        for call_argv, call_options in runner.calls
        if call_argv[0] == "/usr/bin/docker"
    ]
    assert docker_calls
    assert all("CODEX_HOME" not in call["env"] for call in docker_calls)
    assert all(call["env"]["HOME"] != "/home/test" for call in docker_calls)


def test_capability_fails_honestly_when_fast_mode_is_unavailable() -> None:
    runner = AgentRunner(
        features=b"shell_tool stable true\nunified_exec stable true\n",
    )
    provider = LocalCodexCoachProvider(
        _settings(),
        runner=runner,
        executable_resolver=lambda _: "/usr/bin/codex",
    )

    capability = asyncio.run(provider.capability())

    assert capability.state == "unavailable"
    assert capability.reason_code == "fast_mode_unavailable"


@pytest.mark.parametrize(
    ("runner", "reason_code"),
    [
        (
            AgentRunner(docker_available=False),
            "analysis_runtime_unavailable",
        ),
        (
            AgentRunner(image_available=False),
            "analysis_image_unavailable",
        ),
        (
            AgentRunner(image_revision="0" * 64),
            "analysis_image_stale",
        ),
    ],
)
def test_capability_fails_honestly_for_missing_or_stale_analysis_image(
    runner: AgentRunner,
    reason_code: str,
) -> None:
    provider = LocalCodexCoachProvider(
        _settings(),
        runner=runner,
        executable_resolver=lambda _: "/usr/bin/codex",
    )

    capability = asyncio.run(provider.capability())

    assert capability.state == "unavailable"
    assert capability.reason_code == reason_code


def test_agent_cancellation_force_removes_and_verifies_turn_container(
    tmp_path: Path,
) -> None:
    container_name = "mylifegraph-coach-analysis-" + ("a" * 32)

    class CancellingRunner(AgentRunner):
        def __init__(self) -> None:
            super().__init__()
            self.agent_started = asyncio.Event()
            self.agent_workdir: str | None = None
            self.container_state_path: Path | None = None

        async def __call__(self, argv, **kwargs) -> ProcessResult:
            if "--output-last-message" in argv:
                self.calls.append((list(argv), kwargs))
                configs = [
                    argv[index + 1]
                    for index, value in enumerate(argv)
                    if value == "-c"
                ]
                state_setting = next(
                    value
                    for value in configs
                    if value.startswith(
                        "mcp_servers.coach_data.env."
                        "COACH_CONTAINER_STATE_PATH=",
                    )
                )
                self.container_state_path = Path(
                    json.loads(state_setting.split("=", 1)[1]),
                )
                self.container_state_path.write_text(
                    container_name + "\n",
                    encoding="ascii",
                )
                self.agent_workdir = kwargs["cwd"]
                self.agent_started.set()
                await asyncio.Future()
            return await super().__call__(argv, **kwargs)

    async def run() -> CancellingRunner:
        runner = CancellingRunner()
        provider = LocalCodexCoachProvider(
            _settings(),
            runner=runner,
            executable_resolver=lambda _: "/usr/bin/codex",
            environ={
                "HOME": "/home/test",
                "CODEX_HOME": "/home/test/.codex",
                "PATH": "/usr/bin",
            },
        )
        snapshot = tmp_path / "personal.sqlite"
        snapshot.write_bytes(b"immutable snapshot")
        task = asyncio.create_task(
            provider.respond_agent(
                prompt="question",
                snapshot_path=snapshot,
                trace_path=tmp_path / "trace.jsonl",
            ),
        )
        await asyncio.wait_for(runner.agent_started.wait(), timeout=1)
        task.cancel()
        with pytest.raises(asyncio.CancelledError):
            await task
        return runner

    runner = asyncio.run(run())

    cleanup_argv = [
        argv
        for argv, _options in runner.calls
        if argv[1:3] in (["container", "rm"], ["container", "ls"])
    ]
    assert cleanup_argv == [
        [
            "/usr/bin/docker",
            "container",
            "rm",
            "--force",
            container_name,
        ],
        [
            "/usr/bin/docker",
            "container",
            "ls",
            "--all",
            "--filter",
            f"name=^/{container_name}$",
            "--format",
            "{{.Names}}",
        ],
    ]
    assert runner.container_state_path is not None
    assert not runner.container_state_path.exists()
    assert runner.agent_workdir is not None
    assert not Path(runner.agent_workdir).exists()


def test_agent_fails_honestly_when_private_workdir_cannot_be_removed(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    runner = AgentRunner()
    provider = LocalCodexCoachProvider(
        _settings(),
        runner=runner,
        executable_resolver=lambda _: "/usr/bin/codex",
    )
    snapshot = tmp_path / "personal.sqlite"
    snapshot.write_bytes(b"immutable snapshot")

    async def fail_cleanup(
        path: Path,
        *,
        expected_name_prefix: str,
    ) -> None:
        assert path.name.startswith(expected_name_prefix)
        raise PrivateFileCleanupError("simulated retained private output")

    monkeypatch.setattr(
        local_codex_module,
        "remove_private_directory_despite_cancellation",
        fail_cleanup,
    )
    agent_workdir: Path | None = None
    try:
        with pytest.raises(CoachProviderError) as caught:
            asyncio.run(
                provider.respond_agent(
                    prompt="question",
                    snapshot_path=snapshot,
                    trace_path=tmp_path / "trace.jsonl",
                ),
            )

        assert caught.value.code == "provider_failure"
        assert "securely remove private turn files" in str(caught.value)
        agent_call = next(
            options
            for argv, options in runner.calls
            if "--output-last-message" in argv
        )
        agent_workdir = Path(str(agent_call["cwd"]))
        assert agent_workdir.exists()
    finally:
        if agent_workdir is not None:
            shutil.rmtree(agent_workdir, ignore_errors=True)


def test_agent_rejects_model_fallback_or_mismatched_report(tmp_path: Path) -> None:
    wrong_configuration = LocalCodexCoachProvider(
        _settings(LOCAL_CODEX_MODEL="gpt-5.4"),
        runner=AgentRunner(),
        executable_resolver=lambda _: "/usr/bin/codex",
    )
    with pytest.raises(CoachProviderError) as configured:
        asyncio.run(
            wrong_configuration.respond_agent(
                prompt="question",
                snapshot_path=Path("/tmp/snapshot"),
                trace_path=Path("/tmp/trace"),
            ),
        )
    assert configured.value.code == "unavailable_model"

    async def run_mismatch() -> None:
        runner = AgentRunner(model="gpt-5.4")
        provider = LocalCodexCoachProvider(
            _settings(),
            runner=runner,
            executable_resolver=lambda _: "/usr/bin/codex",
        )
        with pytest.raises(CoachProviderError) as reported:
            await provider.respond_agent(
                prompt="question",
                snapshot_path=tmp_path / "snapshot",
                trace_path=tmp_path / "trace",
            )
        assert reported.value.code == "unavailable_model"

    asyncio.run(run_mismatch())


@pytest.mark.parametrize(
    "item",
    [
        {"id": "x", "type": "command_execution", "command": "cat /etc/passwd"},
        {
            "id": "x",
            "type": "mcp_tool_call",
            "server": "another_server",
            "tool": "query_data",
        },
        {
            "id": "x",
            "type": "mcp_tool_call",
            "server": "coach_data",
            "tool": "write_data",
        },
    ],
)
def test_agent_event_gate_rejects_every_non_authorized_operation(item) -> None:
    line = json.dumps({"type": "item.started", "item": item}).encode()

    with pytest.raises(CoachProviderError) as caught:
        _validate_agent_event_line(line)

    assert caught.value.code == "unsafe_provider_event"
