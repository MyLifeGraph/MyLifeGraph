#!/usr/bin/env python3
"""Enrich the local student demo with backend-owned, contract-valid features."""

from __future__ import annotations

import asyncio
import hashlib
import os
import sys
from datetime import UTC, date, datetime, time, timedelta
from pathlib import Path
from urllib.parse import urlparse
from uuid import UUID
from zoneinfo import ZoneInfo


ROOT = Path(__file__).resolve().parents[1]
SERVICE_ROOT = ROOT / "services" / "ai_service"
sys.path.insert(0, str(SERVICE_ROOT))

from app.clients.supabase import SupabaseRestClient  # noqa: E402
from app.core.config import Settings  # noqa: E402
from app.models.briefings import BriefingGenerateRequest  # noqa: E402
from app.models.calendar_integrations import (  # noqa: E402
    CalendarConnectionCreateRequest,
    CalendarFileImportRequest,
)
from app.models.coach import CoachRequest  # noqa: E402
from app.models.deadline_plans import (  # noqa: E402
    DeadlinePlanMutationRequest,
    DeadlinePlanProposalRequest,
)
from app.models.notifications import (  # noqa: E402
    NotificationSettingsUpdateRequest,
)
from app.models.snapshots import SnapshotGenerateRequest  # noqa: E402
from app.models.weekly_reviews import WeeklyReviewGenerateRequest  # noqa: E402
from app.providers.fake import FakeCoachProvider  # noqa: E402
from app.repositories.briefing_repository import (  # noqa: E402
    SupabaseBriefingRepository,
)
from app.repositories.calendar_integration_repository import (  # noqa: E402
    SupabaseCalendarIntegrationRepository,
)
from app.repositories.coach_context_repository import (  # noqa: E402
    SupabaseCoachContextRepository,
)
from app.repositories.coach_repository import SupabaseCoachRepository  # noqa: E402
from app.repositories.deadline_plan_repository import (  # noqa: E402
    SupabaseDeadlinePlanRepository,
)
from app.repositories.notification_repository import (  # noqa: E402
    SupabaseNotificationRepository,
)
from app.repositories.snapshot_repository import (  # noqa: E402
    SupabaseSnapshotRepository,
)
from app.repositories.weekly_review_repository import (  # noqa: E402
    SupabaseWeeklyReviewRepository,
)
from app.services.briefing_service import BriefingService  # noqa: E402
from app.services.calendar_integration_service import (  # noqa: E402
    CalendarIntegrationService,
)
from app.services.coach_context import CoachContextService  # noqa: E402
from app.services.coach_service import CoachService  # noqa: E402
from app.services.deadline_plan_service import DeadlinePlanService  # noqa: E402
from app.services.notification_service import (  # noqa: E402
    NotificationGenerationService,
    NotificationService,
)
from app.services.snapshot_aggregator import SnapshotAggregator  # noqa: E402
from app.services.weekly_review_service import WeeklyReviewService  # noqa: E402


STUDENT_EMAIL = "student@example.test"
STUDENT_DAILY_BUDGET = 180


def _stable_uuid(seed: str) -> UUID:
    raw = bytearray(hashlib.sha256(seed.encode("utf-8")).digest()[:16])
    raw[6] = (raw[6] & 0x0F) | 0x50
    raw[8] = (raw[8] & 0x3F) | 0x80
    return UUID(bytes=bytes(raw))


def _required_environment(name: str) -> str:
    value = os.environ.get(name, "").strip()
    if not value:
        raise RuntimeError(f"{name} is required")
    return value


def _require_local_supabase(url: str) -> None:
    parsed = urlparse(url)
    if (
        parsed.scheme != "http"
        or parsed.hostname not in {"127.0.0.1", "localhost"}
        or parsed.port != 54321
    ):
        raise RuntimeError(
            "Refusing to enrich a non-local Supabase project. "
            "Expected http://127.0.0.1:54321 or http://localhost:54321."
        )


def _latest_completed_week(today: date) -> tuple[date, date, str]:
    current_monday = today - timedelta(days=today.weekday())
    starts_on = current_monday - timedelta(days=7)
    ends_on = current_monday - timedelta(days=1)
    iso_year, iso_week, _ = starts_on.isocalendar()
    return starts_on, ends_on, f"{iso_year}-W{iso_week:02d}"


