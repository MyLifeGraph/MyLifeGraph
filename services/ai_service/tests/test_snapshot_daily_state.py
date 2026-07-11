import json
from copy import deepcopy
from datetime import date, datetime, timedelta, timezone

import pytest

from app.services.snapshot_daily_state import build_snapshot_daily_state


TARGET_DATE = date(2026, 7, 11)
EVENING_DATE = TARGET_DATE - timedelta(days=1)
STALE_EVENING_DATE = TARGET_DATE - timedelta(days=2)
GENERATED_AT = datetime(2026, 7, 11, 7, 30, tzinfo=timezone.utc)

STRESS_SOURCES = (
    "workload",
    "avoidable_pressure",
    "private_emotional",
    "physical_recovery",
    "external_environment",
)
STRESS_CONTROLLABILITY = (
    "hardly_controllable",
    "partly_controllable",
    "mostly_controllable",
)
FOCUS_BANDS = (
    "none",
    "under_30_minutes",
    "30_to_60_minutes",
    "1_to_2_hours",
    "over_2_hours",
)
MAIN_FRICTIONS = (
    "unclear_priorities",
    "too_much_to_do",
    "interruptions",
    "hard_to_start",
    "low_energy",
    "emotional_load",
    "physical_recovery",
    "external_constraints",
)
DAY_SHAPES = ("normal", "constrained", "flexible")

SENSITIVE_PRIORITY = "SENSITIVE_PRIORITY_7f31"
SENSITIVE_REFLECTION = "SENSITIVE_REFLECTION_9b20"
SENSITIVE_BLOCKER = "SENSITIVE_BLOCKER_1aa4"


def _stress_label(value: int) -> str:
    if value >= 8:
        return "high"
    if value >= 5:
        return "medium"
    return "low"


def evening_capture(
    *,
    entry_date: date = EVENING_DATE,
    **overrides,
) -> dict:
    capture = {
        "capture_kind": "evening",
        "entry_date": entry_date.isoformat(),
        "capture_id": f"evening-{entry_date.isoformat()}-fixture",
        "captured_at": f"{entry_date.isoformat()}T20:30:00+00:00",
        "mood": 7,
        "energy": 7,
        "stress_intensity": 3,
        "stress_intensity_label": "low",
        "stress_source": "external_environment",
        "stress_controllability": "mostly_controllable",
        "focus_band": "1_to_2_hours",
        "main_friction": "interruptions",
        "tomorrow_priority": SENSITIVE_PRIORITY,
        "reflection_note": SENSITIVE_REFLECTION,
        "specific_blocker": SENSITIVE_BLOCKER,
    }
    capture.update(overrides)
    if (
        "stress_intensity" in overrides
        and "stress_intensity_label" not in overrides
        and isinstance(overrides["stress_intensity"], int)
        and not isinstance(overrides["stress_intensity"], bool)
        and 1 <= overrides["stress_intensity"] <= 10
    ):
        capture["stress_intensity_label"] = _stress_label(
            overrides["stress_intensity"],
        )
    return capture


def morning_capture(
    *,
    entry_date: date = TARGET_DATE,
    **overrides,
) -> dict:
    capture = {
        "capture_kind": "morning",
        "entry_date": entry_date.isoformat(),
        "capture_id": f"morning-{entry_date.isoformat()}-fixture",
        "captured_at": f"{entry_date.isoformat()}T06:30:00+00:00",
        "sleep_hours": 8.0,
        "current_energy": 8,
        "day_shape": "normal",
    }
    capture.update(overrides)
    return capture


def capture_row(
    *,
    row_id: str,
    entry_date: date,
    evening: dict | None = None,
    morning: dict | None = None,
    metadata: object | None = None,
    **column_overrides,
) -> dict:
    if metadata is None:
        captures = {}
        if evening is not None:
            captures["evening"] = evening
        if morning is not None:
            captures["morning"] = morning
        metadata = {
            "capture_version": "daily-capture-v2",
            "captures": captures,
        }

    row = {
        "id": row_id,
        "entry_date": entry_date.isoformat(),
        "mood_score": evening.get("mood") if evening is not None else None,
        "stress_level": (
            evening.get("stress_intensity") if evening is not None else None
        ),
        "energy_level": (
            morning.get("current_energy")
            if morning is not None
            else evening.get("energy") if evening is not None else None
        ),
        "sleep_hours": (
            morning.get("sleep_hours") if morning is not None else None
        ),
        "focus_minutes": None,
        "metadata": metadata,
        "updated_at": f"{entry_date.isoformat()}T21:00:00+00:00",
    }
    row.update(column_overrides)
    return row


def legacy_row(
    *,
    row_id: str = "legacy-today",
    entry_date: date = TARGET_DATE,
    **overrides,
) -> dict:
    row = {
        "id": row_id,
        "entry_date": entry_date.isoformat(),
        "mood_score": 5,
        "energy_level": 5,
        "stress_level": 5,
        "sleep_hours": 7.0,
        "metadata": None,
        "updated_at": f"{entry_date.isoformat()}T08:00:00+00:00",
    }
    row.update(overrides)
    return row


def active_task(*, task_id: str = "task-active") -> dict:
    return {
        "id": task_id,
        "status": "todo",
        "deadline": (TARGET_DATE + timedelta(days=2)).isoformat(),
    }


