from __future__ import annotations

from dataclasses import dataclass, replace
from datetime import UTC, date, datetime
from math import isfinite
from typing import Any, Literal


DAILY_STATE_CONTRACT_VERSION = "explainable-daily-state-v1"
DAILY_STATE_LOOKBACK_DAYS = 7

DataQuality = Literal["missing", "partial", "current", "stale"]
DailyMode = Literal["push", "steady", "recover", "plan"]
FreshnessState = Literal["missing", "current", "stale"]
CaptureKind = Literal["evening", "morning", "legacy"]


@dataclass(frozen=True)
class DailyStateResult:
    summary: dict[str, Any]
    signals: dict[str, Any]
    mode: DailyMode
    risk_codes: tuple[str, ...]


@dataclass(frozen=True)
class _EvidenceRef:
    table: str
    id: str
    field: str

    def as_json(self) -> dict[str, str]:
        return {"table": self.table, "id": self.id, "field": self.field}


@dataclass(frozen=True)
class _Capture:
    kind: CaptureKind
    row_id: str
    entry_date: date
    captured_at: datetime | None
    source_format: Literal["explicit_capture_v2", "legacy_daily_log"]
    values: dict[str, Any]
    complete: bool
    integrity_ok: bool = True

    def ref(self, field: str) -> _EvidenceRef:
        if self.kind == "legacy":
            path = field
        else:
            path = f"metadata.captures.{self.kind}.{field}"
        return _EvidenceRef(table="daily_logs", id=self.row_id, field=path)


@dataclass(frozen=True)
class _Selection:
    value: Any
    capture: _Capture
    field: str

    @property
    def evidence(self) -> _EvidenceRef:
        return self.capture.ref(self.field)


@dataclass(frozen=True)
class _Reason:
    code: str
    message: str
    evidence: tuple[_EvidenceRef, ...] = ()

    def as_json(self) -> dict[str, Any]:
        return {
            "code": self.code,
            "message": self.message,
            "evidence_refs": [ref.as_json() for ref in self.evidence],
        }


def valid_explicit_capture_kinds(row: dict[str, Any]) -> frozenset[str]:
    """Return only complete, projection-consistent Daily Capture V2 branches.

    Today streak/progress uses the same capture integrity boundary as Daily
    State while deliberately excluding legacy numeric rows. A malformed branch
    is missing evidence, never an inferred completed check-in.
    """

    row_id = _non_empty_string(row.get("id"), max_length=200)
    row_date = _safe_date(row.get("entry_date"))
    metadata = row.get("metadata")
    if (
        row_id is None
        or row_date is None
        or not isinstance(metadata, dict)
        or metadata.get("capture_version") != "daily-capture-v2"
        or not isinstance(metadata.get("captures"), dict)
    ):
        return frozenset()
    captures: dict[CaptureKind, _Capture] = {}
    raw_captures = metadata["captures"]
    for kind in ("evening", "morning"):
        raw = raw_captures.get(kind)
        if raw is None:
            continue
        capture, _ = _parse_v2_capture(
            kind=kind,
            raw=raw,
            row_id=row_id,
            row_date=row_date,
        )
        if capture is not None:
            captures[kind] = capture
    if _projection_issues(row, captures):
        return frozenset()
    return frozenset(
        kind
        for kind, capture in captures.items()
        if capture.complete and capture.integrity_ok
    )


@dataclass(frozen=True)
class _Risk:
    code: str
    evidence: tuple[_EvidenceRef, ...]


