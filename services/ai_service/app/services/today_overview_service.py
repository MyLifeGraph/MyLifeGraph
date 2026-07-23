from __future__ import annotations

import asyncio
from collections.abc import Callable
from datetime import UTC, date, datetime, time, timedelta
from typing import Any, Protocol, TypeVar
from uuid import UUID, uuid5
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from app.models.deadline_plans import DeadlinePlansResponse
from app.models.planner import PlannerOverviewResponse
from app.models.today_overview import (
    TODAY_OVERVIEW_CONTRACT_VERSION,
    TODAY_OVERVIEW_V2_CONTRACT_VERSION,
    TodayCalendarEvent,
    TodayCheckIns,
    TodayFocusSession,
    TodayHabit,
    TodayHabitV2,
    TodayManualCommitment,
    TodayOverviewResponse,
    TodayOverviewV2Response,
    TodayPlannerHabitSlot,
    TodayPlannerTaskBlock,
    TodayPreparationBlock,
    TodayProgress,
    TodaySetupCommitment,
    TodaySourceState,
    TodaySourceStates,
    TodaySourceStatesV2,
    TodayTask,
    TodayTaskV2,
    TodayTasks,
    TodayTasksV2,
    TodayTimelineItem,
    TodayTimelineItemV2,
)
from app.repositories.today_overview_repository import (
    TodayCalendarRows,
    TodayHabitRows,
    TodayOverviewRepository,
)
from app.services.deadline_plan_service import DeadlinePlanService
from app.services.planning_availability import recurring_commitment_applies_on
from app.services.snapshot_daily_state import valid_explicit_capture_kinds


class TodayOverviewUnavailableError(RuntimeError):
    pass


class PlannerOverviewReader(Protocol):
    async def get_overview(self, *, user_id: str) -> PlannerOverviewResponse: ...


_T = TypeVar("_T")
_CAPTURE_PAGE_SIZE = 100


