import asyncio
import json
from dataclasses import replace
from datetime import date
from types import SimpleNamespace

import pytest

from app.models.coach import CoachRequest
from app.models.coach_evidence import (
    CoachEvidenceDigest,
    CoachEvidenceSourceSummary,
    CoachEvidenceWindow,
)
from app.repositories.coach_context_repository import (
    BoundedRows,
    CoachProfileContext,
    CoachRawContext,
    CoachSharedContext,
)
from app.services.coach_context import (
    CoachContextService,
    _safe_daily_context,
)


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


def test_context_uses_freshness_contracts_and_filters_hidden_metadata() -> None:
    raw = _raw_context()
    briefing = Envelope(
        briefing={"id": "briefing"},
        freshness="current",
        payload={
            "contract_version": "daily-briefing-v2",
            "freshness": "current",
            "briefing": {"summary": "Keep the primary action small."},
        },
    )
    weekly = Envelope(
        review={"id": "weekly"},
        freshness="stale",
        payload={
            "contract_version": "weekly-review-v3",
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
    assert context["contract_version"] == "coach-context-v2"
    assert set(context["sources"]["profile"]) == {"local_date", "timezone"}
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
    assert all(
        "context_scope" not in turn and "context_parameters" not in turn
        for turn in context["sources"]["coach_history"]
    )
    habit = context["sources"]["habits"][0]
    assert set(habit["cadence"]) == {"contract_version", "cadence"}
    daily_context = context["sources"]["daily_snapshot"]["daily_state"]["context"]
    assert "context_note" not in daily_context
    assert daily_context["sleep_quality"] == 3
    assert "main_friction" not in daily_context
    assert "additional_frictions" not in daily_context


def test_daily_context_discards_retired_friction_fields() -> None:
    context = _safe_daily_context(
        {
            "main_friction": "interruptions",
            "additional_frictions": ["hard_to_start"],
        },
    )
    assert "main_friction" not in context
    assert "additional_frictions" not in context


@pytest.mark.parametrize("value", [0, 11, True, 3.5, "3"])
def test_daily_context_rejects_invalid_sleep_quality(value) -> None:
    assert _safe_daily_context({"sleep_quality": value})["sleep_quality"] is None


def test_current_weekly_review_is_included() -> None:
    raw = _raw_context()
    briefing = Envelope(briefing=None, freshness="missing", payload={})
    weekly = Envelope(
        review={"id": "weekly"},
        freshness="current",
        payload={
            "contract_version": "weekly-review-v3",
            "freshness": "current",
            "review": {
                "narrative": "Current deterministic review.",
                "proposals": [
                    {
                        "id": "legacy-proposal",
                        "reason": "SECRET_LEGACY_ADJUSTMENT",
                    },
                ],
            },
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
    assert "proposals" not in weekly_source["review"]
    assert "SECRET_LEGACY_ADJUSTMENT" not in package.serialized


def test_oversized_unicode_rows_are_omitted_as_whole_items_deterministically() -> None:
    memories = [
        {
            "id": f"memory-{index}",
            "type": "preference",
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


class SharedRepository(Repository):
    async def load_shared_context(self, **kwargs):
        return CoachSharedContext(
            profile=self.raw.profile,
            selected_memories=self.raw.selected_memories,
            history=self.raw.history,
        )


class EvidenceReader:
    async def build_patterns(self, **kwargs):
        return _evidence()

    async def build_focus(self, **kwargs):
        return _evidence()

    async def build_review(self, **kwargs):
        return _evidence()


def test_v3_patterns_context_contains_only_digest_and_shared_sources() -> None:
    raw = _raw_context()
    service = CoachContextService(
        repository=SharedRepository(raw),
        briefing_reader=Reader(Envelope(briefing=None, freshness="missing")),
        weekly_review_reader=Reader(Envelope(review=None, freshness="missing")),
        evidence_reader=EvidenceReader(),
    )
    request = CoachRequest.model_validate(
        {
            "contract_version": "coach-request-v2",
            "request_id": "11111111-1111-4111-8111-111111111111",
            "message": "What changed?",
            "context_scope": "patterns",
            "context_parameters": {"horizon": "1_year"},
        },
    )

    package = asyncio.run(
        service.build(
            user_id="owner",
            local_date=LOCAL_DATE,
            request=request,
        ),
    )
    context = json.loads(package.serialized)

    assert context["contract_version"] == "coach-context-v3"
    assert context["context_parameters"] == {"horizon": "1_year"}
    assert "tasks" not in context["sources"]
    assert context["evidence"]["evidence_fingerprint"] == "a" * 64
    assert all(
        set(turn) >= {"context_scope", "context_parameters"}
        for turn in context["sources"]["coach_history"]
    )
    assert package.byte_count <= 32_768
    assert {item.source for item in package.used_context} >= {
        "profile",
        "daily_capture",
        "focus_reflections",
        "habit_outcomes",
        "weekly_reviews",
        "task_lifecycle",
        "memories",
        "coach_history",
    }


def test_v2_today_request_builds_the_current_context_as_v3() -> None:
    raw = _raw_context()
    repository = Repository(raw)
    service = CoachContextService(
        repository=repository,
        briefing_reader=Reader(
            Envelope(briefing=None, freshness="missing", payload={}),
        ),
        weekly_review_reader=Reader(
            Envelope(review=None, freshness="missing", payload={}),
        ),
    )
    request = CoachRequest.model_validate(
        {
            "contract_version": "coach-request-v2",
            "request_id": "11111111-1111-4111-8111-111111111111",
            "message": "What matters today?",
            "context_scope": "today",
            "context_parameters": {},
        },
    )

    package = asyncio.run(
        service.build(
            user_id="owner",
            local_date=LOCAL_DATE,
            request=request,
        ),
    )
    context = json.loads(package.serialized)

    assert context["contract_version"] == "coach-context-v3"
    assert context["context_scope"] == "today"
    assert context["context_parameters"] == {}
    assert package.evidence_status == "not_applicable"
    assert repository.calls == [
        {"user_id": "owner", "local_date": LOCAL_DATE.isoformat()},
    ]


def _raw_context() -> CoachRawContext:
    response = {
        "reply": "Prior bounded answer.",
        "uncertainty": {"level": "medium", "reason": "Bounded."},
        "safety": {"classification": "normal"},
    }
    return CoachRawContext(
        profile=CoachProfileContext(timezone="Europe/Berlin"),
        onboarding_snapshot=None,
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
                        "sleep_quality": 3,
                        "main_friction": "no_major_friction",
                        "additional_frictions": [
                            "interruptions",
                            "hard_to_start",
                        ],
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
                    "type": "preference",
                    "title": "Selected preference",
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


def _evidence() -> CoachEvidenceDigest:
    source_names = (
        "daily_capture",
        "focus_reflections",
        "habit_outcomes",
        "weekly_reviews",
        "task_lifecycle",
    )
    return CoachEvidenceDigest(
        contract_version="coach-evidence-v1",
        mode="patterns",
        status="empty",
        generated_at="2026-07-13T08:00:00Z",
        timezone="Europe/Berlin",
        window=CoachEvidenceWindow(
            starts_on=date(2025, 7, 13),
            ends_on=date(2026, 7, 13),
            horizon="1_year",
            granularity="month",
        ),
        sources=[
            CoachEvidenceSourceSummary(
                source=name,
                available_count=0,
                included_count=0,
                partial=False,
            )
            for name in source_names
        ],
        buckets=[],
        summary_metrics={},
        selected_focus=None,
        limitations=["No eligible evidence is available."],
        evidence_fingerprint="a" * 64,
    )