def build_snapshot_daily_state(
    *,
    daily_logs: list[dict[str, Any]],
    tasks: list[dict[str, Any]],
    goals: list[dict[str, Any]],
    target_date: date,
    generated_at: datetime,
) -> DailyStateResult:
    """Parse explicit capture state and classify one explainable target date."""

    captures: dict[CaptureKind, list[_Capture]] = {
        "evening": [],
        "morning": [],
        "legacy": [],
    }
    issues: list[str] = []
    blocked_current_dates: dict[CaptureKind, date] = {}

    ordered_logs = sorted(
        daily_logs,
        key=lambda row: (str(row.get("entry_date") or ""), str(row.get("id") or "")),
    )
    for row in ordered_logs:
        row_id = _non_empty_string(row.get("id"), max_length=200)
        row_date = _safe_date(row.get("entry_date"))
        if row_id is None:
            _append_issue(issues, "daily_log.invalid_id")
            continue
        if row_date is None or row_date > target_date:
            _append_issue(issues, "daily_log.invalid_entry_date")
            continue

        metadata = row.get("metadata")
        if metadata is None:
            legacy, legacy_issues = _parse_legacy_row(row, row_id, row_date)
            issues.extend(legacy_issues)
            if legacy is not None:
                captures["legacy"].append(legacy)
            continue
        if not isinstance(metadata, dict):
            _append_issue(issues, "daily_log.invalid_metadata")
            _block_current_kinds(
                blocked_current_dates,
                row_date=row_date,
                target_date=target_date,
                kinds=("evening", "morning"),
            )
            continue

        capture_version = metadata.get("capture_version")
        if capture_version is None:
            if "captures" in metadata:
                _append_issue(issues, "daily_log.missing_capture_version")
                raw_captures = metadata.get("captures")
                declared_kinds = (
                    tuple(
                        kind
                        for kind in ("evening", "morning")
                        if kind in raw_captures
                    )
                    if isinstance(raw_captures, dict)
                    else ("evening", "morning")
                )
                _block_current_kinds(
                    blocked_current_dates,
                    row_date=row_date,
                    target_date=target_date,
                    kinds=declared_kinds,
                )
                continue
            legacy, legacy_issues = _parse_legacy_row(row, row_id, row_date)
            issues.extend(legacy_issues)
            if legacy is not None:
                captures["legacy"].append(legacy)
            continue
        if capture_version != "daily-capture-v2":
            _append_issue(issues, "daily_log.unsupported_capture_version")
            _block_current_kinds(
                blocked_current_dates,
                row_date=row_date,
                target_date=target_date,
                kinds=("evening", "morning"),
            )
            continue

        raw_captures = metadata.get("captures")
        if not isinstance(raw_captures, dict):
            _append_issue(issues, "daily_log.invalid_captures")
            _block_current_kinds(
                blocked_current_dates,
                row_date=row_date,
                target_date=target_date,
                kinds=("evening", "morning"),
            )
            continue

        row_captures: dict[CaptureKind, _Capture] = {}
        for kind in ("evening", "morning"):
            raw = raw_captures.get(kind)
            if raw is None:
                continue
            capture, capture_issues = _parse_v2_capture(
                kind=kind,
                raw=raw,
                row_id=row_id,
                row_date=row_date,
            )
            issues.extend(capture_issues)
            if capture is None:
                _block_current_kinds(
                    blocked_current_dates,
                    row_date=row_date,
                    target_date=target_date,
                    kinds=(kind,),
                )
                continue
            row_captures[kind] = capture

        projection_issues = _projection_issues(row, row_captures)
        issues.extend(projection_issues)
        if projection_issues:
            row_captures = {
                kind: replace(capture, integrity_ok=False)
                for kind, capture in row_captures.items()
            }
        for kind, capture in row_captures.items():
            captures[kind].append(capture)

    latest = {
        kind: _latest_capture(values)
        for kind, values in captures.items()
    }
    freshness = {
        kind: _freshness(
            kind=kind,
            capture=capture,
            target_date=target_date,
            blocked_on_or_after=blocked_current_dates.get(kind),
        )
        for kind, capture in latest.items()
    }
    data_quality = _data_quality(
        latest=latest,
        freshness=freshness,
    )

    all_selected = [capture for capture in latest.values() if capture is not None]
    current_captures = [
        capture
        for kind, capture in latest.items()
        if capture is not None and freshness[kind]["state"] == "current"
    ]
    context = _build_context(all_selected)
    current_context = _build_context(current_captures)

    overdue_tasks = _overdue_tasks(tasks, target_date)
    active_tasks = [
        row
        for row in tasks
        if _task_is_active(row) and _non_empty_string(row.get("id"), max_length=200)
    ]
    active_goals = [
        row
        for row in goals
        if _goal_is_active(row) and _non_empty_string(row.get("id"), max_length=200)
    ]
    risks = _build_risks(
        data_quality=data_quality,
        current_context=current_context,
        latest=latest,
        freshness=freshness,
        overdue_tasks=overdue_tasks,
    )
    mode, reasons = _classify_mode(
        data_quality=data_quality,
        current_context=current_context,
        risks=risks,
        overdue_tasks=overdue_tasks,
        active_tasks=active_tasks,
        active_goals=active_goals,
        latest=latest,
        freshness=freshness,
    )

    risk_codes = tuple(risk.code for risk in risks)
    reason_codes = tuple(reason.code for reason in reasons)
    basis = _basis(all_selected)
    summary = {
        "contract_version": DAILY_STATE_CONTRACT_VERSION,
        "target_date": target_date.isoformat(),
        "mode": mode,
        "data_quality": data_quality,
        "freshness": freshness,
        "context": context,
        "risk_flags": list(risk_codes),
        "reason_codes": list(reason_codes),
        "reasons": [reason.as_json() for reason in reasons],
        "load_guidance": {
            "push": "protect_focus",
            "steady": "maintain",
            "recover": "reduce",
            "plan": "simplify",
        }[mode],
        "provenance": {
            "kind": "deterministic",
            "basis": basis,
            "baseline": "none",
            "history_claim": "current_state_only",
        },
    }

    risk_evidence = {
        risk.code: [ref.as_json() for ref in _dedupe_refs(risk.evidence)]
        for risk in risks
    }
    reason_evidence = {
        reason.code: [ref.as_json() for ref in _dedupe_refs(reason.evidence)]
        for reason in reasons
    }
    provenance = [
        {
            "kind": capture.source_format,
            "table": "daily_logs",
            "id": capture.row_id,
            "capture_kind": capture.kind,
            "entry_date": capture.entry_date.isoformat(),
            "captured_at": (
                capture.captured_at.isoformat()
                if capture.captured_at is not None
                else None
            ),
        }
        for capture in sorted(all_selected, key=_capture_sort_key)
    ]
    signals = {
        "engine": "deterministic",
        "contract_version": DAILY_STATE_CONTRACT_VERSION,
        "generated_at": generated_at.isoformat(),
        "provenance": provenance,
        "risk_evidence": risk_evidence,
        "reason_evidence": reason_evidence,
        "quality_issues": _dedupe_strings(issues)[:20],
    }
    return DailyStateResult(
        summary=summary,
        signals=signals,
        mode=mode,
        risk_codes=risk_codes,
    )


