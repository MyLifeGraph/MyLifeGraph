from __future__ import annotations

from dataclasses import dataclass
from datetime import UTC, date, datetime, timedelta
from typing import Any
from uuid import UUID, uuid5
from zoneinfo import ZoneInfo

from app.models.deadline_plans import DeadlinePlanProposalRequest
from app.models.multi_exam_plans import MultiExamPlanBlock, MultiExamPlanItem
from app.models.planning_timing import PlanningTimingProvenance
from app.repositories.deadline_plan_repository import DeadlinePlanningContext
from app.repositories.multi_exam_plan_repository import MultiExamPlanSnapshot
from app.repositories.planning_writes import DeadlineBlockWrite, DeadlineProposalWrite
from app.services.deadline_plan_builder import _fingerprint, _timing_preference_from_row
from app.services.deadline_plan_credit import deadline_block_credits
from app.services.planning_availability import BusySources, busy_intervals_by_day


MULTI_EXAM_BALANCE_NAMESPACE = UUID("9a4f48e5-5c25-4d4b-a343-8a61b9b8d431")
MAX_MULTI_EXAM_CHANGED_PLANS = 8
MAX_MULTI_EXAM_SEARCH_NODES = 100_000


@dataclass(frozen=True, slots=True)
class MultiExamCandidate:
    plan_id: UUID
    row: dict[str, Any]
    deadline_at: datetime
    remaining_minutes: int

    @property
    def priority(self) -> tuple[datetime, int, str]:
        return (self.deadline_at, -self.remaining_minutes, str(self.plan_id))


@dataclass(frozen=True, slots=True)
class PreparedMultiExamItem:
    candidate: MultiExamCandidate
    request: DeadlinePlanProposalRequest
    request_fingerprint: str
    write: DeadlineProposalWrite
    current_blocks: tuple[MultiExamPlanBlock, ...]

    @property
    def changed(self) -> bool:
        proposed = tuple(_review_block(block) for block in self.write.blocks)
        return _change_summary(self.current_blocks, proposed) != {
            "retained_minutes": sum(
                block.effective_minutes for block in self.current_blocks
            ),
            "added_minutes": 0,
            "shifted_minutes": 0,
            "removed_minutes": 0,
            "retained_block_count": len(self.current_blocks),
            "added_block_count": 0,
            "shifted_block_count": 0,
            "removed_block_count": 0,
        }

    def child_payload(self) -> dict[str, Any]:
        review = build_review_item(self)
        confirm_request_id = uuid5(
            MULTI_EXAM_BALANCE_NAMESPACE,
            f"{self.request.request_id}:{self.candidate.plan_id}:confirm",
        )
        confirm_fingerprint = _fingerprint(
            {
                "contract_version": "deadline-plan-v1",
                "operation": "confirm",
                "plan_id": str(self.candidate.plan_id),
                "expected_revision": self.request.base_revision + 1,
            },
        )
        return {
            "plan_id": str(self.candidate.plan_id),
            "request_id": str(self.request.request_id),
            "request_fingerprint": self.request_fingerprint,
            "confirm_request_id": str(confirm_request_id),
            "confirm_request_fingerprint": confirm_fingerprint,
            "base_revision": self.request.base_revision,
            "proposal": self.write.proposal_json(),
            "blocks": self.write.blocks_json(),
            "review": review.model_dump(mode="json"),
        }


def candidates(snapshot: MultiExamPlanSnapshot) -> list[MultiExamCandidate]:
    tracked = {
        UUID(str(row.get("plan_id"))): _int(row.get("actual_minutes"))
        for row in snapshot.health.focus_totals
    }
    result: list[MultiExamCandidate] = []
    for raw in snapshot.active_plans:
        row = dict(raw)
        if row.get("kind") != "exam":
            continue
        plan_id = UUID(str(row.get("id")))
        estimate = _int(row.get("estimated_total_minutes"))
        credit = _int(row.get("credited_prior_minutes"))
        remaining = max(0, estimate - credit - tracked.get(plan_id, 0))
        result.append(
            MultiExamCandidate(
                plan_id=plan_id,
                row=row,
                deadline_at=_datetime(row.get("deadline_at")).astimezone(UTC),
                remaining_minutes=remaining,
            ),
        )
    result.sort(key=lambda item: item.priority)
    return result