def overdue_task(*, task_id: str = "task-overdue") -> dict:
    return {
        "id": task_id,
        "status": "todo",
        "deadline": (TARGET_DATE - timedelta(days=1)).isoformat(),
    }


def build_state(
    *,
    daily_logs: list[dict] | None = None,
    tasks: list[dict] | None = None,
    goals: list[dict] | None = None,
):
    return build_snapshot_daily_state(
        daily_logs=daily_logs or [],
        tasks=tasks or [],
        goals=goals or [],
        target_date=TARGET_DATE,
        generated_at=GENERATED_AT,
    )


def current_rows(
    *,
    evening_overrides: dict | None = None,
    morning_overrides: dict | None = None,
) -> list[dict]:
    evening = evening_capture(**(evening_overrides or {}))
    morning = morning_capture(**(morning_overrides or {}))
    return [
        capture_row(
            row_id="log-evening",
            entry_date=EVENING_DATE,
            evening=evening,
        ),
        capture_row(
            row_id="log-morning",
            entry_date=TARGET_DATE,
            morning=morning,
        ),
    ]


@pytest.mark.parametrize("code", STRESS_SOURCES)
def test_parser_accepts_every_stress_source(code: str) -> None:
    result = build_state(
        daily_logs=current_rows(evening_overrides={"stress_source": code}),
    )

    assert result.summary["context"]["stress"]["source"] == code
    assert not any(
        issue == "evening.invalid_stress_source"
        for issue in result.signals["quality_issues"]
    )


@pytest.mark.parametrize("code", STRESS_CONTROLLABILITY)
def test_parser_accepts_every_stress_controllability(code: str) -> None:
    result = build_state(
        daily_logs=current_rows(
            evening_overrides={"stress_controllability": code},
        ),
    )

    assert result.summary["context"]["stress"]["controllability"] == code
    assert "evening.invalid_stress_controllability" not in result.signals[
        "quality_issues"
    ]


@pytest.mark.parametrize("code", FOCUS_BANDS)
def test_parser_accepts_every_focus_band(code: str) -> None:
    result = build_state(
        daily_logs=current_rows(evening_overrides={"focus_band": code}),
    )

    assert result.summary["context"]["focus_band"] == code
    assert "evening.invalid_focus_band" not in result.signals["quality_issues"]


@pytest.mark.parametrize("code", MAIN_FRICTIONS)
def test_parser_accepts_every_main_friction(code: str) -> None:
    result = build_state(
        daily_logs=current_rows(evening_overrides={"main_friction": code}),
    )

    assert result.summary["context"]["main_friction"] == code
    assert "evening.invalid_main_friction" not in result.signals["quality_issues"]


@pytest.mark.parametrize("code", DAY_SHAPES)
def test_parser_accepts_every_day_shape(code: str) -> None:
    result = build_state(
        daily_logs=current_rows(morning_overrides={"day_shape": code}),
    )

    assert result.summary["context"]["day_shape"] == code
    assert "morning.invalid_day_shape" not in result.signals["quality_issues"]


@pytest.mark.parametrize(
    ("intensity", "label"),
    ((1, "low"), (4, "low"), (5, "medium"), (7, "medium"), (8, "high"), (10, "high")),
)
def test_parser_validates_stress_intensity_labels(
    intensity: int,
    label: str,
) -> None:
    result = build_state(
        daily_logs=current_rows(
            evening_overrides={"stress_intensity": intensity},
        ),
    )

    assert result.summary["context"]["stress"]["intensity"] == intensity
    assert result.summary["context"]["stress"]["intensity_label"] == label
    assert "evening.invalid_stress_intensity_label" not in result.signals[
        "quality_issues"
    ]


@pytest.mark.parametrize(
    ("field", "invalid_value", "issue", "context_key"),
    (
        (
            "stress_source",
            "future_source_SECRET",
            "evening.invalid_stress_source",
            ("stress", "source"),
        ),
        (
            "stress_controllability",
            "fully_controllable_SECRET",
            "evening.invalid_stress_controllability",
            ("stress", "controllability"),
        ),
        (
            "focus_band",
            "all_day_SECRET",
            "evening.invalid_focus_band",
            ("focus_band",),
        ),
        (
            "main_friction",
            "future_friction_SECRET",
            "evening.invalid_main_friction",
            ("main_friction",),
        ),
    ),
)
def test_unknown_evening_enum_is_untrusted_without_echoing_raw_value(
    field: str,
    invalid_value: str,
    issue: str,
    context_key: tuple[str, ...],
) -> None:
    result = build_state(
        daily_logs=current_rows(evening_overrides={field: invalid_value}),
    )
    context = result.summary["context"]
    value = context
    for key in context_key:
        value = value[key]

    assert value is None
    assert result.summary["data_quality"] == "partial"
    assert issue in result.signals["quality_issues"]
    assert invalid_value not in json.dumps(
        {"summary": result.summary, "signals": result.signals},
        sort_keys=True,
    )


def test_unknown_morning_enum_is_untrusted() -> None:
    result = build_state(
        daily_logs=current_rows(
            morning_overrides={"day_shape": "unbounded_SECRET"},
        ),
    )

    assert result.summary["context"]["day_shape"] is None
    assert result.summary["data_quality"] == "partial"
    assert "morning.invalid_day_shape" in result.signals["quality_issues"]


