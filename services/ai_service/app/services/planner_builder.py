from __future__ import annotations

import hashlib
import json
from collections.abc import Iterable, Mapping, Sequence
from dataclasses import dataclass
from datetime import UTC, date, datetime, time, timedelta
from typing import Any, Literal
from uuid import NAMESPACE_URL, UUID, uuid5
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from pydantic import TypeAdapter, ValidationError

from app.models.deadline_plans import DeadlinePlanRevision, DeadlinePlansResponse
from app.models.planner import (
    PLANNER_CONTRACT_VERSION,
    PLANNER_OVERVIEW_CONTRACT_VERSION,
    PLANNER_PREFERENCES_CONTRACT_VERSION,
    PlannerActionPlan,
    PlannerActionProposalRequest,
    PlannerActionRevision,
    PlannerActionTarget,
    PlannerAttentionItem,
    PlannerCommitment,
    PlannerCommitmentCreateRequest,
    PlannerCommitmentUpdateRequest,
    PlannerDay,
    PlannerDayItem,
    PlannerHabitSummary,
    PlannerHabitSlot,
    PlannerHabitTarget,
    PlannerHistoryItem,
    PlannerOverviewResponse,
    PlannerPreferencesResponse,
    PlannerPreparationSummary,
    PlannerTaskBlock,
    PlannerTaskSummary,
    PlannerTaskTarget,
    PlannerUnscheduledTask,
    planner_active_task_minutes,
    planner_plan_is_cancelled_tombstone,
    planner_plan_is_pending_create,
    planner_plan_is_released_or_cancelled,
    planner_task_plan_is_released,
    planner_unscheduled_task_reason,
)
from app.models.planning_timing import PlanningTimingProvenance
from app.services.local_time import (
    LocalTimeResolutionError,
    resolve_local_datetime,
    resolve_local_interval,
)
from app.repositories.planner_repository import (
    PlannerAvailabilityContext,
    PlannerOverviewContext,
    PlannerProjection,
)
from app.services.planning_availability import (
    BusySources,
    recurring_commitment_applies_on,
)


from app.services.planner_errors import PlannerConflictError, PlannerNotFoundError


def build_planner_overview(
    *,
    generated_at: datetime,
    context: PlannerOverviewContext,
    deadline_response: DeadlinePlansResponse,
) -> PlannerOverviewResponse:
    _validate_overview_bounds(context)
    zone = _zone(context.timezone)
    local_date = generated_at.astimezone(zone).date()
    days = [local_date + timedelta(days=offset) for offset in range(7)]
    action_plans = _plans_from_projection(context.plans)
    task_titles = _title_map(context.tasks)
    habit_titles = _title_map(context.habits)
    day_items: dict[date, list[PlannerDayItem]] = {day: [] for day in days}

    _add_setup_commitments(
        day_items=day_items,
        rows=context.schedule_items,
        days=days,
        zone=zone,
    )
    _add_manual_commitments(
        day_items=day_items,
        rows=context.commitments,
        days=days,
        zone=zone,
    )
    _add_action_reservations(
        day_items=day_items,
        plans=action_plans,
        days=days,
        zone=zone,
        task_titles=task_titles,
        habit_titles=habit_titles,
    )
    _add_calendar_items(
        day_items=day_items,
        context=context,
        days=days,
        zone=zone,
    )

    ongoing_preparation: list[PlannerPreparationSummary] = []
    for detail in deadline_response.plans:
        projection = detail.active_revision or detail.pending_revision
        next_block: datetime | None = None
        if detail.active_revision is not None:
            upcoming = [
                block
                for block in detail.active_revision.blocks
                if block.ends_at > generated_at
            ]
            if upcoming:
                next_block = min(block.starts_at for block in upcoming)
            for block in detail.active_revision.blocks:
                if block.local_date not in day_items:
                    continue
                day_items[block.local_date].append(
                    PlannerDayItem(
                        id=block.id,
                        kind="preparation",
                        title=detail.plan.title,
                        source_id=detail.plan.id,
                        starts_at=block.starts_at,
                        ends_at=block.ends_at,
                        recovery_minutes=block.recovery_minutes,
                        reserved_ends_at=block.reserved_ends_at,
                        all_day=False,
                        state=block.state,
                    ),
                )
        if detail.plan.status in {"draft", "active"}:
            ongoing_preparation.append(
                PlannerPreparationSummary(
                    plan_id=detail.plan.id,
                    title=detail.plan.title,
                    status=detail.plan.status,
                    remaining_minutes=detail.progress.remaining_minutes,
                    next_block_starts_at=next_block,
                    has_pending_preview=detail.pending_revision is not None,
                ),
            )
        if projection is None and detail.plan.status == "active":
            raise ValueError("Active preparation projection is incomplete.")

    attention_horizon = _attention_horizon(
        local_date=local_date,
        context=context,
        plans=action_plans,
        deadline_response=deadline_response,
        zone=zone,
    )
    attention = _attention_items(
        context=context,
        plans=action_plans,
        days=attention_horizon.reservation_days,
        authoritative_days=attention_horizon.authoritative_days,
        zone=zone,
    )
    attention.extend(
        _preparation_attention_items(
            context=context,
            deadline_response=deadline_response,
            days=attention_horizon.reservation_days,
            authoritative_days=attention_horizon.authoritative_days,
            zone=zone,
            generated_at=generated_at,
        ),
    )
    attention = sorted(
        {item.id: item for item in attention}.values(),
        key=lambda item: (item.kind, item.title.casefold(), item.id),
    )[:500]
    task_targets, habits, unscheduled_tasks, history = _target_overview_items(
        context=context,
        plans=action_plans,
    )
    rendered_days: list[PlannerDay] = []
    for day in days:
        values = day_items[day]
        values.sort(
            key=lambda item: (
                item.starts_at
                or resolve_local_datetime(
                    local_date=day,
                    local_time=time.min,
                    zone=zone,
                    source_id=f"planner-item:{item.id}",
                ),
                _kind_order(item.kind),
                item.title.casefold(),
                str(item.id),
            ),
        )
        rendered_days.append(PlannerDay(local_date=day, items=values))
    ongoing_preparation.sort(
        key=lambda item: (
            item.next_block_starts_at or datetime.max.replace(tzinfo=UTC),
            item.title.casefold(),
            str(item.plan_id),
        ),
    )
    return PlannerOverviewResponse(
        contract_version=PLANNER_OVERVIEW_CONTRACT_VERSION,
        origin="authenticated_backend",
        generated_at=generated_at,
        timezone=context.timezone,
        local_date=local_date,
        preferences=_preferences_response(
            preference=context.preference,
            calendar_import_id=context.calendar.import_id,
            calendar_available=context.calendar.available,
        ),
        action_plans=action_plans,
        commitments=[_commitment_from_row(row) for row in context.commitments],
        needs_attention=attention,
        days=rendered_days,
        ongoing_preparation=ongoing_preparation,
        habits=habits,
        task_targets=task_targets,
        unscheduled_tasks=unscheduled_tasks,
        history=history,
    )


_TARGET_ADAPTER = TypeAdapter(PlannerActionTarget)


def _plan_from_projection(
    *,
    projection: PlannerProjection,
    plan_id: UUID,
) -> PlannerActionPlan:
    plans = _plans_from_projection(projection)
    match = [plan for plan in plans if plan.id == plan_id]
    if len(match) != 1:
        raise ValueError("Planner action plan projection is inconsistent.")
    return match[0]


def _plans_from_projection(projection: PlannerProjection) -> list[PlannerActionPlan]:
    if len(projection.plans) > 1_000:
        raise PlannerConflictError("Planner action plan count exceeds its bound.")
    plan_ids: set[str] = set()
    for row in projection.plans:
        value = str(row.get("id"))
        if value == "None" or value in plan_ids:
            raise ValueError("Planner action plan identity is invalid.")
        plan_ids.add(value)
    revisions_by_plan: dict[str, list[dict[str, Any]]] = {}
    revision_keys: set[tuple[str, int]] = set()
    for row in projection.revisions:
        key = (str(row.get("plan_id")), _int(row.get("revision")))
        if key[0] not in plan_ids or key in revision_keys:
            raise ValueError("Planner revision projection is invalid.")
        revision_keys.add(key)
        revisions_by_plan.setdefault(key[0], []).append(row)
    blocks_by_key: dict[tuple[str, int], list[dict[str, Any]]] = {}
    block_ids: set[str] = set()
    for row in projection.task_blocks:
        key = (str(row.get("plan_id")), _int(row.get("revision")))
        value = str(row.get("id"))
        if key not in revision_keys or value == "None" or value in block_ids:
            raise ValueError("Planner task block projection is invalid.")
        block_ids.add(value)
        blocks_by_key.setdefault(key, []).append(row)
    slots_by_key: dict[tuple[str, int], list[dict[str, Any]]] = {}
    slot_ids: set[str] = set()
    for row in projection.habit_slots:
        key = (str(row.get("plan_id")), _int(row.get("revision")))
        value = str(row.get("id"))
        if key not in revision_keys or value == "None" or value in slot_ids:
            raise ValueError("Planner habit slot projection is invalid.")
        slot_ids.add(value)
        slots_by_key.setdefault(key, []).append(row)

    result: list[PlannerActionPlan] = []
    for plan_row in projection.plans:
        key = str(plan_row["id"])
        revision_rows = revisions_by_plan.get(key, [])
        active_rows = [row for row in revision_rows if row.get("state") == "active"]
        pending_rows = [row for row in revision_rows if row.get("state") == "proposed"]
        if len(active_rows) > 1 or len(pending_rows) > 1:
            raise ValueError("Planner revision lifecycle projection is ambiguous.")
        active = (
            _revision_from_row(
                active_rows[0],
                task_blocks=blocks_by_key.get(
                    (key, _int(active_rows[0]["revision"])),
                    [],
                ),
                habit_slots=slots_by_key.get(
                    (key, _int(active_rows[0]["revision"])),
                    [],
                ),
            )
            if active_rows
            else None
        )
        pending = (
            _revision_from_row(
                pending_rows[0],
                task_blocks=blocks_by_key.get(
                    (key, _int(pending_rows[0]["revision"])),
                    [],
                ),
                habit_slots=slots_by_key.get(
                    (key, _int(pending_rows[0]["revision"])),
                    [],
                ),
            )
            if pending_rows
            else None
        )
        reasons = plan_row.get("attention_reasons", [])
        if not isinstance(reasons, list) or any(
            not isinstance(value, str) or not value or len(value) > 80
            for value in reasons
        ):
            raise ValueError("Planner attention projection is invalid.")
        result.append(
            PlannerActionPlan(
                id=UUID(key),
                target_kind=plan_row["target_kind"],
                target_id=UUID(str(plan_row["target_id"])),
                status=plan_row["status"],
                current_revision=_int(plan_row["current_revision"]),
                latest_revision=_int(plan_row["latest_revision"]),
                needs_attention=bool(reasons),
                attention_reasons=list(dict.fromkeys(reasons)),
                active_revision=active,
                pending_revision=pending,
            ),
        )
    result.sort(key=lambda value: str(value.id))
    return result


