from __future__ import annotations

import asyncio
from collections.abc import Callable
from datetime import UTC, date, datetime, time, timedelta
from typing import Any
from uuid import UUID, uuid5
from zoneinfo import ZoneInfo

from app.models.today_week_agenda import (
    TODAY_WEEK_AGENDA_CONTRACT_VERSION,
    TodayWeekAgendaAction,
    TodayWeekAgendaDay,
    TodayWeekAgendaItem,
    TodayWeekAgendaResponse,
    TodayWeekAgendaSourceState,
    TodayWeekAgendaSourceStates,
)
from app.repositories.today_week_agenda_repository import (
    TodayWeekAgendaRepository,
    WeekCalendarRows,
)
from app.services.local_time import resolve_local_datetime, resolve_local_interval
from app.services.planning_availability import recurring_commitment_applies_on
from app.services.deadline_plan_credit import deadline_block_credits


class TodayWeekAgendaUnavailableError(RuntimeError):
    pass


_OCCURRENCE_NAMESPACE = UUID("668dd529-6b1a-4fc6-a49a-b84fe24bf92d")


class TodayWeekAgendaService:
    def __init__(
        self,
        *,
        repository: TodayWeekAgendaRepository,
        now: Callable[[], datetime] | None = None,
    ) -> None:
        self._repository = repository
        self._now = now or (lambda: datetime.now(UTC))

    async def get_week(self, *, user_id: str) -> TodayWeekAgendaResponse:
        generated_at = _aware_utc(self._now())
        try:
            timezone = await self._repository.get_profile_timezone(user_id=user_id)
            zone = ZoneInfo(timezone)
        except Exception as exc:
            raise TodayWeekAgendaUnavailableError(
                "Full week is unavailable because the profile timezone could not be read.",
            ) from exc

        local_today = generated_at.astimezone(zone).date()
        week_starts_on = local_today - timedelta(days=local_today.isoweekday() - 1)
        week_ends_on = week_starts_on + timedelta(days=6)
        try:
            range_starts_at = _day_boundary(week_starts_on, zone)
            range_ends_at = _day_boundary(week_ends_on + timedelta(days=1), zone)
        except ValueError as exc:
            raise TodayWeekAgendaUnavailableError(
                "Full week is unavailable because its local date boundary is invalid.",
            ) from exc

        results = await asyncio.gather(
            self._setup(
                user_id=user_id,
                week_starts_on=week_starts_on,
                week_ends_on=week_ends_on,
                zone=zone,
            ),
            self._preparation(
                user_id=user_id,
                week_starts_on=week_starts_on,
                week_ends_on=week_ends_on,
                generated_at=generated_at,
                zone=zone,
            ),
            self._calendar(
                user_id=user_id,
                week_starts_on=week_starts_on,
                week_ends_on=week_ends_on,
                range_starts_at=range_starts_at,
                range_ends_at=range_ends_at,
                zone=zone,
            ),
            self._focus(
                user_id=user_id,
                week_starts_on=week_starts_on,
                week_ends_on=week_ends_on,
                range_starts_at=range_starts_at,
                range_ends_at=range_ends_at,
                generated_at=generated_at,
                zone=zone,
            ),
            self._tasks(
                user_id=user_id,
                week_starts_on=week_starts_on,
                week_ends_on=week_ends_on,
                zone=zone,
            ),
            self._habits(
                user_id=user_id,
                week_starts_on=week_starts_on,
                week_ends_on=week_ends_on,
                local_today=local_today,
                zone=zone,
            ),
            self._fixed_commitments(
                user_id=user_id,
                week_starts_on=week_starts_on,
                week_ends_on=week_ends_on,
                range_starts_at=range_starts_at,
                range_ends_at=range_ends_at,
                zone=zone,
            ),
            return_exceptions=True,
        )
        source_names = (
            "setup",
            "preparation",
            "calendar",
            "focus",
            "tasks",
            "habits",
            "fixed_commitments",
        )
        messages = {
            "setup": "Setup commitments are unavailable.",
            "preparation": "Preparation is unavailable.",
            "calendar": "Calendar planning data is unavailable.",
            "focus": "Focus sessions are unavailable.",
            "tasks": "Planner Tasks are unavailable.",
            "habits": "Habit slots are unavailable.",
            "fixed_commitments": "Fixed commitments are unavailable.",
        }
        items: list[TodayWeekAgendaItem] = []
        states: dict[str, TodayWeekAgendaSourceState] = {}
        for name, result in zip(source_names, results, strict=True):
            if isinstance(result, BaseException):
                states[name] = TodayWeekAgendaSourceState(
                    status="unavailable",
                    message=messages[name],
                )
            else:
                if not isinstance(result, list) or any(
                    not isinstance(item, TodayWeekAgendaItem) for item in result
                ):
                    raise TypeError(
                        "Week agenda source returned an invalid projection."
                    )
                states[name] = TodayWeekAgendaSourceState(status="current")
                items.extend(result)

        days = [
            TodayWeekAgendaDay(
                local_date=week_starts_on + timedelta(days=offset),
                items=sorted(
                    (
                        item
                        for item in items
                        if item.local_date == week_starts_on + timedelta(days=offset)
                    ),
                    key=_item_sort_key,
                ),
            )
            for offset in range(7)
        ]
        return TodayWeekAgendaResponse(
            contract_version=TODAY_WEEK_AGENDA_CONTRACT_VERSION,
            origin="authenticated_backend",
            generated_at=generated_at,
            timezone=timezone,
            local_today=local_today,
            week_starts_on=week_starts_on,
            week_ends_on=week_ends_on,
            days=days,
            source_states=TodayWeekAgendaSourceStates(**states),
        )

    async def _setup(
        self,
        *,
        user_id: str,
        week_starts_on: date,
        week_ends_on: date,
        zone: ZoneInfo,
    ) -> list[TodayWeekAgendaItem]:
        rows = await self._repository.list_setup(user_id=user_id)
        if len(rows) > 1_000:
            raise ValueError("Week agenda Setup bound was exceeded.")
        items: list[TodayWeekAgendaItem] = []
        candidates = [week_starts_on - timedelta(days=1)] + _dates(
            week_starts_on,
            week_ends_on,
        )
        for row in rows:
            source_id = _uuid(row.get("id"))
            weekday = _integer(row.get("weekday"), minimum=1, maximum=7)
            start = _local_time(row.get("starts_at"))
            end = _local_time(row.get("ends_at"))
            for occurrence_date in candidates:
                if (
                    occurrence_date.isoweekday() != weekday
                    or not recurring_commitment_applies_on(
                        row,
                        occurrence_date,
                    )
                ):
                    continue
                starts_at, ends_at = resolve_local_interval(
                    local_date=occurrence_date,
                    starts_at=start,
                    ends_at=end,
                    zone=zone,
                    source_id=f"week-setup:{source_id}",
                )
                items.extend(
                    _project_timed_days(
                        category="setup",
                        source_id=source_id,
                        title=_text(row.get("title"), maximum=200),
                        detail=_optional_text(row.get("location"), maximum=300),
                        status="scheduled",
                        starts_at=starts_at,
                        ends_at=ends_at,
                        week_starts_on=week_starts_on,
                        week_ends_on=week_ends_on,
                        zone=zone,
                    ),
                )
        return items

    async def _preparation(
        self,
        *,
        user_id: str,
        week_starts_on: date,
        week_ends_on: date,
        generated_at: datetime,
        zone: ZoneInfo,
    ) -> list[TodayWeekAgendaItem]:
        source = await self._repository.load_preparation(
            user_id=user_id,
            week_starts_on=week_starts_on,
            week_ends_on=week_ends_on,
        )
        if (
            len(source.plans) > 1_000
            or len(source.blocks) > 10_000
            or len(source.revisions) > len(source.plans)
            or len(source.credit_blocks) > len(source.plans) * 120
            or len(source.focus_facts) > 10_000
        ):
            raise ValueError("Week agenda Preparation bound was exceeded.")
        plans: dict[UUID, dict[str, Any]] = {}
        for row in source.plans:
            plan_id = _uuid(row.get("id"))
            if plan_id in plans or row.get("status") not in {"active", "completed"}:
                raise ValueError("Week agenda Preparation plan is invalid.")
            if _uuid(row.get("managed_task_id")) != plan_id:
                raise ValueError("Week agenda Preparation task authority is invalid.")
            _aware_datetime(row.get("first_activated_at"))
            plans[plan_id] = row

        revisions: dict[UUID, dict[str, Any]] = {}
        for row in source.revisions:
            plan_id = _uuid(row.get("plan_id"))
            plan = plans.get(plan_id)
            if (
                plan is None
                or plan_id in revisions
                or row.get("state") != "active"
                or _integer(row.get("revision"), minimum=1)
                != _integer(plan.get("current_revision"), minimum=1)
            ):
                raise ValueError("Week agenda Preparation revision is invalid.")
            _integer(row.get("tracked_focus_minutes_at_proposal"), minimum=0)
            revisions[plan_id] = row
        if set(revisions) != set(plans):
            raise ValueError("Week agenda Preparation revision is missing.")

        credit_blocks_by_plan: dict[UUID, list[dict[str, Any]]] = {
            plan_id: [] for plan_id in plans
        }
        credit_block_ids: set[UUID] = set()
        sequences: set[tuple[UUID, int]] = set()
        for block in source.credit_blocks:
            plan_id = _uuid(block.get("plan_id"))
            plan = plans.get(plan_id)
            block_id = _uuid(block.get("id"))
            sequence = _integer(block.get("sequence"), minimum=1, maximum=120)
            if (
                plan is None
                or block_id in credit_block_ids
                or (plan_id, sequence) in sequences
                or _integer(block.get("revision"), minimum=1)
                != _integer(plan.get("current_revision"), minimum=1)
                or block.get("reservation_state")
                != ("active" if plan.get("status") == "active" else "superseded")
            ):
                raise ValueError("Week agenda Preparation block is invalid.")
            _integer(block.get("planned_minutes"), minimum=5, maximum=240)
            _aware_datetime(block.get("starts_at"))
            _aware_datetime(block.get("ends_at"))
            credit_block_ids.add(block_id)
            sequences.add((plan_id, sequence))
            credit_blocks_by_plan[plan_id].append(block)

        facts_by_plan: dict[UUID, list[dict[str, Any]]] = {
            plan_id: [] for plan_id in plans
        }
        fact_ids: set[UUID] = set()
        for fact in source.focus_facts:
            plan_id = _uuid(fact.get("plan_id"))
            plan = plans.get(plan_id)
            fact_id = _uuid(fact.get("id"))
            if plan is None or fact_id in fact_ids:
                raise ValueError("Week agenda Preparation Focus fact is invalid.")
            started_at = _aware_datetime(fact.get("started_at"))
            _integer(fact.get("actual_minutes"), minimum=0)
            source_block_id = fact.get("deadline_plan_block_id")
            if source_block_id is not None:
                _uuid(source_block_id)
            fact_ids.add(fact_id)
            if started_at >= _aware_datetime(plan.get("first_activated_at")):
                facts_by_plan[plan_id].append(fact)

        credits_by_plan = {
            plan_id: deadline_block_credits(
                blocks,
                facts_by_plan[plan_id],
                tracked_focus_minutes_at_proposal=_integer(
                    revisions[plan_id].get("tracked_focus_minutes_at_proposal"),
                    minimum=0,
                ),
            )
            for plan_id, blocks in credit_blocks_by_plan.items()
        }
        items: list[TodayWeekAgendaItem] = []
        for block in source.blocks:
            plan_id = _uuid(block.get("plan_id"))
            plan = plans.get(plan_id)
            if plan is None:
                if block.get("reservation_state") == "superseded":
                    continue
                raise ValueError("Week agenda Preparation plan is missing.")
            if _integer(block.get("revision"), minimum=1) != _integer(
                plan.get("current_revision"),
                minimum=1,
            ):
                if block.get("reservation_state") == "active":
                    raise ValueError(
                        "Week agenda Preparation active block is not current.",
                    )
                continue
            block_id = _uuid(block.get("id"))
            expected_reservation = (
                "active" if plan.get("status") == "active" else "superseded"
            )
            if (
                block.get("reservation_state") != expected_reservation
                or block_id not in credit_block_ids
            ):
                raise ValueError("Week agenda Preparation current block is invalid.")
            block_date = _calendar_date(block.get("local_date"))
            starts_at = _aware_datetime(block.get("starts_at"))
            ends_at = _aware_datetime(block.get("ends_at"))
            planned = _integer(
                block.get("planned_minutes"),
                minimum=5,
                maximum=240,
            )
            credit = credits_by_plan[plan_id].get(str(block_id))
            if credit is None or not 0 <= credit <= planned:
                raise ValueError("Week agenda Preparation credit is invalid.")
            remaining = planned - credit
            if credit == planned:
                status = "completed"
            elif credit > 0:
                status = "partial"
            elif plan.get("status") == "completed" or generated_at >= ends_at:
                status = "missed"
            else:
                status = "upcoming"
            if plan.get("status") == "completed":
                action = TodayWeekAgendaAction(
                    kind="open_preparation_plan",
                    target_id=plan_id,
                )
            elif status != "completed" and remaining >= 5:
                action = TodayWeekAgendaAction(
                    kind="start_preparation_focus",
                    target_id=block_id,
                    source_kind="deadline_plan_block",
                )
            else:
                action = None
            items.append(
                _timed_item(
                    category="preparation",
                    source_id=block_id,
                    plan_id=plan_id,
                    local_date=block_date,
                    title=_text(plan.get("title"), maximum=200),
                    detail=f"{remaining} min remaining · {credit}/{planned} min tracked",
                    status=status,
                    planned_minutes=planned,
                    credited_tracked_minutes=credit,
                    remaining_minutes=remaining,
                    starts_at=starts_at,
                    ends_at=ends_at,
                    zone=zone,
                    action=action,
                ),
            )
        return items

    async def _calendar(
        self,
        *,
        user_id: str,
        week_starts_on: date,
        week_ends_on: date,
        range_starts_at: datetime,
        range_ends_at: datetime,
        zone: ZoneInfo,
    ) -> list[TodayWeekAgendaItem]:
        source = await self._repository.load_calendar(
            user_id=user_id,
            week_starts_on=week_starts_on,
            week_ends_on=week_ends_on,
            range_starts_at=range_starts_at,
            range_ends_at=range_ends_at,
        )
        if len(source.events) > 5_000:
            raise ValueError("Week agenda Calendar bound was exceeded.")
        return _calendar_items(
            source,
            week_starts_on=week_starts_on,
            week_ends_on=week_ends_on,
            zone=zone,
        )

    async def _focus(
        self,
        *,
        user_id: str,
        week_starts_on: date,
        week_ends_on: date,
        range_starts_at: datetime,
        range_ends_at: datetime,
        generated_at: datetime,
        zone: ZoneInfo,
    ) -> list[TodayWeekAgendaItem]:
        rows = await self._repository.list_focus(
            user_id=user_id,
            range_starts_at=range_starts_at,
            range_ends_at=range_ends_at,
        )
        if len(rows) > 5_000:
            raise ValueError("Week agenda Focus bound was exceeded.")
        items: list[TodayWeekAgendaItem] = []
        for row in rows:
            status = row.get("status")
            if status not in {"active", "completed", "abandoned"}:
                raise ValueError("Week agenda Focus status is invalid.")
            starts_at = _aware_datetime(row.get("started_at"))
            ends_at = (
                generated_at
                if status == "active"
                else _aware_datetime(row.get("ended_at"))
            )
            if ends_at <= starts_at:
                ends_at = starts_at + timedelta(seconds=1)
            metadata = _metadata(row.get("metadata"))
            local_date = _optional_calendar_date(metadata.get("entry_date"))
            if local_date is None:
                local_date = starts_at.astimezone(UTC).date()
            if not week_starts_on <= local_date <= week_ends_on:
                continue
            session_id = _uuid(row.get("id"))
            actual = row.get("actual_minutes")
            detail = (
                f"{_integer(actual, minimum=0)} min"
                if actual is not None
                else "In progress"
            )
            items.append(
                _timed_item(
                    category="focus",
                    source_id=session_id,
                    local_date=local_date,
                    title=_optional_text(row.get("label"), maximum=200)
                    or "Focus session",
                    detail=detail,
                    status=status,
                    starts_at=starts_at,
                    ends_at=ends_at,
                    zone=zone,
                    action=TodayWeekAgendaAction(
                        kind="resume_focus" if status == "active" else "reflect_focus",
                        target_id=session_id,
                    ),
                ),
            )
        return items

    async def _tasks(
        self,
        *,
        user_id: str,
        week_starts_on: date,
        week_ends_on: date,
        zone: ZoneInfo,
    ) -> list[TodayWeekAgendaItem]:
        source = await self._repository.load_tasks(
            user_id=user_id,
            week_starts_on=week_starts_on,
            week_ends_on=week_ends_on,
        )
        if (
            len(source.plans) > 1_000
            or len(source.blocks) > 10_000
            or len(source.tasks) > 1_000
        ):
            raise ValueError("Week agenda Task bound was exceeded.")
        tasks = {_uuid(row.get("id")): row for row in source.tasks}
        plans = {_uuid(row.get("id")): row for row in source.plans}
        items: list[TodayWeekAgendaItem] = []
        for block in source.blocks:
            plan = plans.get(_uuid(block.get("plan_id")))
            if plan is None:
                continue
            if _integer(block.get("revision"), minimum=1) != _integer(
                plan.get("current_revision"),
                minimum=1,
            ):
                continue
            task_id = _uuid(plan.get("target_id"))
            task = tasks.get(task_id)
            if task is None:
                raise ValueError("Week agenda Task target is missing.")
            if task.get("source") == "deadline-plan-v1":
                raise ValueError("Week agenda Planner Task has Deadline ownership.")
            block_id = _uuid(block.get("id"))
            task_status = _task_status(task.get("status"))
            items.append(
                _timed_item(
                    category="task",
                    source_id=block_id,
                    local_date=_calendar_date(block.get("local_date")),
                    title=_text(task.get("title"), maximum=200),
                    detail=f"{_integer(block.get('planned_minutes'), minimum=5, maximum=240)} min",
                    status=task_status,
                    starts_at=_aware_datetime(block.get("starts_at")),
                    ends_at=_aware_datetime(block.get("ends_at")),
                    zone=zone,
                    action=(
                        TodayWeekAgendaAction(
                            kind="start_task_focus",
                            target_id=block_id,
                            source_kind="planner_task_block",
                        )
                        if task_status in {"todo", "in_progress"}
                        else None
                    ),
                ),
            )
        return items

    async def _habits(
        self,
        *,
        user_id: str,
        week_starts_on: date,
        week_ends_on: date,
        local_today: date,
        zone: ZoneInfo,
    ) -> list[TodayWeekAgendaItem]:
        source = await self._repository.load_habits(
            user_id=user_id,
            week_starts_on=week_starts_on,
            week_ends_on=week_ends_on,
        )
        if any(
            count > maximum
            for count, maximum in (
                (len(source.plans), 1_000),
                (len(source.slots), 5_000),
                (len(source.habits), 1_000),
                (len(source.logs), 5_000),
            )
        ):
            raise ValueError("Week agenda Habit bound was exceeded.")
        habits = {_uuid(row.get("id")): row for row in source.habits}
        plans = {_uuid(row.get("id")): row for row in source.plans}
        outcomes: dict[tuple[UUID, date], str] = {}
        for row in source.logs:
            key = (_uuid(row.get("habit_id")), _calendar_date(row.get("entry_date")))
            status = row.get("status")
            if status not in {"completed", "skipped"} or key in outcomes:
                raise ValueError("Week agenda Habit outcome is invalid.")
            outcomes[key] = status
        items: list[TodayWeekAgendaItem] = []
        for slot in source.slots:
            plan = plans.get(_uuid(slot.get("plan_id")))
            if plan is None:
                continue
            if _integer(slot.get("revision"), minimum=1) != _integer(
                plan.get("current_revision"),
                minimum=1,
            ):
                continue
            habit_id = _uuid(plan.get("target_id"))
            habit = habits.get(habit_id)
            if habit is None:
                raise ValueError("Week agenda Habit target is missing.")
            weekday = _integer(slot.get("weekday"), minimum=1, maximum=7)
            occurrence_date = week_starts_on + timedelta(days=weekday - 1)
            starts_at, ends_at = resolve_local_interval(
                local_date=occurrence_date,
                starts_at=_local_time(slot.get("starts_at")),
                ends_at=_local_time(slot.get("ends_at")),
                zone=zone,
                source_id=f"week-habit:{slot.get('id')}",
            )
            outcome = outcomes.get((habit_id, occurrence_date))
            action = (
                TodayWeekAgendaAction(
                    kind="open_habit",
                    target_id=habit_id,
                    local_date=occurrence_date,
                )
                if occurrence_date == local_today
                else None
            )
            items.append(
                _timed_item(
                    category="habit",
                    source_id=_uuid(slot.get("id")),
                    habit_id=habit_id,
                    local_date=occurrence_date,
                    title=_text(habit.get("title"), maximum=200),
                    detail=f"{_integer(slot.get('duration_minutes'), minimum=5, maximum=240)} min",
                    status=outcome or "open",
                    starts_at=starts_at,
                    ends_at=ends_at,
                    zone=zone,
                    action=action,
                ),
            )
        return items

    async def _fixed_commitments(
        self,
        *,
        user_id: str,
        week_starts_on: date,
        week_ends_on: date,
        range_starts_at: datetime,
        range_ends_at: datetime,
        zone: ZoneInfo,
    ) -> list[TodayWeekAgendaItem]:
        rows = await self._repository.list_fixed_commitments(
            user_id=user_id,
            range_starts_at=range_starts_at,
            range_ends_at=range_ends_at,
        )
        if len(rows) > 1_000:
            raise ValueError("Week agenda fixed-commitment bound was exceeded.")
        items: list[TodayWeekAgendaItem] = []
        for row in rows:
            source_id = _uuid(row.get("id"))
            recurrence = row.get("recurrence")
            intervals: list[tuple[datetime, datetime]] = []
            if recurrence == "one_off":
                intervals.append(
                    (
                        _aware_datetime(row.get("starts_at")),
                        _aware_datetime(row.get("ends_at")),
                    ),
                )
            elif recurrence == "weekly":
                weekday = _integer(row.get("weekday"), minimum=1, maximum=7)
                for day in [week_starts_on - timedelta(days=1)] + _dates(
                    week_starts_on,
                    week_ends_on,
                ):
                    if day.isoweekday() != weekday:
                        continue
                    intervals.append(
                        resolve_local_interval(
                            local_date=day,
                            starts_at=_local_time(row.get("local_starts_at")),
                            ends_at=_local_time(row.get("local_ends_at")),
                            zone=zone,
                            source_id=f"week-fixed:{source_id}",
                        ),
                    )
            else:
                raise ValueError("Week agenda fixed recurrence is invalid.")
            for starts_at, ends_at in intervals:
                items.extend(
                    _project_timed_days(
                        category="fixed_commitment",
                        source_id=source_id,
                        title=_text(row.get("title"), maximum=200),
                        detail=_optional_text(row.get("location"), maximum=300),
                        status="scheduled",
                        starts_at=starts_at,
                        ends_at=ends_at,
                        week_starts_on=week_starts_on,
                        week_ends_on=week_ends_on,
                        zone=zone,
                    ),
                )
        return items