@pytest.mark.parametrize("invalid", (0, 11, True, "8", 8.5, float("inf")))
def test_invalid_evening_rating_is_partial_and_not_trusted(invalid) -> None:
    result = build_state(
        daily_logs=current_rows(
            evening_overrides={"stress_intensity": invalid},
        ),
    )

    assert result.summary["context"]["stress"]["intensity"] is None
    assert result.summary["context"]["stress"]["source"] is None
    assert result.summary["data_quality"] == "partial"
    assert "evening.invalid_stress_intensity" in result.signals["quality_issues"]
    assert not {
        "private_emotional_stress",
        "physical_recovery_stress",
        "high_stress",
    }.intersection(result.summary["risk_flags"])


@pytest.mark.parametrize(
    "invalid",
    (-0.5, 12.5, 5.25, True, "5.5", float("inf")),
)
def test_invalid_morning_sleep_is_partial_and_not_trusted(invalid) -> None:
    result = build_state(
        daily_logs=current_rows(morning_overrides={"sleep_hours": invalid}),
    )

    assert result.summary["context"]["sleep_hours"] is None
    assert result.summary["data_quality"] == "partial"
    assert "morning.invalid_sleep_hours" in result.signals["quality_issues"]
    assert "low_sleep" not in result.summary["risk_flags"]


@pytest.mark.parametrize(
    ("branch_update", "issue"),
    (
        ({"capture_kind": "morning"}, "evening.invalid_capture_kind"),
        ({"entry_date": TARGET_DATE.isoformat()}, "evening.invalid_entry_date"),
        ({"capture_id": ""}, "evening.invalid_capture_id"),
        ({"captured_at": "2026-07-10T20:30:00"}, "evening.invalid_captured_at"),
    ),
)
def test_invalid_evening_identity_drops_the_branch(
    branch_update: dict,
    issue: str,
) -> None:
    branch = evening_capture()
    branch.update(branch_update)
    result = build_state(
        daily_logs=[
            capture_row(
                row_id="bad-evening",
                entry_date=EVENING_DATE,
                evening=branch,
            ),
        ],
    )

    assert result.summary["freshness"]["evening"]["state"] == "missing"
    assert result.summary["data_quality"] == "missing"
    assert issue in result.signals["quality_issues"]


@pytest.mark.parametrize(
    ("metadata", "issue"),
    (
        ("not-an-object", "daily_log.invalid_metadata"),
        (
            {"capture_version": "daily-capture-v3", "captures": {}},
            "daily_log.unsupported_capture_version",
        ),
        (
            {"capture_version": "daily-capture-v2", "captures": []},
            "daily_log.invalid_captures",
        ),
        (
            {
                "capture_version": "daily-capture-v2",
                "captures": {"morning": "not-an-object"},
            },
            "morning.invalid_object",
        ),
    ),
)
def test_malformed_v2_metadata_does_not_fall_back_to_projected_numbers(
    metadata: object,
    issue: str,
) -> None:
    row = capture_row(
        row_id="malformed-v2",
        entry_date=TARGET_DATE,
        metadata=metadata,
        mood_score=1,
        energy_level=1,
        stress_level=10,
        sleep_hours=2.0,
    )
    result = build_state(daily_logs=[row])

    assert result.summary["data_quality"] == "missing"
    assert result.summary["context"] == {
        "mood": None,
        "current_energy": None,
        "sleep_hours": None,
        "stress": {
            "intensity": None,
            "intensity_label": None,
            "source": None,
            "controllability": None,
        },
        "focus_band": None,
        "main_friction": None,
        "day_shape": None,
    }
    assert issue in result.signals["quality_issues"]
    assert result.mode == "steady"


def test_unknown_future_metadata_is_ignored_without_changing_valid_state() -> None:
    evening = evening_capture(future_branch_field={"opaque": True})
    morning = morning_capture()
    row_evening = capture_row(
        row_id="log-evening",
        entry_date=EVENING_DATE,
        evening=evening,
    )
    row_evening["metadata"]["future_top_level"] = {"opaque": True}
    row_evening["metadata"]["captures"]["midday"] = {"future": True}

    result = build_state(
        daily_logs=[
            row_evening,
            capture_row(
                row_id="log-morning",
                entry_date=TARGET_DATE,
                morning=morning,
            ),
        ],
        tasks=[active_task()],
    )

    assert result.summary["data_quality"] == "current"
    assert result.mode == "push"
    assert result.signals["quality_issues"] == []


def test_mismatched_stress_label_is_not_trusted_and_downgrades_quality() -> None:
    result = build_state(
        daily_logs=current_rows(
            evening_overrides={
                "stress_intensity": 9,
                "stress_intensity_label": "low",
            },
        ),
    )

    assert result.summary["context"]["stress"]["intensity"] == 9
    assert result.summary["context"]["stress"]["intensity_label"] is None
    assert result.summary["data_quality"] == "partial"
    assert "evening.invalid_stress_intensity_label" in result.signals[
        "quality_issues"
    ]