def _parse_v2_capture(
    *,
    kind: Literal["evening", "morning"],
    raw: Any,
    row_id: str,
    row_date: date,
) -> tuple[_Capture | None, list[str]]:
    issues: list[str] = []
    if not isinstance(raw, dict):
        return None, [f"{kind}.invalid_object"]
    if raw.get("capture_kind") != kind:
        return None, [f"{kind}.invalid_capture_kind"]
    branch_date = _strict_entry_date(raw.get("entry_date"))
    if branch_date is None or branch_date != row_date:
        return None, [f"{kind}.invalid_entry_date"]
    capture_id = _non_empty_string(raw.get("capture_id"), max_length=160)
    if capture_id is None:
        return None, [f"{kind}.invalid_capture_id"]
    captured_at = _safe_aware_datetime(raw.get("captured_at"))
    if captured_at is None:
        return None, [f"{kind}.invalid_captured_at"]

    values: dict[str, Any] = {}
    if kind == "evening":
        required = {
            "mood": _rating(raw.get("mood"), minimum=1),
            "energy": _rating(raw.get("energy"), minimum=1),
            "stress_intensity": _rating(raw.get("stress_intensity"), minimum=1),
            "main_friction": _enum_value(raw.get("main_friction"), _MAIN_FRICTIONS),
        }
        for field, value in required.items():
            if value is None:
                _append_issue(issues, f"evening.invalid_{field}")
            else:
                values[field] = value
        additional_frictions = _additional_friction_values(
            raw.get("additional_frictions"),
            main_friction=required["main_friction"],
        )
        if additional_frictions is None:
            _append_issue(issues, "evening.invalid_additional_frictions")
        else:
            values["additional_frictions"] = additional_frictions
        stress = values.get("stress_intensity")
        source = _enum_value(raw.get("stress_source"), _STRESS_SOURCES)
        controllability = _enum_value(
            raw.get("stress_controllability"),
            _STRESS_CONTROLLABILITY,
        )
        if "stress_source" in raw and source is None:
            _append_issue(issues, "evening.invalid_stress_source")
        if "stress_controllability" in raw and controllability is None:
            _append_issue(issues, "evening.invalid_stress_controllability")
        if (source is None) != (controllability is None):
            _append_issue(issues, "evening.incomplete_stress_context")
        if stress is not None and stress >= 5 and source is None:
            _append_issue(issues, "evening.missing_stress_context")
        if source is not None and controllability is not None:
            values["stress_source"] = source
            values["stress_controllability"] = controllability

        if "focus_band" in raw:
            focus_band = _enum_value(raw.get("focus_band"), _FOCUS_BANDS)
            if focus_band is None:
                _append_issue(issues, "evening.invalid_focus_band")
            else:
                values["focus_band"] = focus_band

        tomorrow_priority = raw.get("tomorrow_priority")
        if tomorrow_priority is None:
            values["has_tomorrow_priority"] = False
        elif _non_empty_string(tomorrow_priority, max_length=160) is not None:
            values["has_tomorrow_priority"] = True
        else:
            _append_issue(issues, "evening.invalid_tomorrow_priority")
        stored_label = _enum_value(
            raw.get("stress_intensity_label"),
            _STRESS_LABELS,
        )
        expected_label = _stress_label(stress) if stress is not None else None
        if stored_label != expected_label:
            _append_issue(issues, "evening.invalid_stress_intensity_label")
        elif expected_label is not None:
            values["stress_intensity_label"] = expected_label
        complete = all(value is not None for value in required.values()) and (
            stress is not None
            and (stress < 5 or (source is not None and controllability is not None))
        )
    else:
        required = {
            "sleep_hours": _sleep_hours(raw.get("sleep_hours"), half_hours=True),
            "current_energy": _rating(raw.get("current_energy"), minimum=1),
            "day_shape": _enum_value(raw.get("day_shape"), _DAY_SHAPES),
        }
        for field, value in required.items():
            if value is None:
                _append_issue(issues, f"morning.invalid_{field}")
            else:
                values[field] = value
        if "sleep_quality" in raw:
            sleep_quality = _rating(raw.get("sleep_quality"), minimum=1)
            if sleep_quality is None:
                _append_issue(issues, "morning.invalid_sleep_quality")
            else:
                values["sleep_quality"] = sleep_quality
        complete = all(value is not None for value in required.values())

    return (
        _Capture(
            kind=kind,
            row_id=row_id,
            entry_date=row_date,
            captured_at=captured_at,
            source_format="explicit_capture_v2",
            values=values,
            complete=complete,
            integrity_ok=not issues,
        ),
        issues,
    )


def _parse_legacy_row(
    row: dict[str, Any],
    row_id: str,
    row_date: date,
) -> tuple[_Capture | None, list[str]]:
    issues: list[str] = []
    values: dict[str, Any] = {}
    validators = {
        "mood_score": lambda value: _rating(value, minimum=0),
        "energy_level": lambda value: _rating(value, minimum=0),
        "stress_level": lambda value: _rating(value, minimum=0),
        "sleep_hours": lambda value: _sleep_hours(value, half_hours=False),
    }
    for field, validator in validators.items():
        raw = row.get(field)
        if raw is None:
            continue
        value = validator(raw)
        if value is None:
            _append_issue(issues, f"legacy.invalid_{field}")
        else:
            values[field] = value
    if not values:
        return None, issues
    return (
        _Capture(
            kind="legacy",
            row_id=row_id,
            entry_date=row_date,
            captured_at=_safe_aware_datetime(row.get("updated_at")),
            source_format="legacy_daily_log",
            values=values,
            complete=False,
        ),
        issues,
    )


def _projection_issues(
    row: dict[str, Any],
    captures: dict[CaptureKind, _Capture],
) -> list[str]:
    evening = captures.get("evening")
    morning = captures.get("morning")
    expectations: list[tuple[str, Any, str]] = []
    if evening is not None:
        expectations.extend(
            [
                ("mood_score", evening.values.get("mood"), "projection.mood_mismatch"),
                (
                    "stress_level",
                    evening.values.get("stress_intensity"),
                    "projection.stress_mismatch",
                ),
            ],
        )
    if morning is not None:
        expectations.extend(
            [
                (
                    "energy_level",
                    morning.values.get("current_energy"),
                    "projection.energy_mismatch",
                ),
                (
                    "sleep_hours",
                    morning.values.get("sleep_hours"),
                    "projection.sleep_mismatch",
                ),
            ],
        )
    elif evening is not None:
        expectations.append(
            (
                "energy_level",
                evening.values.get("energy"),
                "projection.energy_mismatch",
            ),
        )
    issues: list[str] = []
    for column, expected, issue in expectations:
        actual = row.get(column)
        if expected is None:
            continue
        if actual is None or not _numbers_equal(actual, expected):
            _append_issue(issues, issue)
    return issues


