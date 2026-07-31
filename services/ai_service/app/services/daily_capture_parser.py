from __future__ import annotations

from dataclasses import dataclass
from datetime import UTC, date, datetime
from math import isfinite
from typing import Literal


@dataclass(frozen=True)
class DailyCaptureV4SleepPlan:
    capture_id: str
    entry_date: date
    captured_at: datetime
    planned_sleep_time: str
    sleep_target_minutes: int


@dataclass(frozen=True)
class DailyCaptureV4SleepEpisode:
    capture_id: str
    entry_date: date
    captured_at: datetime
    estimated_sleep_started_at: datetime
    woke_at: datetime
    estimated_sleep_minutes: int
    sleep_target_minutes: int
    sleep_quality: int
    current_energy: int
    day_shape: Literal["normal", "constrained", "flexible"]
    source_evening_capture_id: str | None

    @property
    def target_deviation_minutes(self) -> int:
        return self.estimated_sleep_minutes - self.sleep_target_minutes


@dataclass(frozen=True)
class DailyCaptureV4ParseResult:
    value: DailyCaptureV4SleepPlan | DailyCaptureV4SleepEpisode | None
    issues: tuple[str, ...]


def parse_daily_capture_v4_sleep_plan(
    raw: object,
    *,
    row_date: date,
) -> DailyCaptureV4ParseResult:
    kind = "evening"
    common, issues = _common_v4_branch(raw, kind=kind, row_date=row_date)
    if common is None:
        return DailyCaptureV4ParseResult(None, tuple(issues))
    assert isinstance(raw, dict)

    mood = _whole_number(raw.get("mood"), minimum=1, maximum=10)
    energy = _whole_number(raw.get("energy"), minimum=1, maximum=10)
    stress = _whole_number(
        raw.get("stress_intensity"),
        minimum=1,
        maximum=10,
    )
    if mood is None:
        issues.append("evening.invalid_mood")
    if energy is None:
        issues.append("evening.invalid_energy")
    if stress is None:
        issues.append("evening.invalid_stress_intensity")
    source = raw.get("stress_source")
    controllability = raw.get("stress_controllability")
    if stress is not None and stress >= 5 and (
        source not in _STRESS_SOURCES
        or controllability not in _STRESS_CONTROLLABILITY
    ):
        issues.append("evening.missing_stress_context")
    if (source is None) != (controllability is None):
        issues.append("evening.incomplete_stress_context")
    if source is not None and source not in _STRESS_SOURCES:
        issues.append("evening.invalid_stress_source")
    if (
        controllability is not None
        and controllability not in _STRESS_CONTROLLABILITY
    ):
        issues.append("evening.invalid_stress_controllability")

    planned_sleep_time = raw.get("planned_sleep_time")
    target = _sleep_target_minutes(raw.get("sleep_target_minutes"))
    if not _valid_clock(planned_sleep_time):
        issues.append("evening.invalid_planned_sleep_time")
    if target is None:
        issues.append("evening.invalid_sleep_target_minutes")
    if issues:
        return DailyCaptureV4ParseResult(None, tuple(_dedupe(issues)))
    assert isinstance(planned_sleep_time, str)
    assert target is not None
    return DailyCaptureV4ParseResult(
        DailyCaptureV4SleepPlan(
            capture_id=common.capture_id,
            entry_date=row_date,
            captured_at=common.captured_at,
            planned_sleep_time=planned_sleep_time,
            sleep_target_minutes=target,
        ),
        (),
    )