def test_missing_state_is_explicit_and_conservative() -> None:
    result = build_state()

    assert result.summary["data_quality"] == "missing"
    assert result.summary["freshness"] == {
        "evening": {
            "state": "missing",
            "entry_date": None,
            "captured_at": None,
            "age_days": None,
        },
        "morning": {
            "state": "missing",
            "entry_date": None,
            "captured_at": None,
            "age_days": None,
        },
        "legacy": {
            "state": "missing",
            "entry_date": None,
            "captured_at": None,
            "age_days": None,
        },
    }
    assert result.mode == "steady"
    assert result.summary["reason_codes"] == ["steady_missing_state"]
    assert result.summary["risk_flags"] == ["missing_calibration"]
    assert result.summary["provenance"]["basis"] == "none"


def test_current_legacy_numeric_state_is_partial_without_invented_taxonomy() -> None:
    result = build_state(daily_logs=[legacy_row()])

    assert result.summary["data_quality"] == "partial"
    assert result.summary["freshness"]["legacy"]["state"] == "current"
    assert result.summary["provenance"]["basis"] == "legacy_numeric"
    assert result.summary["context"]["stress"] == {
        "intensity": 5,
        "intensity_label": None,
        "source": None,
        "controllability": None,
    }
    assert result.summary["context"]["focus_band"] is None
    assert result.summary["context"]["main_friction"] is None
    assert result.summary["context"]["day_shape"] is None


def test_current_morning_only_is_partial() -> None:
    result = build_state(
        daily_logs=[
            capture_row(
                row_id="morning-only",
                entry_date=TARGET_DATE,
                morning=morning_capture(),
            ),
        ],
    )

    assert result.summary["data_quality"] == "partial"
    assert result.summary["freshness"]["morning"]["state"] == "current"
    assert result.summary["freshness"]["evening"]["state"] == "missing"


def test_previous_evening_and_target_morning_are_both_current() -> None:
    result = build_state(daily_logs=current_rows(), tasks=[active_task()])

    assert result.summary["data_quality"] == "current"
    assert result.summary["freshness"]["evening"] == {
        "state": "current",
        "entry_date": EVENING_DATE.isoformat(),
        "captured_at": f"{EVENING_DATE.isoformat()}T20:30:00+00:00",
        "age_days": 1,
    }
    assert result.summary["freshness"]["morning"] == {
        "state": "current",
        "entry_date": TARGET_DATE.isoformat(),
        "captured_at": f"{TARGET_DATE.isoformat()}T06:30:00+00:00",
        "age_days": 0,
    }
    assert result.mode == "push"


def test_evening_two_days_old_is_stale_while_target_morning_is_current() -> None:
    stale_evening = evening_capture(entry_date=STALE_EVENING_DATE)
    result = build_state(
        daily_logs=[
            capture_row(
                row_id="stale-evening",
                entry_date=STALE_EVENING_DATE,
                evening=stale_evening,
            ),
            capture_row(
                row_id="current-morning",
                entry_date=TARGET_DATE,
                morning=morning_capture(),
            ),
        ],
    )

    assert result.summary["data_quality"] == "partial"
    assert result.summary["freshness"]["evening"]["state"] == "stale"
    assert result.summary["freshness"]["evening"]["age_days"] == 2
    assert result.summary["freshness"]["morning"]["state"] == "current"
    assert result.mode == "steady"


@pytest.mark.parametrize("kind", ("evening", "morning"))
def test_capture_without_any_current_counterpart_is_stale(kind: str) -> None:
    if kind == "evening":
        entry_date = STALE_EVENING_DATE
        branch = evening_capture(entry_date=entry_date)
        row = capture_row(
            row_id="stale-evening",
            entry_date=entry_date,
            evening=branch,
        )
    else:
        entry_date = EVENING_DATE
        branch = morning_capture(entry_date=entry_date)
        row = capture_row(
            row_id="stale-morning",
            entry_date=entry_date,
            morning=branch,
        )

    result = build_state(daily_logs=[row])

    assert result.summary["data_quality"] == "stale"
    assert result.summary["freshness"][kind]["state"] == "stale"
    assert result.mode == "steady"
    assert result.summary["reason_codes"] == ["steady_stale_state"]
    assert result.summary["risk_flags"] == ["stale_calibration"]


def test_local_entry_date_not_utc_calendar_date_controls_freshness() -> None:
    morning = morning_capture(captured_at="2026-07-10T22:30:00+00:00")
    result = build_state(
        daily_logs=[
            capture_row(
                row_id="local-morning",
                entry_date=TARGET_DATE,
                morning=morning,
            ),
        ],
    )

    assert result.summary["freshness"]["morning"]["state"] == "current"
    assert result.summary["freshness"]["morning"]["age_days"] == 0