def _aware_local(day: date, hour: int, minute: int, zone: ZoneInfo) -> datetime:
    return datetime.combine(day, time(hour, minute), tzinfo=zone)


def _ical_datetime(value: datetime) -> str:
    return value.strftime("%Y%m%dT%H%M%S")


def _calendar_fixture(*, today: date, timezone: str) -> str:
    zone = ZoneInfo(timezone)
    tutorial = _aware_local(today + timedelta(days=2), 10, 0, zone)
    study_group = _aware_local(today + timedelta(days=5), 16, 0, zone)
    essay_due = _aware_local(today + timedelta(days=24), 14, 0, zone)
    office_hours = _aware_local(today + timedelta(days=7), 12, 0, zone)
    conference = today + timedelta(days=9)
    recurring = _aware_local(today + timedelta(days=3), 8, 0, zone)
    lines = [
        "BEGIN:VCALENDAR",
        "VERSION:2.0",
        "PRODID:-//MyLifeGraph//Student Feature Demo//EN",
        "CALSCALE:GREGORIAN",
        "BEGIN:VEVENT",
        "UID:student-statistics-tutorial@example.test",
        f"DTSTART;TZID={timezone}:{_ical_datetime(tutorial)}",
        f"DTEND;TZID={timezone}:{_ical_datetime(tutorial + timedelta(minutes=90))}",
        "SUMMARY:Statistics tutorial",
        "LOCATION:Seminar room B12",
        "STATUS:CONFIRMED",
        "TRANSP:OPAQUE",
        "END:VEVENT",
        "BEGIN:VEVENT",
        "UID:student-study-group@example.test",
        f"DTSTART;TZID={timezone}:{_ical_datetime(study_group)}",
        f"DTEND;TZID={timezone}:{_ical_datetime(study_group + timedelta(minutes=90))}",
        "SUMMARY:Campus study group",
        "LOCATION:Main library",
        "STATUS:TENTATIVE",
        "TRANSP:OPAQUE",
        "END:VEVENT",
        "BEGIN:VEVENT",
        "UID:student-essay-deadline@example.test",
        f"DTSTART;TZID={timezone}:{_ical_datetime(essay_due)}",
        f"DTEND;TZID={timezone}:{_ical_datetime(essay_due + timedelta(hours=1))}",
        "SUMMARY:Research methods essay due",
        "LOCATION:Online submission",
        "STATUS:CONFIRMED",
        "TRANSP:OPAQUE",
        "END:VEVENT",
        "BEGIN:VEVENT",
        "UID:student-office-hours@example.test",
        f"DTSTART;TZID={timezone}:{_ical_datetime(office_hours)}",
        f"DTEND;TZID={timezone}:{_ical_datetime(office_hours + timedelta(hours=1))}",
        "SUMMARY:Optional professor office hours",
        "LOCATION:Faculty office",
        "STATUS:CONFIRMED",
        "TRANSP:TRANSPARENT",
        "END:VEVENT",
        "BEGIN:VEVENT",
        "UID:student-conference@example.test",
        f"DTSTART;VALUE=DATE:{conference.strftime('%Y%m%d')}",
        f"DTEND;VALUE=DATE:{(conference + timedelta(days=1)).strftime('%Y%m%d')}",
        "SUMMARY:Student research conference",
        "STATUS:CONFIRMED",
        "TRANSP:OPAQUE",
        "END:VEVENT",
        "BEGIN:VEVENT",
        "UID:student-unsupported-recurrence@example.test",
        f"DTSTART;TZID={timezone}:{_ical_datetime(recurring)}",
        f"DTEND;TZID={timezone}:{_ical_datetime(recurring + timedelta(minutes=30))}",
        "RRULE:FREQ=DAILY;COUNT=3",
        "SUMMARY:Recurring review reminder",
        "END:VEVENT",
        "END:VCALENDAR",
        "",
    ]
    return "\r\n".join(lines)