def _calendar_items(
    source: WeekCalendarRows,
    *,
    week_starts_on: date,
    week_ends_on: date,
    zone: ZoneInfo,
) -> list[TodayWeekAgendaItem]:
    if source.source_label is None and source.events:
        raise ValueError("Week agenda Calendar events have no source.")
    items: list[TodayWeekAgendaItem] = []
    for row in source.events:
        source_id = _uuid(row.get("id"))
        status = row.get("event_status")
        if status not in {"confirmed", "tentative"}:
            raise ValueError("Week agenda Calendar status is invalid.")
        title = _text(row.get("title"), maximum=200)
        location = _optional_text(row.get("location"), maximum=300)
        if row.get("event_kind") == "all_day":
            starts_on = _calendar_date(row.get("starts_on"))
            ends_on = _calendar_date(row.get("ends_on"))
            if ends_on <= starts_on:
                raise ValueError("Week agenda all-day Calendar interval is invalid.")
            for day in _dates(
                max(starts_on, week_starts_on),
                min(ends_on - timedelta(days=1), week_ends_on),
            ):
                items.append(
                    TodayWeekAgendaItem(
                        id=_occurrence_id("calendar", source_id, day),
                        category="calendar",
                        source_id=source_id,
                        local_date=day,
                        title=title,
                        detail=location or source.source_label,
                        status=status,
                        all_day=True,
                    ),
                )
        elif row.get("event_kind") == "timed":
            items.extend(
                _project_timed_days(
                    category="calendar",
                    source_id=source_id,
                    title=title,
                    detail=location or source.source_label,
                    status=status,
                    starts_at=_aware_datetime(row.get("starts_at")),
                    ends_at=_aware_datetime(row.get("ends_at")),
                    week_starts_on=week_starts_on,
                    week_ends_on=week_ends_on,
                    zone=zone,
                ),
            )
        else:
            raise ValueError("Week agenda Calendar kind is invalid.")
    return items


