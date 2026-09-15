"""Additive daily observations. Existing Personal Patterns remain untouched."""

from collections import defaultdict
from datetime import date, datetime
from typing import Any

from app.contracts.daily_capture_v4 import validate_daily_capture_branch
from app.contracts.skillset_capture import valid_skillset_signals


def skillset_observations(
    *,
    daily_rows,
    sessions,
    reflections,
    session_rows,
    generated_at: datetime,
    first_date: date,
    last_date: date,
):
    points: dict[date, dict[str, float]] = defaultdict(dict)
    for row in daily_rows:
        try:
            day = date.fromisoformat(row["entry_date"])
            updated = datetime.fromisoformat(row["updated_at"].replace("Z", "+00:00"))
        except (KeyError, TypeError, ValueError, AttributeError):
            continue
        if (
            updated.tzinfo is None
            or updated > generated_at
            or not first_date <= day <= last_date
        ):
            continue
        metadata = row.get("metadata")
        if not isinstance(metadata, dict) or metadata.get("capture_version") not in {
            "daily-capture-v4",
            "daily-capture-v5",
        }:
            continue
        captures = metadata.get("captures")
        if not isinstance(captures, dict):
            continue
        for kind in ("evening", "morning"):
            raw = captures.get(kind)
            if not isinstance(raw, dict):
                continue
            version = raw.get("branch_version")
            if version != metadata["capture_version"] and not (
                version == "daily-capture-v4"
                and raw.get("compatibility") is True
                and metadata["capture_version"] == "daily-capture-v5"
            ):
                continue
            branch = {
                key: value
                for key, value in raw.items()
                if key not in {"compatibility", "skillset"}
            }
            if validate_daily_capture_branch(branch, row_date=day, branch=kind):
                continue
            try:
                captured = datetime.fromisoformat(
                    raw["captured_at"].replace("Z", "+00:00")
                )
            except (KeyError, TypeError, ValueError, AttributeError):
                continue
            if captured.tzinfo is None or captured > generated_at:
                continue
            mapping = (
                {
                    "mood": "mood_score",
                    "stress_intensity": "stress_level",
                    "energy": "energy_level",
                }
                if kind == "evening"
                else {
                    "sleep_hours": "sleep_hours",
                    "sleep_quality": "sleep_quality",
                    "current_energy": "energy_level",
                }
            )
            for source, target in mapping.items():
                points[day][target] = float(raw[source])
            extras = raw.get("skillset")
            if valid_skillset_signals(extras, morning=kind == "morning"):
                for source, target in (
                    ("sport", "sport_activity"),
                    ("social", "social_activity"),
                    ("motivation", "study_motivation"),
                ):
                    value = extras.get(source)
                    if value is not None:
                        points[day][target] = float(value)

    learning_ids = set()
    for row in session_rows:
        source = row.get("focus_session_schedule_sources")
        if isinstance(source, list):
            source = source[0] if len(source) == 1 else None
        if (
            isinstance(source, dict)
            and source.get("source_kind") == "deadline_plan_block"
        ):
            learning_ids.add(row.get("id"))
    ratings: dict[date, list[Any]] = defaultdict(list)
    for session in sessions:
        day = session.local_date
        if not first_date <= day <= last_date:
            continue
        values = points[day]
        values["focus_count"] = values.get("focus_count", 0) + 1
        values["focus_completed"] = values.get("focus_completed", 0) + (
            session.status == "completed"
        )
        if session.id in learning_ids:
            values["learning_count"] = values.get("learning_count", 0) + 1
            values["learning_completed"] = values.get("learning_completed", 0) + (
                session.status == "completed"
            )
        reflection = reflections.get(session.id)
        if reflection is not None:
            ratings[day].append(reflection)
    for day, values in ratings.items():
        points[day]["focus_quality"] = sum(v.focus_quality for v in values) / len(
            values
        )
        points[day]["useful_progress"] = sum(v.useful_progress for v in values) / len(
            values
        )
    return [
        {"local_date": day, "values": values}
        for day, values in sorted(points.items())
        if values
    ]