def require_target(
    snapshot: MultiExamPlanSnapshot,
    *,
    target_plan_id: UUID,
    expected_revision: int,
) -> MultiExamCandidate:
    matches = [item for item in candidates(snapshot) if item.plan_id == target_plan_id]
    if len(matches) != 1:
        raise ValueError("Selected Exam is unavailable.")
    target = matches[0]
    if _int(target.row.get("latest_revision")) != expected_revision:
        raise ValueError("Selected Exam changed. Reload before balancing.")
    if any(row.get("pending_revision") is not None for row in snapshot.active_plans):
        raise ValueError(
            "Confirm or discard existing preparation previews before balancing Exams.",
        )
    return target


def colliding_candidates(
    snapshot: MultiExamPlanSnapshot,
    *,
    target: MultiExamCandidate,
) -> list[MultiExamCandidate]:
    # Every active Exam remains an exact-search candidate. A reservation that
    # does not overlap the target's old window can still constrain a
    # higher-priority collider after redistribution. Even an Exam with no
    # current future block must not be heuristically removed: proving that it
    # cannot participate belongs to the exact evaluation, while the documented
    # node/changed-plan bounds fail closed if the full search is too large.
    return [
        candidate
        for candidate in candidates(snapshot)
        if candidate.plan_id != target.plan_id
    ]


def deadline_request(
    candidate: MultiExamCandidate,
    *,
    outer_request_id: UUID,
) -> DeadlinePlanProposalRequest:
    row = candidate.row
    plan_id = candidate.plan_id
    child_request_id = uuid5(
        MULTI_EXAM_BALANCE_NAMESPACE,
        f"{outer_request_id}:{plan_id}:proposal",
    )
    payload: dict[str, Any] = {
        "request_id": str(child_request_id),
        "plan_id": str(plan_id),
        "base_revision": _int(row.get("latest_revision")),
        "kind": "exam",
        "title": _text(row.get("title")),
        "deadline_at": _datetime(row.get("deadline_at")).isoformat(),
        "estimated_total_minutes": _int(row.get("estimated_total_minutes")),
        "credited_prior_minutes": _int(row.get("credited_prior_minutes")),
        "preferred_session_minutes": _int(row.get("preferred_session_minutes")),
        "max_daily_minutes": _int(row.get("max_daily_minutes")),
        "planning_start_on": _date(row.get("planning_start_on")).isoformat(),
        "buffer_days": _int(row.get("buffer_days")),
        "source_kind": _text(row.get("source_kind")),
        "use_calendar_availability": bool(row.get("use_calendar_availability")),
    }
    if row.get("source_kind") == "calendar_event":
        payload["source_calendar_event_id"] = str(
            UUID(str(row.get("source_calendar_event_id"))),
        )
        payload["source_calendar_event_fingerprint"] = _text(
            row.get("source_calendar_event_fingerprint"),
        )
    return DeadlinePlanProposalRequest.model_validate(payload)


def existing_plan_row(candidate: MultiExamCandidate) -> dict[str, Any]:
    row = candidate.row
    return {
        "id": str(candidate.plan_id),
        "kind": "exam",
        "status": "active",
        "latest_revision": _int(row.get("latest_revision")),
        "managed_task_id": str(candidate.plan_id),
        "first_activated_at": row.get("first_activated_at"),
    }


def timing_preference(candidate: MultiExamCandidate) -> PlanningTimingProvenance:
    return _timing_preference_from_row(candidate.row)