def _project_timed_days(
    *,
    category: str,
    source_id: UUID,
    title: str,
    detail: str | None,
    status: str,
    starts_at: datetime,
    ends_at: datetime,
    week_starts_on: date,
    week_ends_on: date,
    zone: ZoneInfo,
) -> list[TodayWeekAgendaItem]:
    if ends_at <= starts_at:
        raise ValueError("Week agenda projected interval is invalid.")
    local_start = starts_at.astimezone(zone).date()
    local_end = (ends_at - timedelta(microseconds=1)).astimezone(zone).date()
    if local_end < week_starts_on or local_start > week_ends_on:
        return []
    items: list[TodayWeekAgendaItem] = []
    for day in _dates(max(local_start, week_starts_on), min(local_end, week_ends_on)):
        boundary_start = _day_boundary(day, zone)
        boundary_end = _day_boundary(day + timedelta(days=1), zone)
        clipped_start = max(
            starts_at, boundary_start, key=lambda value: value.astimezone(UTC)
        )
        clipped_end = min(
            ends_at, boundary_end, key=lambda value: value.astimezone(UTC)
        )
        if clipped_end.astimezone(UTC) <= clipped_start.astimezone(UTC):
            continue
        items.append(
            _timed_item(
                category=category,
                source_id=source_id,
                local_date=day,
                title=title,
                detail=detail,
                status=status,
                starts_at=clipped_start,
                ends_at=clipped_end,
                zone=zone,
            ),
        )
    return items


