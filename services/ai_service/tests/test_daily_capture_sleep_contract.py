from datetime import date

import pytest

from app.contracts.daily_capture_v4 import (
    parse_daily_capture_sleep_episode,
    parse_daily_capture_sleep_plan,
)


ROW_DATE = date(2026, 8, 4)
_OMIT = object()


def _branch(kind: str, version: str, compatibility: object) -> dict[str, object]:
    common: dict[str, object] = {
        "branch_version": version,
        "capture_kind": kind,
        "entry_date": ROW_DATE.isoformat(),
        "capture_id": f"{kind}-capture",
        "captured_at": "2026-08-04T08:05:00Z",
    }
    if compatibility is not _OMIT:
        common["compatibility"] = compatibility
    if kind == "evening":
        return {
            **common,
            "mood": 7,
            "energy": 6,
            "stress_intensity": 3,
            "stress_intensity_label": "low",
            "planned_sleep_time": "23:00",
            "sleep_target_minutes": 480,
        }
    return {
        **common,
        "sleep_hours": 8.0,
        "sleep_quality": 7,
        "current_energy": 7,
        **({"day_shape": "normal"} if version == "daily-capture-v4" else {}),
        "estimated_sleep_started_at": "2026-08-03T23:00:00Z",
        "woke_at": "2026-08-04T07:00:00Z",
        "estimated_sleep_minutes": 480,
        "sleep_target_minutes": 480,
    }


@pytest.mark.parametrize("kind", ("evening", "morning"))
@pytest.mark.parametrize(
    ("container", "branch", "compatibility", "expected_issue"),
    (
        ("daily-capture-v4", "daily-capture-v4", _OMIT, None),
        ("daily-capture-v5", "daily-capture-v5", _OMIT, None),
        ("daily-capture-v5", "daily-capture-v4", True, None),
        (
            "daily-capture-v5",
            "daily-capture-v4",
            _OMIT,
            "missing_compatibility",
        ),
        (
            "daily-capture-v5",
            "daily-capture-v4",
            False,
            "missing_compatibility",
        ),
        (
            "daily-capture-v4",
            "daily-capture-v5",
            _OMIT,
            "invalid_branch_version",
        ),
        (
            "daily-capture-v4",
            "daily-capture-v5",
            True,
            "invalid_branch_version",
        ),
        (
            "daily-capture-v4",
            "daily-capture-v4",
            True,
            "invalid_compatibility",
        ),
        (
            "daily-capture-v5",
            "daily-capture-v5",
            True,
            "invalid_compatibility",
        ),
        (
            "daily-capture-v3",
            "daily-capture-v4",
            _OMIT,
            "invalid_container_version",
        ),
    ),
)
def test_precise_sleep_parser_enforces_container_branch_identity(
    kind: str,
    container: str,
    branch: str,
    compatibility: object,
    expected_issue: str | None,
) -> None:
    raw = _branch(kind, branch, compatibility)
    result = (
        parse_daily_capture_sleep_plan(
            raw,
            row_date=ROW_DATE,
            container_version=container,
        )
        if kind == "evening"
        else parse_daily_capture_sleep_episode(
            raw,
            row_date=ROW_DATE,
            container_version=container,
        )
    )

    if expected_issue is None:
        assert result.value is not None
        assert result.issues == ()
    else:
        assert result.value is None
        assert f"{kind}.{expected_issue}" in result.issues