def _revision_from_row(
    row: Mapping[str, Any],
    *,
    task_blocks: Sequence[Mapping[str, Any]],
    habit_slots: Sequence[Mapping[str, Any]],
) -> PlannerActionRevision:
    raw_target = row.get("target_payload")
    if not isinstance(raw_target, dict):
        raise ValueError("Planner target projection is invalid.")
    try:
        target = _TARGET_ADAPTER.validate_json(
            json.dumps(raw_target, separators=(",", ":")),
        )
    except ValidationError as exc:
        raise ValueError("Planner target projection is invalid.") from exc
    rendered_blocks = [
        PlannerTaskBlock(
            id=UUID(str(block["id"])),
            sequence=_int(block["sequence"]),
            starts_at=_datetime(block["starts_at"]),
            ends_at=_datetime(block["ends_at"]),
            local_date=_date(block["local_date"]),
            planned_minutes=_int(block["planned_minutes"]),
            recovery_minutes=_int(block.get("recovery_minutes", 0)),
            reserved_ends_at=_datetime(
                block.get("reserved_ends_at", block["ends_at"]),
            ),
            state=block["state"],
        )
        for block in sorted(
            task_blocks,
            key=lambda value: (_int(value["sequence"]), str(value["id"])),
        )
    ]
    rendered_slots = [
        PlannerHabitSlot(
            id=UUID(str(slot["id"])),
            weekday=_int(slot["weekday"]),
            starts_at=_time(slot["starts_at"]),
            ends_at=_time(slot["ends_at"]),
            duration_minutes=_int(slot["duration_minutes"]),
            state=slot["state"],
        )
        for slot in sorted(
            habit_slots,
            key=lambda value: (
                _int(value["weekday"]),
                str(value["starts_at"]),
                str(value["id"]),
            ),
        )
    ]
    return PlannerActionRevision(
        revision=_int(row["revision"]),
        base_revision=_int(row["base_revision"]),
        state=row["state"],
        target=target,
        timezone=row["timezone"],
        best_energy_window=row["best_energy_window"],
        planning_start_on=_date(row["planning_start_on"]),
        planning_fingerprint=row["planning_fingerprint"],
        timing_preference=_timing_preference_from_row(row),
        calendar_import_id=(
            UUID(str(row["calendar_import_id"]))
            if row.get("calendar_import_id")
            else None
        ),
        study_setup_revision=(
            _int(row["study_setup_revision"])
            if row.get("study_setup_revision") is not None
            else None
        ),
        recovery_minutes=_int(row.get("recovery_minutes", 0)),
        planned_minutes=_int(row["planned_minutes"]),
        unscheduled_minutes=_int(row["unscheduled_minutes"]),
        task_blocks=rendered_blocks,
        habit_slots=rendered_slots,
        created_at=_datetime(row["created_at"]),
        activated_at=_optional_datetime(row.get("activated_at")),
        superseded_at=_optional_datetime(row.get("superseded_at")),
    )


def _timing_preference_from_row(
    row: Mapping[str, Any],
) -> PlanningTimingProvenance:
    return PlanningTimingProvenance(
        source=row.get("timing_preference_source", "setup"),
        window=row.get("timing_preference_window"),
        evidence_count=_int(row.get("timing_evidence_count", 0)),
        evidence_starts_on=(
            _date(row["timing_evidence_starts_on"])
            if row.get("timing_evidence_starts_on") is not None
            else None
        ),
        evidence_ends_on=(
            _date(row["timing_evidence_ends_on"])
            if row.get("timing_evidence_ends_on") is not None
            else None
        ),
        evidence_fingerprint=row.get("timing_evidence_fingerprint"),
        fell_back_to_setup=bool(row.get("timing_fell_back_to_setup", False)),
        warning=row.get("timing_warning"),
    )


def _preferences_response(
    *,
    preference: Mapping[str, Any] | None,
    calendar_import_id: UUID | None,
    calendar_available: bool,
) -> PlannerPreferencesResponse:
    return PlannerPreferencesResponse(
        contract_version=PLANNER_PREFERENCES_CONTRACT_VERSION,
        origin="authenticated_backend",
        use_calendar_busy_time=bool(
            preference and preference.get("use_calendar_busy_time") is True
        ),
        updated_at=(
            _datetime(preference["updated_at"])
            if preference and preference.get("updated_at")
            else None
        ),
        current_calendar_import_id=calendar_import_id,
        calendar_available=calendar_available,
    )


def _planning_end(
    *,
    request: PlannerActionProposalRequest,
    generated_at: datetime,
) -> date:
    if isinstance(request.target, PlannerTaskTarget) and request.target.deadline_at:
        # The profile zone is not loaded yet. The UTC date is only a bounded
        # repository hint; the definitive local-date validation runs later.
        return request.target.deadline_at.astimezone(UTC).date() + timedelta(days=1)
    if isinstance(request.target, PlannerHabitTarget):
        return request.planning_start_on + timedelta(days=27)
    return max(request.planning_start_on, generated_at.date())


def _validate_target_projection(
    target: PlannerActionTarget,
    row: Mapping[str, Any] | None,
) -> None:
    if target.operation == "create":
        if row is not None:
            raise PlannerConflictError("The new target id is already in use.")
        return
    if row is None:
        raise PlannerNotFoundError("The target to plan is unavailable.")
    updated = _datetime(row.get("updated_at"))
    if updated != target.expected_updated_at:
        raise PlannerConflictError("The target changed. Reload before planning it.")
    if isinstance(target, PlannerTaskTarget):
        if row.get("status") not in {"todo", "in_progress"}:
            raise PlannerConflictError("A terminal task cannot be planned.")
        return
    metadata = row.get("metadata")
    if not isinstance(metadata, dict):
        raise ValueError("Habit metadata is invalid.")
    if row.get("active") is not True:
        raise PlannerConflictError("A paused or archived habit cannot be planned.")
    if metadata.get("managed_by") == "setup":
        existing = _habit_definition_from_row(row)
        proposed = {
            "title": target.title,
            "description": target.description,
            "cadence": target.cadence.model_dump(mode="json"),
        }
        if existing != proposed:
            raise PlannerConflictError(
                "Setup-owned habit definitions can only be changed in Settings.",
            )


def _habit_definition_from_row(row: Mapping[str, Any]) -> dict[str, Any]:
    metadata = row.get("metadata")
    if not isinstance(metadata, dict):
        raise ValueError("Habit metadata is invalid.")
    cadence = metadata.get("cadence")
    if cadence == "weekdays":
        weekdays = metadata.get("scheduled_weekdays")
        if not isinstance(weekdays, list):
            raise ValueError("Habit cadence is invalid.")
        value = {
            "kind": "weekdays",
            "scheduled_weekdays": weekdays,
            "weekly_target": 1,
        }
    elif cadence == "weekly_target" or (
        cadence is None and row.get("frequency") == "weekly"
    ):
        value = {
            "kind": "weekly_target",
            "scheduled_weekdays": [],
            "weekly_target": _int(row.get("target")),
        }
    else:
        value = {
            "kind": "daily",
            "scheduled_weekdays": [],
            "weekly_target": 1,
        }
    return {
        "title": row.get("title"),
        "description": row.get("description"),
        "cadence": value,
    }


def _habit_weekdays(target: PlannerHabitTarget) -> list[int]:
    if target.cadence.kind == "daily":
        return list(range(1, 8))
    if target.cadence.kind == "weekdays":
        return sorted(target.cadence.scheduled_weekdays)
    # Spread a weekly target before filling adjacent weekdays. This is stable,
    # deterministic, and never infers a cadence the user did not choose.
    return [1, 3, 5, 7, 2, 4, 6][: target.cadence.weekly_target]