async def _profile(client: SupabaseRestClient) -> dict[str, object]:
    rows = await client.select(
        "profiles",
        params={
            "select": "id,email,timezone,onboarding_completed_at,role",
            "email": f"eq.{STUDENT_EMAIL}",
            "limit": "2",
        },
    )
    if len(rows) != 1:
        raise RuntimeError("The local student demo profile is unavailable.")
    row = rows[0]
    if row.get("onboarding_completed_at") is None or row.get("role") != "user":
        raise RuntimeError("The local student demo profile is not Setup-eligible.")
    return row


async def _seed_calendar(
    *,
    client: SupabaseRestClient,
    user_id: str,
    today: date,
    timezone: str,
) -> tuple[CalendarIntegrationService, object]:
    service = CalendarIntegrationService(
        repository=SupabaseCalendarIntegrationRepository(client)
    )
    connection = await service.create_connection(
        user_id=user_id,
        request=CalendarConnectionCreateRequest.model_validate(
            {
                "request_id": str(
                    _stable_uuid(f"demo-seed:calendar-connect:{user_id}")
                ),
                "source_kind": "ical_file",
                "source_label": "Maya study calendar",
                "consent": {
                    "consent_version": "calendar-import-consent-v1",
                    "read_calendar_events": True,
                    "store_event_basics": True,
                    "provider_writes": False,
                    "llm_processing": False,
                },
            }
        ),
    )
    if connection.connection is None:
        raise RuntimeError("Student calendar connection was not persisted.")
    await service.import_file(
        user_id=user_id,
        connection_id=connection.connection.id,
        request=CalendarFileImportRequest.model_validate(
            {
                "request_id": str(
                    _stable_uuid(f"demo-seed:calendar-import:{user_id}")
                ),
                "calendar_text": _calendar_fixture(
                    today=today,
                    timezone=timezone,
                ),
            }
        ),
    )
    events = await service.get_events(
        user_id=user_id,
        connection_id=connection.connection.id,
        cursor=None,
        limit=50,
    )
    source_event = next(
        (
            event
            for event in events.events
            if event.title == "Research methods essay due"
        ),
        None,
    )
    if source_event is None or source_event.starts_at is None:
        raise RuntimeError("Student calendar deadline event was not imported.")
    return service, source_event


async def _propose_plan(
    *,
    service: DeadlinePlanService,
    user_id: str,
    seed: str,
    payload: dict[str, object],
    confirm: bool,
):
    plan_id = _stable_uuid(f"demo-seed:deadline-plan:{user_id}:{seed}")
    response = await service.propose(
        user_id=user_id,
        request=DeadlinePlanProposalRequest.model_validate(
            {
                "request_id": str(
                    _stable_uuid(f"demo-seed:deadline-proposal:{user_id}:{seed}")
                ),
                "plan_id": str(plan_id),
                "base_revision": 0,
                **payload,
            }
        ),
    )
    if not confirm:
        return response
    return await service.confirm(
        user_id=user_id,
        plan_id=plan_id,
        request=DeadlinePlanMutationRequest.model_validate(
            {
                "request_id": str(
                    _stable_uuid(f"demo-seed:deadline-confirm:{user_id}:{seed}")
                ),
                "expected_revision": response.plan.latest_revision,
            }
        ),
    )