@pytest.mark.parametrize(
    (
        "evening_overrides",
        "morning_overrides",
        "tasks",
        "expected_mode",
        "expected_reason",
        "load_guidance",
    ),
    (
        (
            {},
            {},
            [active_task()],
            "push",
            "push_good_current_capacity",
            "protect_focus",
        ),
        (
            {},
            {"current_energy": 5, "sleep_hours": 7.0},
            [],
            "steady",
            "steady_balanced_state",
            "maintain",
        ),
        (
            {
                "stress_intensity": 9,
                "stress_source": "private_emotional",
                "stress_controllability": "hardly_controllable",
            },
            {"current_energy": 3, "sleep_hours": 5.5, "day_shape": "constrained"},
            [overdue_task()],
            "recover",
            "recover_private_emotional_stress",
            "reduce",
        ),
        (
            {
                "stress_intensity": 7,
                "stress_source": "avoidable_pressure",
                "stress_controllability": "mostly_controllable",
                "main_friction": "unclear_priorities",
            },
            {},
            [],
            "plan",
            "plan_avoidable_pressure",
            "simplify",
        ),
    ),
    ids=("push", "steady", "recover", "plan"),
)
def test_classifies_all_four_modes(
    evening_overrides: dict,
    morning_overrides: dict,
    tasks: list[dict],
    expected_mode: str,
    expected_reason: str,
    load_guidance: str,
) -> None:
    result = build_state(
        daily_logs=current_rows(
            evening_overrides=evening_overrides,
            morning_overrides=morning_overrides,
        ),
        tasks=tasks,
    )

    assert result.mode == expected_mode
    assert result.summary["mode"] == expected_mode
    assert result.summary["reason_codes"][0] == expected_reason
    assert result.summary["load_guidance"] == load_guidance


@pytest.mark.parametrize(
    ("evening_overrides", "morning_overrides", "expected_reason"),
    (
        (
            {
                "stress_intensity": 9,
                "stress_source": "private_emotional",
                "stress_controllability": "hardly_controllable",
                "main_friction": "unclear_priorities",
            },
            {"sleep_hours": 8.0, "current_energy": 9, "day_shape": "flexible"},
            "recover_private_emotional_stress",
        ),
        (
            {
                "stress_intensity": 6,
                "stress_source": "physical_recovery",
                "stress_controllability": "mostly_controllable",
                "main_friction": "unclear_priorities",
            },
            {"sleep_hours": 8.0, "current_energy": 9, "day_shape": "flexible"},
            "recover_physical_recovery_stress",
        ),
        (
            {
                "stress_intensity": 6,
                "stress_source": "workload",
                "stress_controllability": "hardly_controllable",
            },
            {"sleep_hours": 8.0, "current_energy": 9, "day_shape": "flexible"},
            "recover_low_control_stress",
        ),
        (
            {
                "stress_intensity": 7,
                "stress_source": "avoidable_pressure",
                "stress_controllability": "mostly_controllable",
                "main_friction": "unclear_priorities",
            },
            {"sleep_hours": 5.5, "current_energy": 9, "day_shape": "flexible"},
            "recover_short_sleep",
        ),
        (
            {
                "stress_intensity": 7,
                "stress_source": "avoidable_pressure",
                "stress_controllability": "mostly_controllable",
                "main_friction": "unclear_priorities",
            },
            {"sleep_hours": 8.0, "current_energy": 3, "day_shape": "flexible"},
            "recover_low_energy",
        ),
    ),
    ids=(
        "private-over-plan-and-push",
        "physical-over-plan-and-push",
        "low-control-over-overdue-and-push",
        "short-sleep-over-plan",
        "low-energy-over-plan",
    ),
)
def test_recovery_safeguards_override_planning_and_push(
    evening_overrides: dict,
    morning_overrides: dict,
    expected_reason: str,
) -> None:
    result = build_state(
        daily_logs=current_rows(
            evening_overrides=evening_overrides,
            morning_overrides=morning_overrides,
        ),
        tasks=[overdue_task()],
    )

    assert result.mode == "recover"
    assert result.summary["reason_codes"][0] == expected_reason
    assert result.summary["load_guidance"] == "reduce"


def test_low_intensity_private_context_prevents_push_without_forcing_recover() -> None:
    result = build_state(
        daily_logs=current_rows(
            evening_overrides={
                "stress_intensity": 3,
                "stress_source": "private_emotional",
                "stress_controllability": "mostly_controllable",
            },
        ),
        tasks=[active_task()],
    )

    assert result.mode == "steady"
    assert result.summary["reason_codes"] == ["steady_supportive_guard"]
    assert "private_emotional_stress" in result.summary["risk_flags"]


def test_stale_recovery_context_does_not_drive_current_mode_or_risks() -> None:
    stale_evening = evening_capture(
        entry_date=STALE_EVENING_DATE,
        stress_intensity=10,
        stress_source="private_emotional",
        stress_controllability="hardly_controllable",
        main_friction="emotional_load",
    )
    result = build_state(
        daily_logs=[
            capture_row(
                row_id="stale-private-evening",
                entry_date=STALE_EVENING_DATE,
                evening=stale_evening,
            ),
            capture_row(
                row_id="current-morning",
                entry_date=TARGET_DATE,
                morning=morning_capture(),
            ),
        ],
        tasks=[active_task()],
    )

    assert result.summary["data_quality"] == "partial"
    assert result.mode == "steady"
    assert result.summary["reason_codes"] == ["steady_partial_state"]
    assert not {
        "private_emotional_stress",
        "low_controllability",
        "high_stress",
    }.intersection(result.summary["risk_flags"])


def test_latest_current_evening_wins_over_older_recovery_capture() -> None:
    old_evening = evening_capture(
        entry_date=STALE_EVENING_DATE,
        stress_intensity=10,
        stress_source="private_emotional",
        stress_controllability="hardly_controllable",
    )
    result = build_state(
        daily_logs=[
            capture_row(
                row_id="old-evening",
                entry_date=STALE_EVENING_DATE,
                evening=old_evening,
            ),
            *current_rows(),
        ],
        tasks=[active_task()],
    )

    assert result.summary["data_quality"] == "current"
    assert result.summary["context"]["stress"]["intensity"] == 3
    assert result.mode == "push"
    assert "private_emotional_stress" not in result.summary["risk_flags"]