def _availability_sources(
    *,
    context: PlannerAvailabilityContext,
    calendar_enabled: bool,
) -> BusySources:
    recurring: list[dict[str, Any]] = []
    timed: list[dict[str, Any]] = []
    all_day: list[dict[str, Any]] = []
    for row in context.schedule_items:
        recurring.append(
            {
                "weekday": row.get("weekday"),
                "starts_at": row.get("starts_at"),
                "ends_at": row.get("ends_at"),
                "metadata": row.get("metadata"),
            },
        )
    for row in context.commitments:
        if row.get("recurrence") == "weekly":
            recurring.append(
                {
                    "weekday": row.get("weekday"),
                    "starts_at": row.get("local_starts_at"),
                    "ends_at": row.get("local_ends_at"),
                },
            )
        elif row.get("recurrence") == "one_off":
            timed.append(
                {"starts_at": row.get("starts_at"), "ends_at": row.get("ends_at")},
            )
        else:
            raise ValueError("Planner commitment recurrence is invalid.")
    recurring.extend(
        {
            "weekday": row.get("weekday"),
            "starts_at": row.get("starts_at"),
            "ends_at": row.get("ends_at"),
        }
        for row in context.habit_slots
    )
    timed.extend(
        {
            "starts_at": row.get("starts_at"),
            "ends_at": row.get("ends_at"),
            "reserved_ends_at": row.get("reserved_ends_at", row.get("ends_at")),
        }
        for row in [*context.task_blocks, *context.deadline_blocks]
    )
    if calendar_enabled:
        timed.extend(
            {"starts_at": row.get("starts_at"), "ends_at": row.get("ends_at")}
            for row in context.calendar.timed_events
            if row.get("busy_status") == "busy"
        )
        all_day.extend(
            {"starts_on": row.get("starts_on"), "ends_on": row.get("ends_on")}
            for row in context.calendar.all_day_events
            if row.get("busy_status") == "busy"
        )
    return BusySources(
        recurring_commitments=recurring,
        timed_intervals=timed,
        all_day_intervals=all_day,
    )


def _study_rhythm(
    row: Mapping[str, Any] | None,
) -> tuple[int, int, int] | None:
    if row is None:
        return None
    revision = _int(row.get("setup_revision"))
    focus = row.get("focus_minutes")
    recovery = row.get("recovery_minutes")
    if focus is None and recovery is None:
        return None
    focus_minutes = _int(focus)
    recovery_minutes = _int(recovery)
    if (
        revision < 1
        or focus_minutes < 25
        or focus_minutes > 180
        or focus_minutes % 5 != 0
        or recovery_minutes < 5
        or recovery_minutes > 60
        or recovery_minutes % 5 != 0
    ):
        raise ValueError("Study Setup rhythm projection is invalid.")
    return revision, focus_minutes, recovery_minutes


def _commitment_payload(
    value: PlannerCommitmentCreateRequest | PlannerCommitmentUpdateRequest,
) -> dict[str, Any]:
    payload = value.model_dump(mode="json")
    for key in ("request_id", "commitment_id", "expected_updated_at"):
        payload.pop(key, None)
    return payload


def _commitment_from_row(row: Mapping[str, Any]) -> PlannerCommitment:
    return PlannerCommitment(
        id=UUID(str(row["id"])),
        title=row["title"],
        location=row.get("location"),
        recurrence=row["recurrence"],
        status=row["status"],
        starts_at=_optional_datetime(row.get("starts_at")),
        ends_at=_optional_datetime(row.get("ends_at")),
        weekday=_optional_int(row.get("weekday")),
        local_starts_at=_optional_time(row.get("local_starts_at")),
        local_ends_at=_optional_time(row.get("local_ends_at")),
        created_at=_datetime(row["created_at"]),
        updated_at=_datetime(row["updated_at"]),
        archived_at=_optional_datetime(row.get("archived_at")),
    )


def _add_setup_commitments(
    *,
    day_items: dict[date, list[PlannerDayItem]],
    rows: Sequence[Mapping[str, Any]],
    days: Sequence[date],
    zone: ZoneInfo,
) -> None:
    for row in rows:
        weekday = _int(row.get("weekday"))
        starts = _time(row.get("starts_at"))
        ends = _time(row.get("ends_at"))
        for day in days:
            if day.isoweekday() != weekday or not recurring_commitment_applies_on(
                row, day
            ):
                continue
            source_id = UUID(str(row["id"]))
            try:
                starts_at, ends_at = resolve_local_interval(
                    local_date=day,
                    starts_at=starts,
                    ends_at=ends,
                    zone=zone,
                    source_id=f"setup:{source_id}",
                )
            except LocalTimeResolutionError:
                # The long-horizon attention scan reports the invalid source.
                # Only this occurrence is absent from the visible agenda.
                continue
            day_items[day].append(
                PlannerDayItem(
                    id=_occurrence_id("setup", source_id, day),
                    kind="setup_commitment",
                    title=_title(row),
                    source_id=source_id,
                    starts_at=starts_at,
                    ends_at=ends_at,
                    recovery_minutes=0,
                    reserved_ends_at=ends_at,
                    all_day=False,
                ),
            )


def _add_manual_commitments(
    *,
    day_items: dict[date, list[PlannerDayItem]],
    rows: Sequence[Mapping[str, Any]],
    days: Sequence[date],
    zone: ZoneInfo,
) -> None:
    day_set = set(days)
    for row in rows:
        if row.get("status") != "active":
            continue
        source_id = UUID(str(row["id"]))
        if row.get("recurrence") == "one_off":
            starts = _datetime(row.get("starts_at"))
            ends = _datetime(row.get("ends_at"))
            local_day = starts.astimezone(zone).date()
            if local_day not in day_set:
                continue
            day_items[local_day].append(
                PlannerDayItem(
                    id=source_id,
                    kind="manual_commitment",
                    title=_title(row),
                    source_id=source_id,
                    starts_at=starts,
                    ends_at=ends,
                    recovery_minutes=0,
                    reserved_ends_at=ends,
                    all_day=False,
                ),
            )
            continue
        weekday = _int(row.get("weekday"))
        starts_local = _time(row.get("local_starts_at"))
        ends_local = _time(row.get("local_ends_at"))
        for day in days:
            if day.isoweekday() != weekday:
                continue
            try:
                starts, ends = resolve_local_interval(
                    local_date=day,
                    starts_at=starts_local,
                    ends_at=ends_local,
                    zone=zone,
                    source_id=f"planner-commitment:{source_id}",
                )
            except LocalTimeResolutionError:
                # Attention owns the source/date explanation. Only this weekly
                # occurrence is absent from the visible agenda.
                continue
            day_items[day].append(
                PlannerDayItem(
                    id=_occurrence_id("commitment", source_id, day),
                    kind="manual_commitment",
                    title=_title(row),
                    source_id=source_id,
                    starts_at=starts,
                    ends_at=ends,
                    recovery_minutes=0,
                    reserved_ends_at=ends,
                    all_day=False,
                ),
            )


def _add_action_reservations(
    *,
    day_items: dict[date, list[PlannerDayItem]],
    plans: Sequence[PlannerActionPlan],
    days: Sequence[date],
    zone: ZoneInfo,
    task_titles: Mapping[str, str],
    habit_titles: Mapping[str, str],
) -> None:
    day_set = set(days)
    for plan in plans:
        revision = plan.active_revision
        if revision is None:
            continue
        if isinstance(revision.target, PlannerTaskTarget):
            title = task_titles.get(str(plan.target_id), revision.target.title)
            for block in revision.task_blocks:
                if block.state != "active" or block.local_date not in day_set:
                    continue
                day_items[block.local_date].append(
                    PlannerDayItem(
                        id=block.id,
                        kind="task_block",
                        title=title,
                        source_id=plan.target_id,
                        starts_at=block.starts_at,
                        ends_at=block.ends_at,
                        recovery_minutes=block.recovery_minutes,
                        reserved_ends_at=block.reserved_ends_at,
                        all_day=False,
                        state=block.state,
                    ),
                )
        else:
            title = habit_titles.get(str(plan.target_id), revision.target.title)
            for slot in revision.habit_slots:
                if slot.state != "active":
                    continue
                for day in days:
                    if day.isoweekday() != slot.weekday:
                        continue
                    try:
                        starts, ends = resolve_local_interval(
                            local_date=day,
                            starts_at=slot.starts_at,
                            ends_at=slot.ends_at,
                            zone=zone,
                            source_id=f"planner-habit-slot:{slot.id}",
                        )
                    except LocalTimeResolutionError:
                        # Needs attention owns the source-specific explanation.
                        # A later valid weekly occurrence remains materialized.
                        continue
                    day_items[day].append(
                        PlannerDayItem(
                            id=_occurrence_id("habit", slot.id, day),
                            kind="habit_slot",
                            title=title,
                            source_id=plan.target_id,
                            starts_at=starts,
                            ends_at=ends,
                            recovery_minutes=0,
                            reserved_ends_at=ends,
                            all_day=False,
                            state=slot.state,
                        ),
                    )


def _add_calendar_items(
    *,
    day_items: dict[date, list[PlannerDayItem]],
    context: PlannerOverviewContext,
    days: Sequence[date],
    zone: ZoneInfo,
) -> None:
    if not context.calendar.available:
        return
    day_set = set(days)
    for row in context.calendar.timed_events:
        starts = _datetime(row.get("starts_at"))
        ends = _datetime(row.get("ends_at"))
        day = starts.astimezone(zone).date()
        if day not in day_set:
            continue
        source_id = UUID(str(row["id"]))
        day_items[day].append(
            PlannerDayItem(
                id=source_id,
                kind="calendar_event",
                title=_title(row),
                source_id=source_id,
                starts_at=starts,
                ends_at=ends,
                recovery_minutes=0,
                reserved_ends_at=ends,
                all_day=False,
                state=row.get("busy_status"),
            ),
        )
    for row in context.calendar.all_day_events:
        starts_on = _date(row.get("starts_on"))
        ends_on = _date(row.get("ends_on"))
        source_id = UUID(str(row["id"]))
        for day in days:
            if starts_on <= day < ends_on:
                day_items[day].append(
                    PlannerDayItem(
                        id=_occurrence_id("calendar", source_id, day),
                        kind="calendar_event",
                        title=_title(row),
                        source_id=source_id,
                        starts_at=None,
                        ends_at=None,
                        recovery_minutes=0,
                        reserved_ends_at=None,
                        all_day=True,
                        state=row.get("busy_status"),
                    ),
                )