def _build_context(captures: list[_Capture]) -> dict[str, Any]:
    mood = _select(captures, "mood", "mood_score")
    energy = _select(captures, "current_energy", "energy", "energy_level")
    sleep = _select(captures, "sleep_hours")
    sleep_quality = _select(captures, "sleep_quality")
    stress = _select(captures, "stress_intensity", "stress_level")

    stress_source = None
    stress_controllability = None
    stress_label = None
    if stress is not None and stress.capture.kind == "evening":
        stress_source = stress.capture.values.get("stress_source")
        stress_controllability = stress.capture.values.get("stress_controllability")
        stress_label = stress.capture.values.get("stress_intensity_label")

    evening = _latest_capture(
        [capture for capture in captures if capture.kind == "evening"],
    )
    morning = _latest_capture(
        [capture for capture in captures if capture.kind == "morning"],
    )
    return {
        "mood": mood.value if mood is not None else None,
        "current_energy": energy.value if energy is not None else None,
        "sleep_hours": sleep.value if sleep is not None else None,
        "sleep_quality": (
            sleep_quality.value if sleep_quality is not None else None
        ),
        "stress": {
            "intensity": stress.value if stress is not None else None,
            "intensity_label": stress_label,
            "source": stress_source,
            "controllability": stress_controllability,
        },
        "focus_band": evening.values.get("focus_band") if evening is not None else None,
        "main_friction": (
            evening.values.get("main_friction") if evening is not None else None
        ),
        "additional_frictions": (
            evening.values.get("additional_frictions", [])
            if evening is not None
            else []
        ),
        "day_shape": morning.values.get("day_shape") if morning is not None else None,
    }


def _build_risks(
    *,
    data_quality: DataQuality,
    current_context: dict[str, Any],
    latest: dict[CaptureKind, _Capture | None],
    freshness: dict[CaptureKind, dict[str, Any]],
    overdue_tasks: list[dict[str, Any]],
) -> list[_Risk]:
    stress = current_context["stress"]
    intensity = _as_float(stress.get("intensity"))
    source = stress.get("source")
    controllability = stress.get("controllability")
    energy = _as_float(current_context.get("current_energy"))
    sleep = _as_float(current_context.get("sleep_hours"))
    sleep_quality = _as_float(current_context.get("sleep_quality"))
    day_shape = current_context.get("day_shape")
    friction = current_context.get("main_friction")

    current_evening = _current_capture(latest, freshness, "evening")
    current_morning = _current_capture(latest, freshness, "morning")
    current_values = [
        capture
        for capture in latest.values()
        if capture is not None and freshness[capture.kind]["state"] == "current"
    ]
    sleep_capture = _selection_capture(
        current_values,
        freshness,
        "sleep_hours",
    )
    sleep_quality_capture = _selection_capture(
        current_values,
        freshness,
        "sleep_quality",
    )
    stress_capture = _selection_capture(
        current_values,
        freshness,
        "stress_intensity",
        "stress_level",
    )
    risks: list[_Risk] = []

    def add(code: str, *refs: _EvidenceRef | None) -> None:
        risks.append(
            _Risk(
                code=code,
                evidence=tuple(ref for ref in refs if ref is not None),
            ),
        )

    if source == "private_emotional":
        add(
            "private_emotional_stress",
            current_evening.ref("stress_source") if current_evening else None,
        )
    if source == "physical_recovery":
        add(
            "physical_recovery_stress",
            current_evening.ref("stress_source") if current_evening else None,
        )
    if controllability == "hardly_controllable":
        add(
            "low_controllability",
            current_evening.ref("stress_controllability") if current_evening else None,
        )
    if sleep is not None and sleep < 6.5:
        add(
            "low_sleep",
            sleep_capture.ref("sleep_hours") if sleep_capture else None,
        )
    if sleep_quality is not None and sleep_quality <= 4:
        add(
            "low_sleep_quality",
            (
                sleep_quality_capture.ref("sleep_quality")
                if sleep_quality_capture
                else None
            ),
        )
    if energy is not None and energy <= 3:
        energy_capture = _selection_capture(
            [capture for capture in latest.values() if capture is not None],
            freshness,
            "current_energy",
            "energy",
            "energy_level",
        )
        add(
            "low_energy",
            (
                energy_capture.ref(_energy_field(energy_capture))
                if energy_capture
                else None
            ),
        )
    if intensity is not None and intensity >= 8:
        add(
            "high_stress",
            (
                stress_capture.ref(
                    "stress_intensity"
                    if stress_capture.kind == "evening"
                    else "stress_level",
                )
                if stress_capture
                else None
            ),
        )
    if day_shape == "constrained":
        add(
            "constrained_capacity",
            current_morning.ref("day_shape") if current_morning else None,
        )
    workload_overload = (
        intensity is not None and intensity >= 8 and source == "workload"
    )
    friction_overload = (
        intensity is not None
        and intensity >= 7
        and friction == "too_much_to_do"
    )
    if workload_overload or friction_overload:
        add(
            "overload",
            current_evening.ref("stress_intensity") if current_evening else None,
            (
                current_evening.ref("stress_source")
                if current_evening and workload_overload
                else None
            ),
            (
                current_evening.ref("main_friction")
                if current_evening and friction_overload
                else None
            ),
        )
    if source == "avoidable_pressure":
        add(
            "avoidable_pressure",
            current_evening.ref("stress_source") if current_evening else None,
        )
    if source == "workload":
        add(
            "workload_pressure",
            current_evening.ref("stress_source") if current_evening else None,
        )
    morning_state = freshness["morning"]["state"]
    legacy_state = freshness["legacy"]["state"]
    has_current_calibration = "current" in {morning_state, legacy_state}
    has_stale_calibration = "stale" in {morning_state, legacy_state}
    if not has_current_calibration and (
        has_stale_calibration or data_quality == "stale"
    ):
        stale_captures = [
            capture
            for kind in ("morning", "legacy")
            if (capture := latest[kind]) is not None
            and freshness[kind]["state"] == "stale"
        ]
        if not stale_captures and data_quality == "stale":
            stale_captures = [
                capture
                for kind, capture in latest.items()
                if capture is not None and freshness[kind]["state"] == "stale"
            ]
        stale_refs = tuple(capture.ref("entry_date") for capture in stale_captures)
        risks.append(_Risk(code="stale_calibration", evidence=stale_refs))
    elif not has_current_calibration:
        add("missing_calibration")
    if overdue_tasks:
        risks.append(
            _Risk(
                code="overdue_tasks",
                evidence=tuple(
                    _EvidenceRef("tasks", str(row["id"]), "deadline")
                    for row in overdue_tasks[:3]
                    if row.get("id") is not None
                ),
            ),
        )
    return _dedupe_risks(risks)


