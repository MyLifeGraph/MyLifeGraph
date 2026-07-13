import asyncio
import json
import os
import re

import pytest

from app.core.config import Settings
from app.providers.base import CoachProviderError
from app.providers.local_codex import LocalCodexCoachProvider, run_bounded_process
from app.services.coach_context import CoachContextPackage
from app.services.coach_prompt import build_coach_prompt


pytestmark = pytest.mark.skipif(
    os.getenv("RUN_LOCAL_CODEX_SMOKE", "").lower() != "true",
    reason="Set RUN_LOCAL_CODEX_SMOKE=true for the explicit local subscription smoke.",
)


def test_opt_in_local_codex_smoke_uses_only_synthetic_context() -> None:
    settings = Settings()
    lifecycle: list[str] = []

    async def sanitized_runner(*args, **kwargs):
        result = await run_bounded_process(*args, **kwargs)
        for line in result.stdout.splitlines():
            try:
                event = json.loads(line)
            except (UnicodeDecodeError, json.JSONDecodeError):
                continue
            if not isinstance(event, dict):
                continue
            event_type = event.get("type")
            if isinstance(event_type, str) and re.fullmatch(
                r"[a-z][a-z0-9_.-]{0,63}",
                event_type,
            ):
                lifecycle.append(f"event:{event_type}")
            item = event.get("item")
            item_type = item.get("type") if isinstance(item, dict) else None
            if isinstance(item_type, str) and re.fullmatch(
                r"[a-z][a-z0-9_.-]{0,63}",
                item_type,
            ):
                safe_keys = sorted(
                    key
                    for key in item
                    if isinstance(key, str)
                    and re.fullmatch(r"[a-z][a-z0-9_.-]{0,63}", key)
                )
                lifecycle.append(
                    f"item:{item_type}:keys={'+'.join(safe_keys) or 'none'}",
                )
        return result

    provider = LocalCodexCoachProvider(settings, runner=sanitized_runner)
    capability = asyncio.run(provider.capability())
    assert capability.state == "ready", (
        "Local Coach smoke unavailable: " + capability.reason_code
    )
    prompt = build_coach_prompt(
        message="Suggest one small, review-only planning step for a fictional day.",
        context=CoachContextPackage(
            serialized=(
                '{"context_scope":"today","contract_version":"coach-context-v1",'
                '"local_date":"2026-01-01","sources":{}}'
            ),
            used_context=[],
            daily_state_freshness="missing",
            daily_state_quality="missing",
        ),
    )
    try:
        result = asyncio.run(provider.respond(prompt=prompt))
    except CoachProviderError as exc:
        sanitized_lifecycle = ",".join(lifecycle) or "none"
        pytest.fail(
            "Local Coach smoke failed with sanitized code/lifecycle: "
            f"{exc.code}; {sanitized_lifecycle}",
            pytrace=False,
        )
    except Exception:
        pytest.fail(
            "Local Coach smoke failed with an unexpected sanitized error.",
            pytrace=False,
        )
    assert result.output.reply.strip()
    assert len(result.output.reply) <= 4_000