def _attention_items(
    *,
    context: PlannerOverviewContext,
    plans: Sequence[PlannerActionPlan],
    days: Sequence[date],
    authoritative_days: Sequence[date] | None = None,
    zone: ZoneInfo,
) -> list[PlannerAttentionItem]:
    result = _course_selection_attention(
        context.study_setup,
        local_date=days[0],
    )
    current_study = _study_rhythm(context.study_setup)
    current_study_revision = current_study[0] if current_study else None
    calendar_enabled = bool(
        context.preference and context.preference.get("use_calendar_busy_time") is True
    )
    authoritative_day_values = tuple(
        authoritative_days
        if authoritative_days is not None
        else _attention_authoritative_days(days)
    )
    authoritative = _authoritative_intervals(
        context=context,
        days=authoritative_day_values,
        zone=zone,
        calendar_enabled=calendar_enabled,
    )
    authoritative_by_day = _authoritative_intervals_by_day(
        intervals=authoritative.intervals,
        days=authoritative_day_values,
        zone=zone,
    )
    for plan in plans:
        revision = plan.active_revision
        title = (
            revision.target.title
            if revision is not None
            else (
                plan.pending_revision.target.title
                if plan.pending_revision is not None
                else "Planned action"
            )
        )
        pending = plan.pending_revision
        for reason in plan.attention_reasons:
            # Current reservations provide the authoritative conflict origin and
            # exact unplaced minutes. Released targets remain discoverable in
            # their own projection instead of producing a duplicate warning.
            # Persisted stale reasons describe an older planning event and may
            # outlive later proposals. A pending revision is assessed only from
            # its current target, timezone, Calendar, and Study facts below.
            if reason in {
                "commitment_conflict",
                "target_released",
                "unplaced_minutes",
            } or pending is not None:
                continue
            result.append(
                PlannerAttentionItem(
                    id=f"{plan.id}:persisted:{reason}",
                    kind=(
                        "study_rhythm_changed"
                        if reason == "study_rhythm_changed"
                        else "stale_preview"
                    ),
                    target="plan",
                    title=title,
                    detail=_attention_detail(reason),
                    plan_id=plan.id,
                    unplaced_minutes=0,
                ),
            )
        if pending is not None:
            if pending.unscheduled_minutes:
                result.append(
                    PlannerAttentionItem(
                        id=f"{plan.id}:unscheduled:{pending.revision}",
                        kind="unscheduled",
                        target="plan",
                        title=pending.target.title,
                        detail=_unplaced_detail(pending),
                        plan_id=plan.id,
                        unplaced_minutes=pending.unscheduled_minutes,
                    ),
                )
            preview_uses_calendar = pending.calendar_import_id is not None
            if (
                preview_uses_calendar != calendar_enabled
                or (
                    preview_uses_calendar
                    and (
                        not context.calendar.available
                        or pending.calendar_import_id != context.calendar.import_id
                    )
                )
            ):
                result.append(
                    PlannerAttentionItem(
                        id=f"{plan.id}:calendar-stale:{pending.revision}",
                        kind="stale_preview",
                        target="plan",
                        title=pending.target.title,
                        detail=(
                            "The Planner calendar setting or current import changed. "
                            "Create a new preview."
                        ),
                        plan_id=plan.id,
                        unplaced_minutes=0,
                    ),
                )
            if _pending_target_is_stale(pending.target, context=context):
                result.append(
                    PlannerAttentionItem(
                        id=f"{plan.id}:target-stale:{pending.revision}",
                        kind="stale_preview",
                        target="plan",
                        title=pending.target.title,
                        detail="The Task or Habit changed. Create a new preview.",
                        plan_id=plan.id,
                        unplaced_minutes=0,
                    ),
                )
            if (
                isinstance(pending.target, PlannerTaskTarget)
                and pending.target.use_study_rhythm
                and pending.study_setup_revision != current_study_revision
            ):
                result.append(
                    PlannerAttentionItem(
                        id=f"{plan.id}:study-stale:{pending.revision}",
                        kind="stale_preview",
                        target="plan",
                        title=pending.target.title,
                        detail=(
                            "The Study rhythm changed. Create a new preview "
                            "before confirming."
                        ),
                        plan_id=plan.id,
                        unplaced_minutes=0,
                    ),
                )
            if pending.timezone != context.timezone:
                result.append(
                    PlannerAttentionItem(
                        id=f"{plan.id}:timezone-stale:{pending.revision}",
                        kind="stale_preview",
                        target="plan",
                        title=pending.target.title,
                        detail=(
                            "The account timezone changed. Create a new preview "
                            "before confirming."
                        ),
                        plan_id=plan.id,
                        unplaced_minutes=0,
                    ),
                )
        if (
            revision is not None
            and revision.unscheduled_minutes
            and (_active_task_minutes(plan) > 0 or _active_habit_slot_count(plan) > 0)
        ):
            result.append(
                PlannerAttentionItem(
                    id=f"{plan.id}:unscheduled:{revision.revision}",
                    kind="unscheduled",
                    target="plan",
                    title=title,
                    detail=_unplaced_detail(revision),
                    plan_id=plan.id,
                    unplaced_minutes=revision.unscheduled_minutes,
                ),
            )
        if revision is not None:
            conflict_scan = _revision_conflict_sources(
                plan_id=plan.id,
                revision=revision,
                days=days,
                zone=zone,
                authoritative_by_day=authoritative_by_day,
            )
            for source in conflict_scan.sources:
                result.append(
                    PlannerAttentionItem(
                        id=(f"{plan.id}:current-conflict:{source}:{revision.revision}"),
                        kind="conflict",
                        target="plan",
                        title=title,
                        detail=_conflict_detail(source, preparation=False),
                        plan_id=plan.id,
                        unplaced_minutes=0,
                        conflict_source=source,
                    ),
                )
            invalid_occurrences = [
                *conflict_scan.invalid_habit_occurrences,
                *(
                    occurrence
                    for occurrence in authoritative.invalid_setup_occurrences
                    if conflict_scan.candidate_days.intersection(
                        occurrence.affected_days,
                    )
                ),
                *(
                    occurrence
                    for occurrence in (
                        authoritative.invalid_fixed_commitment_occurrences
                    )
                    if conflict_scan.candidate_days.intersection(
                        occurrence.affected_days,
                    )
                ),
            ]
            if invalid_occurrences:
                result.append(
                    PlannerAttentionItem(
                        id=(f"{plan.id}:local-time-invalid:{revision.revision}"),
                        kind="stale_preview",
                        target="plan",
                        title=title,
                        detail=_invalid_recurrence_detail(
                            invalid_occurrences,
                            timezone=context.timezone,
                        ),
                        plan_id=plan.id,
                        unplaced_minutes=0,
                    ),
                )
        if (
            revision is not None
            and isinstance(revision.target, PlannerTaskTarget)
            and revision.target.use_study_rhythm
            and revision.study_setup_revision != current_study_revision
            and "study_rhythm_changed" not in plan.attention_reasons
        ):
            result.append(
                PlannerAttentionItem(
                    id=f"{plan.id}:study-changed:{revision.revision}",
                    kind="study_rhythm_changed",
                    target="plan",
                    title=title,
                    detail=(
                        "The Study rhythm changed. Review and confirm a new "
                        "preview before reservations change."
                    ),
                    plan_id=plan.id,
                    unplaced_minutes=0,
                ),
            )
    unique: dict[str, PlannerAttentionItem] = {item.id: item for item in result}
    values = list(unique.values())
    values.sort(key=lambda item: (item.kind, item.title.casefold(), item.id))
    return values[:500]


def _pending_target_is_stale(
    target: PlannerActionTarget,
    *,
    context: PlannerOverviewContext,
) -> bool:
    rows = context.tasks if isinstance(target, PlannerTaskTarget) else context.habits
    matching = [row for row in rows if str(row.get("id")) == str(target.target_id)]
    if len(matching) > 1:
        raise ValueError("Planner target overview projection is ambiguous.")
    if target.operation == "create":
        return bool(matching)
    if not matching:
        return True
    row = matching[0]
    if _datetime(row.get("updated_at")) != target.expected_updated_at:
        return True
    if isinstance(target, PlannerTaskTarget):
        return row.get("status") not in {"todo", "in_progress"}
    metadata = row.get("metadata")
    if not isinstance(metadata, dict):
        raise ValueError("Habit metadata is invalid.")
    return (
        row.get("active") is not True or metadata.get("lifecycle", "active") != "active"
    )


def _course_selection_attention(
    study_setup: Mapping[str, Any] | None,
    *,
    local_date: date,
) -> list[PlannerAttentionItem]:
    if study_setup is None or study_setup.get("next_semester") is None:
        return []
    semester = study_setup.get("next_semester")
    if not isinstance(semester, Mapping):
        raise ValueError("Next semester projection is invalid.")
    completed = semester.get("course_selection_completed")
    if not isinstance(completed, bool):
        raise ValueError("Course selection state is invalid.")
    if completed:
        return []
    starts_on = _date(semester.get("course_selection_starts_on"))
    ends_on = _date(semester.get("course_selection_ends_on"))
    if local_date < starts_on:
        return []
    overdue = local_date > ends_on
    return [
        PlannerAttentionItem(
            id=f"study-setup:course-selection:{starts_on.isoformat()}",
            kind=("course_selection_overdue" if overdue else "course_selection_open"),
            target="study_setup",
            title="Choose next semester courses",
            detail=(
                "The course selection window has ended. Review Study Setup."
                if overdue
                else "The course selection window is open. Review Study Setup."
            ),
            plan_id=None,
            unplaced_minutes=0,
        ),
    ]