def _classify_mode(
    *,
    data_quality: DataQuality,
    current_context: dict[str, Any],
    risks: list[_Risk],
    overdue_tasks: list[dict[str, Any]],
    active_tasks: list[dict[str, Any]],
    active_goals: list[dict[str, Any]],
    latest: dict[CaptureKind, _Capture | None],
    freshness: dict[CaptureKind, dict[str, Any]],
) -> tuple[DailyMode, tuple[_Reason, ...]]:
    stress = current_context["stress"]
    intensity = _as_float(stress.get("intensity"))
    source = stress.get("source")
    controllability = stress.get("controllability")
    energy = _as_float(current_context.get("current_energy"))
    sleep = _as_float(current_context.get("sleep_hours"))
    sleep_quality = _as_float(current_context.get("sleep_quality"))
    day_shape = current_context.get("day_shape")
    friction = current_context.get("main_friction")
    risk_map = {risk.code: risk for risk in risks}
    current_evening = _current_capture(latest, freshness, "evening")
    current_morning = _current_capture(latest, freshness, "morning")
    current_values = [
        capture
        for capture in latest.values()
        if capture is not None and freshness[capture.kind]["state"] == "current"
    ]
    energy_selection = _select(
        current_values,
        "current_energy",
        "energy",
        "energy_level",
    )
    sleep_selection = _select(current_values, "sleep_hours")
    sleep_quality_selection = _select(current_values, "sleep_quality")
    stress_selection = _select(
        current_values,
        "stress_intensity",
        "stress_level",
    )
    intensity_ref = stress_selection.evidence if stress_selection is not None else None

    recover_reasons: list[_Reason] = []
    if source == "private_emotional" and intensity is not None and intensity >= 8:
        recover_reasons.append(
            _reason_from_risks(
                "recover_private_emotional_stress",
                "High private or emotional stress supports a lower-load day.",
                risk_map,
                "private_emotional_stress",
                "high_stress",
            ),
        )
    if source == "physical_recovery" and intensity is not None and intensity >= 5:
        recover_reasons.append(
            _with_reason_evidence(
                _reason_from_risks(
                    "recover_physical_recovery_stress",
                    "Current physical-recovery stress supports reducing load.",
                    risk_map,
                    "physical_recovery_stress",
                ),
                intensity_ref,
            ),
        )
    if (
        controllability == "hardly_controllable"
        and intensity is not None
        and intensity >= 5
    ):
        recover_reasons.append(
            _with_reason_evidence(
                _reason_from_risks(
                    "recover_low_control_stress",
                    "Current stress is hard to influence, so the state stays "
                    "conservative.",
                    risk_map,
                    "low_controllability",
                ),
                intensity_ref,
            ),
        )
    if energy is not None and energy <= 3:
        recover_reasons.append(
            _reason_from_risks(
                "recover_low_energy",
                "Current energy supports protecting essential capacity.",
                risk_map,
                "low_energy",
            ),
        )
    if sleep is not None and sleep < 6.0:
        recover_reasons.append(
            _reason_from_risks(
                "recover_short_sleep",
                "Short sleep supports a lower-load day.",
                risk_map,
                "low_sleep",
            ),
        )
    if sleep_quality is not None and sleep_quality <= 3:
        recover_reasons.append(
            _reason_from_risks(
                "recover_poor_sleep_quality",
                "Poor sleep quality independently supports a lower-load day.",
                risk_map,
                "low_sleep_quality",
            ),
        )
    compound_count = sum(
        (
            energy is not None and energy <= 4,
            sleep is not None and sleep < 6.5,
            sleep_quality is not None and sleep_quality <= 4,
            intensity is not None and intensity >= 8,
        ),
    )
    if compound_count >= 2:
        compound_refs: list[_EvidenceRef] = []
        if energy is not None and energy <= 4 and energy_selection is not None:
            compound_refs.append(energy_selection.evidence)
        if sleep is not None and sleep < 6.5 and sleep_selection is not None:
            compound_refs.append(sleep_selection.evidence)
        if (
            sleep_quality is not None
            and sleep_quality <= 4
            and sleep_quality_selection is not None
        ):
            compound_refs.append(sleep_quality_selection.evidence)
        if intensity is not None and intensity >= 8 and intensity_ref is not None:
            compound_refs.append(intensity_ref)
        recover_reasons.append(
            _Reason(
                code="recover_compound_risk",
                message="Multiple current recovery signals support reducing load.",
                evidence=tuple(_dedupe_refs(tuple(compound_refs))),
            ),
        )
    if recover_reasons:
        return "recover", tuple(_dedupe_reasons(recover_reasons)[:3])

    if data_quality == "missing":
        return (
            "steady",
            (
                _Reason(
                    "steady_missing_state",
                    "Current calibration is missing, so the state remains "
                    "conservative.",
                ),
            ),
        )
    if data_quality == "stale":
        return (
            "steady",
            (
                _reason_from_risks(
                    "steady_stale_state",
                    "Available calibration is stale, so it does not drive "
                    "today's load.",
                    risk_map,
                    "stale_calibration",
                ),
            ),
        )

    supportive_codes = [
        code
        for code in (
            "private_emotional_stress",
            "physical_recovery_stress",
            "low_controllability",
        )
        if code in risk_map
    ]
    if supportive_codes:
        refs = tuple(
            ref
            for code in supportive_codes
            for ref in risk_map[code].evidence
        )
        return (
            "steady",
            (
                _Reason(
                    "steady_supportive_guard",
                    "Current context supports a steady plan without added pressure.",
                    tuple(_dedupe_refs(refs)),
                ),
            ),
        )

    plan_reasons: list[_Reason] = []
    if source == "avoidable_pressure" and intensity is not None and intensity >= 5:
        plan_reasons.append(
            _with_reason_evidence(
                _reason_from_risks(
                    "plan_avoidable_pressure",
                    "Avoidable pressure supports simplifying the next decision.",
                    risk_map,
                    "avoidable_pressure",
                ),
                intensity_ref,
            ),
        )
    if friction == "unclear_priorities":
        plan_reasons.append(
            _Reason(
                "plan_unclear_priorities",
                "Priorities are unclear, so choosing before executing is more useful.",
                (
                    current_evening.ref("main_friction"),
                )
                if current_evening is not None
                else (),
            ),
        )
    if friction == "too_much_to_do" or "overload" in risk_map:
        overload_reason = _reason_from_risks(
            "plan_overload",
            "Current load supports reducing scope before execution.",
            risk_map,
            "overload",
        )
        plan_reasons.append(
            _with_reason_evidence(
                overload_reason,
                (
                    current_evening.ref("main_friction")
                    if current_evening is not None
                    and friction == "too_much_to_do"
                    else None
                ),
            ),
        )
    if source == "workload" and intensity is not None and intensity >= 7:
        plan_reasons.append(
            _with_reason_evidence(
                _reason_from_risks(
                    "plan_workload_pressure",
                    "Workload pressure supports a short prioritization pass.",
                    risk_map,
                    "workload_pressure",
                ),
                intensity_ref,
            ),
        )
    if friction == "hard_to_start":
        plan_reasons.append(
            _Reason(
                "plan_start_friction",
                "Start friction supports making the next step smaller and clearer.",
                (
                    current_evening.ref("main_friction"),
                )
                if current_evening is not None
                else (),
            ),
        )
    if overdue_tasks:
        plan_reasons.append(
            _reason_from_risks(
                "plan_overdue_work",
                "Open overdue work supports a bounded review of priorities.",
                risk_map,
                "overdue_tasks",
            ),
        )
    if plan_reasons:
        return "plan", tuple(_dedupe_reasons(plan_reasons)[:3])

    if "low_sleep_quality" in risk_map:
        return (
            "steady",
            (
                _reason_from_risks(
                    "steady_low_sleep_quality",
                    "Lower sleep quality supports a steady day without added "
                    "load.",
                    risk_map,
                    "low_sleep_quality",
                ),
            ),
        )

    if (
        data_quality == "current"
        and energy is not None
        and energy >= 7
        and sleep is not None
        and sleep >= 7
        and (sleep_quality is None or sleep_quality >= 7)
        and intensity is not None
        and intensity <= 4
        and day_shape in {"normal", "flexible"}
        and not overdue_tasks
        and (active_tasks or active_goals)
    ):
        action_ref = (
            _EvidenceRef("tasks", str(active_tasks[0]["id"]), "status")
            if active_tasks
            else _EvidenceRef("goals", str(active_goals[0]["id"]), "status")
        )
        return (
            "push",
            (
                _Reason(
                    "push_good_current_capacity",
                    "Current energy, sleep duration and quality, stress, and "
                    "day shape support protected focus.",
                    tuple(
                        ref
                        for ref in (
                            (
                                current_morning.ref("current_energy")
                                if current_morning is not None
                                else None
                            ),
                            (
                                current_morning.ref("sleep_hours")
                                if current_morning is not None
                                else None
                            ),
                            (
                                current_morning.ref("sleep_quality")
                                if current_morning is not None
                                and sleep_quality is not None
                                else None
                            ),
                            (
                                current_morning.ref("day_shape")
                                if current_morning is not None
                                else None
                            ),
                            (
                                current_evening.ref("stress_intensity")
                                if current_evening is not None
                                else None
                            ),
                            action_ref,
                        )
                        if ref is not None
                    ),
                ),
            ),
        )

    if data_quality == "partial":
        partial_refs = tuple(
            capture.ref("entry_date")
            for kind, capture in latest.items()
            if capture is not None and freshness[kind]["state"] == "current"
        )
        return (
            "steady",
            (
                _Reason(
                    "steady_partial_state",
                    "Current state is partial, so the mode remains conservative.",
                    partial_refs,
                ),
            ),
        )
    balanced_refs = tuple(
        ref
        for ref in (
            (
                current_morning.ref("current_energy")
                if current_morning is not None
                else None
            ),
            (
                current_morning.ref("sleep_hours")
                if current_morning is not None
                else None
            ),
            (
                current_morning.ref("sleep_quality")
                if current_morning is not None
                and sleep_quality is not None
                else None
            ),
            (
                current_morning.ref("day_shape")
                if current_morning is not None
                else None
            ),
            (
                current_evening.ref("stress_intensity")
                if current_evening is not None
                else None
            ),
        )
        if ref is not None
    )
    return (
        "steady",
        (
            _Reason(
                "steady_balanced_state",
                "Current signals support maintaining a realistic load.",
                balanced_refs,
            ),
        ),
    )