def test_sensitive_capture_text_is_excluded_from_summary_and_signals() -> None:
    result = build_state(daily_logs=current_rows(), tasks=[active_task()])
    serialized = json.dumps(
        {"summary": result.summary, "signals": result.signals},
        sort_keys=True,
    )

    assert SENSITIVE_PRIORITY not in serialized
    assert SENSITIVE_REFLECTION not in serialized
    assert SENSITIVE_BLOCKER not in serialized
    assert "tomorrow_priority" not in serialized
    assert "reflection_note" not in serialized
    assert "specific_blocker" not in serialized


def test_recovery_risks_and_reason_link_to_exact_capture_fields() -> None:
    result = build_state(
        daily_logs=current_rows(
            evening_overrides={
                "stress_intensity": 9,
                "stress_source": "private_emotional",
                "stress_controllability": "hardly_controllable",
            },
            morning_overrides={"sleep_hours": 5.5, "current_energy": 3},
        ),
    )

    assert result.signals["risk_evidence"]["private_emotional_stress"] == [
        {
            "table": "daily_logs",
            "id": "log-evening",
            "field": "metadata.captures.evening.stress_source",
        },
    ]
    assert result.signals["risk_evidence"]["low_sleep"] == [
        {
            "table": "daily_logs",
            "id": "log-morning",
            "field": "metadata.captures.morning.sleep_hours",
        },
    ]
    expected_reason_refs = [
        {
            "table": "daily_logs",
            "id": "log-evening",
            "field": "metadata.captures.evening.stress_source",
        },
        {
            "table": "daily_logs",
            "id": "log-evening",
            "field": "metadata.captures.evening.stress_intensity",
        },
    ]
    assert result.signals["reason_evidence"][
        "recover_private_emotional_stress"
    ] == expected_reason_refs
    assert result.summary["reasons"][0]["evidence_refs"] == expected_reason_refs


def test_overdue_planning_reason_links_to_the_exact_task() -> None:
    task = overdue_task(task_id="overdue-evidence")
    result = build_state(
        daily_logs=current_rows(
            evening_overrides={
                "stress_intensity": 4,
                "stress_source": "external_environment",
                "main_friction": "interruptions",
            },
        ),
        tasks=[task],
    )

    assert result.mode == "plan"
    expected = [
        {
            "table": "tasks",
            "id": "overdue-evidence",
            "field": "deadline",
        },
    ]
    assert result.signals["reason_evidence"]["plan_overdue_work"] == expected
    reason = next(
        item
        for item in result.summary["reasons"]
        if item["code"] == "plan_overdue_work"
    )
    assert reason["evidence_refs"] == expected


@pytest.mark.parametrize(
    ("evening_overrides", "morning_overrides", "tasks", "reason_code"),
    (
        ({}, {}, [active_task()], "push_good_current_capacity"),
        (
            {"main_friction": "unclear_priorities"},
            {},
            [],
            "plan_unclear_priorities",
        ),
        (
            {},
            {"current_energy": 5},
            [],
            "steady_balanced_state",
        ),
    ),
    ids=("push", "plan-friction", "steady"),
)
def test_substantive_mode_reason_has_specific_input_evidence(
    evening_overrides: dict,
    morning_overrides: dict,
    tasks: list[dict],
    reason_code: str,
) -> None:
    result = build_state(
        daily_logs=current_rows(
            evening_overrides=evening_overrides,
            morning_overrides=morning_overrides,
        ),
        tasks=tasks,
    )
    evidence = result.signals["reason_evidence"][reason_code]

    assert evidence
    assert all(ref["table"] in {"daily_logs", "tasks", "goals"} for ref in evidence)
    assert all(ref["id"] for ref in evidence)
    assert all(ref["field"] for ref in evidence)
    summary_reason = next(
        item for item in result.summary["reasons"] if item["code"] == reason_code
    )
    assert summary_reason["evidence_refs"] == evidence


def test_evidence_is_deduplicated_and_only_links_to_known_input_rows() -> None:
    rows = current_rows(
        evening_overrides={
            "stress_intensity": 9,
            "stress_source": "private_emotional",
            "stress_controllability": "hardly_controllable",
        },
        morning_overrides={"sleep_hours": 5.5, "current_energy": 3},
    )
    task = overdue_task()
    result = build_state(daily_logs=rows, tasks=[task])
    known_ids = {row["id"] for row in rows} | {task["id"]}

    for evidence_map in (
        result.signals["risk_evidence"],
        result.signals["reason_evidence"],
    ):
        for refs in evidence_map.values():
            keys = [(ref["table"], ref["id"], ref["field"]) for ref in refs]
            assert len(keys) == len(set(keys))
            assert all(ref["id"] in known_ids for ref in refs)


def test_inputs_are_not_mutated_during_parsing_and_classification() -> None:
    logs = current_rows()
    tasks = [active_task()]
    goals = [{"id": "goal-1", "status": "active"}]
    original = deepcopy((logs, tasks, goals))

    build_state(daily_logs=logs, tasks=tasks, goals=goals)

    assert (logs, tasks, goals) == original