_MAX_ATTENTION_RESERVATION_DAYS = 366
_MAX_ATTENTION_AUTHORITATIVE_DAYS = _MAX_ATTENTION_RESERVATION_DAYS + 2


@dataclass(frozen=True)
class _AttentionHorizon:
    reservation_days: tuple[date, ...]
    authoritative_days: tuple[date, ...]


def _attention_horizon(
    *,
    local_date: date,
    context: PlannerOverviewContext,
    plans: Sequence[PlannerActionPlan],
    deadline_response: DeadlinePlansResponse,
    zone: ZoneInfo,
) -> _AttentionHorizon:
    last_date = local_date + timedelta(days=365)
    values = {local_date + timedelta(days=offset) for offset in range(28)}

    def add(candidate: date) -> None:
        if local_date <= candidate <= last_date:
            values.add(candidate)

    for plan in plans:
        if plan.active_revision is None:
            continue
        for block in plan.active_revision.task_blocks:
            if block.state == "active":
                add(block.local_date)
                add(block.starts_at.astimezone(zone).date())
                add(
                    (block.reserved_ends_at.astimezone(UTC) - timedelta(microseconds=1))
                    .astimezone(zone)
                    .date(),
                )
    active_habit_weekdays = {
        slot.weekday
        for plan in plans
        if plan.active_revision is not None
        for slot in plan.active_revision.habit_slots
        if slot.state == "active"
    }
    if active_habit_weekdays:
        # A confirmed Habit slot recurs beyond the 28-day proposal proof.
        # Include only its relevant weekdays through the bounded Planner
        # horizon so later semester Setup rows and recurring commitments can
        # produce current conflict attention without expanding past 366 days.
        for offset in range(28, 366):
            candidate = local_date + timedelta(days=offset)
            if candidate.isoweekday() in active_habit_weekdays:
                values.add(candidate)
    for detail in deadline_response.plans:
        if detail.active_revision is None:
            continue
        for block in detail.active_revision.blocks:
            add(block.local_date)
            add(block.starts_at.astimezone(zone).date())
            add(
                (block.reserved_ends_at.astimezone(UTC) - timedelta(microseconds=1))
                .astimezone(zone)
                .date(),
            )
    for row in context.commitments:
        if row.get("status") == "active" and row.get("recurrence") == "one_off":
            starts_at = _datetime(row.get("starts_at"))
            ends_at = _datetime(row.get("ends_at"))
            add(starts_at.astimezone(zone).date())
            add(
                (ends_at.astimezone(UTC) - timedelta(microseconds=1))
                .astimezone(zone)
                .date(),
            )
    if context.calendar.available:
        for row in context.calendar.timed_events:
            starts_at = _datetime(row.get("starts_at"))
            ends_at = _datetime(row.get("ends_at"))
            add(starts_at.astimezone(zone).date())
            add(
                (ends_at.astimezone(UTC) - timedelta(microseconds=1))
                .astimezone(zone)
                .date(),
            )
        for row in context.calendar.all_day_events:
            starts_on = _date(row.get("starts_on"))
            ends_on = _date(row.get("ends_on"))
            # Seven representative days are enough to cover every recurring
            # Habit weekday; Task and Preparation dates were added above.
            for offset in range(min(7, max(0, (ends_on - starts_on).days))):
                add(starts_on + timedelta(days=offset))
    reservation_days = tuple(sorted(values))
    if len(reservation_days) > _MAX_ATTENTION_RESERVATION_DAYS:
        raise ValueError("Planner attention horizon exceeds 366 local days.")
    return _AttentionHorizon(
        reservation_days=reservation_days,
        authoritative_days=_attention_authoritative_days(reservation_days),
    )


def _attention_authoritative_days(days: Sequence[date]) -> tuple[date, ...]:
    reservation_days = set(days)
    if len(reservation_days) > _MAX_ATTENTION_RESERVATION_DAYS:
        raise ValueError("Planner attention horizon exceeds 366 local days.")
    values = (
        reservation_days
        | {candidate - timedelta(days=1) for candidate in reservation_days}
        | {candidate + timedelta(days=1) for candidate in reservation_days}
    )
    if len(values) > _MAX_ATTENTION_AUTHORITATIVE_DAYS:
        raise ValueError("Planner attention anchors exceed their local-day bound.")
    return tuple(sorted(values))


def _preparation_attention_items(
    *,
    context: PlannerOverviewContext,
    deadline_response: DeadlinePlansResponse,
    days: Sequence[date],
    authoritative_days: Sequence[date] | None = None,
    zone: ZoneInfo,
    generated_at: datetime,
) -> list[PlannerAttentionItem]:
    authoritative_day_values = tuple(
        authoritative_days
        if authoritative_days is not None
        else _attention_authoritative_days(days)
    )
    authoritative = _authoritative_intervals(
        context=context,
        days=authoritative_day_values,
        zone=zone,
        calendar_enabled=bool(
            context.preference
            and context.preference.get("use_calendar_busy_time") is True
        ),
    )
    authoritative_by_day = _authoritative_intervals_by_day(
        intervals=authoritative.intervals,
        days=authoritative_day_values,
        zone=zone,
    )
    result: list[PlannerAttentionItem] = []
    current_study = _study_rhythm(context.study_setup)
    current_study_revision = current_study[0] if current_study else None
    for detail in deadline_response.plans:
        revision = detail.active_revision
        pending = detail.pending_revision
        for reason in detail.plan.attention_reasons:
            if reason in {
                "commitment_conflict",
                "target_released",
                "unplaced_minutes",
            }:
                continue
            result.append(
                PlannerAttentionItem(
                    id=f"deadline:{detail.plan.id}:persisted:{reason}",
                    kind=(
                        "study_rhythm_changed"
                        if reason == "study_rhythm_changed"
                        else "stale_preview"
                    ),
                    target="plan",
                    title=detail.plan.title,
                    detail=_attention_detail(reason, preparation=True),
                    plan_id=detail.plan.id,
                    unplaced_minutes=0,
                ),
            )
        if pending is not None and pending.unscheduled_minutes:
            result.append(
                PlannerAttentionItem(
                    id=(f"deadline:{detail.plan.id}:unscheduled:{pending.revision}"),
                    kind="unscheduled",
                    target="plan",
                    title=detail.plan.title,
                    detail=(
                        f"{pending.unscheduled_minutes} preparation minutes "
                        "could not be placed."
                    ),
                    plan_id=detail.plan.id,
                    unplaced_minutes=pending.unscheduled_minutes,
                ),
            )
        if (
            pending is not None
            and pending.study_setup_revision != current_study_revision
            and "study_rhythm_changed" not in detail.plan.attention_reasons
        ):
            result.append(
                PlannerAttentionItem(
                    id=(f"deadline:{detail.plan.id}:study-stale:{pending.revision}"),
                    kind="stale_preview",
                    target="plan",
                    title=detail.plan.title,
                    detail=(
                        "The Study rhythm changed. Create a new preparation "
                        "preview before confirming."
                    ),
                    plan_id=detail.plan.id,
                    unplaced_minutes=0,
                ),
            )
        if revision is None:
            continue
        if revision.unscheduled_minutes:
            result.append(
                PlannerAttentionItem(
                    id=(f"deadline:{detail.plan.id}:unscheduled:{revision.revision}"),
                    kind="unscheduled",
                    target="plan",
                    title=detail.plan.title,
                    detail=(
                        f"{revision.unscheduled_minutes} preparation minutes "
                        "could not be placed."
                    ),
                    plan_id=detail.plan.id,
                    unplaced_minutes=revision.unscheduled_minutes,
                ),
            )
        for source in _deadline_revision_conflict_sources(
            revision=revision,
            authoritative_by_day=authoritative_by_day,
            zone=zone,
            generated_at=generated_at,
        ):
            result.append(
                PlannerAttentionItem(
                    id=(
                        f"deadline:{detail.plan.id}:current-conflict:{source}:"
                        f"{revision.revision}"
                    ),
                    kind="conflict",
                    target="plan",
                    title=detail.plan.title,
                    detail=_conflict_detail(source, preparation=True),
                    plan_id=detail.plan.id,
                    unplaced_minutes=0,
                    conflict_source=source,
                ),
            )
        deadline_candidate_days = _deadline_revision_candidate_days(
            revision=revision,
            zone=zone,
            generated_at=generated_at,
        )
        invalid_setup_occurrences = [
            occurrence
            for occurrence in authoritative.invalid_setup_occurrences
            if deadline_candidate_days.intersection(occurrence.affected_days)
        ]
        invalid_fixed_commitment_occurrences = [
            occurrence
            for occurrence in authoritative.invalid_fixed_commitment_occurrences
            if deadline_candidate_days.intersection(occurrence.affected_days)
        ]
        invalid_occurrences = [
            *invalid_setup_occurrences,
            *invalid_fixed_commitment_occurrences,
        ]
        if invalid_occurrences:
            result.append(
                PlannerAttentionItem(
                    id=(
                        f"deadline:{detail.plan.id}:local-time-invalid:"
                        f"{revision.revision}"
                    ),
                    kind="stale_preview",
                    target="plan",
                    title=detail.plan.title,
                    detail=_invalid_recurrence_detail(
                        invalid_occurrences,
                        timezone=context.timezone,
                    ),
                    plan_id=detail.plan.id,
                    unplaced_minutes=0,
                ),
            )
        if (
            revision.study_setup_revision != current_study_revision
            and "study_rhythm_changed" not in detail.plan.attention_reasons
        ):
            result.append(
                PlannerAttentionItem(
                    id=(f"deadline:{detail.plan.id}:study-changed:{revision.revision}"),
                    kind="study_rhythm_changed",
                    target="plan",
                    title=detail.plan.title,
                    detail=(
                        "The Study rhythm changed. Review and confirm a new "
                        "preparation preview before reservations change."
                    ),
                    plan_id=detail.plan.id,
                    unplaced_minutes=0,
                ),
            )
    return result