def _timed_item(
    *,
    category: str,
    source_id: UUID,
    plan_id: UUID | None = None,
    habit_id: UUID | None = None,
    local_date: date,
    title: str,
    detail: str | None,
    status: str,
    planned_minutes: int | None = None,
    credited_tracked_minutes: int | None = None,
    remaining_minutes: int | None = None,
    starts_at: datetime,
    ends_at: datetime,
    zone: ZoneInfo,
    action: TodayWeekAgendaAction | None = None,
) -> TodayWeekAgendaItem:
    local_start = starts_at.astimezone(zone).replace(tzinfo=None)
    local_end = ends_at.astimezone(zone).replace(tzinfo=None)
    return TodayWeekAgendaItem(
        id=_occurrence_id(category, source_id, local_date),
        category=category,
        source_id=source_id,
        plan_id=plan_id,
        habit_id=habit_id,
        local_date=local_date,
        title=title,
        detail=detail,
        status=status,
        planned_minutes=planned_minutes,
        credited_tracked_minutes=credited_tracked_minutes,
        remaining_minutes=remaining_minutes,
        all_day=False,
        local_starts_at=local_start.isoformat(timespec="seconds"),
        local_ends_at=local_end.isoformat(timespec="seconds"),
        starts_at=starts_at,
        ends_at=ends_at,
        action=action,
    )