class TodayOverviewService:
    def __init__(
        self,
        *,
        repository: TodayOverviewRepository,
        deadline_plan_service: DeadlinePlanService,
        planner_service: PlannerOverviewReader | None = None,
        now: Callable[[], datetime] | None = None,
    ) -> None:
        self._repository = repository
        self._deadline_plan_service = deadline_plan_service
        self._planner_service = planner_service
        self._now = now or (lambda: datetime.now(UTC))

    async def get_overview(self, *, user_id: str) -> TodayOverviewResponse:
        generated_at = _aware_utc(self._now())
        try:
            timezone = await self._repository.get_profile_timezone(user_id=user_id)
            zone = ZoneInfo(timezone)
        except (ValueError, ZoneInfoNotFoundError) as exc:
            raise TodayOverviewUnavailableError(
                "Today is unavailable because the account timezone could not "
                "be loaded.",
            ) from exc
        local_date = generated_at.astimezone(zone).date()
        week_starts_on = local_date - timedelta(days=local_date.isoweekday() - 1)
        range_starts_at = datetime.combine(local_date, time.min, tzinfo=zone)
        range_ends_at = datetime.combine(
            local_date + timedelta(days=1),
            time.min,
            tzinfo=zone,
        )

        results = await asyncio.gather(
            self._load_check_ins(user_id=user_id, local_date=local_date),
            self._load_tasks(user_id=user_id, local_date=local_date, zone=zone),
            self._load_habits(
                user_id=user_id,
                week_starts_on=week_starts_on,
                local_date=local_date,
            ),
            self._load_setup_commitments(
                user_id=user_id,
                local_date=local_date,
                zone=zone,
                range_starts_at=range_starts_at,
                range_ends_at=range_ends_at,
            ),
            self._load_preparation(user_id=user_id, local_date=local_date),
            self._load_calendar(
                user_id=user_id,
                local_date=local_date,
                range_starts_at=range_starts_at,
                range_ends_at=range_ends_at,
            ),
            self._load_focus(
                user_id=user_id,
                generated_at=generated_at,
                range_starts_at=range_starts_at,
                range_ends_at=range_ends_at,
            ),
            return_exceptions=True,
        )

        check_ins = _result(results[0], TodayCheckIns)
        tasks = _result(results[1], TodayTasks)
        habits = _result_list(results[2], TodayHabit)
        setup = _result_list(results[3], TodaySetupCommitment)
        preparation = _result_list(results[4], TodayPreparationBlock)
        calendar = _result_list(results[5], TodayCalendarEvent)
        focus = _result_list(results[6], TodayFocusSession)

        source_states = TodaySourceStates(
            check_ins=_source_state(results[0], "Check-ins could not be loaded."),
            tasks=_source_state(results[1], "Tasks could not be loaded."),
            habits=_source_state(results[2], "Habits could not be loaded."),
            setup_commitments=_source_state(
                results[3],
                "Setup commitments could not be loaded.",
            ),
            preparation=_source_state(
                results[4],
                "Preparation blocks could not be loaded.",
            ),
            calendar_events=_source_state(
                results[5],
                "Calendar events could not be loaded.",
            ),
            focus_sessions=_source_state(
                results[6],
                "Focus sessions could not be loaded.",
            ),
        )
        unavailable_progress_sources = [
            name
            for name in ("check_ins", "tasks", "habits", "preparation")
            if getattr(source_states, name).status == "unavailable"
        ]

        timeline: list[TodayTimelineItem] = [
            *setup,
            *preparation,
            *calendar,
            *focus,
        ]
        timeline.sort(key=_timeline_sort_key)
        safe_tasks = tasks or TodayTasks(today=[], all=[])
        safe_habits = habits
        progress = None
        if not unavailable_progress_sources:
            assert check_ins is not None
            progress = TodayProgress(
                completed=(
                    int(check_ins.morning_saved)
                    + int(check_ins.evening_saved)
                    + sum(task.status == "done" for task in safe_tasks.today)
                    + sum(habit.outcome == "completed" for habit in safe_habits)
                    + sum(block.state == "completed" for block in preparation)
                ),
                total=(
                    2
                    + len(safe_tasks.today)
                    + len(safe_habits)
                    + len(preparation)
                ),
            )

        return TodayOverviewResponse(
            contract_version=TODAY_OVERVIEW_CONTRACT_VERSION,
            origin="authenticated_backend",
            local_date=local_date,
            timezone=timezone,
            generated_at=generated_at,
            check_ins=check_ins,
            progress=progress,
            progress_unavailable_sources=unavailable_progress_sources,
            timeline=timeline,
            tasks=safe_tasks,
            habits=safe_habits,
            source_states=source_states,
        )

    async def get_overview_v2(self, *, user_id: str) -> TodayOverviewV2Response:
        base_result, planner_result = await asyncio.gather(
            self.get_overview(user_id=user_id),
            (
                self._planner_service.get_overview(user_id=user_id)
                if self._planner_service is not None
                else _missing_planner()
            ),
            return_exceptions=True,
        )
        if isinstance(base_result, BaseException):
            if isinstance(base_result, TodayOverviewUnavailableError):
                raise base_result
            raise TodayOverviewUnavailableError("Today could not be loaded.") from base_result
        if not isinstance(base_result, TodayOverviewResponse):
            raise TypeError("Today V1 returned an unexpected projection.")
        base = base_result
        planner = (
            planner_result
            if isinstance(planner_result, PlannerOverviewResponse)
            and planner_result.local_date == base.local_date
            and planner_result.timezone == base.timezone
            else None
        )
        planner_state = TodaySourceState(
            status="current" if planner is not None else "unavailable",
            message=None if planner is not None else "Planned blocks could not be loaded.",
        )
        planner_items = planner.days[0].items if planner is not None else []
        scheduled_task_ids = {
            item.source_id for item in planner_items if item.kind == "task_block"
        }
        scheduled_habit_ids = {
            item.source_id for item in planner_items if item.kind == "habit_slot"
        }

        source_values = base.source_states.model_dump()
        tasks_state = base.source_states.tasks
        all_task_ids = {task.id for task in base.tasks.all}
        if planner is not None and not scheduled_task_ids.issubset(all_task_ids):
            tasks_state = TodaySourceState(
                status="unavailable",
                message="Tasks changed while Today was loading.",
            )
            source_values["tasks"] = tasks_state.model_dump()
        safe_tasks = _today_v2_tasks(
            base.tasks if tasks_state.status == "current" else TodayTasks(today=[], all=[]),
            scheduled_ids=scheduled_task_ids,
        )

        habits_state = base.source_states.habits
        safe_habits: list[TodayHabitV2]
        if planner is not None and habits_state.status == "current":
            try:
                week_starts_on = base.local_date - timedelta(
                    days=base.local_date.isoweekday() - 1,
                )
                forced = await self._load_habits(
                    user_id=user_id,
                    week_starts_on=week_starts_on,
                    local_date=base.local_date,
                    forced_ids=scheduled_habit_ids,
                )
                safe_habits = [
                    TodayHabitV2(
                        **habit.model_dump(),
                        scheduled_today=habit.id in scheduled_habit_ids,
                    )
                    for habit in forced
                ]
            except Exception:
                habits_state = TodaySourceState(
                    status="unavailable",
                    message="Habits changed while Today was loading.",
                )
                source_values["habits"] = habits_state.model_dump()
                safe_habits = []
        else:
            safe_habits = [
                TodayHabitV2(**habit.model_dump(), scheduled_today=False)
                for habit in base.habits
            ]

        source_states = TodaySourceStatesV2(
            **source_values,
            planner=planner_state,
        )
        unavailable_progress_sources = [
            name
            for name in ("check_ins", "tasks", "habits", "preparation", "planner")
            if getattr(source_states, name).status == "unavailable"
        ]
        timeline: list[TodayTimelineItemV2] = [*base.timeline]
        for item in planner_items:
            if item.kind not in {"task_block", "habit_slot", "manual_commitment"}:
                continue
            if item.kind == "task_block" and tasks_state.status != "current":
                continue
            if item.kind == "habit_slot" and habits_state.status != "current":
                continue
            if item.starts_at is None or item.ends_at is None:
                raise ValueError("A timed Planner item has no interval.")
            common = {
                "id": item.id,
                "title": item.title,
                "location": None,
                "all_day": False,
                "starts_at": item.starts_at,
                "ends_at": item.ends_at,
            }
            if item.kind == "task_block":
                timeline.append(
                    TodayPlannerTaskBlock(
                        **common,
                        kind="task_block",
                        task_id=item.source_id,
                        planned_minutes=_interval_minutes(
                            item.starts_at,
                            item.ends_at,
                        ),
                    ),
                )
            elif item.kind == "habit_slot":
                timeline.append(
                    TodayPlannerHabitSlot(
                        **common,
                        kind="habit_slot",
                        habit_id=item.source_id,
                        planned_minutes=_interval_minutes(
                            item.starts_at,
                            item.ends_at,
                        ),
                    ),
                )
            else:
                timeline.append(
                    TodayManualCommitment(
                        **common,
                        kind="manual_commitment",
                        commitment_id=item.source_id,
                    ),
                )
        timeline.sort(key=_timeline_v2_sort_key)
        progress = None
        if not unavailable_progress_sources:
            assert base.check_ins is not None
            preparation = [
                item for item in timeline if isinstance(item, TodayPreparationBlock)
            ]
            progress = TodayProgress(
                completed=(
                    int(base.check_ins.morning_saved)
                    + int(base.check_ins.evening_saved)
                    + sum(task.status == "done" for task in safe_tasks.today)
                    + sum(habit.outcome == "completed" for habit in safe_habits)
                    + sum(block.state == "completed" for block in preparation)
                ),
                total=(
                    2
                    + len(safe_tasks.today)
                    + len(safe_habits)
                    + len(preparation)
                ),
            )
        return TodayOverviewV2Response(
            contract_version=TODAY_OVERVIEW_V2_CONTRACT_VERSION,
            origin="authenticated_backend",
            local_date=base.local_date,
            timezone=base.timezone,
            generated_at=base.generated_at,
            check_ins=base.check_ins,
            progress=progress,
            progress_unavailable_sources=unavailable_progress_sources,
            timeline=timeline,
            tasks=safe_tasks,
            habits=safe_habits,
            source_states=source_states,
        )

    async def _load_check_ins(
        self,
        *,
        user_id: str,
        local_date: date,
    ) -> TodayCheckIns:
        offset = 0
        by_date: dict[date, frozenset[str]] = {}
        reached_end = False
        expected: date | None = None
        streak = 0
        while True:
            page = await self._repository.list_daily_logs_page(
                user_id=user_id,
                offset=offset,
                limit=_CAPTURE_PAGE_SIZE,
            )
            if len(page) > _CAPTURE_PAGE_SIZE:
                raise ValueError("Today capture page exceeded its requested bound.")
            for row in page:
                row_date = _date(row.get("entry_date"))
                if row_date > local_date or row_date in by_date:
                    continue
                by_date[row_date] = valid_explicit_capture_kinds(row)
            reached_end = len(page) < _CAPTURE_PAGE_SIZE

            today_kinds = by_date.get(local_date, frozenset())
            if expected is None:
                expected = (
                    local_date
                    if {"morning", "evening"}.issubset(today_kinds)
                    else local_date - timedelta(days=1)
                )
            while expected in by_date:
                kinds = by_date[expected]
                if not {"morning", "evening"}.issubset(kinds):
                    return TodayCheckIns(
                        morning_saved="morning" in today_kinds,
                        evening_saved="evening" in today_kinds,
                        completed_days_streak=streak,
                    )
                streak += 1
                expected -= timedelta(days=1)

            older_loaded = any(row_date < expected for row_date in by_date)
            if reached_end or older_loaded:
                return TodayCheckIns(
                    morning_saved="morning" in today_kinds,
                    evening_saved="evening" in today_kinds,
                    completed_days_streak=streak,
                )
            offset += len(page)
            if not page:
                raise ValueError("Today capture pagination did not converge.")

    async def _load_tasks(
        self,
        *,
        user_id: str,
        local_date: date,
        zone: ZoneInfo,
    ) -> TodayTasks:
        rows = await self._repository.list_tasks(user_id=user_id)
        if len(rows) > 1_000:
            raise ValueError("Today task count exceeds its response bound.")
        parsed: list[TodayTask] = []
        selected: list[tuple[int, datetime | None, TodayTask]] = []
        for row in rows:
            task = _task(row)
            parsed.append(task)
            if task.deadline_plan_id is not None:
                continue
            deadline_date = (
                task.deadline.astimezone(zone).date()
                if task.deadline is not None
                else None
            )
            reason = None
            rank = 99
            if task.status == "todo" and deadline_date is not None:
                if deadline_date < local_date:
                    reason, rank = "overdue", 0
                elif deadline_date == local_date:
                    reason, rank = "due_today", 1
            elif task.status == "in_progress":
                reason, rank = "in_progress", 2
            elif (
                task.status == "done"
                and task.completed_at is not None
                and task.completed_at.astimezone(zone).date() == local_date
            ):
                reason, rank = "completed_today", 3
            if reason is not None:
                selected.append(
                    (
                        rank,
                        task.deadline,
                        task.model_copy(update={"today_reason": reason}),
                    ),
                )
        selected.sort(
            key=lambda item: (
                item[0],
                item[1] or datetime.max.replace(tzinfo=UTC),
                item[2].title.casefold(),
                str(item[2].id),
            ),
        )
        parsed.sort(
            key=lambda task: (
                task.status in {"done", "cancelled"},
                task.deadline or datetime.max.replace(tzinfo=UTC),
                task.title.casefold(),
                str(task.id),
            ),
        )
        return TodayTasks(today=[item[2] for item in selected], all=parsed)

    async def _load_habits(
        self,
        *,
        user_id: str,
        week_starts_on: date,
        local_date: date,
        forced_ids: set[UUID] | None = None,
    ) -> list[TodayHabit]:
        source = await self._repository.load_habits(
            user_id=user_id,
            week_starts_on=week_starts_on,
            local_date=local_date,
        )
        if len(source.habits) > 500 or len(source.logs) > 5_000:
            raise ValueError("Today habit projection exceeds its response bound.")
        logs_by_habit: dict[UUID, dict[date, str]] = {}
        for row in source.logs:
            habit_id = _uuid(row.get("habit_id"))
            entry_date = _date(row.get("entry_date"))
            status = row.get("status")
            value = row.get("value")
            if status not in {"completed", "skipped"} or (
                (status == "completed" and value != 1)
                or (status == "skipped" and value != 0)
            ):
                raise ValueError("Today habit outcome is invalid.")
            habit_logs = logs_by_habit.setdefault(habit_id, {})
            if entry_date in habit_logs:
                raise ValueError("Today habit outcome is duplicated.")
            habit_logs[entry_date] = status

        habits: list[TodayHabit] = []
        for row in source.habits:
            metadata = _metadata(row.get("metadata"))
            setup_state = str(
                metadata.get("setup_state") or metadata.get("status") or "",
            )
            lifecycle = str(metadata.get("lifecycle") or "active")
            if (
                setup_state in {"candidate", "archived", "paused"}
                or lifecycle != "active"
            ):
                continue
            cadence, weekdays, target, cadence_label = _habit_cadence(row, metadata)
            habit_id = _uuid(row.get("id"))
            outcome_by_date = logs_by_habit.get(habit_id, {})
            outcome = outcome_by_date.get(local_date)
            weekly_completed = sum(
                value == "completed" for value in outcome_by_date.values()
            )
            relevant = cadence == "daily" or (
                cadence == "weekdays" and local_date.isoweekday() in weekdays
            )
            if cadence == "weekly_target":
                relevant = weekly_completed < target or outcome is not None
            if forced_ids and habit_id in forced_ids:
                relevant = True
            if not relevant:
                continue
            habits.append(
                TodayHabit(
                    id=habit_id,
                    title=_text(row.get("title"), maximum=160),
                    description=_optional_text(row.get("description"), maximum=2_000),
                    cadence=cadence,
                    cadence_label=cadence_label,
                    outcome=outcome,
                    weekly_completed=weekly_completed,
                    weekly_target=target,
                    setup_managed=metadata.get("managed_by") == "setup",
                ),
            )
        habits.sort(
            key=lambda habit: (
                habit.outcome is not None,
                habit.title.casefold(),
                str(habit.id),
            ),
        )
        return habits

    async def _load_setup_commitments(
        self,
        *,
        user_id: str,
        local_date: date,
        zone: ZoneInfo,
        range_starts_at: datetime,
        range_ends_at: datetime,
    ) -> list[TodaySetupCommitment]:
        rows = await self._repository.list_schedule_items(user_id=user_id)
        if len(rows) > 1_000:
            raise ValueError("Today setup commitment count exceeds its bound.")
        items: list[TodaySetupCommitment] = []
        for row in rows:
            row_id = _uuid(row.get("id"))
            weekday = _int(row.get("weekday"), minimum=1, maximum=7)
            start_time = _time(row.get("starts_at"))
            end_time = _time(row.get("ends_at"))
            for occurrence_date in (local_date - timedelta(days=1), local_date):
                if (
                    occurrence_date.isoweekday() != weekday
                    or not recurring_commitment_applies_on(row, occurrence_date)
                ):
                    continue
                starts_at = datetime.combine(occurrence_date, start_time, tzinfo=zone)
                ends_at = datetime.combine(occurrence_date, end_time, tzinfo=zone)
                if ends_at <= starts_at:
                    ends_at += timedelta(days=1)
                if starts_at >= range_ends_at or ends_at <= range_starts_at:
                    continue
                items.append(
                    TodaySetupCommitment(
                        kind="setup_commitment",
                        id=uuid5(row_id, occurrence_date.isoformat()),
                        title=_text(row.get("title"), maximum=200),
                        location=_optional_text(row.get("location"), maximum=300),
                        all_day=False,
                        starts_at=starts_at,
                        ends_at=ends_at,
                    ),
                )
        return items

    async def _load_preparation(
        self,
        *,
        user_id: str,
        local_date: date,
    ) -> list[TodayPreparationBlock]:
        response = await self._deadline_plan_service.list_plans(user_id=user_id)
        return _preparation_items(response, local_date=local_date)

    async def _load_calendar(
        self,
        *,
        user_id: str,
        local_date: date,
        range_starts_at: datetime,
        range_ends_at: datetime,
    ) -> list[TodayCalendarEvent]:
        source = await self._repository.load_current_calendar(user_id=user_id)
        if len(source.events) > 500:
            raise ValueError("Today calendar event count exceeds its bound.")
        if source.source_label is None:
            if source.events:
                raise ValueError("Today calendar events have no current source.")
            return []
        return _calendar_items(
            source,
            local_date=local_date,
            range_starts_at=range_starts_at,
            range_ends_at=range_ends_at,
        )

    async def _load_focus(
        self,
        *,
        user_id: str,
        generated_at: datetime,
        range_starts_at: datetime,
        range_ends_at: datetime,
    ) -> list[TodayFocusSession]:
        rows = await self._repository.list_focus_sessions(
            user_id=user_id,
            range_starts_at=range_starts_at,
            range_ends_at=range_ends_at,
        )
        if len(rows) > 1_000:
            raise ValueError("Today focus session count exceeds its bound.")
        items: list[TodayFocusSession] = []
        for row in rows:
            status = row.get("status")
            if status not in {"active", "completed", "abandoned"}:
                raise ValueError("Today focus status is invalid.")
            starts_at = _datetime(row.get("started_at"))
            ended = row.get("ended_at")
            ends_at = generated_at if status == "active" else _datetime(ended)
            if ends_at < starts_at:
                raise ValueError("Today focus interval is invalid.")
            # A just-started active session still needs a positive renderable range.
            if ends_at == starts_at:
                ends_at += timedelta(seconds=1)
            if starts_at >= range_ends_at or ends_at <= range_starts_at:
                continue
            actual = row.get("actual_minutes")
            if status == "active":
                if actual is not None:
                    raise ValueError("Active Today focus contains actual minutes.")
                actual_minutes = None
            else:
                actual_minutes = _int(actual, minimum=0)
            label = _optional_text(row.get("label"), maximum=200)
            items.append(
                TodayFocusSession(
                    kind="focus_session",
                    id=_uuid(row.get("id")),
                    title=label or "Focus session",
                    location=None,
                    all_day=False,
                    starts_at=starts_at,
                    ends_at=ends_at,
                    status=status,
                    actual_minutes=actual_minutes,
                ),
            )
        return items