def _data_quality(
    *,
    latest: dict[CaptureKind, _Capture | None],
    freshness: dict[CaptureKind, dict[str, Any]],
) -> DataQuality:
    evening = latest["evening"]
    morning = latest["morning"]
    current_evening = (
        evening is not None
        and freshness["evening"]["state"] == "current"
        and evening.complete
        and evening.integrity_ok
    )
    current_morning = (
        morning is not None
        and freshness["morning"]["state"] == "current"
        and morning.complete
        and morning.integrity_ok
    )
    if current_evening and current_morning:
        return "current"
    if any(value["state"] == "current" for value in freshness.values()):
        return "partial"
    if any(capture is not None for capture in latest.values()):
        return "stale"
    return "missing"


def _freshness(
    *,
    kind: CaptureKind,
    capture: _Capture | None,
    target_date: date,
    blocked_on_or_after: date | None,
) -> dict[str, Any]:
    if capture is None:
        return {
            "state": "missing",
            "entry_date": None,
            "captured_at": None,
            "age_days": None,
        }
    age_days = (target_date - capture.entry_date).days
    current = _is_current_capture_date(kind, capture.entry_date, target_date)
    blocked = (
        blocked_on_or_after is not None
        and capture.entry_date <= blocked_on_or_after
    )
    state: FreshnessState = "current" if current and not blocked else "stale"
    return {
        "state": state,
        "entry_date": capture.entry_date.isoformat(),
        "captured_at": (
            capture.captured_at.isoformat()
            if capture.captured_at is not None
            else None
        ),
        "age_days": age_days,
    }


