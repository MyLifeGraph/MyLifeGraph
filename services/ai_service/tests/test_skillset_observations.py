import asyncio
from datetime import UTC, datetime

import pytest

from app.contracts.daily_capture_v4 import validate_daily_capture_branch
from app.contracts.skillset_capture import SKILLSET_CAPTURE_VERSION
from tests.test_daily_capture_sleep_contract import _branch, _OMIT, ROW_DATE
from tests.test_personal_patterns_service import Repository, _service, _focus

NOW = datetime(2026, 8, 4, 20, tzinfo=UTC)


@pytest.mark.parametrize(
    "kind,field",
    [("morning", "motivation"), ("evening", "sport"), ("evening", "social")],
)
@pytest.mark.parametrize("value", [None, 0, 1, 2])
def test_all_optional_choices_validate(kind, field, value):
    branch = _branch(kind, "daily-capture-v5", _OMIT)
    branch["skillset"] = {"version": SKILLSET_CAPTURE_VERSION, field: value}
    assert not validate_daily_capture_branch(branch, row_date=ROW_DATE, branch=kind)


@pytest.mark.parametrize("value", [True, -1, 3, 1.5, "1"])
def test_invalid_extra_never_reaches_storage(value):
    branch = _branch("evening", "daily-capture-v5", _OMIT)
    branch["skillset"] = {"version": SKILLSET_CAPTURE_VERSION, "sport": value}
    assert "evening.invalid_skillset" in validate_daily_capture_branch(
        branch, row_date=ROW_DATE, branch="evening"
    )


def test_inputs_flow_into_skillset_without_changing_existing_analysis():
    captures = {
        kind: _branch(kind, "daily-capture-v5", _OMIT)
        for kind in ("morning", "evening")
    }
    row = {
        "entry_date": ROW_DATE.isoformat(),
        "updated_at": NOW.isoformat(),
        "metadata": {"capture_version": "daily-capture-v5", "captures": captures},
    }
    session, reflection = _focus(index=1, local_day=ROW_DATE, hour=12)
    session["focus_session_schedule_sources"] = {"source_kind": "deadline_plan_block"}
    repository = Repository(
        sessions=[session], reflections=[reflection], daily_logs=[row]
    )
    service, _ = _service(repository, now=NOW)
    before = asyncio.run(service.get_patterns(user_id="owner"))
    captures["morning"]["skillset"] = {
        "version": SKILLSET_CAPTURE_VERSION,
        "motivation": 0,
    }
    captures["evening"]["skillset"] = {
        "version": SKILLSET_CAPTURE_VERSION,
        "sport": 2,
        "social": 1,
    }
    after = asyncio.run(service.get_patterns(user_id="owner"))
    assert before.model_dump(exclude={"skillset_points"}) == after.model_dump(
        exclude={"skillset_points"}
    )
    values = after.skillset_points[0].values
    assert values["sport_activity"] == 2
    assert values["social_activity"] == 1
    assert values["study_motivation"] == 0
    assert values["sleep_quality"] == 7
    assert values["energy_level"] == 7
    assert values["mood_score"] == 7
    assert values["stress_level"] == 3
    assert values["focus_quality"] == 4
    assert values["useful_progress"] == 4
    assert values["focus_count"] == values["focus_completed"] == 1
    assert values["learning_count"] == values["learning_completed"] == 1
    disabled, _ = _service(repository, enabled=False, now=NOW)
    assert not asyncio.run(disabled.get_patterns(user_id="owner")).skillset_points


def test_checkins_do_not_need_focus_and_missing_answers_stay_absent():
    captures = {
        kind: _branch(kind, "daily-capture-v5", _OMIT)
        for kind in ("morning", "evening")
    }
    captures["evening"]["skillset"] = {
        "version": SKILLSET_CAPTURE_VERSION,
        "sport": None,
    }
    row = {
        "entry_date": ROW_DATE.isoformat(),
        "updated_at": NOW.isoformat(),
        "metadata": {"capture_version": "daily-capture-v5", "captures": captures},
    }
    service, _ = _service(Repository(daily_logs=[row]), now=NOW)
    values = (
        asyncio.run(service.get_patterns(user_id="owner")).skillset_points[0].values
    )
    assert values["sleep_quality"] == values["mood_score"] == 7
    assert "sport_activity" not in values
    assert "study_motivation" not in values
    assert "learning_count" not in values