def parse_daily_capture_v4_sleep_episode(
    raw: object,
    *,
    row_date: date,
) -> DailyCaptureV4ParseResult:
    kind = "morning"
    common, issues = _common_v4_branch(raw, kind=kind, row_date=row_date)
    if common is None:
        return DailyCaptureV4ParseResult(None, tuple(issues))
    assert isinstance(raw, dict)

    started_at = _aware_datetime(raw.get("estimated_sleep_started_at"))
    woke_at = _aware_datetime(raw.get("woke_at"))
    estimated = _whole_number(
        raw.get("estimated_sleep_minutes"),
        minimum=1,
        maximum=16 * 60,
    )
    target = _sleep_target_minutes(raw.get("sleep_target_minutes"))
    sleep_hours = _finite_number(raw.get("sleep_hours"))
    sleep_quality = _whole_number(
        raw.get("sleep_quality"),
        minimum=1,
        maximum=10,
    )
    current_energy = _whole_number(
        raw.get("current_energy"),
        minimum=1,
        maximum=10,
    )
    day_shape = raw.get("day_shape")
    source_evening_capture_id = raw.get("source_evening_capture_id")

    if started_at is None:
        issues.append("morning.invalid_estimated_sleep_started_at")
    if woke_at is None:
        issues.append("morning.invalid_woke_at")
    interval_minutes: int | None = None
    if started_at is not None and woke_at is not None:
        seconds = (woke_at - started_at).total_seconds()
        if seconds <= 0 or seconds > 16 * 60 * 60 or seconds % 60 != 0:
            issues.append("morning.invalid_sleep_interval")
        else:
            interval_minutes = int(seconds // 60)
    if estimated is None or estimated != interval_minutes:
        issues.append("morning.invalid_estimated_sleep_minutes")
    if target is None:
        issues.append("morning.invalid_sleep_target_minutes")
    if (
        sleep_hours is None
        or estimated is None
        or abs(sleep_hours - estimated / 60) > 0.0001
    ):
        issues.append("morning.sleep_duration_mismatch")
    if sleep_quality is None:
        issues.append("morning.invalid_sleep_quality")
    if current_energy is None:
        issues.append("morning.invalid_current_energy")
    if day_shape not in _DAY_SHAPES:
        issues.append("morning.invalid_day_shape")
    if (
        source_evening_capture_id is not None
        and _bounded_string(source_evening_capture_id, maximum=160) is None
    ):
        issues.append("morning.invalid_source_evening_capture_id")

    if issues:
        return DailyCaptureV4ParseResult(None, tuple(_dedupe(issues)))
    assert started_at is not None
    assert woke_at is not None
    assert estimated is not None
    assert target is not None
    assert sleep_quality is not None
    assert current_energy is not None
    assert isinstance(day_shape, str)
    return DailyCaptureV4ParseResult(
        DailyCaptureV4SleepEpisode(
            capture_id=common.capture_id,
            entry_date=row_date,
            captured_at=common.captured_at,
            estimated_sleep_started_at=started_at,
            woke_at=woke_at,
            estimated_sleep_minutes=estimated,
            sleep_target_minutes=target,
            sleep_quality=sleep_quality,
            current_energy=current_energy,
            day_shape=day_shape,
            source_evening_capture_id=source_evening_capture_id,
        ),
        (),
    )


@dataclass(frozen=True)
class _CommonBranch:
    capture_id: str
    captured_at: datetime


def _common_v4_branch(
    raw: object,
    *,
    kind: str,
    row_date: date,
) -> tuple[_CommonBranch | None, list[str]]:
    if not isinstance(raw, dict):
        return None, [f"{kind}.invalid_object"]
    issues: list[str] = []
    if raw.get("branch_version") != "daily-capture-v4":
        issues.append(f"{kind}.invalid_branch_version")
    compatibility = raw.get("compatibility")
    if compatibility is not None and compatibility is not False:
        issues.append(f"{kind}.invalid_compatibility")
    if raw.get("capture_kind") != kind:
        issues.append(f"{kind}.invalid_capture_kind")
    if raw.get("entry_date") != row_date.isoformat():
        issues.append(f"{kind}.invalid_entry_date")
    capture_id = _bounded_string(raw.get("capture_id"), maximum=160)
    if capture_id is None:
        issues.append(f"{kind}.invalid_capture_id")
    captured_at = _aware_datetime(raw.get("captured_at"))
    if captured_at is None:
        issues.append(f"{kind}.invalid_captured_at")
    if issues:
        return None, issues
    assert capture_id is not None
    assert captured_at is not None
    return _CommonBranch(capture_id, captured_at), []


def _aware_datetime(value: object) -> datetime | None:
    if isinstance(value, datetime):
        parsed = value
    elif isinstance(value, str):
        try:
            parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
        except ValueError:
            return None
    else:
        return None
    if parsed.tzinfo is None or parsed.utcoffset() is None:
        return None
    return parsed.astimezone(UTC)


def _bounded_string(value: object, *, maximum: int) -> str | None:
    if not isinstance(value, str):
        return None
    clean = value.strip()
    return clean if clean and len(clean) <= maximum else None


def _whole_number(
    value: object,
    *,
    minimum: int,
    maximum: int,
) -> int | None:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        return None
    numeric = float(value)
    if not isfinite(numeric) or not numeric.is_integer():
        return None
    integer = int(numeric)
    return integer if minimum <= integer <= maximum else None


def _finite_number(value: object) -> float | None:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        return None
    numeric = float(value)
    return numeric if isfinite(numeric) and 0 <= numeric <= 16 else None


def _sleep_target_minutes(value: object) -> int | None:
    target = _whole_number(value, minimum=300, maximum=720)
    return target if target is not None and target % 15 == 0 else None


def _valid_clock(value: object) -> bool:
    if not isinstance(value, str) or len(value) != 5:
        return False
    try:
        return datetime.strptime(value, "%H:%M").strftime("%H:%M") == value
    except ValueError:
        return False


def _dedupe(values: list[str]) -> list[str]:
    return list(dict.fromkeys(values))


_STRESS_SOURCES = frozenset(
    {
        "workload",
        "avoidable_pressure",
        "private_emotional",
        "physical_recovery",
        "external_environment",
    },
)
_STRESS_CONTROLLABILITY = frozenset(
    {"hardly_controllable", "partly_controllable", "mostly_controllable"},
)
_DAY_SHAPES = frozenset({"normal", "constrained", "flexible"})