async def _seed_deadline_plans(
    *,
    client: SupabaseRestClient,
    user_id: str,
    today: date,
    timezone: str,
    source_event: object,
    now: datetime,
) -> DeadlinePlanService:
    await client.rpc(
        "set_daily_preparation_budget_v1",
        params={
            "p_user_id": user_id,
            "p_daily_preparation_budget_minutes": STUDENT_DAILY_BUDGET,
        },
    )
    planner_now = now - timedelta(days=2)
    service = DeadlinePlanService(
        repository=SupabaseDeadlinePlanRepository(client),
        now=lambda: planner_now,
    )
    zone = ZoneInfo(timezone)
    planning_start = (today - timedelta(days=2)).isoformat()
    calculus = await _propose_plan(
        service=service,
        user_id=user_id,
        seed="calculus",
        confirm=True,
        payload={
            "kind": "exam",
            "title": "Calculus final exam",
            "deadline_at": _aware_local(
                today + timedelta(days=18), 12, 0, zone
            ).isoformat(),
            "estimated_total_minutes": 420,
            "credited_prior_minutes": 60,
            "preferred_session_minutes": 60,
            "max_daily_minutes": 120,
            "planning_start_on": planning_start,
            "buffer_days": 1,
            "source_kind": "manual",
            "use_calendar_availability": False,
        },
    )
    await _propose_plan(
        service=service,
        user_id=user_id,
        seed="research-essay",
        confirm=True,
        payload={
            "kind": "assignment",
            "title": "Research methods essay",
            "deadline_at": source_event.starts_at.isoformat(),
            "estimated_total_minutes": 300,
            "credited_prior_minutes": 30,
            "preferred_session_minutes": 45,
            "max_daily_minutes": 90,
            "planning_start_on": planning_start,
            "buffer_days": 2,
            "source_kind": "calendar_event",
            "source_calendar_event_id": str(source_event.id),
            "source_calendar_event_fingerprint": source_event.source_fingerprint,
            "use_calendar_availability": True,
        },
    )
    await _propose_plan(
        service=service,
        user_id=user_id,
        seed="statistics-preview",
        confirm=False,
        payload={
            "kind": "exam",
            "title": "Statistics practice exam",
            "deadline_at": _aware_local(
                today + timedelta(days=35), 10, 0, zone
            ).isoformat(),
            "estimated_total_minutes": 240,
            "credited_prior_minutes": 0,
            "preferred_session_minutes": 40,
            "max_daily_minutes": 80,
            "planning_start_on": today.isoformat(),
            "buffer_days": 1,
            "source_kind": "manual",
            "use_calendar_availability": False,
        },
    )

    focus_start = planner_now + timedelta(hours=2)
    focus_end = focus_start + timedelta(minutes=40)
    await client.insert(
        "focus_sessions",
        rows=[
            {
                "id": str(
                    _stable_uuid(f"demo-seed:deadline-focus:{user_id}:calculus")
                ),
                "user_id": user_id,
                "started_at": focus_start.isoformat(),
                "ended_at": focus_end.isoformat(),
                "planned_minutes": 40,
                "actual_minutes": 40,
                "label": "Calculus plan focus",
                "distractions": 0,
                "social_media_warning": False,
                "notes": "Completed one planner-linked practice block.",
                "metadata": {
                    "source": "demo_seed_v2",
                    "entry_date": focus_start.astimezone(zone).date().isoformat(),
                },
                "status": "completed",
                "task_id": str(calculus.plan.id),
                "habit_id": None,
                "created_at": focus_start.isoformat(),
                "updated_at": focus_end.isoformat(),
            }
        ],
    )
    return service


def _briefing_actions(briefing: object) -> list[object]:
    return [briefing.primary_action, *briefing.support_actions]


async def _seed_feedback(
    *,
    client: SupabaseRestClient,
    user_id: str,
    weekly_habit_id: str,
    other_habit_ids: set[str],
    briefings: list[tuple[date, object]],
    timezone: str,
) -> None:
    actions = [
        (briefing_date, briefing, action)
        for briefing_date, briefing in briefings
        for action in _briefing_actions(briefing)
    ]
    weekly_action = next(
        (
            item
            for item in actions
            if item[2].target.kind == "habit"
            and item[2].target.target_id == weekly_habit_id
        ),
        None,
    )
    other_habit_action = next(
        (
            item
            for item in actions
            if item[2].target.kind == "habit"
            and item[2].target.target_id in other_habit_ids
        ),
        None,
    )
    task_actions = [item for item in actions if item[2].target.kind == "task"]
    if weekly_action is None or other_habit_action is None or not task_actions:
        raise RuntimeError(
            "Student briefings did not expose the habit/task feedback coverage."
        )
    selections = [
        ("too_much", weekly_action),
        ("does_not_fit", other_habit_action),
        ("done", task_actions[0]),
        ("later", task_actions[min(1, len(task_actions) - 1)]),
        ("not_helpful", task_actions[-1]),
    ]
    zone = ZoneInfo(timezone)
    rows: list[dict[str, object]] = []
    for index, (feedback_type, selected) in enumerate(selections):
        briefing_date, briefing, action = selected
        created_at = _aware_local(briefing_date, 18, index, zone).astimezone(UTC)
        rows.append(
            {
                "id": str(
                    _stable_uuid(
                        f"demo-seed:decision-feedback:{user_id}:{feedback_type}"
                    )
                ),
                "user_id": user_id,
                "request_id": str(
                    _stable_uuid(
                        f"demo-seed:decision-feedback-request:{user_id}:{feedback_type}"
                    )
                ),
                "briefing_id": briefing.id,
                "recommendation_id": action.recommendation_id,
                "action_id": action.target.id,
                "action_kind": action.target.kind,
                "feedback_type": feedback_type,
                "context_mode": briefing.mode,
                "estimated_minutes": action.target.estimated_minutes,
                "rule_key": action.target.command,
                "metadata": {
                    "contract_version": "decision-feedback-v1",
                    "briefing_date": briefing_date.isoformat(),
                    "source": "demo_seed_v2",
                },
                "created_at": created_at.isoformat(),
            }
        )
    await client.insert("decision_feedback", rows=rows)