def planning_context(
    snapshot: MultiExamPlanSnapshot,
    *,
    candidate: MultiExamCandidate,
) -> DeadlinePlanningContext:
    health = snapshot.health
    preference = health.planner_preference
    use_calendar = preference.get("use_calendar_busy_time") is True
    imported = health.calendar_import
    zone = ZoneInfo(_text(health.profile.get("timezone")))
    start_day = max(health.local_today, _date(candidate.row.get("planning_start_on")))
    deadline_day = _datetime(candidate.row.get("deadline_at")).astimezone(zone).date()
    calendar_current = bool(
        imported is not None
        and imported.get("planning_status") == "current"
        and imported.get("timezone") == health.profile.get("timezone")
        and imported.get("profile_timezone_revision")
        == health.profile.get("timezone_revision")
        and _date(imported.get("window_starts_on")) <= start_day
        and _date(imported.get("window_ends_before")) > deadline_day
    )
    recurring = [
        {
            "id": row.get("id"),
            "weekday": row.get("weekday"),
            "starts_at": row.get("starts_at"),
            "ends_at": row.get("ends_at"),
        }
        for row in health.planner_habit_slots
    ]
    timed = [dict(row) for row in health.planner_task_blocks]
    for row in health.planner_commitments:
        if row.get("recurrence") == "weekly":
            recurring.append(
                {
                    "id": row.get("id"),
                    "weekday": row.get("weekday"),
                    "starts_at": row.get("local_starts_at"),
                    "ends_at": row.get("local_ends_at"),
                },
            )
        elif row.get("recurrence") == "one_off":
            timed.append(dict(row))
        else:
            raise ValueError("Exam balance Planner commitment is invalid.")
    source = candidate.row.get("source_calendar_event")
    return DeadlinePlanningContext(
        timezone=_text(health.profile.get("timezone")),
        best_energy_window=health.best_energy_window,
        schedule_items=[dict(row) for row in health.schedule_items],
        confirmed_blocks=[dict(row) for row in health.deadline_blocks],
        timed_calendar_events=[dict(row) for row in health.calendar_timed_events],
        all_day_calendar_events=[dict(row) for row in health.calendar_all_day_events],
        source_calendar_event=dict(source) if isinstance(source, dict) else None,
        calendar_availability_current=calendar_current,
        availability_connection_id=(
            UUID(str(imported.get("connection_id")))
            if use_calendar and calendar_current and imported is not None
            else None
        ),
        availability_import_id=(
            UUID(str(imported.get("import_id")))
            if use_calendar and calendar_current and imported is not None
            else None
        ),
        daily_preparation_budget_minutes=health.profile.get(
            "daily_preparation_budget_minutes",
        ),
        planner_recurring_commitments=recurring,
        planner_timed_intervals=timed,
        planner_use_calendar_busy_time=use_calendar,
        study_setup=(dict(health.study_setup) if health.study_setup else None),
    )


def retained_blocks(
    snapshot: MultiExamPlanSnapshot,
    *,
    candidate: MultiExamCandidate,
    outer_request_id: UUID,
) -> tuple[DeadlineBlockWrite, ...]:
    health = snapshot.health
    zone = ZoneInfo(_text(health.profile.get("timezone")))
    if (
        candidate.row.get("timezone") != zone.key
        or not _current_study_matches(snapshot, candidate)
        or not _current_calendar_matches(snapshot, candidate)
    ):
        return ()
    plan_blocks = sorted(
        _blocks_by_plan(snapshot).get(candidate.plan_id, ()),
        key=lambda row: (_datetime(row.get("starts_at")), str(row.get("id"))),
    )
    credits = deadline_block_credits(
        [dict(row) for row in plan_blocks],
        [
            dict(row)
            for row in health.focus_facts
            if str(row.get("plan_id")) == str(candidate.plan_id)
        ],
        tracked_focus_minutes_at_proposal=_int(
            candidate.row.get("tracked_focus_minutes_at_proposal"),
        ),
    )
    last_day = _last_preferred_day(candidate.row, zone)
    external_busy = _external_busy_by_day(snapshot, candidate.plan_id, plan_blocks)
    account_budget = health.profile.get("daily_preparation_budget_minutes")
    max_daily = _int(candidate.row.get("max_daily_minutes"))
    other_daily: dict[date, int] = {}
    for row in health.deadline_blocks:
        if str(row.get("plan_id")) == str(candidate.plan_id):
            continue
        day = _date(row.get("local_date"))
        other_daily[day] = other_daily.get(day, 0) + _int(row.get("planned_minutes"))
    retained_daily: dict[date, int] = {}
    retained: list[DeadlineBlockWrite] = []
    retained_total = 0
    for row in plan_blocks:
        block_id = str(row.get("id"))
        starts_at = _datetime(row.get("starts_at"))
        ends_at = _datetime(row.get("ends_at"))
        reserved_end = _datetime(row.get("reserved_ends_at"))
        local_day = _date(row.get("local_date"))
        minutes = _int(row.get("planned_minutes"))
        recovery = _int(row.get("recovery_minutes"))
        if (
            credits.get(block_id, 0) != 0
            or starts_at <= health.generated_at
            or local_day > last_day
            or reserved_end <= ends_at
            and recovery > 0
            or any(
                starts_at < busy_end and reserved_end > busy_start
                for busy_start, busy_end in external_busy.get(local_day, ())
            )
            or retained_daily.get(local_day, 0) + minutes > max_daily
            or retained_total + minutes > candidate.remaining_minutes
            or account_budget is not None
            and other_daily.get(local_day, 0)
            + retained_daily.get(local_day, 0)
            + minutes
            > account_budget
        ):
            continue
        retained_total += minutes
        retained_daily[local_day] = retained_daily.get(local_day, 0) + minutes
        retained.append(
            DeadlineBlockWrite(
                id=uuid5(
                    MULTI_EXAM_BALANCE_NAMESPACE,
                    f"{outer_request_id}:{candidate.plan_id}:retained:{block_id}",
                ),
                sequence=len(retained) + 1,
                starts_at=starts_at,
                ends_at=ends_at,
                recovery_minutes=recovery,
                reserved_ends_at=reserved_end,
                local_date=local_day,
                local_start_time=starts_at.astimezone(zone).time().replace(tzinfo=None),
                local_end_time=ends_at.astimezone(zone).time().replace(tzinfo=None),
                planned_minutes=minutes,
            ),
        )
    return tuple(retained)


