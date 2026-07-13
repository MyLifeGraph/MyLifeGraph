import asyncio
import json
from dataclasses import replace
from datetime import date
from types import SimpleNamespace

import pytest

from app.repositories.coach_context_repository import (
    BoundedRows,
    CoachProfileContext,
    CoachRawContext,
)
from app.services.coach_context import CoachContextService, _coaching_preference


LOCAL_DATE = date(2026, 7, 13)


class Repository:
    def __init__(self, raw: CoachRawContext) -> None:
        self.raw = raw
        self.calls = []

    async def load_today_context(self, **kwargs):
        self.calls.append(kwargs)
        return self.raw


class Reader:
    def __init__(self, envelope) -> None:
        self.envelope = envelope

    async def get_for_date(self, **kwargs):
        return self.envelope

    async def get_latest(self, **kwargs):
        return self.envelope


class Envelope(SimpleNamespace):
    def model_dump(self, *, mode):
        return self.payload


@pytest.mark.parametrize("value", ["direct", "gentle", "analytical", "accountability"])
def test_structured_intake_coaching_preferences_are_allowlisted(value: str) -> None:
    assert _coaching_preference({"summary": {"coaching_style": value}}) == value


def test_unknown_coaching_preference_is_excluded() -> None:
    assert _coaching_preference({"summary": {"coaching_style": "hidden text"}}) is None


def test_context_uses_freshness_contracts_and_filters_hidden_metadata() -> None:
    raw = _raw_context()
    briefing = Envelope(
        briefing={"id": "briefing"},
        freshness="current",
        payload={
            "contract_version": "daily-briefing-v1",
            "freshness": "current",
            "briefing": {"summary": "Keep the primary action small."},
        },
    )
    weekly = Envelope(
        review={"id": "weekly"},
        freshness="stale",
        payload={
            "contract_version": "weekly-review-v1",
            "freshness": "stale",
            "review": {"narrative": "SECRET_STALE_WEEKLY"},
        },
    )
    service = CoachContextService(
        repository=Repository(raw),
        briefing_reader=Reader(briefing),
        weekly_review_reader=Reader(weekly),
    )

    package = asyncio.run(
        service.build_today(user_id="owner", local_date=LOCAL_DATE),
    )
    context = json.loads(package.serialized)

    assert package.byte_count <= 32_768
    assert context["sources"]["profile"]["coaching_preference"] == "analytical"
    assert context["sources"]["daily_briefing"]["freshness"] == "current"
    assert context["sources"]["weekly_review"] is None
    assert "SECRET" not in package.serialized
    manifests = {item.source: item for item in package.used_context}
    assert manifests["weekly_review"].model_dump() == {
        "source": "weekly_review",
        "available_count": 1,
        "included_count": 0,
        "omitted_count": 1,
        "freshness": "stale",
    }
    assert manifests["coach_history"].available_count == 50
    assert manifests["coach_history"].included_count == 6
    assert manifests["coach_history"].omitted_count == 44
    habit = context["sources"]["habits"][0]
    assert set(habit["cadence"]) == {"contract_version", "cadence"}
    daily_context = context["sources"]["daily_snapshot"]["daily_state"]["context"]
    assert "context_note" not in daily_context


def test_current_weekly_review_is_included() -> None:
    raw = _raw_context()
    briefing = Envelope(briefing=None, freshness="missing", payload={})
    weekly = Envelope(
        review={"id": "weekly"},
        freshness="current",
        payload={
            "contract_version": "weekly-review-v1",
            "freshness": "current",
            "review": {"narrative": "Current deterministic review."},
        },
    )
    package = asyncio.run(
        CoachContextService(
            repository=Repository(raw),
            briefing_reader=Reader(briefing),
            weekly_review_reader=Reader(weekly),
        ).build_today(user_id="owner", local_date=LOCAL_DATE),
    )
    weekly_source = json.loads(package.serialized)["sources"]["weekly_review"]
    assert weekly_source["freshness"] == "current"