async def _seed_coach(
    *,
    client: SupabaseRestClient,
    user_id: str,
    settings: Settings,
    briefing_service: BriefingService,
    weekly_service: WeeklyReviewService,
) -> CoachService:
    context_repository = SupabaseCoachContextRepository(client)
    service = CoachService(
        settings=settings,
        repository=SupabaseCoachRepository(client),
        context_repository=context_repository,
        context_service=CoachContextService(
            repository=context_repository,
            briefing_reader=briefing_service,
            weekly_review_reader=weekly_service,
        ),
        provider=FakeCoachProvider(settings),
        global_semaphore=asyncio.Semaphore(2),
    )
    memories = await service.memories(user_id=user_id)
    eligible = [memory for memory in memories.memories if memory.type != "preference"]
    if len(eligible) < 2:
        raise RuntimeError("Student Coach coverage requires two eligible memories.")
    for memory in eligible[:2]:
        await service.set_memory_selection(
            user_id=user_id,
            memory_id=memory.id,
            selected=True,
        )
    messages = [
        "How should I balance calculus preparation and the essay today?",
        "What is a sensible fallback if my energy drops this afternoon?",
    ]
    for index, message in enumerate(messages):
        await service.respond(
            user_id=user_id,
            request=CoachRequest.model_validate(
                {
                    "contract_version": "coach-request-v1",
                    "request_id": str(
                        _stable_uuid(f"demo-seed:coach-request:{user_id}:{index}")
                    ),
                    "message": message,
                    "context_scope": "today",
                }
            ),
        )
    return service


async def _seed_notifications(
    *,
    client: SupabaseRestClient,
    user_id: str,
    today: date,
    now: datetime,
    weekly_service: WeeklyReviewService,
) -> tuple[NotificationService, object]:
    repository = SupabaseNotificationRepository(client)
    service = NotificationService(repository=repository)
    current = await service.get_settings(user_id=user_id)
    await service.update_settings(
        user_id=user_id,
        request=NotificationSettingsUpdateRequest.model_validate(
            {
                "contract_version": "notification-settings-v1",
                "request_id": str(
                    _stable_uuid(f"demo-seed:notification-settings:{user_id}")
                ),
                "expected_updated_at": current.updated_at.isoformat(),
                "in_app_delivery_enabled": True,
                "consent_version": "in-app-notification-consent-v1",
                "categories": {
                    "focus_prompt": True,
                    "recovery_prompt": True,
                    "weekly_summary": True,
                },
                "quiet_hours": None,
                "daily_limit": 3,
            }
        ),
    )
    result = await NotificationGenerationService(
        repository=repository,
        weekly_review_reader=weekly_service,
    ).generate_for_user(
        user_id=user_id,
        delivery_date=today,
        run_at=now,
    )
    return service, result


async def _row_count(
    client: SupabaseRestClient,
    *,
    table: str,
    user_id: str,
) -> int:
    rows = await client.select(
        table,
        params={
            "select": "id",
            "user_id": f"eq.{user_id}",
            "limit": "1000",
        },
    )
    return len(rows)


