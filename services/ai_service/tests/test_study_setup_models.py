from copy import deepcopy

import pytest
from pydantic import ValidationError

from app.models.intake import IntakeResponses


PREPARATION_KEY = "4abc0000-0000-4000-8000-000000000001"


def _responses() -> dict:
    return {
        "primary_focus_areas": ["focus"],
        "weekday_shape": "Classes in the morning.",
        "best_energy_window": "morning",
        "coaching_style": "direct",
        "reminder_preference": {"enabled": False},
    }


def _study_setup() -> dict:
    return {
        "focus_rhythm": {
            "focus_minutes": 45,
            "recovery_minutes": 10,
            "preparation_items": [
                {
                    "key": PREPARATION_KEY,
                    "label": "Water",
                    "active": True,
                },
            ],
        },
        "semester_planning": {
            "current_semester": {
                "name": "Summer 2026",
                "starts_on": "2026-04-01",
                "ends_on": "2026-09-30",
            },
            "next_semester": {
                "name": "Winter 2026/27",
                "starts_on": "2026-10-01",
                "ends_on": "2027-03-31",
                "course_selection_starts_on": "2026-08-15",
                "course_selection_ends_on": "2026-09-15",
                "course_names": ["Algorithms", "Linear algebra"],
                "course_selection_completed": False,
            },
        },
    }


def _parse(study_setup: object = ...) -> IntakeResponses:
    payload = _responses()
    if study_setup is not ...:
        payload["study_setup"] = study_setup
    return IntakeResponses.model_validate(payload)


def test_legacy_intake_without_study_setup_remains_readable() -> None:
    parsed = _parse()

    assert parsed.study_setup is None
    assert "study_setup" not in parsed.model_dump(mode="json", exclude_none=True)


def test_exact_study_setup_round_trips_without_invented_fields() -> None:
    study = _study_setup()

    parsed = _parse(study)

    assert parsed.model_dump(mode="json", exclude_none=True)["study_setup"] == study


@pytest.mark.parametrize(
    "mutate",
    [
        lambda value: value.update({"unexpected": True}),
        lambda value: value["focus_rhythm"].update({"focus_minutes": "45"}),
        lambda value: value["focus_rhythm"]["preparation_items"][0].update(
            {"active": 1},
        ),
        lambda value: value["focus_rhythm"]["preparation_items"][0].update(
            {"key": PREPARATION_KEY.upper()},
        ),
        lambda value: value["semester_planning"]["next_semester"].update(
            {"course_selection_completed": 0},
        ),
    ],
)
def test_study_setup_rejects_unknown_coerced_and_noncanonical_values(
    mutate,
) -> None:
    study = deepcopy(_study_setup())
    mutate(study)

    with pytest.raises(ValidationError):
        _parse(study)


@pytest.mark.parametrize(
    ("field", "value"),
    [
        ("focus_minutes", 20),
        ("focus_minutes", 181),
        ("focus_minutes", 46),
        ("recovery_minutes", 0),
        ("recovery_minutes", 61),
        ("recovery_minutes", 11),
    ],
)
def test_study_rhythm_enforces_bounds_and_five_minute_steps(
    field: str,
    value: int,
) -> None:
    study = deepcopy(_study_setup())
    study["focus_rhythm"][field] = value

    with pytest.raises(ValidationError):
        _parse(study)


@pytest.mark.parametrize(
    "study_setup",
    [
        None,
        {},
        {"focus_rhythm": None},
        {"semester_planning": None},
    ],
)
def test_optional_study_sections_must_be_omitted_instead_of_null(
    study_setup: object,
) -> None:
    with pytest.raises(ValidationError):
        _parse(study_setup)


def test_study_setup_rejects_duplicate_ritual_keys_and_labels() -> None:
    duplicate_key = deepcopy(_study_setup())
    duplicate_key["focus_rhythm"]["preparation_items"].append(
        {
            "key": PREPARATION_KEY,
            "label": "Snack",
            "active": True,
        },
    )
    duplicate_label = deepcopy(_study_setup())
    duplicate_label["focus_rhythm"]["preparation_items"].append(
        {
            "key": "50000000-0000-4000-8000-000000000001",
            "label": "water",
            "active": False,
        },
    )

    with pytest.raises(ValidationError):
        _parse(duplicate_key)
    with pytest.raises(ValidationError):
        _parse(duplicate_label)


def test_study_setup_rejects_duplicate_courses_and_invalid_date_order() -> None:
    duplicate_courses = deepcopy(_study_setup())
    duplicate_courses["semester_planning"]["next_semester"]["course_names"] = [
        "Algorithms",
        "algorithms",
    ]
    reversed_current = deepcopy(_study_setup())
    reversed_current["semester_planning"]["current_semester"].update(
        {
            "starts_on": "2026-10-01",
            "ends_on": "2026-09-30",
        },
    )
    reversed_selection_window = deepcopy(_study_setup())
    reversed_selection_window["semester_planning"]["next_semester"].update(
        {
            "course_selection_starts_on": "2026-09-15",
            "course_selection_ends_on": "2026-08-15",
        },
    )

    for study in (
        duplicate_courses,
        reversed_current,
        reversed_selection_window,
    ):
        with pytest.raises(ValidationError):
            _parse(study)