_ConflictSource = Literal["setup", "fixed_commitment", "calendar"]


@dataclass(frozen=True)
class _AuthoritativeInterval:
    starts_at: datetime
    ends_at: datetime
    source: _ConflictSource


_InvalidRecurrenceSource = Literal["habit", "setup", "fixed_commitment"]


@dataclass(frozen=True)
class _InvalidRecurrence:
    source: _InvalidRecurrenceSource
    local_date: date
    local_time: time
    reason: str
    affected_days: frozenset[date]


@dataclass(frozen=True)
class _AuthoritativeProjection:
    intervals: tuple[_AuthoritativeInterval, ...]
    invalid_setup_occurrences: tuple[_InvalidRecurrence, ...]
    invalid_fixed_commitment_occurrences: tuple[_InvalidRecurrence, ...]


@dataclass(frozen=True)
class _ActionConflictScan:
    sources: tuple[_ConflictSource, ...]
    invalid_habit_occurrences: tuple[_InvalidRecurrence, ...]
    candidate_days: frozenset[date]


def _authoritative_intervals_by_day(
    *,
    intervals: Sequence[_AuthoritativeInterval],
    days: Sequence[date],
    zone: ZoneInfo,
) -> dict[date, tuple[_AuthoritativeInterval, ...]]:
    requested = set(days)
    if not requested:
        return {}
    first_requested = min(requested)
    last_requested = max(requested)
    values: dict[date, list[_AuthoritativeInterval]] = {day: [] for day in requested}
    for interval in intervals:
        first = max(interval.starts_at.astimezone(zone).date(), first_requested)
        inclusive_end = interval.ends_at.astimezone(UTC) - timedelta(microseconds=1)
        last = min(inclusive_end.astimezone(zone).date(), last_requested)
        if last < first:
            continue
        for offset in range((last - first).days + 1):
            candidate = first + timedelta(days=offset)
            if candidate in requested:
                values[candidate].append(interval)
    return {
        day: tuple(
            sorted(
                day_intervals,
                key=lambda interval: (
                    interval.starts_at,
                    interval.ends_at,
                    interval.source,
                ),
            ),
        )
        for day, day_intervals in values.items()
    }


def _authoritative_intervals(
    *,
    context: PlannerOverviewContext,
    days: Sequence[date],
    zone: ZoneInfo,
    calendar_enabled: bool,
) -> _AuthoritativeProjection:
    intervals: list[_AuthoritativeInterval] = []
    invalid_setup_occurrences: list[_InvalidRecurrence] = []
    invalid_fixed_commitment_occurrences: list[_InvalidRecurrence] = []
    for row in context.schedule_items:
        weekday = _int(row.get("weekday"))
        starts = _time(row.get("starts_at"))
        ends = _time(row.get("ends_at"))
        for day in days:
            if day.isoweekday() == weekday and recurring_commitment_applies_on(
                row,
                day,
            ):
                try:
                    resolved = resolve_local_interval(
                        local_date=day,
                        starts_at=starts,
                        ends_at=ends,
                        zone=zone,
                        source_id=f"setup:{row.get('id', weekday)}",
                    )
                except LocalTimeResolutionError as error:
                    invalid_setup_occurrences.append(
                        _invalid_recurrence(
                            source="setup",
                            anchor_day=day,
                            starts_at=starts,
                            ends_at=ends,
                            error=error,
                        ),
                    )
                    continue
                intervals.append(
                    _AuthoritativeInterval(*resolved, source="setup"),
                )
    for row in context.commitments:
        if row.get("status") != "active":
            continue
        if row.get("recurrence") == "one_off":
            intervals.append(
                _AuthoritativeInterval(
                    _datetime(row.get("starts_at")),
                    _datetime(row.get("ends_at")),
                    "fixed_commitment",
                ),
            )
        else:
            weekday = _int(row.get("weekday"))
            starts = _time(row.get("local_starts_at"))
            ends = _time(row.get("local_ends_at"))
            for day in days:
                if day.isoweekday() == weekday:
                    try:
                        resolved = resolve_local_interval(
                            local_date=day,
                            starts_at=starts,
                            ends_at=ends,
                            zone=zone,
                            source_id=(
                                f"planner-commitment:{row.get('id', weekday)}"
                            ),
                        )
                    except LocalTimeResolutionError as error:
                        invalid_fixed_commitment_occurrences.append(
                            _invalid_recurrence(
                                source="fixed_commitment",
                                anchor_day=day,
                                starts_at=starts,
                                ends_at=ends,
                                error=error,
                            ),
                        )
                        continue
                    intervals.append(
                        _AuthoritativeInterval(
                            *resolved,
                            source="fixed_commitment",
                        ),
                    )
    if calendar_enabled and context.calendar.available:
        intervals.extend(
            _AuthoritativeInterval(
                _datetime(row.get("starts_at")),
                _datetime(row.get("ends_at")),
                "calendar",
            )
            for row in context.calendar.timed_events
            if row.get("busy_status") == "busy"
        )
        for row in context.calendar.all_day_events:
            if row.get("busy_status") != "busy":
                continue
            starts_on = _date(row.get("starts_on"))
            ends_on = _date(row.get("ends_on"))
            intervals.append(
                _AuthoritativeInterval(
                    resolve_local_datetime(
                        local_date=starts_on,
                        local_time=time.min,
                        zone=zone,
                        source_id=f"calendar-all-day:{row.get('id', starts_on)}",
                    ),
                    resolve_local_datetime(
                        local_date=ends_on,
                        local_time=time.min,
                        zone=zone,
                        source_id=f"calendar-all-day:{row.get('id', starts_on)}",
                    ),
                    "calendar",
                ),
            )
    return _AuthoritativeProjection(
        intervals=tuple(intervals),
        invalid_setup_occurrences=_dedupe_invalid_recurrences(
            invalid_setup_occurrences,
        ),
        invalid_fixed_commitment_occurrences=_dedupe_invalid_recurrences(
            invalid_fixed_commitment_occurrences,
        ),
    )


def _revision_conflict_sources(
    *,
    plan_id: UUID,
    revision: PlannerActionRevision,
    days: Sequence[date],
    zone: ZoneInfo,
    authoritative_by_day: Mapping[
        date,
        Sequence[_AuthoritativeInterval],
    ],
) -> _ActionConflictScan:
    del plan_id
    candidates: list[tuple[datetime, datetime]] = []
    candidate_days: set[date] = set()
    invalid_habit_occurrences: list[_InvalidRecurrence] = []
    for block in revision.task_blocks:
        if block.state != "active" or block.local_date not in days:
            continue
        candidates.append((block.starts_at, block.reserved_ends_at))
        candidate_days.update(
            _interval_local_days(
                starts_at=block.starts_at,
                ends_at=block.reserved_ends_at,
                zone=zone,
            ),
        )
    for slot in revision.habit_slots:
        if slot.state != "active":
            continue
        for day in days:
            if day.isoweekday() != slot.weekday:
                continue
            candidate_days.update(
                _wall_interval_local_days(
                    local_date=day,
                    starts_at=slot.starts_at,
                    ends_at=slot.ends_at,
                ),
            )
            try:
                candidates.append(
                    resolve_local_interval(
                        local_date=day,
                        starts_at=slot.starts_at,
                        ends_at=slot.ends_at,
                        zone=zone,
                        source_id=f"planner-habit-slot:{slot.id}",
                    ),
                )
            except LocalTimeResolutionError as error:
                invalid_habit_occurrences.append(
                    _invalid_recurrence(
                        source="habit",
                        anchor_day=day,
                        starts_at=slot.starts_at,
                        ends_at=slot.ends_at,
                        error=error,
                    ),
                )
    sources: set[_ConflictSource] = set()
    for start, end in candidates:
        for local_day in _interval_local_days(
            starts_at=start,
            ends_at=end,
            zone=zone,
        ):
            for busy in authoritative_by_day.get(local_day, ()):
                if busy.starts_at >= end:
                    break
                if max(start, busy.starts_at) < min(end, busy.ends_at):
                    sources.add(busy.source)
        if len(sources) == 3:
            break
    return _ActionConflictScan(
        sources=tuple(
            sorted(sources, key=("setup", "fixed_commitment", "calendar").index),
        ),
        invalid_habit_occurrences=_dedupe_invalid_recurrences(
            invalid_habit_occurrences,
        ),
        candidate_days=frozenset(candidate_days),
    )


def _interval_local_days(
    *,
    starts_at: datetime,
    ends_at: datetime,
    zone: ZoneInfo,
) -> tuple[date, ...]:
    first = starts_at.astimezone(zone).date()
    last = (ends_at.astimezone(UTC) - timedelta(microseconds=1)).astimezone(zone).date()
    count = (last - first).days + 1
    if count < 1 or count > _MAX_ATTENTION_RESERVATION_DAYS:
        raise ValueError("Planner attention interval exceeds its local-day bound.")
    return tuple(first + timedelta(days=offset) for offset in range(count))


def _wall_interval_local_days(
    *,
    local_date: date,
    starts_at: time,
    ends_at: time,
) -> frozenset[date]:
    values = {local_date}
    if ends_at <= starts_at:
        values.add(local_date + timedelta(days=1))
    return frozenset(values)