async def _verify(
    *,
    client: SupabaseRestClient,
    user_id: str,
    today: date,
    briefing_service: BriefingService,
    weekly_service: WeeklyReviewService,
    calendar_service: CalendarIntegrationService,
    deadline_service: DeadlinePlanService,
    coach_service: CoachService,
    notification_service: NotificationService,
) -> dict[str, int]:
    today_briefing = await briefing_service.get_today(user_id=user_id)
    if today_briefing.freshness != "current" or today_briefing.briefing is None:
        raise RuntimeError("Student Today briefing is not current.")
    weekly = await weekly_service.get_latest(user_id=user_id)
    proposals = weekly.review.proposals if weekly.review else []
    operations = {proposal.operation for proposal in proposals}
    if weekly.freshness != "current" or not {"replace", "shrink"}.issubset(
        operations
    ):
        raise RuntimeError("Student Weekly Review lacks staged and direct proposals.")
    connection = await calendar_service.get_connection(user_id=user_id)
    if connection.connection is None or connection.connection.status != "connected":
        raise RuntimeError("Student Calendar import is not connected.")
    events = await calendar_service.get_events(
        user_id=user_id,
        connection_id=connection.connection.id,
        cursor=None,
        limit=50,
    )
    if len(events.events) < 5:
        raise RuntimeError("Student Calendar import has insufficient event variety.")
    plans = await deadline_service.list_plans(user_id=user_id)
    statuses = [plan.plan.status for plan in plans.plans]
    if statuses.count("active") != 2 or statuses.count("draft") != 1:
        raise RuntimeError("Student Preparation plans lack active/draft coverage.")
    workload = await deadline_service.get_workload(user_id=user_id)
    if (
        len(workload.days) != 7
        or workload.daily_preparation_budget_minutes != STUDENT_DAILY_BUDGET
    ):
        raise RuntimeError("Student preparation workload is incomplete.")
    history = await coach_service.history(user_id=user_id)
    memories = await coach_service.memories(user_id=user_id)
    selected_memory_count = sum(memory.selected for memory in memories.memories)
    if len(history.turns) != 2 or selected_memory_count < 2:
        raise RuntimeError("Student Coach history or memory selection is incomplete.")
    settings = await notification_service.get_settings(user_id=user_id)
    if not settings.in_app_delivery_enabled or settings.daily_limit != 3:
        raise RuntimeError("Student foreground notification consent is incomplete.")

    minimums = {
        "daily_logs": 21,
        "behavioral_events": 80,
        "tasks": 6,
        "habits": 3,
        "habit_logs": 15,
        "focus_sessions": 4,
        "daily_briefings": 8,
        "decision_feedback": 5,
        "weekly_reviews": 1,
        "calendar_events": 5,
        "notifications": 4,
        "coach_requests": 2,
        "coach_messages": 6,
        "deadline_plans": 3,
        "deadline_plan_revisions": 3,
        "deadline_plan_blocks": 3,
    }
    counts = {
        table: await _row_count(client, table=table, user_id=user_id)
        for table in minimums
    }
    failures = {
        table: (counts[table], minimum)
        for table, minimum in minimums.items()
        if counts[table] < minimum
    }
    if failures:
        raise RuntimeError(f"Student feature seed coverage is incomplete: {failures}")
    active_focus = await client.select(
        "focus_sessions",
        params={
            "select": "id",
            "user_id": f"eq.{user_id}",
            "status": "eq.active",
            "limit": "2",
        },
    )
    if len(active_focus) != 1:
        raise RuntimeError(
            "Student demo must have exactly one resumable Focus session."
        )
    generated = await client.select(
        "notifications",
        params={
            "select": "id",
            "user_id": f"eq.{user_id}",
            "generation_key": "not.is.null",
            "delivery_date": f"eq.{today.isoformat()}",
            "limit": "3",
        },
    )
    if not generated:
        raise RuntimeError("Student demo has no pending generated notification.")
    return counts