def _source_state(value: object, message: str) -> TodaySourceState:
    return TodaySourceState(
        status="unavailable" if isinstance(value, BaseException) else "current",
        message=message if isinstance(value, BaseException) else None,
    )


def _result(value: object, expected: type[_T]) -> _T | None:
    if isinstance(value, BaseException):
        return None
    if not isinstance(value, expected):
        raise TypeError("Today source returned an unexpected projection.")
    return value


def _result_list(value: object, expected: type[_T]) -> list[_T]:
    if isinstance(value, BaseException):
        return []
    if not isinstance(value, list) or any(
        not isinstance(item, expected) for item in value
    ):
        raise TypeError("Today source returned an unexpected list projection.")
    return value


def _task(row: dict[str, Any]) -> TodayTask:
    status = row.get("status")
    if status not in {"todo", "in_progress", "done", "cancelled"}:
        raise ValueError("Today task status is invalid.")
    priority = row.get("priority")
    if priority not in {"low", "medium", "high", "critical"}:
        raise ValueError("Today task priority is invalid.")
    source = _text(row.get("source"), maximum=100)
    task_id = _uuid(row.get("id"))
    completed_at = _optional_datetime(row.get("completed_at"))
    return TodayTask(
        id=task_id,
        title=_text(row.get("title"), maximum=160),
        description=_optional_text(row.get("description"), maximum=2_000),
        status=status,
        priority=priority,
        deadline=_optional_datetime(row.get("deadline")),
        estimated_minutes=_optional_int(
            row.get("estimated_minutes"),
            minimum=5,
            maximum=480,
        ),
        completed_at=completed_at,
        source=source,
        deadline_plan_id=task_id if source == "deadline-plan-v1" else None,
    )