def current_review_blocks(
    snapshot: MultiExamPlanSnapshot,
    candidate: MultiExamCandidate,
) -> tuple[MultiExamPlanBlock, ...]:
    plan_blocks = list(_blocks_by_plan(snapshot).get(candidate.plan_id, ()))
    credits = deadline_block_credits(
        [dict(row) for row in plan_blocks],
        [
            dict(row)
            for row in snapshot.health.focus_facts
            if str(row.get("plan_id")) == str(candidate.plan_id)
        ],
        tracked_focus_minutes_at_proposal=_int(
            candidate.row.get("tracked_focus_minutes_at_proposal"),
        ),
    )
    blocks = [
        row
        for row in plan_blocks
        if _datetime(row.get("starts_at")) >= snapshot.health.generated_at
        and credits.get(str(row.get("id")), 0) < _int(row.get("planned_minutes"))
    ]
    blocks.sort(key=lambda row: (_datetime(row.get("starts_at")), str(row.get("id"))))
    return tuple(
        MultiExamPlanBlock(
            id=UUID(str(row.get("id"))),
            sequence=index,
            starts_at=_datetime(row.get("starts_at")),
            ends_at=_datetime(row.get("ends_at")),
            recovery_minutes=_int(row.get("recovery_minutes")),
            reserved_ends_at=_datetime(row.get("reserved_ends_at")),
            local_date=_date(row.get("local_date")),
            planned_minutes=_int(row.get("planned_minutes")),
            credited_minutes=credits.get(str(row.get("id")), 0),
        )
        for index, row in enumerate(blocks, start=1)
    )


def as_confirmed_rows(item: PreparedMultiExamItem) -> tuple[dict[str, Any], ...]:
    return tuple(
        {
            "id": str(block.id),
            "plan_id": str(item.candidate.plan_id),
            "local_date": block.local_date.isoformat(),
            "planned_minutes": block.planned_minutes,
            "starts_at": block.starts_at,
            "ends_at": block.ends_at,
            "reserved_ends_at": block.reserved_ends_at,
            "recovery_minutes": block.recovery_minutes,
        }
        for block in item.write.blocks
    )


def build_review_item(item: PreparedMultiExamItem) -> MultiExamPlanItem:
    current = list(item.current_blocks)
    proposed = [_review_block(block) for block in item.write.blocks]
    summary = _change_summary(tuple(current), tuple(proposed))
    return MultiExamPlanItem(
        position=1,
        plan_id=item.candidate.plan_id,
        title=_text(item.candidate.row.get("title")),
        deadline_at=item.candidate.deadline_at,
        remaining_minutes=item.candidate.remaining_minutes,
        active_revision=_int(item.candidate.row.get("current_revision")),
        base_revision=item.request.base_revision,
        proposed_revision=item.request.base_revision + 1,
        current_blocks=current,
        proposed_blocks=proposed,
        **summary,
    )


def normalize_review_positions(
    prepared: list[PreparedMultiExamItem],
) -> list[dict[str, Any]]:
    ordered = sorted(prepared, key=lambda item: item.candidate.priority)
    result: list[dict[str, Any]] = []
    for position, item in enumerate(ordered, start=1):
        review = build_review_item(item).model_copy(update={"position": position})
        payload = item.child_payload()
        payload["review"] = review.model_dump(mode="json")
        result.append(payload)
    return result