def _is_current_capture_date(
    kind: CaptureKind,
    entry_date: date,
    target_date: date,
) -> bool:
    age_days = (target_date - entry_date).days
    if age_days < 0:
        return False
    if kind == "evening":
        return age_days <= 1
    return age_days == 0


def _block_current_kinds(
    blocked: dict[CaptureKind, date],
    *,
    row_date: date,
    target_date: date,
    kinds: tuple[Literal["evening", "morning"], ...],
) -> None:
    for kind in kinds:
        if not _is_current_capture_date(kind, row_date, target_date):
            continue
        previous = blocked.get(kind)
        if previous is None or row_date > previous:
            blocked[kind] = row_date


def _latest_capture(captures: list[_Capture]) -> _Capture | None:
    if not captures:
        return None
    return max(captures, key=_capture_sort_key)


def _capture_sort_key(capture: _Capture) -> tuple[date, datetime, str]:
    captured_at = capture.captured_at or datetime.min.replace(tzinfo=UTC)
    return capture.entry_date, captured_at, capture.row_id


def _select(captures: list[_Capture], *fields: str) -> _Selection | None:
    options: list[_Selection] = []
    for capture in captures:
        for field in fields:
            if field in capture.values:
                options.append(_Selection(capture.values[field], capture, field))
                break
    if not options:
        return None
    precedence = {"legacy": 0, "evening": 1, "morning": 2}
    return max(
        options,
        key=lambda item: (
            item.capture.entry_date,
            precedence[item.capture.kind],
            item.capture.captured_at or datetime.min.replace(tzinfo=UTC),
            item.capture.row_id,
        ),
    )


def _selection_capture(
    captures: list[_Capture],
    freshness: dict[CaptureKind, dict[str, Any]],
    *fields: str,
) -> _Capture | None:
    current = [
        capture
        for capture in captures
        if freshness[capture.kind]["state"] == "current"
    ]
    selected = _select(current, *fields)
    return selected.capture if selected is not None else None


def _energy_field(capture: _Capture) -> str:
    if capture.kind == "morning":
        return "current_energy"
    if capture.kind == "evening":
        return "energy"
    return "energy_level"


def _current_capture(
    latest: dict[CaptureKind, _Capture | None],
    freshness: dict[CaptureKind, dict[str, Any]],
    kind: CaptureKind,
) -> _Capture | None:
    capture = latest[kind]
    if capture is None or freshness[kind]["state"] != "current":
        return None
    return capture


def _basis(captures: list[_Capture]) -> str:
    formats = {capture.source_format for capture in captures}
    if not formats:
        return "none"
    if formats == {"explicit_capture_v2"}:
        return "explicit_capture"
    if formats == {"legacy_daily_log"}:
        return "legacy_numeric"
    return "mixed"


def _overdue_tasks(
    tasks: list[dict[str, Any]],
    target_date: date,
) -> list[dict[str, Any]]:
    rows = []
    for row in tasks:
        if not _task_is_active(row):
            continue
        deadline = _safe_date(row.get("deadline"))
        if deadline is not None and deadline < target_date:
            rows.append(row)
    return sorted(rows, key=lambda row: (str(row.get("deadline")), str(row.get("id"))))