def test_same_inputs_recompute_to_identical_daily_state() -> None:
    daily_logs = current_rows()
    tasks = [active_task()]

    first = build_state(daily_logs=daily_logs, tasks=tasks)
    second = build_state(daily_logs=daily_logs, tasks=tasks)

    assert second == first


def test_same_day_edit_removes_obsolete_risks_reasons_and_evidence() -> None:
    private_rows = current_rows(
        evening_overrides={
            "stress_intensity": 9,
            "stress_source": "private_emotional",
            "stress_controllability": "hardly_controllable",
        },
    )
    workload_rows = current_rows(
        evening_overrides={
            "stress_intensity": 3,
            "stress_source": "workload",
            "stress_controllability": "mostly_controllable",
        },
    )

    before = build_state(daily_logs=private_rows, tasks=[active_task()])
    after = build_state(daily_logs=workload_rows, tasks=[active_task()])

    assert before.mode == "recover"
    assert "private_emotional_stress" in before.risk_codes
    assert after.mode == "push"
    assert "private_emotional_stress" not in after.risk_codes
    assert "low_controllability" not in after.risk_codes
    serialized = json.dumps(
        {"summary": after.summary, "signals": after.signals},
        sort_keys=True,
    )
    assert "recover_private_emotional_stress" not in serialized
    assert "recover_low_control_stress" not in serialized


def test_projection_mismatch_downgrades_quality_without_overriding_metadata() -> None:
    rows = current_rows()
    morning_row = next(row for row in rows if row["id"] == "log-morning")
    morning_row["energy_level"] = 2

    result = build_state(daily_logs=rows, tasks=[active_task()])

    assert result.summary["context"]["current_energy"] == 8
    assert result.summary["data_quality"] == "partial"
    assert "projection.energy_mismatch" in result.signals["quality_issues"]
    assert result.mode == "steady"


def test_newer_malformed_evening_blocks_older_evening_from_current_state() -> None:
    older = evening_capture(
        stress_intensity=9,
        stress_source="private_emotional",
        stress_controllability="hardly_controllable",
    )
    malformed = evening_capture(
        entry_date=TARGET_DATE,
        capture_id="",
    )
    result = build_state(
        daily_logs=[
            capture_row(
                row_id="older-valid-evening",
                entry_date=EVENING_DATE,
                evening=older,
            ),
            capture_row(
                row_id="newer-malformed-evening",
                entry_date=TARGET_DATE,
                evening=malformed,
            ),
            capture_row(
                row_id="current-morning",
                entry_date=TARGET_DATE,
                morning=morning_capture(),
            ),
        ],
        tasks=[active_task()],
    )

    assert result.summary["freshness"]["evening"]["state"] == "stale"
    assert result.summary["data_quality"] == "partial"
    assert "evening.invalid_capture_id" in result.signals["quality_issues"]
    assert result.mode == "steady"
    assert "private_emotional_stress" not in result.risk_codes


def test_invalid_optional_gentle_flag_is_ignored_without_downgrading_core_state(
) -> None:
    result = build_state(
        daily_logs=current_rows(
            evening_overrides={"gentle_tomorrow": "yes"},
        ),
        tasks=[active_task()],
    )

    assert result.summary["data_quality"] == "current"
    assert result.mode == "push"
    assert "evening.invalid_gentle_tomorrow" in result.signals["quality_issues"]


def test_evening_only_marks_missing_morning_calibration() -> None:
    result = build_state(
        daily_logs=[
            capture_row(
                row_id="evening-only",
                entry_date=EVENING_DATE,
                evening=evening_capture(),
            ),
        ],
    )

    assert result.summary["data_quality"] == "partial"
    assert "missing_calibration" in result.risk_codes


def test_current_evening_with_stale_morning_marks_stale_calibration() -> None:
    stale_morning = morning_capture(entry_date=EVENING_DATE)
    result = build_state(
        daily_logs=[
            capture_row(
                row_id="previous-day-captures",
                entry_date=EVENING_DATE,
                evening=evening_capture(),
                morning=stale_morning,
            ),
        ],
    )

    assert result.summary["data_quality"] == "partial"
    assert result.summary["freshness"]["evening"]["state"] == "current"
    assert result.summary["freshness"]["morning"]["state"] == "stale"
    assert "stale_calibration" in result.risk_codes
    assert "missing_calibration" not in result.risk_codes
    assert result.signals["risk_evidence"]["stale_calibration"] == [
        {
            "table": "daily_logs",
            "id": "previous-day-captures",
            "field": "metadata.captures.morning.entry_date",
        },
    ]


def test_missing_numeric_projection_downgrades_current_v2_state() -> None:
    rows = current_rows()
    morning_row = next(row for row in rows if row["id"] == "log-morning")
    morning_row["energy_level"] = None

    result = build_state(daily_logs=rows, tasks=[active_task()])

    assert result.summary["context"]["current_energy"] == 8
    assert result.summary["data_quality"] == "partial"
    assert "projection.energy_mismatch" in result.signals["quality_issues"]
    assert result.mode == "steady"