async def main() -> None:
    supabase_url = _required_environment("SUPABASE_URL").rstrip("/")
    service_role_key = _required_environment("SUPABASE_SERVICE_ROLE_KEY")
    _require_local_supabase(supabase_url)
    client = SupabaseRestClient(
        url=supabase_url,
        service_role_key=service_role_key,
        timeout_seconds=20,
    )
    profile = await _profile(client)
    user_id = str(UUID(str(profile["id"])))
    timezone = str(profile["timezone"])
    zone = ZoneInfo(timezone)
    now = datetime.now(UTC).replace(microsecond=0)
    today = now.astimezone(zone).date()
    week_start, week_end, period_key = _latest_completed_week(today)

    settings = Settings(
        APP_ENV="development",
        USE_MOCK_DATA=False,
        SUPABASE_URL=supabase_url,
        SUPABASE_SERVICE_ROLE_KEY=service_role_key,
        COACH_PROVIDER="fake",
        COACH_FAKE_PROVIDER_ENABLED=True,
    )
    calendar_service, source_event = await _seed_calendar(
        client=client,
        user_id=user_id,
        today=today,
        timezone=timezone,
    )
    deadline_service = await _seed_deadline_plans(
        client=client,
        user_id=user_id,
        today=today,
        timezone=timezone,
        source_event=source_event,
        now=now,
    )

    snapshot_aggregator = SnapshotAggregator(
        repository=SupabaseSnapshotRepository(client)
    )
    briefing_service = BriefingService(
        repository=SupabaseBriefingRepository(client),
        snapshot_aggregator=snapshot_aggregator,
    )
    weekly_service = WeeklyReviewService(
        repository=SupabaseWeeklyReviewRepository(client),
        snapshot_aggregator=snapshot_aggregator,
    )
    review_days = [week_start + timedelta(days=offset) for offset in range(7)]
    for target_date in [*review_days, today]:
        await snapshot_aggregator.generate_snapshot(
            user_id=user_id,
            request=SnapshotGenerateRequest(
                scope="daily",
                target_date=target_date,
                window_days=7,
            ),
        )
    review_briefings: list[tuple[date, object]] = []
    for target_date in review_days:
        prepared = await briefing_service.prepare_for_date(
            user_id=user_id,
            briefing_date=target_date,
        )
        if prepared.response.briefing is None:
            raise RuntimeError("Student historical briefing was not persisted.")
        review_briefings.append((target_date, prepared.response.briefing))

    habits = await client.select(
        "habits",
        params={
            "select": "id,metadata",
            "user_id": f"eq.{user_id}",
            "order": "id.asc",
            "limit": "20",
        },
    )
    weekly_habits = [
        str(row["id"])
        for row in habits
        if isinstance(row.get("metadata"), dict)
        and row["metadata"].get("cadence") == "weekly_target"
    ]
    if len(weekly_habits) != 1:
        raise RuntimeError("Student demo requires one weekly-target habit.")
    await _seed_feedback(
        client=client,
        user_id=user_id,
        weekly_habit_id=weekly_habits[0],
        other_habit_ids={str(row["id"]) for row in habits} - set(weekly_habits),
        briefings=review_briefings,
        timezone=timezone,
    )
    await briefing_service.generate_today(
        user_id=user_id,
        request=BriefingGenerateRequest(force=True),
    )
    weekly = await weekly_service.generate(
        user_id=user_id,
        request=WeeklyReviewGenerateRequest(period_key=period_key, force=True),
    )
    if weekly.freshness != "current":
        raise RuntimeError("Student Weekly Review could not be generated.")

    coach_service = await _seed_coach(
        client=client,
        user_id=user_id,
        settings=settings,
        briefing_service=briefing_service,
        weekly_service=weekly_service,
    )
    notification_service, generation = await _seed_notifications(
        client=client,
        user_id=user_id,
        today=today,
        now=now,
        weekly_service=weekly_service,
    )
    if generation.created_count < 1:
        raise RuntimeError("Student notification generation produced no demo row.")

    counts = await _verify(
        client=client,
        user_id=user_id,
        today=today,
        briefing_service=briefing_service,
        weekly_service=weekly_service,
        calendar_service=calendar_service,
        deadline_service=deadline_service,
        coach_service=coach_service,
        notification_service=notification_service,
    )
    print("Student feature demo enriched and verified for local Supabase.")
    print(
        "Coverage: "
        f"{counts['daily_logs']} daily logs, "
        f"{counts['daily_briefings']} briefings, "
        f"{counts['focus_sessions']} focus sessions, "
        f"{counts['calendar_events']} calendar events, "
        f"{counts['deadline_plans']} preparation plans, "
        f"{counts['coach_requests']} Coach turns."
    )


if __name__ == "__main__":
    asyncio.run(main())
