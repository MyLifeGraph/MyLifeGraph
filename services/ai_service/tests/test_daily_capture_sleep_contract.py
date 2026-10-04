import ast
from datetime import date
from pathlib import Path

import pytest

from app.contracts.daily_capture_v4 import (
    parse_daily_capture_sleep_episode,
    parse_daily_capture_sleep_plan,
    validate_daily_capture_branch,
)


ROW_DATE = date(2026, 8, 4)
_OMIT = object()


@pytest.mark.parametrize("note", ["", "  ", "A calmer morning.", "x" * 500])
def test_optional_morning_note_accepts_clear_and_bounded_context(note):
    raw = _branch("morning", "daily-capture-v5", _OMIT)
    baseline = parse_daily_capture_sleep_episode(
        raw, row_date=ROW_DATE, container_version="daily-capture-v5",
    )
    raw["reflection_note"] = note
    assert validate_daily_capture_branch(raw, row_date=ROW_DATE, branch="morning") == ()
    assert parse_daily_capture_sleep_episode(
        raw, row_date=ROW_DATE, container_version="daily-capture-v5",
    ) == baseline


@pytest.mark.parametrize(
    "note",
    [None, 5, True, [], {}, "x" * 501, "x" * 500 + " ", " " + "x" * 500, " " * 501],
)
def test_optional_morning_note_rejects_invalid_values(note):
    raw = _branch("morning", "daily-capture-v5", _OMIT)
    raw["reflection_note"] = note
    assert "morning.invalid_reflection_note" in validate_daily_capture_branch(
        raw, row_date=ROW_DATE, branch="morning",
    )


def test_morning_note_does_not_extend_legacy_v4_write_shape():
    raw = _branch("morning", "daily-capture-v4", _OMIT)
    raw["reflection_note"] = "Only current V5 writers add this field."
    assert "morning.unexpected_fields" in validate_daily_capture_branch(
        raw, row_date=ROW_DATE, branch="morning",
    )


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


def test_every_precise_sleep_parser_caller_binds_the_container_version() -> None:
    repository_root = Path(__file__).resolve().parents[3]
    source_roots = (
        repository_root / "scripts",
        repository_root / "services" / "ai_service" / "app",
    )
    parser_names = {
        "parse_daily_capture_sleep_episode",
        "parse_daily_capture_sleep_plan",
    }
    missing_bindings: list[str] = []

    for source_root in source_roots:
        for path in source_root.rglob("*.py"):
            tree = ast.parse(path.read_text(encoding="utf-8"), filename=str(path))
            for node in ast.walk(tree):
                if not isinstance(node, ast.Call):
                    continue
                if (
                    not isinstance(node.func, ast.Name)
                    or node.func.id not in parser_names
                ):
                    continue
                if not any(
                    keyword.arg == "container_version" for keyword in node.keywords
                ):
                    relative_path = path.relative_to(repository_root)
                    missing_bindings.append(
                        f"{relative_path}:{node.lineno} {node.func.id}"
                    )

    assert missing_bindings == []
