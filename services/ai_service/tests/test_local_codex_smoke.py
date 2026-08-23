import asyncio
import json
import os
from pathlib import Path

import pytest

from app.core.config import Settings
from app.providers.base import CoachProviderError
from app.providers.local_codex import LocalCodexCoachProvider, run_bounded_process
from app.services.coach_agent_prompt import build_coach_agent_prompt
from app.services.coach_snapshot import _write_snapshot


pytestmark = pytest.mark.skipif(
    os.getenv("RUN_LOCAL_CODEX_SMOKE", "").lower() != "true",
    reason="Set RUN_LOCAL_CODEX_SMOKE=true for the explicit local subscription smoke.",
)


def test_opt_in_local_codex_smoke_uses_fast_multi_tool_data_agent(
    tmp_path: Path,
) -> None:
    snapshot_path = tmp_path / "personal.sqlite"
    trace_path = tmp_path / "agent-trace.jsonl"
    _write_snapshot(
        snapshot_path,
        {
            "daily_logs": [
                {
                    "id": f"daily-{index}",
                    "entry_date": f"2026-07-{index:02d}",
                    "estimated_sleep_hours": sleep,
                }
                for index, sleep in enumerate(
                    [6.5, 7.8, 8.0, 6.9, 7.6, 8.2, 7.4, 7.9],
                    start=1,
                )
            ],
            "focus_sessions": [
                {
                    "id": f"focus-{index}",
                    "started_at": f"2026-07-{index:02d}T09:00:00+00:00",
                    "ended_at": f"2026-07-{index:02d}T09:30:00+00:00",
                    "actual_minutes": 30,
                    "state": "completed",
                }
                for index in range(1, 9)
            ],
            "focus_session_reflections": [
                {
                    "id": f"reflection-{index}",
                    "focus_session_id": f"focus-{index}",
                    "focus_rating": rating,
                    "created_at": f"2026-07-{index:02d}T09:35:00+00:00",
                }
                for index, rating in enumerate(
                    [2, 4, 5, 3, 4, 5, 2, 4],
                    start=1,
                )
            ],
        },
    )
    os.chmod(snapshot_path, 0o444)

    settings = Settings(
        APP_ENV="development",
        USE_MOCK_DATA=False,
        COACH_PROVIDER="local_codex_oauth",
        LOCAL_CODEX_ENABLED=True,
        LOCAL_CODEX_MODEL="gpt-5.5",
        LOCAL_CODEX_TIMEOUT_SECONDS=120,
        COACH_AGENT_TIMEOUT_SECONDS=180,
        COACH_ANALYSIS_IMAGE=os.getenv(
            "COACH_ANALYSIS_IMAGE",
            "mylifegraph-coach-analysis:1",
        ),
        COACH_ANALYSIS_DOCKER_BIN=os.getenv(
            "COACH_ANALYSIS_DOCKER_BIN",
            "docker",
        ),
        SUPABASE_URL="http://127.0.0.1:54321",
        SUPABASE_SERVICE_ROLE_KEY="local-smoke-placeholder",
    )
    observed_argv: list[str] = []
    observed_mcp_statuses: list[tuple[str, str]] = []

    async def sanitized_runner(argv, **kwargs):
        observed_argv[:] = argv
        result = await run_bounded_process(argv, **kwargs)
        for line in result.stdout.splitlines():
            try:
                event = json.loads(line)
            except (UnicodeDecodeError, json.JSONDecodeError):
                continue
            if not isinstance(event, dict):
                continue
            item = event.get("item")
            if (
                isinstance(item, dict)
                and item.get("type") in {"mcp_tool_call", "mcp_call"}
                and isinstance(item.get("tool"), str)
                and isinstance(item.get("status"), str)
            ):
                observed_mcp_statuses.append((item["tool"], item["status"]))
        return result

    provider = LocalCodexCoachProvider(settings, runner=sanitized_runner)

    async def run_smoke():
        capability = await provider.capability()
        assert capability.state == "ready", (
            "Local Coach smoke unavailable: " + capability.reason_code
        )
        prompt = build_coach_agent_prompt(
                message=(
                    "Join every retained Focus reflection through its "
                    "focus_session_id to the Focus session, then match the "
                    "session's start date to that date's sleep record. Test "
                    "whether focus ratings were usually higher after at least "
                    "7.5 hours of estimated sleep. Use an appropriate statistical "
                    "Python check, look for counterexamples, and separate "
                    "observation from interpretation."
                ),
        )
        return await provider.respond_agent(
            prompt=prompt,
            snapshot_path=snapshot_path,
            trace_path=trace_path,
        )

    try:
        result = asyncio.run(run_smoke())
    except CoachProviderError as exc:
        pytest.fail(
            f"Local Coach smoke failed with sanitized code: {exc.code}",
            pytrace=False,
        )
    except Exception:
        pytest.fail(
            "Local Coach smoke failed with an unexpected sanitized error.",
            pytrace=False,
        )

    # Current Codex JSONL may omit a model field. A reported value must match;
    # the strict explicit argv below is the non-fallback model identity proof.
    assert result.model_reported in {None, "gpt-5.5"}
    assert result.output.reply.strip()
    assert len(result.output.reply) <= 4_000
    assert 'service_tier="fast"' in observed_argv
    assert "features.fast_mode=true" in observed_argv
    assert observed_argv[observed_argv.index("--model") + 1] == "gpt-5.5"
    assert not [
        (tool, status)
        for tool, status in observed_mcp_statuses
        if status == "failed"
    ]

    rows = [
        json.loads(line)
        for line in trace_path.read_text(encoding="utf-8").splitlines()
    ]
    completed = [
        row
        for row in rows
        if isinstance(row, dict) and row.get("status") == "completed"
    ]
    tools = [row.get("tool") for row in completed]
    assert len(completed) >= 2
    assert "inspect_data" in tools
    assert "run_python" in tools
    query_tables = {
        table
        for row in completed
        if row.get("tool") == "query_data"
        for table in row.get("tables", [])
        if isinstance(table, str)
    }
    assert query_tables <= {
        "daily_logs",
        "focus_sessions",
        "focus_session_reflections",
        "_coach_catalog",
        "_coach_relationships",
    }
    python_steps = [row for row in completed if row.get("tool") == "run_python"]
    assert python_steps
    assert all(row.get("full_snapshot_access") is True for row in python_steps)
    assert all(row.get("tables") == [] for row in python_steps)

    # The synthetic data have complete separation: all five >=7.5-hour days
    # have ratings 4-5, while all three shorter-sleep days have ratings 2-3.
    # Keep this semantic check tolerant of the model's choice of appropriate
    # test and wording, while still requiring the threshold and observational
    # limitation requested by the smoke.
    reply = result.output.reply.casefold()
    assert "7.5" in reply
    assert "higher" in reply
    assert any(marker in reply for marker in {"4.4", "median 4", "five"})
    assert any(
        marker in reply
        for marker in {"caus", "association", "observational", "cannot establish"}
    )