def _item_sort_key(item: TodayWeekAgendaItem) -> tuple[Any, ...]:
    category_rank = {
        "setup": 0,
        "fixed_commitment": 1,
        "task": 2,
        "habit": 3,
        "preparation": 4,
        "calendar": 5,
        "focus": 6,
    }
    return (
        0 if item.all_day else 1,
        item.local_starts_at or "",
        category_rank[item.category],
        item.title.casefold(),
        str(item.id),
    )


def _dates(starts_on: date, ends_on: date) -> list[date]:
    if ends_on < starts_on:
        return []
    return [
        starts_on + timedelta(days=offset)
        for offset in range((ends_on - starts_on).days + 1)
    ]


def _day_boundary(day: date, zone: ZoneInfo) -> datetime:
    return resolve_local_datetime(
        local_date=day,
        local_time=time.min,
        zone=zone,
        source_id="week-agenda-boundary",
    )


def _occurrence_id(category: str, source_id: UUID, local_date: date) -> UUID:
    return uuid5(
        _OCCURRENCE_NAMESPACE,
        f"{category}:{source_id}:{local_date.isoformat()}",
    )


def _aware_utc(value: datetime) -> datetime:
    if value.tzinfo is None or value.utcoffset() is None:
        raise ValueError("Week agenda now must be timezone-aware.")
    return value.astimezone(UTC)


