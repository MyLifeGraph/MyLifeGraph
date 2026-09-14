import asyncio
from datetime import UTC, date, datetime, time, timedelta
from zoneinfo import ZoneInfo

import pytest

from app.services.important_reminder_rules import (
    ReminderPreferences,
    important_reminders,
)
from tests.test_sleep_recommendation_service import _evidence, _get
from tests.test_personal_patterns_service import Repository, _rows, _service


def evaluate(**changes):
    values = dict(
        now=datetime(2026, 9, 14, 7, 5, tzinfo=UTC),
        timezone="Europe/Berlin",
        preferences=ReminderPreferences(enabled=True),
        reserved_today=0,
        reserved_keys=set(),
        has_open_deadlines_today=True,
    )
    values.update(changes)
    return important_reminders(**values)


def test_deadlines_are_one_grouped_short_lived_candidate():
    result = evaluate()
    assert len(result) == 1
    assert result[0].kind == "deadlines"
    assert result[0].expires_at == datetime(2026, 9, 14, 7, 15, tzinfo=UTC)
    assert result[0].destination == "/planner"


@pytest.mark.parametrize(
    "changes",
    [
        {"preferences": ReminderPreferences()},
        {"reserved_today": 2},
        {"reserved_keys": {"deadlines:2026-09-14"}},
        {"has_open_deadlines_today": False},
        {"now": datetime(2026, 9, 14, 7, 15, tzinfo=UTC)},
        {"now": datetime(2026, 9, 14, 15, 0, tzinfo=UTC)},
        {
            "preferences": ReminderPreferences(
                enabled=True, quiet_start=time(8), quiet_end=time(10)
            )
        },
        {
            "preferences": ReminderPreferences(
                enabled=True, quiet_start=time(9), quiet_end=time(9)
            )
        },
    ],
)
def test_consent_cap_dedupe_quiet_hours_and_no_catchup(changes):
    assert evaluate(**changes) == []


def test_invalid_counter_or_naive_clock_fails_closed():
    with pytest.raises(ValueError):
        evaluate(reserved_today=-1)
    with pytest.raises(ValueError):
        evaluate(now=datetime(2026, 9, 14))


def test_sleep_uses_current_ready_window_and_respects_warning_and_freshness():
    evidence = _evidence(30)
    for row in evidence[2]:
        row["metadata"]["captures"]["morning"]["sleep_target_minutes"] = 480
    result, _, _ = _get(evidence)
    assert result.recommendation is not None
    bedtime = time.fromisoformat(result.recommendation.bedtime.start_local_time)
    instant = datetime.combine(
        date(2026, 7, 30), bedtime, tzinfo=ZoneInfo("Europe/Berlin")
    )
    now = instant - timedelta(minutes=25)
    fresh = result.model_copy(update={"generated_at": now})
    preferences = ReminderPreferences(
        enabled=True, quiet_start=time(1), quiet_end=time(7)
    )
    candidates = evaluate(now=now, sleep=fresh, preferences=preferences)
    assert [candidate.kind for candidate in candidates] == ["sleep"]
    assert evaluate(now=instant, sleep=fresh, preferences=preferences) == []
    assert (
        evaluate(
            now=now,
            sleep=result.model_copy(
                update={"generated_at": now - timedelta(minutes=16)}
            ),
            preferences=preferences,
        )
        == []
    )
    warned = fresh.model_copy(
        update={
            "recommendation": fresh.recommendation.model_copy(
                update={"warning": "below_confirmed_sleep_target"}
            )
        }
    )
    assert evaluate(now=now, sleep=warned, preferences=preferences) == []


def test_important_pattern_uses_real_stable_evidence_and_monthly_cooldown():
    specs = [
        (
            date(2026, 6, 15) + timedelta(days=index * 2),
            9 if index % 2 == 0 else 14,
            5 if index % 2 == 0 else 3,
            4,
        )
        for index in range(20)
    ]
    sessions, reflections = _rows(specs)
    service, _ = _service(Repository(sessions=sessions, reflections=reflections))
    patterns = asyncio.run(service.get_patterns(user_id="owner"))
    assert patterns.status == "stable"
    now = datetime(2026, 7, 30, 10, 5, tzinfo=UTC)
    patterns = patterns.model_copy(update={"generated_at": now})
    assert [candidate.kind for candidate in evaluate(now=now, patterns=patterns)] == [
        "pattern"
    ]
    assert (
        evaluate(
            now=now,
            patterns=patterns,
            last_pattern_reserved_at=now - timedelta(days=29),
        )
        == []
    )
    assert (
        evaluate(now=now, patterns=patterns.model_copy(update={"status": "emerging"}))
        == []
    )