def _invalid_recurrence(
    *,
    source: _InvalidRecurrenceSource,
    anchor_day: date,
    starts_at: time,
    ends_at: time,
    error: LocalTimeResolutionError,
) -> _InvalidRecurrence:
    return _InvalidRecurrence(
        source=source,
        local_date=error.local_date,
        local_time=error.local_time,
        reason=error.reason,
        affected_days=_wall_interval_local_days(
            local_date=anchor_day,
            starts_at=starts_at,
            ends_at=ends_at,
        ),
    )


def _dedupe_invalid_recurrences(
    values: Iterable[_InvalidRecurrence],
) -> tuple[_InvalidRecurrence, ...]:
    unique = {
        (
            value.source,
            value.local_date,
            value.local_time,
            value.reason,
            tuple(sorted(value.affected_days)),
        ): value
        for value in values
    }
    return tuple(
        unique[key]
        for key in sorted(
            unique,
            key=lambda value: (value[1], value[2], value[0], value[3], value[4]),
        )
    )


def _deadline_revision_candidate_days(
    *,
    revision: DeadlinePlanRevision,
    zone: ZoneInfo,
    generated_at: datetime,
) -> frozenset[date]:
    values: set[date] = set()
    for block in revision.blocks:
        if (
            block.state not in {"upcoming", "partial"}
            or block.reserved_ends_at <= generated_at
        ):
            continue
        values.update(
            _interval_local_days(
                starts_at=block.starts_at,
                ends_at=block.reserved_ends_at,
                zone=zone,
            ),
        )
    return frozenset(values)


def _deadline_revision_conflict_sources(
    *,
    revision: DeadlinePlanRevision,
    authoritative_by_day: Mapping[
        date,
        Sequence[_AuthoritativeInterval],
    ],
    zone: ZoneInfo,
    generated_at: datetime,
) -> list[_ConflictSource]:
    sources: set[_ConflictSource] = set()
    for block in revision.blocks:
        if (
            block.state not in {"upcoming", "partial"}
            or block.reserved_ends_at <= generated_at
        ):
            continue
        for local_day in _interval_local_days(
            starts_at=block.starts_at,
            ends_at=block.reserved_ends_at,
            zone=zone,
        ):
            for busy in authoritative_by_day.get(local_day, ()):
                if busy.starts_at >= block.reserved_ends_at:
                    break
                if max(block.starts_at, busy.starts_at) < min(
                    block.reserved_ends_at,
                    busy.ends_at,
                ):
                    sources.add(busy.source)
        if len(sources) == 3:
            break
    return sorted(sources, key=("setup", "fixed_commitment", "calendar").index)


@dataclass(frozen=True)
class _PlannerHistoryProjection:
    item: PlannerHistoryItem
    required: bool
    created_at: datetime
    source_order: int


def _target_overview_items(
    *,
    context: PlannerOverviewContext,
    plans: Sequence[PlannerActionPlan],
) -> tuple[
    list[PlannerTaskSummary],
    list[PlannerHabitSummary],
    list[PlannerUnscheduledTask],
    list[PlannerHistoryItem],
]:
    plan_by_target: dict[tuple[str, str], PlannerActionPlan] = {}
    for plan in plans:
        key = (plan.target_kind, str(plan.target_id))
        if key in plan_by_target:
            raise ValueError("Planner target has more than one action plan.")
        plan_by_target[key] = plan

    task_targets: list[PlannerTaskSummary] = []
    habits: list[PlannerHabitSummary] = []
    unscheduled_tasks: list[PlannerUnscheduledTask] = []
    history_candidates: list[_PlannerHistoryProjection] = []
    known: set[tuple[str, str]] = set()
    history_source_order = 0

    for row in context.tasks:
        target_id = _target_identity(row, kind="task", known=known)
        if _is_deadline_managed_task(row):
            continue
        plan = _persisted_target_plan(
            plan_by_target=plan_by_target,
            kind="task",
            target_id=target_id,
        )
        if row.get("status") not in {"todo", "in_progress"}:
            if plan is not None and not planner_task_plan_is_released(plan):
                raise ValueError(
                    "Historical Planner Task has a non-released action plan."
                )
            history_candidates.append(
                _history_projection(
                    row=row,
                    plan=plan,
                    source_order=history_source_order,
                    item=PlannerHistoryItem(
                        id=UUID(target_id),
                        kind="task",
                        title=_title(row),
                    ),
                ),
            )
            history_source_order += 1
            continue
        summary_values = _task_summary(row)
        task_summary = PlannerTaskSummary(
            id=UUID(target_id),
            title=_title(row),
            **summary_values,
        )
        task_targets.append(task_summary)
        if planner_active_task_minutes(plan) > 0:
            continue
        unscheduled_tasks.append(
            PlannerUnscheduledTask(
                **task_summary.model_dump(),
                reason=planner_unscheduled_task_reason(task_summary, plan),
            ),
        )

    for row in context.habits:
        target_id = _target_identity(row, kind="habit", known=known)
        plan = _persisted_target_plan(
            plan_by_target=plan_by_target,
            kind="habit",
            target_id=target_id,
        )
        metadata = row.get("metadata")
        if not isinstance(metadata, dict):
            raise ValueError("Habit metadata is invalid.")
        active = (
            row.get("active") is True
            and metadata.get("lifecycle", "active") == "active"
        )
        if not active:
            if plan is not None and not planner_plan_is_released_or_cancelled(plan):
                raise ValueError(
                    "Historical Planner Habit has a non-released action plan."
                )
            history_candidates.append(
                _history_projection(
                    row=row,
                    plan=plan,
                    source_order=history_source_order,
                    item=PlannerHistoryItem(
                        id=UUID(target_id),
                        kind="habit",
                        title=_title(row),
                    ),
                ),
            )
            history_source_order += 1
            continue
        definition = _habit_definition_from_row(row)
        active_duration = (
            plan.active_revision.target.duration_minutes
            if plan is not None
            and plan.active_revision is not None
            and isinstance(plan.active_revision.target, PlannerHabitTarget)
            else None
        )
        duration = _optional_int(metadata.get("planner_duration_minutes"))
        habits.append(
            PlannerHabitSummary(
                id=UUID(target_id),
                title=_title(row),
                description=_optional_description(row),
                expected_updated_at=_datetime(row.get("updated_at")),
                ownership=(
                    "setup" if metadata.get("managed_by") == "setup" else "manual"
                ),
                cadence=definition["cadence"],
                duration_minutes=duration if duration is not None else active_duration,
                planning_status=(
                    "scheduled"
                    if plan is not None and _active_habit_slot_count(plan) > 0
                    else "unplanned"
                ),
                plan_id=plan.id if plan is not None else None,
                has_pending_preview=(
                    plan is not None and plan.pending_revision is not None
                ),
            ),
        )

    unscheduled_tasks.sort(key=lambda item: (item.title.casefold(), str(item.id)))
    history_candidates.sort(
        key=lambda candidate: (
            not candidate.required,
            candidate.created_at,
            str(candidate.item.id),
            candidate.item.kind,
            candidate.source_order,
        ),
    )
    required_history_count = sum(
        1 for candidate in history_candidates if candidate.required
    )
    if required_history_count > 1_000:
        raise ValueError(
            "Required Planner history targets exceed the overview bound.",
        )
    history = [candidate.item for candidate in history_candidates[:1_000]]
    task_targets = task_targets[:1_000]
    habits = habits[:1_000]
    projected_task_ids = {item.id for item in task_targets}
    unscheduled_tasks = [
        item for item in unscheduled_tasks if item.id in projected_task_ids
    ][:1_000]
    represented_targets = {
        *(("task", str(item.id)) for item in task_targets),
        *(("habit", str(item.id)) for item in habits),
        *((item.kind, str(item.id)) for item in history),
    }
    for plan in plans:
        if planner_plan_is_pending_create(
            plan
        ) or planner_plan_is_cancelled_tombstone(plan):
            continue
        if (plan.target_kind, str(plan.target_id)) not in represented_targets:
            raise ValueError(
                "Persisted Planner action plan has no target projection.",
            )
    return (
        task_targets,
        habits,
        unscheduled_tasks,
        history,
    )


def _history_projection(
    *,
    row: Mapping[str, Any],
    plan: PlannerActionPlan | None,
    source_order: int,
    item: PlannerHistoryItem,
) -> _PlannerHistoryProjection:
    created_at_value = row.get("created_at")
    return _PlannerHistoryProjection(
        item=item,
        required=(
            plan is not None
            and not planner_plan_is_pending_create(plan)
            and not planner_plan_is_cancelled_tombstone(plan)
        ),
        created_at=(
            _datetime(created_at_value)
            if created_at_value is not None
            else datetime.max.replace(tzinfo=UTC)
        ),
        source_order=source_order,
    )


def _persisted_target_plan(
    *,
    plan_by_target: Mapping[tuple[str, str], PlannerActionPlan],
    kind: Literal["task", "habit"],
    target_id: str,
) -> PlannerActionPlan | None:
    plan = plan_by_target.get((kind, target_id))
    if (
        plan is not None
        and planner_plan_is_pending_create(plan)
    ):
        raise ValueError("Persisted Planner target is bound to a create preview.")
    return plan


def _target_identity(
    row: Mapping[str, Any],
    *,
    kind: Literal["task", "habit"],
    known: set[tuple[str, str]],
) -> str:
    target_id = str(row.get("id"))
    key = (kind, target_id)
    if target_id == "None" or key in known:
        raise ValueError("Planner target overview projection is invalid.")
    known.add(key)
    return target_id


def _is_deadline_managed_task(row: Mapping[str, Any]) -> bool:
    metadata = row.get("metadata")
    if metadata is None:
        metadata = {}
    if not isinstance(metadata, dict):
        raise ValueError("Planner Task metadata is invalid.")
    return row.get("source") == "deadline-plan-v1" or (
        metadata.get("contract_version") == "deadline-plan-v1"
    )