def _habit_cadence(
    row: dict[str, Any],
    metadata: dict[str, Any],
) -> tuple[str, set[int], int, str]:
    raw_cadence = metadata.get("cadence")
    if raw_cadence is not None and metadata.get("contract_version") != "habit-v1":
        raise ValueError("Today habit cadence contract is invalid.")
    if raw_cadence == "weekdays":
        raw_days = metadata.get("scheduled_weekdays")
        if not isinstance(raw_days, list):
            raise ValueError("Today habit weekdays are invalid.")
        days = {_int(value, minimum=1, maximum=7) for value in raw_days}
        if not days or len(days) != len(raw_days):
            raise ValueError("Today habit weekdays are invalid.")
        labels = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
        return (
            "weekdays",
            days,
            1,
            "On " + ", ".join(labels[day - 1] for day in sorted(days)),
        )
    target = _int(row.get("target"), minimum=1, maximum=7)
    if raw_cadence == "weekly_target" or (
        raw_cadence is None and row.get("frequency") == "weekly"
    ):
        return "weekly_target", set(), target, f"{target} times per week"
    if raw_cadence not in {None, "daily"} or row.get("frequency") not in {
        "daily",
        "weekly",
    }:
        raise ValueError("Today habit cadence is invalid.")
    return "daily", set(), 1, "Daily"