def _aware_datetime(value: Any) -> datetime:
    if isinstance(value, datetime):
        parsed = value
    elif isinstance(value, str):
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    else:
        raise ValueError("Week agenda timestamp is invalid.")
    if parsed.tzinfo is None or parsed.utcoffset() is None:
        raise ValueError("Week agenda timestamp must be aware.")
    return parsed


def _calendar_date(value: Any) -> date:
    if isinstance(value, date) and not isinstance(value, datetime):
        parsed = value
    elif isinstance(value, str):
        parsed = date.fromisoformat(value)
    else:
        raise ValueError("Week agenda date is invalid.")
    if isinstance(value, str) and parsed.isoformat() != value:
        raise ValueError("Week agenda date is invalid.")
    return parsed


def _optional_calendar_date(value: Any) -> date | None:
    if value is None:
        return None
    try:
        return _calendar_date(value)
    except (TypeError, ValueError):
        return None


def _local_time(value: Any) -> time:
    if isinstance(value, time):
        parsed = value
    elif isinstance(value, str):
        parsed = time.fromisoformat(value)
    else:
        raise ValueError("Week agenda local time is invalid.")
    if parsed.tzinfo is not None:
        raise ValueError("Week agenda local time cannot carry an offset.")
    return parsed


def _integer(value: Any, *, minimum: int, maximum: int | None = None) -> int:
    if not isinstance(value, int) or isinstance(value, bool) or value < minimum:
        raise ValueError("Week agenda integer is invalid.")
    if maximum is not None and value > maximum:
        raise ValueError("Week agenda integer is invalid.")
    return value


def _uuid(value: Any) -> UUID:
    if not isinstance(value, str):
        raise ValueError("Week agenda UUID is invalid.")
    parsed = UUID(value)
    if str(parsed) != value.lower():
        raise ValueError("Week agenda UUID is invalid.")
    return parsed


def _metadata(value: Any) -> dict[str, Any]:
    if value is None:
        return {}
    if not isinstance(value, dict):
        raise ValueError("Week agenda metadata is invalid.")
    return value


def _text(value: Any, *, maximum: int) -> str:
    if (
        not isinstance(value, str)
        or not value
        or value.strip() != value
        or len(value) > maximum
    ):
        raise ValueError("Week agenda text is invalid.")
    return value


def _optional_text(value: Any, *, maximum: int) -> str | None:
    return None if value is None else _text(value, maximum=maximum)


def _task_status(value: Any) -> str:
    if value not in {"todo", "in_progress", "done", "cancelled"}:
        raise ValueError("Week agenda Task status is invalid.")
    return value