def test_captures_without_version_are_malformed_not_legacy_fallback() -> None:
    result = build_state(
        daily_logs=[
            capture_row(
                row_id="missing-version",
                entry_date=TARGET_DATE,
                metadata={"captures": {"morning": morning_capture()}},
                energy_level=1,
                sleep_hours=2.0,
            ),
        ],
    )

    assert result.summary["data_quality"] == "missing"
    assert result.summary["provenance"]["basis"] == "none"
    assert "daily_log.missing_capture_version" in result.signals[
        "quality_issues"
    ]


@pytest.mark.parametrize(
    ("newer_metadata", "expected_quality"),
    (
        ("not-an-object", "stale"),
        (
            {
                "capture_version": "daily-capture-v3",
                "captures": {"evening": {}},
            },
            "stale",
        ),
        ({"captures": {"evening": {}}}, "partial"),
    ),
)
def test_newer_malformed_container_blocks_older_evening_from_current(
    newer_metadata: object,
    expected_quality: str,
) -> None:
    older = evening_capture(
        stress_intensity=9,
        stress_source="private_emotional",
        stress_controllability="hardly_controllable",
    )
    result = build_state(
        daily_logs=[
            capture_row(
                row_id="older-valid-evening",
                entry_date=EVENING_DATE,
                evening=older,
            ),
            capture_row(
                row_id="newer-malformed-container",
                entry_date=TARGET_DATE,
                metadata=newer_metadata,
                energy_level=9,
                stress_level=9,
            ),
            capture_row(
                row_id="current-morning",
                entry_date=TARGET_DATE,
                morning=morning_capture(),
            ),
        ],
        tasks=[active_task()],
    )

    assert result.summary["freshness"]["evening"]["state"] == "stale"
    assert result.summary["data_quality"] == expected_quality
    assert result.mode == "steady"
    assert "private_emotional_stress" not in result.risk_codes


def test_newer_valid_evening_supersedes_an_older_malformed_container() -> None:
    result = build_state(
        daily_logs=[
            capture_row(
                row_id="older-malformed-evening",
                entry_date=EVENING_DATE,
                metadata="not-an-object",
            ),
            capture_row(
                row_id="newer-valid-captures",
                entry_date=TARGET_DATE,
                evening=evening_capture(entry_date=TARGET_DATE),
                morning=morning_capture(),
            ),
        ],
        tasks=[active_task()],
    )

    assert result.summary["freshness"]["evening"]["state"] == "current"
    assert result.summary["freshness"]["morning"]["state"] == "current"
    assert result.summary["data_quality"] == "current"
    assert result.mode == "push"


def test_capture_entry_date_requires_strict_calendar_date() -> None:
    morning = morning_capture(entry_date=TARGET_DATE)
    morning["entry_date"] = f"{TARGET_DATE.isoformat()}T00:00:00+00:00"
    result = build_state(
        daily_logs=[
            capture_row(
                row_id="datetime-entry-date",
                entry_date=TARGET_DATE,
                morning=morning,
            ),
        ],
    )

    assert result.summary["data_quality"] == "missing"
    assert "morning.invalid_entry_date" in result.signals["quality_issues"]


@pytest.mark.parametrize(
    (
        "evening_overrides",
        "reason_code",
        "expected_fields",
    ),
    (
        (
            {
                "stress_intensity": 6,
                "stress_source": "physical_recovery",
            },
            "recover_physical_recovery_stress",
            {"stress_source", "stress_intensity"},
        ),
        (
            {
                "stress_intensity": 6,
                "stress_source": "workload",
                "stress_controllability": "hardly_controllable",
            },
            "recover_low_control_stress",
            {"stress_controllability", "stress_intensity"},
        ),
        (
            {
                "stress_intensity": 6,
                "stress_source": "avoidable_pressure",
            },
            "plan_avoidable_pressure",
            {"stress_source", "stress_intensity"},
        ),
        (
            {
                "stress_intensity": 7,
                "stress_source": "workload",
            },
            "plan_workload_pressure",
            {"stress_source", "stress_intensity"},
        ),
        (
            {
                "stress_intensity": 3,
                "main_friction": "too_much_to_do",
            },
            "plan_overload",
            {"main_friction"},
        ),
    ),
)
def test_threshold_reasons_reference_every_required_capture_field(
    evening_overrides: dict,
    reason_code: str,
    expected_fields: set[str],
) -> None:
    result = build_state(
        daily_logs=current_rows(evening_overrides=evening_overrides),
    )

    fields = {
        ref["field"].rsplit(".", 1)[-1]
        for ref in result.signals["reason_evidence"][reason_code]
    }
    assert expected_fields <= fields


def test_compound_recovery_reason_references_energy_and_sleep_thresholds() -> None:
    result = build_state(
        daily_logs=current_rows(
            morning_overrides={"current_energy": 4, "sleep_hours": 6.0},
        ),
    )

    assert result.summary["reason_codes"][0] == "recover_compound_risk"
    fields = {
        ref["field"].rsplit(".", 1)[-1]
        for ref in result.signals["reason_evidence"]["recover_compound_risk"]
    }
    assert fields == {"current_energy", "sleep_hours"}


def test_push_reason_references_the_required_active_action_context() -> None:
    task = active_task(task_id="push-task")
    result = build_state(daily_logs=current_rows(), tasks=[task])

    assert result.mode == "push"
    assert {
        "table": "tasks",
        "id": "push-task",
        "field": "status",
    } in result.signals["reason_evidence"]["push_good_current_capacity"]