def _preparation_items(
    response: DeadlinePlansResponse,
    *,
    local_date: date,
) -> list[TodayPreparationBlock]:
    items: list[TodayPreparationBlock] = []
    for detail in response.plans:
        if detail.plan.status != "active" or detail.active_revision is None:
            continue
        managed_task_id = detail.plan.managed_task_id
        if managed_task_id is None:
            raise ValueError("Active Today preparation has no managed task.")
        for block in detail.active_revision.blocks:
            if block.local_date != local_date:
                continue
            if block.state == "proposed":
                raise ValueError("Active Today preparation block is still proposed.")
            items.append(
                TodayPreparationBlock(
                    kind="preparation",
                    id=block.id,
                    title=detail.plan.title,
                    location=None,
                    all_day=False,
                    starts_at=block.starts_at,
                    ends_at=block.ends_at,
                    plan_id=detail.plan.id,
                    block_id=block.id,
                    managed_task_id=managed_task_id,
                    state=block.state,
                    planned_minutes=block.planned_minutes,
                    credited_tracked_minutes=block.credited_tracked_minutes,
                ),
            )
    return items


def _calendar_items(
    source: TodayCalendarRows,
    *,
    local_date: date,
    range_starts_at: datetime,
    range_ends_at: datetime,
) -> list[TodayCalendarEvent]:
    assert source.source_label is not None
    items: list[TodayCalendarEvent] = []
    for row in source.events:
        event_kind = row.get("event_kind")
        if row.get("event_status") not in {"confirmed", "tentative"} or row.get(
            "busy_status",
        ) not in {"busy", "free"}:
            raise ValueError("Today calendar event state is invalid.")
        common = {
            "kind": "calendar_event",
            "id": _uuid(row.get("id")),
            "title": _text(row.get("title"), maximum=200),
            "location": _optional_text(row.get("location"), maximum=300),
            "source_label": source.source_label,
        }
        if event_kind == "all_day":
            starts_on = _date(row.get("starts_on"))
            ends_on = _date(row.get("ends_on"))
            if not (starts_on <= local_date < ends_on):
                continue
            items.append(
                TodayCalendarEvent(
                    **common,
                    all_day=True,
                    starts_on=starts_on,
                    ends_on=ends_on,
                ),
            )
        elif event_kind == "timed":
            starts_at = _datetime(row.get("starts_at"))
            ends_at = _datetime(row.get("ends_at"))
            if starts_at >= range_ends_at or ends_at <= range_starts_at:
                continue
            items.append(
                TodayCalendarEvent(
                    **common,
                    all_day=False,
                    starts_at=starts_at,
                    ends_at=ends_at,
                ),
            )
        else:
            raise ValueError("Today calendar event kind is invalid.")
    return items