def shifted_minutes(prepared: list[PreparedMultiExamItem]) -> int:
    return sum(build_review_item(item).shifted_minutes for item in prepared)


def subset_tie_key(
    prepared: list[PreparedMultiExamItem],
    *,
    target_plan_id: UUID,
) -> tuple[Any, ...]:
    additional = sorted(
        (
            item.candidate
            for item in prepared
            if item.candidate.plan_id != target_plan_id
        ),
        key=lambda item: (item.deadline_at, str(item.plan_id)),
    )
    return (
        shifted_minutes(prepared),
        tuple(-item.deadline_at.timestamp() for item in additional),
        tuple(str(item.plan_id) for item in additional),
    )


def block_signatures(
    blocks: tuple[DeadlineBlockWrite, ...],
) -> tuple[tuple[datetime, datetime, datetime, int, int], ...]:
    return tuple(
        (
            block.starts_at.astimezone(UTC),
            block.ends_at.astimezone(UTC),
            block.reserved_ends_at.astimezone(UTC),
            block.planned_minutes,
            block.recovery_minutes,
        )
        for block in blocks
    )


def _review_block(block: DeadlineBlockWrite) -> MultiExamPlanBlock:
    return MultiExamPlanBlock(
        id=block.id,
        sequence=block.sequence,
        starts_at=block.starts_at,
        ends_at=block.ends_at,
        reserved_ends_at=block.reserved_ends_at,
        local_date=block.local_date,
        planned_minutes=block.planned_minutes,
        recovery_minutes=block.recovery_minutes,
        credited_minutes=0,
    )


def _change_summary(
    current: tuple[MultiExamPlanBlock, ...],
    proposed: tuple[MultiExamPlanBlock, ...],
) -> dict[str, int]:
    proposed_remaining = list(proposed)
    retained_minutes = retained_count = 0
    old_minutes = old_count = 0
    for block in current:
        signature = block.schedule_signature
        index = next(
            (
                position
                for position, proposed_block in enumerate(proposed_remaining)
                if block.credited_minutes == 0
                and proposed_block.schedule_signature == signature
            ),
            None,
        )
        if index is None:
            old_minutes += block.effective_minutes
            old_count += 1
        else:
            proposed_remaining.pop(index)
            retained_minutes += block.effective_minutes
            retained_count += 1
    new_minutes = sum(block.effective_minutes for block in proposed_remaining)
    new_count = len(proposed_remaining)
    shifted = min(old_minutes, new_minutes)
    shifted_count = min(old_count, new_count)
    return {
        "retained_minutes": retained_minutes,
        "added_minutes": new_minutes - shifted,
        "shifted_minutes": shifted,
        "removed_minutes": old_minutes - shifted,
        "retained_block_count": retained_count,
        "added_block_count": new_count - shifted_count,
        "shifted_block_count": shifted_count,
        "removed_block_count": old_count - shifted_count,
    }


def _blocks_by_plan(
    snapshot: MultiExamPlanSnapshot,
) -> dict[UUID, list[dict[str, Any]]]:
    active_revisions = {
        UUID(str(row.get("id"))): _int(row.get("current_revision"))
        for row in snapshot.active_plans
    }
    result: dict[UUID, list[dict[str, Any]]] = {}
    for raw in snapshot.health.deadline_blocks:
        row = dict(raw)
        plan_id = UUID(str(row.get("plan_id")))
        if active_revisions.get(plan_id) != _int(row.get("revision")):
            continue
        result.setdefault(plan_id, []).append(row)
    return result


