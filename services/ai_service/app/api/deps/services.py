from collections.abc import Callable
from typing import TypeVar

from fastapi import HTTPException, Request, status

from app.api.deps.composition import get_application_composition
from app.clients.supabase import SupabaseConfigurationError
from app.composition import ApplicationComposition
from app.services.account_service import AccountService
from app.services.assignment_series_service import AssignmentSeriesService
from app.services.briefing_service import BriefingService
from app.services.calendar_integration_service import CalendarIntegrationService
from app.services.daily_capture_service import DailyCaptureService
from app.services.deadline_plan_service import DeadlinePlanService
from app.services.multi_exam_plan_service import MultiExamPlanService
from app.services.feedback_service import FeedbackService
from app.services.focus_service import FocusService
from app.services.intake_service import IntakeService
from app.services.learning_service import LearningService
from app.services.notification_service import NotificationService
from app.services.personal_patterns_service import PersonalPatternsService
from app.services.sleep_recommendation_service import SleepRecommendationService
from app.services.planner_service import PlannerService
from app.services.recommendation_engine import RecommendationEngine
from app.services.scheduled_refresh import ScheduledRefreshService
from app.services.snapshot_aggregator import SnapshotAggregator
from app.services.today_overview_service import TodayOverviewService
from app.services.today_week_agenda_service import TodayWeekAgendaService
from app.services.weekly_review_service import WeeklyReviewService


_ServiceT = TypeVar("_ServiceT")


def _service(
    request: Request,
    *,
    select: Callable[[ApplicationComposition], _ServiceT],
    unavailable_detail: str,
) -> _ServiceT:
    try:
        return select(get_application_composition(request))
    except SupabaseConfigurationError as exc:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail=unavailable_detail,
        ) from exc


async def get_account_service(request: Request) -> AccountService:
    return _service(
        request,
        select=lambda composition: composition.account_service,
        unavailable_detail="Account persistence is not configured.",
    )


async def get_assignment_series_service(
    request: Request,
) -> AssignmentSeriesService:
    return _service(
        request,
        select=lambda composition: composition.assignment_series_service,
        unavailable_detail="Assignment series persistence is not configured.",
    )


async def get_briefing_service(request: Request) -> BriefingService:
    return _service(
        request,
        select=lambda composition: composition.briefing_service,
        unavailable_detail="Briefing persistence is not configured.",
    )


async def get_calendar_integration_service(
    request: Request,
) -> CalendarIntegrationService:
    return _service(
        request,
        select=lambda composition: composition.calendar_integration_service,
        unavailable_detail="Calendar integration persistence is not configured.",
    )


async def get_daily_capture_service(request: Request) -> DailyCaptureService:
    return _service(
        request,
        select=lambda composition: composition.daily_capture_service,
        unavailable_detail="Daily Capture persistence is not configured.",
    )


async def get_deadline_plan_service(request: Request) -> DeadlinePlanService:
    return _service(
        request,
        select=lambda composition: composition.deadline_plan_service,
        unavailable_detail="Deadline plan persistence is not configured.",
    )


async def get_multi_exam_plan_service(request: Request) -> MultiExamPlanService:
    return _service(
        request,
        select=lambda composition: composition.multi_exam_plan_service,
        unavailable_detail="Exam balance persistence is not configured.",
    )


async def get_feedback_service(request: Request) -> FeedbackService:
    return _service(
        request,
        select=lambda composition: composition.feedback_service,
        unavailable_detail="Feedback persistence is not configured.",
    )


async def get_focus_service(request: Request) -> FocusService:
    return _service(
        request,
        select=lambda composition: composition.focus_service,
        unavailable_detail="Focus persistence is not configured.",
    )


async def get_intake_service(request: Request) -> IntakeService:
    return _service(
        request,
        select=lambda composition: composition.intake_service,
        unavailable_detail="Intake persistence is not configured.",
    )


async def get_learning_service(request: Request) -> LearningService:
    return _service(
        request,
        select=lambda composition: composition.learning_service,
        unavailable_detail="Personal learning persistence is not configured.",
    )


async def get_notification_service(request: Request) -> NotificationService:
    return _service(
        request,
        select=lambda composition: composition.notification_service,
        unavailable_detail="Notification lifecycle persistence is not configured.",
    )


async def get_personal_patterns_service(
    request: Request,
) -> PersonalPatternsService:
    return _service(
        request,
        select=lambda composition: composition.personal_patterns_service,
        unavailable_detail="Personal pattern analysis is not configured.",
    )


async def get_sleep_recommendation_service(
    request: Request,
) -> SleepRecommendationService:
    return _service(
        request,
        select=lambda composition: composition.sleep_recommendation_service,
        unavailable_detail="Sleep recommendation analysis is not configured.",
    )


async def get_planner_service(request: Request) -> PlannerService:
    return _service(
        request,
        select=lambda composition: composition.planner_service,
        unavailable_detail="Planner persistence is not configured.",
    )


async def get_recommendation_engine(request: Request) -> RecommendationEngine:
    return _service(
        request,
        select=lambda composition: composition.recommendation_engine,
        unavailable_detail="Recommendation persistence is not configured.",
    )


async def get_scheduled_refresh_service(
    request: Request,
) -> ScheduledRefreshService:
    return _service(
        request,
        select=lambda composition: composition.scheduled_refresh_service,
        unavailable_detail="Scheduled refresh persistence is not configured.",
    )


async def get_snapshot_aggregator(request: Request) -> SnapshotAggregator:
    return _service(
        request,
        select=lambda composition: composition.snapshot_aggregator,
        unavailable_detail="Snapshot persistence is not configured.",
    )


async def get_today_overview_service(request: Request) -> TodayOverviewService:
    return _service(
        request,
        select=lambda composition: composition.today_overview_service,
        unavailable_detail="Today persistence is not configured.",
    )


async def get_today_week_agenda_service(request: Request) -> TodayWeekAgendaService:
    return _service(
        request,
        select=lambda composition: composition.today_week_agenda_service,
        unavailable_detail="Full week persistence is not configured.",
    )


async def get_weekly_review_service(request: Request) -> WeeklyReviewService:
    return _service(
        request,
        select=lambda composition: composition.weekly_review_service,
        unavailable_detail="Weekly review persistence is not configured.",
    )