def _active_task_minutes(plan: PlannerActionPlan) -> int:
    revision = plan.active_revision
    if revision is None or not isinstance(revision.target, PlannerTaskTarget):
        return 0
    return sum(
        block.planned_minutes
        for block in revision.task_blocks
        if block.state == "active"
    )


def _active_habit_slot_count(plan: PlannerActionPlan) -> int:
    revision = plan.active_revision
    if revision is None or not isinstance(revision.target, PlannerHabitTarget):
        return 0
    return sum(
        1
        for slot in revision.habit_slots
        if slot.state == "active" and slot.duration_minutes > 0
    )


def _optional_description(row: Mapping[str, Any]) -> str | None:
    description = row.get("description")
    if description is not None and not isinstance(description, str):
        raise ValueError("Planner target description is invalid.")
    return description


def _task_summary(row: Mapping[str, Any]) -> dict[str, Any]:
    updated_at = _datetime(row.get("updated_at"))
    metadata = row.get("metadata")
    if metadata is None:
        metadata = {}
    if not isinstance(metadata, dict):
        raise ValueError("Planner Task metadata is invalid.")
    return {
        "expected_updated_at": updated_at,
        "description": _optional_description(row),
        "priority": row.get("priority"),
        "estimated_minutes": _optional_int(row.get("estimated_minutes")),
        "deadline_at": _optional_datetime(row.get("deadline")),
        "preferred_session_minutes": _optional_int(
            metadata.get("preferred_session_minutes"),
        ),
        "use_study_rhythm": metadata.get("use_study_rhythm") is True,
    }


def _validate_context_bounds(context: PlannerAvailabilityContext) -> None:
    values = (
        (context.schedule_items, 1_000, "Setup commitments"),
        (context.commitments, 1_000, "Planner commitments"),
        (context.task_blocks, 10_000, "Task reservations"),
        (context.habit_slots, 1_000, "Habit reservations"),
        (context.deadline_blocks, 10_000, "Preparation reservations"),
        (context.calendar.timed_events, 2_000, "Calendar events"),
        (context.calendar.all_day_events, 2_000, "Calendar events"),
    )
    for rows, maximum, label in values:
        if len(rows) > maximum:
            raise PlannerConflictError(f"{label} exceed the Planner bound.")


def _validate_overview_bounds(context: PlannerOverviewContext) -> None:
    values = (
        (context.schedule_items, 1_000, "Setup commitments"),
        (context.commitments, 1_000, "Planner commitments"),
        (context.tasks, 1_000, "Tasks"),
        (context.habits, 1_000, "Habits"),
        (context.calendar.timed_events, 2_000, "Calendar events"),
        (context.calendar.all_day_events, 2_000, "Calendar events"),
    )
    for rows, maximum, label in values:
        if len(rows) > maximum:
            raise PlannerConflictError(f"{label} exceed the Planner overview bound.")


def _require_matching_request(
    row: Mapping[str, Any],
    *,
    user_id: str,
    operation: str,
    resource_id: UUID,
    fingerprint: str,
) -> None:
    if (
        row.get("user_id") != user_id
        or row.get("operation") != operation
        or str(row.get("resource_id")) != str(resource_id)
        or row.get("request_fingerprint") != fingerprint
    ):
        raise PlannerConflictError(
            "request_id is already bound to another Planner operation.",
        )


def _stable_rows(rows: Iterable[Mapping[str, Any]]) -> list[dict[str, Any]]:
    values = [
        {str(key): _json_value(value) for key, value in sorted(row.items())}
        for row in rows
    ]
    values.sort(key=lambda row: json.dumps(row, sort_keys=True, separators=(",", ":")))
    return values


def _json_value(value: Any) -> Any:
    if isinstance(value, (datetime, date, time, UUID)):
        return value.isoformat() if hasattr(value, "isoformat") else str(value)
    if isinstance(value, dict):
        return {str(key): _json_value(item) for key, item in sorted(value.items())}
    if isinstance(value, list):
        return [_json_value(item) for item in value]
    return value


def _fingerprint(value: Mapping[str, Any]) -> str:
    encoded = json.dumps(
        _json_value(dict(value)),
        sort_keys=True,
        separators=(",", ":"),
        ensure_ascii=False,
    ).encode()
    return hashlib.sha256(encoded).hexdigest()


def _attention_detail(reason: str, *, preparation: bool = False) -> str:
    noun = "preparation preview" if preparation else "preview"
    return {
        "target_changed": f"The target changed. Create a new {noun}.",
        "calendar_changed": f"Calendar busy time changed. Create a new {noun}.",
        "timezone_changed": (
            f"The account timezone changed. Create and confirm a new {noun}."
        ),
        "study_rhythm_changed": (
            f"The Study rhythm changed. Create and confirm a new {noun}."
        ),
    }.get(reason, f"This plan needs a new {noun} before its times can be trusted.")


def _unplaced_detail(revision: PlannerActionRevision) -> str:
    assert revision.unscheduled_minutes > 0
    missing_inputs = isinstance(revision.target, PlannerTaskTarget) and any(
        value is None
        for value in (
            revision.target.estimated_minutes,
            revision.target.deadline_at,
            revision.target.preferred_session_minutes,
        )
    )
    return (
        f"{revision.unscheduled_minutes} minutes still need scheduling inputs."
        if missing_inputs
        else f"{revision.unscheduled_minutes} minutes could not be placed."
    )


def _conflict_detail(
    source: _ConflictSource,
    *,
    preparation: bool,
) -> str:
    noun = "preparation plan" if preparation else "plan"
    source_copy = {
        "setup": "A current Setup commitment",
        "fixed_commitment": "A current fixed commitment",
        "calendar": "A current imported Calendar event",
    }[source]
    return f"{source_copy} overlaps this {noun}. Nothing moved automatically."


def _invalid_recurrence_detail(
    values: Sequence[_InvalidRecurrence],
    *,
    timezone: str,
) -> str:
    contexts = sorted(
        {
            (value.source, value.local_date, value.local_time, value.reason)
            for value in values
        },
        key=lambda value: (value[1], value[2], value[0], value[3]),
    )
    source_copy = {
        "habit": "Saved Habit",
        "setup": "Weekly Setup",
        "fixed_commitment": "Weekly fixed commitment",
    }
    sources = sorted(
        {source for source, _, _, _ in contexts},
        key=("habit", "setup", "fixed_commitment").index,
    )
    labels = ", ".join(source_copy[source] for source in sources)
    _, first_day, first_time, first_reason = contexts[0]
    occurrence_copy = (
        "That invalid occurrence was"
        if len(contexts) == 1
        else f"All {len(contexts)} invalid occurrences were"
    )
    return (
        f"Invalid recurring times ({labels}) include {first_day.isoformat()} "
        f"{first_time.isoformat(timespec='minutes')} ({first_reason}) in {timezone}. "
        f"{occurrence_copy} omitted; nothing moved automatically."
    )


def _kind_order(value: str) -> int:
    return {
        "setup_commitment": 0,
        "manual_commitment": 1,
        "task_block": 2,
        "habit_slot": 3,
        "preparation": 4,
        "calendar_event": 5,
    }[value]


def _title_map(rows: Sequence[Mapping[str, Any]]) -> dict[str, str]:
    result: dict[str, str] = {}
    for row in rows:
        key = str(row.get("id"))
        if key == "None" or key in result:
            raise ValueError("Planner target title projection is invalid.")
        result[key] = _title(row)
    return result


def _title(row: Mapping[str, Any]) -> str:
    value = row.get("title")
    if not isinstance(value, str) or not value or value.strip() != value:
        raise ValueError("Planner source title is invalid.")
    return value


def _occurrence_id(prefix: str, source_id: UUID, day: date) -> UUID:
    return uuid5(
        NAMESPACE_URL,
        f"{PLANNER_CONTRACT_VERSION}:{prefix}:{source_id}:{day.isoformat()}",
    )


def _aware_utc(value: datetime) -> datetime:
    if value.tzinfo is None or value.utcoffset() is None:
        raise ValueError("Planner clock must be timezone-aware.")
    return value.astimezone(UTC)


def _zone(value: str) -> ZoneInfo:
    try:
        return ZoneInfo(value)
    except ZoneInfoNotFoundError as exc:
        raise ValueError("Planner profile timezone is invalid.") from exc


def _datetime(value: Any) -> datetime:
    if isinstance(value, datetime):
        result = value
    elif isinstance(value, str):
        result = datetime.fromisoformat(value.replace("Z", "+00:00"))
    else:
        raise ValueError("Planner timestamp is invalid.")
    if result.tzinfo is None or result.utcoffset() is None:
        raise ValueError("Planner timestamp must be timezone-aware.")
    return result


def _optional_datetime(value: Any) -> datetime | None:
    return None if value is None else _datetime(value)


def _date(value: Any) -> date:
    if isinstance(value, datetime):
        raise ValueError("Planner date is invalid.")
    if isinstance(value, date):
        return value
    if isinstance(value, str):
        return date.fromisoformat(value)
    raise ValueError("Planner date is invalid.")


def _time(value: Any) -> time:
    if isinstance(value, time):
        result = value
    elif isinstance(value, str):
        result = time.fromisoformat(value)
    else:
        raise ValueError("Planner time is invalid.")
    if result.tzinfo is not None:
        raise ValueError("Planner wall-clock time must not contain a timezone.")
    return result


def _optional_time(value: Any) -> time | None:
    return None if value is None else _time(value)


def _int(value: Any) -> int:
    if isinstance(value, bool) or not isinstance(value, int):
        raise ValueError("Planner integer projection is invalid.")
    return value


def _optional_int(value: Any) -> int | None:
    return None if value is None else _int(value)