def _timeline_sort_key(item: TodayTimelineItem) -> tuple[object, ...]:
    if isinstance(item, TodayCalendarEvent) and item.all_day:
        return (
            0,
            datetime.min.replace(tzinfo=UTC),
            item.title.casefold(),
            str(item.id),
        )
    starts_at = getattr(item, "starts_at", None)
    if not isinstance(starts_at, datetime):
        raise ValueError("Today timed item has no start timestamp.")
    kind_rank = {
        "setup_commitment": 0,
        "preparation": 1,
        "calendar_event": 2,
        "focus_session": 3,
    }[item.kind]
    return (
        1,
        starts_at.astimezone(UTC),
        kind_rank,
        item.title.casefold(),
        str(item.id),
    )


async def _missing_planner() -> PlannerOverviewResponse:
    raise RuntimeError("Planner service is unavailable.")


def _today_v2_tasks(
    source: TodayTasks,
    *,
    scheduled_ids: set[UUID],
) -> TodayTasksV2:
    all_by_id = {task.id: task for task in source.all}
    selected = {task.id: task for task in source.today}
    for task_id in scheduled_ids:
        task = all_by_id.get(task_id)
        if task is None:
            continue
        selected.setdefault(
            task_id,
            task.model_copy(update={"today_reason": "scheduled_today"}),
        )
    all_tasks = [
        TodayTaskV2(
            **task.model_dump(),
            scheduled_today=task.id in scheduled_ids,
        )
        for task in source.all
    ]
    reason_rank = {
        "overdue": 0,
        "due_today": 1,
        "in_progress": 2,
        "completed_today": 3,
        "scheduled_today": 4,
    }
    today_tasks = [
        TodayTaskV2(
            **task.model_dump(),
            scheduled_today=task.id in scheduled_ids,
        )
        for task in selected.values()
    ]
    today_tasks.sort(
        key=lambda task: (
            reason_rank[task.today_reason or "scheduled_today"],
            task.deadline or datetime.max.replace(tzinfo=UTC),
            task.title.casefold(),
            str(task.id),
        ),
    )
    return TodayTasksV2(today=today_tasks, all=all_tasks)