def _task_is_active(row: dict[str, Any]) -> bool:
    return str(row.get("status") or "") not in {"done", "cancelled", "archived"}


def _goal_is_active(row: dict[str, Any]) -> bool:
    return str(row.get("status") or "active") == "active"


def _reason_from_risks(
    code: str,
    message: str,
    risk_map: dict[str, _Risk],
    *risk_codes: str,
) -> _Reason:
    refs = tuple(
        ref
        for risk_code in risk_codes
        if (risk := risk_map.get(risk_code)) is not None
        for ref in risk.evidence
    )
    return _Reason(code=code, message=message, evidence=tuple(_dedupe_refs(refs)))


def _with_reason_evidence(
    reason: _Reason,
    *refs: _EvidenceRef | None,
) -> _Reason:
    combined = [*reason.evidence, *(ref for ref in refs if ref is not None)]
    return replace(reason, evidence=tuple(_dedupe_refs(combined)))


def _dedupe_refs(
    refs: tuple[_EvidenceRef, ...] | list[_EvidenceRef],
) -> list[_EvidenceRef]:
    seen: set[tuple[str, str, str]] = set()
    result: list[_EvidenceRef] = []
    for ref in refs:
        key = (ref.table, ref.id, ref.field)
        if key in seen:
            continue
        seen.add(key)
        result.append(ref)
    return result


def _dedupe_risks(risks: list[_Risk]) -> list[_Risk]:
    merged: dict[str, list[_EvidenceRef]] = {}
    order: list[str] = []
    for risk in risks:
        if risk.code not in merged:
            merged[risk.code] = []
            order.append(risk.code)
        merged[risk.code].extend(risk.evidence)
    return [
        _Risk(code=code, evidence=tuple(_dedupe_refs(merged[code])))
        for code in order
    ]


def _dedupe_reasons(reasons: list[_Reason]) -> list[_Reason]:
    seen: set[str] = set()
    result: list[_Reason] = []
    for reason in reasons:
        if reason.code in seen:
            continue
        seen.add(reason.code)
        result.append(reason)
    return result


def _dedupe_strings(values: list[str]) -> list[str]:
    return list(dict.fromkeys(values))


def _append_issue(issues: list[str], issue: str) -> None:
    if issue not in issues:
        issues.append(issue)


def _safe_date(value: Any) -> date | None:
    if not isinstance(value, str) or not value:
        return None
    try:
        if "T" in value or " " in value:
            return datetime.fromisoformat(value.replace("Z", "+00:00")).date()
        return date.fromisoformat(value)
    except ValueError:
        return None


def _strict_entry_date(value: Any) -> date | None:
    if not isinstance(value, str) or len(value) != 10:
        return None
    try:
        parsed = date.fromisoformat(value)
    except ValueError:
        return None
    return parsed if parsed.isoformat() == value else None


def _safe_aware_datetime(value: Any) -> datetime | None:
    if not isinstance(value, str) or not value:
        return None
    try:
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return None
    if parsed.tzinfo is None or parsed.utcoffset() is None:
        return None
    return parsed.astimezone(UTC)


def _non_empty_string(value: Any, *, max_length: int) -> str | None:
    if not isinstance(value, str):
        return None
    normalized = value.strip()
    if not normalized or len(normalized) > max_length:
        return None
    return normalized


def _rating(value: Any, *, minimum: int) -> int | None:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        return None
    numeric = float(value)
    if not isfinite(numeric) or not numeric.is_integer():
        return None
    integer = int(numeric)
    return integer if minimum <= integer <= 10 else None


def _sleep_hours(value: Any, *, half_hours: bool) -> float | None:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        return None
    numeric = float(value)
    if not isfinite(numeric) or not 0 <= numeric <= 12:
        return None
    if half_hours and abs(numeric * 2 - round(numeric * 2)) > 0.0001:
        return None
    return numeric


def _enum_value(value: Any, allowed: frozenset[str]) -> str | None:
    return value if isinstance(value, str) and value in allowed else None


def _additional_friction_values(
    value: Any,
    *,
    main_friction: str | None,
) -> list[str] | None:
    if value is None:
        return []
    if not isinstance(value, list) or len(value) > 2:
        return None
    if any(
        not isinstance(item, str) or item not in _ADDITIONAL_FRICTIONS
        for item in value
    ):
        return None
    if len(set(value)) != len(value) or main_friction in value:
        return None
    return list(value)


def _stress_label(value: Any) -> str | None:
    if not isinstance(value, int):
        return None
    if value >= 8:
        return "high"
    if value >= 5:
        return "medium"
    return "low"


def _numbers_equal(left: Any, right: Any) -> bool:
    left_number = _as_float(left)
    right_number = _as_float(right)
    return (
        left_number is not None
        and right_number is not None
        and abs(left_number - right_number) < 0.0001
    )


def _as_float(value: Any) -> float | None:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        return None
    numeric = float(value)
    return numeric if isfinite(numeric) else None


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
_FOCUS_BANDS = frozenset(
    {
        "none",
        "under_30_minutes",
        "30_to_60_minutes",
        "1_to_2_hours",
        "over_2_hours",
    },
)
_MAIN_FRICTIONS = frozenset(
    {
        "no_major_friction",
        "unclear_priorities",
        "too_much_to_do",
        "interruptions",
        "hard_to_start",
        "low_energy",
        "emotional_load",
        "physical_recovery",
        "external_constraints",
    },
)
_ADDITIONAL_FRICTIONS = _MAIN_FRICTIONS - {"no_major_friction"}
_DAY_SHAPES = frozenset({"normal", "constrained", "flexible"})
_STRESS_LABELS = frozenset({"low", "medium", "high"})