def test_oversized_unicode_rows_are_omitted_as_whole_items_deterministically() -> None:
    memories = [
        {
            "id": f"memory-{index}",
            "type": "goal",
            "title": f"Memory {index}",
            "content": "🌱" * 1_200,
            "selected_at": f"2026-07-13T0{index}:00:00Z",
        }
        for index in range(8)
    ]
    raw = replace(
        _raw_context(),
        selected_memories=BoundedRows(available_count=8, rows=memories),
    )
    briefing = Envelope(briefing=None, freshness="missing", payload={})
    weekly = Envelope(review=None, freshness="missing", payload={})

    async def build():
        return await CoachContextService(
            repository=Repository(raw),
            briefing_reader=Reader(briefing),
            weekly_review_reader=Reader(weekly),
        ).build_today(user_id="owner", local_date=LOCAL_DATE)

    first = asyncio.run(build())
    second = asyncio.run(build())
    assert first.serialized == second.serialized
    assert first.byte_count <= 32_768
    manifest = next(item for item in first.used_context if item.source == "memories")
    assert 0 < manifest.included_count < 8
    assert manifest.included_count + manifest.omitted_count == manifest.available_count
    included = json.loads(first.serialized)["sources"]["memories"]
    assert [item["id"] for item in included] == [
        f"memory-{index}" for index in range(manifest.included_count)
    ]
    assert all(item["content"] == "🌱" * 1_000 for item in included)


def _raw_context() -> CoachRawContext:
    response = {
        "reply": "Prior bounded answer.",
        "uncertainty": {"level": "medium", "reason": "Bounded."},
        "safety": {"classification": "normal"},
    }
    return CoachRawContext(
        profile=CoachProfileContext(timezone="Europe/Berlin"),
        onboarding_snapshot={
            "summary": {
                "coaching_style": "analytical",
                "context_note": "SECRET_INTAKE_NOTE",
            },
        },
        daily_snapshot={
            "id": "snapshot",
            "generated_at": "2026-07-13T06:00:00Z",
            "summary": {
                "daily_state": {
                    "contract_version": "explainable-daily-state-v1",
                    "target_date": "2026-07-13",
                    "mode": "steady",
                    "data_quality": "current",
                    "freshness": {},
                    "context": {
                        "mood": 6,
                        "current_energy": 5,
                        "sleep_hours": 7.5,
                        "context_note": "SECRET_CAPTURE_NOTE",
                    },
                    "risk_flags": [],
                    "reason_codes": ["steady_balanced_state"],
                    "reasons": [
                        {
                            "code": "steady_balanced_state",
                            "message": "Current values support a steady load.",
                            "secret": "SECRET_REASON_METADATA",
                        },
                    ],
                    "load_guidance": "maintain",
                    "provenance": {
                        "kind": "deterministic",
                        "basis": "explicit_capture",
                        "baseline": "none",
                        "history_claim": "current_state_only",
                        "secret": "SECRET_PROVENANCE",
                    },
                },
            },
        },
        goals=BoundedRows(
            available_count=1,
            rows=[{"id": "goal", "title": "Finish report", "status": "active"}],
        ),
        tasks=BoundedRows(
            available_count=1,
            rows=[{"id": "task", "title": "Write outline", "status": "todo"}],
        ),
        habits=BoundedRows(
            available_count=1,
            rows=[
                {
                    "id": "habit",
                    "title": "Walk",
                    "frequency": "daily",
                    "target": 1,
                    "metadata": {
                        "contract_version": "habit-v1",
                        "cadence": "daily",
                        "notes": "SECRET_HABIT_METADATA",
                    },
                },
            ],
        ),
        focus_sessions=BoundedRows(available_count=0, rows=[]),
        selected_memories=BoundedRows(
            available_count=1,
            rows=[
                {
                    "id": "memory",
                    "type": "goal",
                    "title": "Selected goal",
                    "content": "Protect morning focus.",
                    "metadata": {"secret": "SECRET_MEMORY_METADATA"},
                    "selected_at": "2026-07-13T05:00:00Z",
                },
            ],
        ),
        history=BoundedRows(
            available_count=50,
            rows=[
                {
                    "request_id": f"00000000-0000-4000-8000-{index:012d}",
                    "message": f"Prior message {index}",
                    "response": response,
                    "completed_at": "2026-07-13T05:00:00Z",
                }
                for index in range(6)
            ],
        ),
    )