def _interval_minutes(starts_at: datetime, ends_at: datetime) -> int:
    seconds = (ends_at.astimezone(UTC) - starts_at.astimezone(UTC)).total_seconds()
    if seconds <= 0 or seconds % 300 != 0:
        raise ValueError("Planner Today block duration is invalid.")
    minutes = int(seconds // 60)
    if minutes < 5 or minutes > 240:
        raise ValueError("Planner Today block duration is out of range.")
    return minutes


def _timeline_v2_sort_key(item: TodayTimelineItemV2) -> tuple[object, ...]:
    if isinstance(item, TodayCalendarEvent) and item.all_day:
        return (
            0,
            datetime.min.replace(tzinfo=UTC),
            item.title.casefold(),
            str(item.id),
        )
    starts_at = getattr(item, "starts_at", None)
    if not isinstance(starts_at, datetime):
        raise ValueError("Today-v2 timed item has no start timestamp.")
    kind_rank = {
        "setup_commitment": 0,
        "manual_commitment": 1,
        "task_block": 2,
        "habit_slot": 3,
        "preparation": 4,
        "calendar_event": 5,
        "focus_session": 6,
    }[item.kind]
    return (
        1,
        starts_at.astimezone(UTC),
        kind_rank,
        item.title.casefold(),
        str(item.id),
    )


def _metadata(value: Any) -> dict[str, Any]:
    if value is None:
        return {}
    if not isinstance(value, dict):
        raise ValueError("Today metadata is invalid.")
    return value


def _text(value: Any, *, maximum: int) -> str:
    if (
        not isinstance(value, str)
        or not value
        or value.strip() != value
        or len(value) > maximum
    ):
        raise ValueError("Today text is invalid.")
    return value


def _optional_text(value: Any, *, maximum: int) -> str | None:
    if value is None:
        return None
    return _text(value, maximum=maximum)


def _uuid(value: Any) -> UUID:
    if not isinstance(value, str):
        raise ValueError("Today UUID is invalid.")
    parsed = UUID(value)
    if str(parsed) != value.lower():
        raise ValueError("Today UUID is invalid.")
    return parsed


def _date(value: Any) -> date:
    if isinstance(value, date) and not isinstance(value, datetime):
        return value
    if not isinstance(value, str):
        raise ValueError("Today date is invalid.")
    parsed = date.fromisoformat(value)
    if parsed.isoformat() != value:
        raise ValueError("Today date is invalid.")
    return parsed


def _time(value: Any) -> time:
    if isinstance(value, time):
        parsed = value
    elif isinstance(value, str):
        parsed = time.fromisoformat(value)
    else:
        raise ValueError("Today time is invalid.")
    if parsed.tzinfo is not None:
        raise ValueError("Today local time cannot carry an offset.")
    return parsed


def _datetime(value: Any) -> datetime:
    if isinstance(value, datetime):
        parsed = value
    elif isinstance(value, str):
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    else:
        raise ValueError("Today timestamp is invalid.")
    if parsed.tzinfo is None or parsed.utcoffset() is None:
        raise ValueError("Today timestamp must be timezone-aware.")
    return parsed


def _optional_datetime(value: Any) -> datetime | None:
    return None if value is None else _datetime(value)


def _int(value: Any, *, minimum: int, maximum: int | None = None) -> int:
    if isinstance(value, bool) or not isinstance(value, int):
        raise ValueError("Today integer is invalid.")
    if value < minimum or (maximum is not None and value > maximum):
        raise ValueError("Today integer is outside its bound.")
    return value


def _optional_int(
    value: Any,
    *,
    minimum: int,
    maximum: int | None = None,
) -> int | None:
    return None if value is None else _int(value, minimum=minimum, maximum=maximum)


def _aware_utc(value: datetime) -> datetime:
    if value.tzinfo is None or value.utcoffset() is None:
        raise ValueError("Today clock must be timezone-aware.")
    return value.astimezone(UTC)