def _external_busy_by_day(
    snapshot: MultiExamPlanSnapshot,
    plan_id: UUID,
    plan_blocks: list[dict[str, Any]],
) -> dict[date, list[tuple[datetime, datetime]]]:
    health = snapshot.health
    days = sorted({_date(row.get("local_date")) for row in plan_blocks})
    if not days:
        return {}
    recurring = [dict(row) for row in health.schedule_items]
    recurring.extend(
        {
            "id": row.get("id"),
            "weekday": row.get("weekday"),
            "starts_at": row.get("starts_at"),
            "ends_at": row.get("ends_at"),
        }
        for row in health.planner_habit_slots
    )
    timed = [
        dict(row)
        for row in health.deadline_blocks
        if str(row.get("plan_id")) != str(plan_id)
    ]
    timed.extend(dict(row) for row in health.planner_task_blocks)
    for row in health.planner_commitments:
        if row.get("recurrence") == "weekly":
            recurring.append(
                {
                    "id": row.get("id"),
                    "weekday": row.get("weekday"),
                    "starts_at": row.get("local_starts_at"),
                    "ends_at": row.get("local_ends_at"),
                },
            )
        else:
            timed.append(dict(row))
    use_calendar = health.planner_preference.get("use_calendar_busy_time") is True
    if use_calendar:
        timed.extend(dict(row) for row in health.calendar_timed_events)
    all_day = (
        [dict(row) for row in health.calendar_all_day_events] if use_calendar else []
    )
    return busy_intervals_by_day(
        days=days,
        sources=BusySources(
            recurring_commitments=recurring,
            timed_intervals=timed,
            all_day_intervals=all_day,
        ),
        zone=ZoneInfo(_text(health.profile.get("timezone"))),
        local_now=health.generated_at.astimezone(
            ZoneInfo(_text(health.profile.get("timezone"))),
        ),
    )


def _current_study_matches(
    snapshot: MultiExamPlanSnapshot,
    candidate: MultiExamCandidate,
) -> bool:
    setup = snapshot.health.study_setup
    saved_revision = candidate.row.get("study_setup_revision")
    saved_recovery = _int(candidate.row.get("recovery_minutes"))
    if setup is None or setup.get("focus_minutes") is None:
        return saved_revision is None and saved_recovery == 0
    return (
        saved_revision == setup.get("setup_revision")
        and _int(candidate.row.get("preferred_session_minutes"))
        == _int(setup.get("focus_minutes"))
        and saved_recovery == _int(setup.get("recovery_minutes"))
    )


def _current_calendar_matches(
    snapshot: MultiExamPlanSnapshot,
    candidate: MultiExamCandidate,
) -> bool:
    use_calendar = (
        snapshot.health.planner_preference.get("use_calendar_busy_time") is True
    )
    if use_calendar != bool(candidate.row.get("use_calendar_availability")):
        return False
    if not use_calendar:
        return True
    imported = snapshot.health.calendar_import
    zone = ZoneInfo(_text(snapshot.health.profile.get("timezone")))
    starts_on = max(
        snapshot.health.local_today,
        _date(candidate.row.get("planning_start_on")),
    )
    deadline_day = _datetime(candidate.row.get("deadline_at")).astimezone(zone).date()
    return bool(
        imported
        and imported.get("planning_status") == "current"
        and imported.get("timezone") == snapshot.health.profile.get("timezone")
        and imported.get("profile_timezone_revision")
        == snapshot.health.profile.get("timezone_revision")
        and str(imported.get("connection_id"))
        == str(candidate.row.get("availability_connection_id"))
        and str(imported.get("import_id"))
        == str(candidate.row.get("availability_import_id"))
        and _date(imported.get("window_starts_on")) <= starts_on
        and _date(imported.get("window_ends_before")) > deadline_day
    )


def _last_preferred_day(row: dict[str, Any], zone: ZoneInfo) -> date:
    deadline_day = _datetime(row.get("deadline_at")).astimezone(zone).date()
    buffer_days = _int(row.get("buffer_days"))
    return (
        deadline_day
        if buffer_days == 0
        else deadline_day - timedelta(days=buffer_days + 1)
    )


def _datetime(value: object) -> datetime:
    if isinstance(value, datetime):
        result = value
    elif isinstance(value, str):
        result = datetime.fromisoformat(value.replace("Z", "+00:00"))
    else:
        raise ValueError("Exam balance datetime is invalid.")
    if result.tzinfo is None or result.utcoffset() is None:
        raise ValueError("Exam balance datetime must be aware.")
    return result


def _date(value: object) -> date:
    if isinstance(value, date) and not isinstance(value, datetime):
        return value
    if isinstance(value, str):
        return date.fromisoformat(value)
    raise ValueError("Exam balance date is invalid.")


def _int(value: object) -> int:
    if isinstance(value, bool) or not isinstance(value, int):
        raise ValueError("Exam balance integer is invalid.")
    return value


def _text(value: object) -> str:
    if not isinstance(value, str) or not value or value != value.strip():
        raise ValueError("Exam balance text is invalid.")
    return value
