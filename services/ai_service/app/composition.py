import asyncio
from dataclasses import dataclass

from app.clients.supabase import SupabaseRestClient
from app.coach_turn_lifecycle import CoachTurnLifecycle, utc_now
from app.core.config import Settings
from app.providers.base import CoachProvider
from app.providers.disabled import DisabledCoachProvider
from app.providers.fake import FakeCoachProvider
from app.providers.local_codex import LocalCodexCoachProvider
from app.repositories.account_repository import SupabaseAccountRepository
from app.repositories.briefing_repository import SupabaseBriefingRepository
from app.repositories.calendar_integration_repository import (
    SupabaseCalendarIntegrationRepository,
)
from app.repositories.coach_context_repository import SupabaseCoachContextRepository
from app.repositories.coach_evidence_repository import (
    SupabaseCoachEvidenceRepository,
)
from app.repositories.coach_repository import SupabaseCoachRepository
from app.repositories.daily_capture_repository import SupabaseDailyCaptureRepository
from app.repositories.deadline_plan_repository import SupabaseDeadlinePlanRepository
from app.repositories.feedback_repository import SupabaseFeedbackRepository
from app.repositories.focus_repository import SupabaseFocusRepository
from app.repositories.intake_repository import SupabaseIntakeRepository
from app.repositories.learning_repository import SupabaseLearningRepository
from app.repositories.notification_repository import SupabaseNotificationRepository
from app.repositories.personal_patterns_repository import (
    SupabasePersonalPatternsRepository,
)
from app.repositories.planner_repository import SupabasePlannerRepository
from app.repositories.recommendation_repository import (
    SupabaseRecommendationRepository,
)
from app.repositories.scheduled_refresh_repository import (
    SupabaseScheduledRefreshRepository,
)
from app.repositories.snapshot_repository import SupabaseSnapshotRepository
from app.repositories.today_overview_repository import (
    SupabaseTodayOverviewRepository,
)
from app.repositories.today_planner_read_repository import (
    SupabaseTodayPlannerReadRepository,
)
from app.repositories.user_context_repository import SupabaseUserContextRepository
from app.repositories.weekly_review_repository import (
    SupabaseWeeklyReviewRepository,
)
from app.services.account_service import AccountService
from app.services.briefing_service import BriefingService
from app.services.calendar_integration_service import CalendarIntegrationService
from app.services.coach_agent_service import CoachAgentService
from app.services.coach_context import CoachContextService
from app.services.coach_evidence_service import CoachEvidenceService
from app.services.coach_service import CoachService
from app.services.coach_snapshot import CoachSnapshotService
from app.services.daily_capture_service import DailyCaptureService
from app.services.deadline_plan_service import DeadlinePlanService
from app.services.feedback_service import FeedbackService
from app.services.focus_service import FocusService
from app.services.intake_service import IntakeService
from app.services.learned_timing import LearnedTimingResolver
from app.services.learning_service import LearningService
from app.services.notification_service import (
    NotificationGenerationService,
    NotificationService,
)
from app.services.personal_patterns_service import PersonalPatternsService
from app.services.planner_service import PlannerService
from app.services.recommendation_engine import RecommendationEngine
from app.services.scheduled_refresh import ScheduledRefreshService
from app.services.snapshot_aggregator import SnapshotAggregator
from app.services.today_overview_service import TodayOverviewService
from app.services.today_planner_read_context import TodayPlannerReadContextFactory
from app.services.weekly_review_service import WeeklyReviewService


@dataclass(frozen=True, slots=True)
class CoachServices:
    current: CoachAgentService
    legacy: CoachService


@dataclass(frozen=True, slots=True)
class ApplicationComposition:
    """One application-owned graph over the lifespan-owned Supabase client."""

    supabase_client: SupabaseRestClient
    account_service: AccountService
    briefing_service: BriefingService
    calendar_integration_service: CalendarIntegrationService
    coach_services: CoachServices
    daily_capture_service: DailyCaptureService
    deadline_plan_service: DeadlinePlanService
    feedback_service: FeedbackService
    focus_service: FocusService
    intake_service: IntakeService
    learning_service: LearningService
    notification_service: NotificationService
    personal_patterns_service: PersonalPatternsService
    planner_service: PlannerService
    recommendation_engine: RecommendationEngine
    scheduled_refresh_service: ScheduledRefreshService
    snapshot_aggregator: SnapshotAggregator
    today_overview_service: TodayOverviewService
    weekly_review_service: WeeklyReviewService

    @classmethod
    def build(
        cls,
        *,
        supabase_client: SupabaseRestClient,
        settings: Settings,
    ) -> "ApplicationComposition":
        account_repository = SupabaseAccountRepository(supabase_client)
        briefing_repository = SupabaseBriefingRepository(supabase_client)
        coach_context_repository = SupabaseCoachContextRepository(supabase_client)
        coach_repository = SupabaseCoachRepository(supabase_client)
        learning_service = LearningService(
            repository=SupabaseLearningRepository(supabase_client),
        )
        snapshot_aggregator = SnapshotAggregator(
            repository=SupabaseSnapshotRepository(supabase_client),
        )
        briefing_service = BriefingService(
            repository=briefing_repository,
            snapshot_aggregator=snapshot_aggregator,
        )
        weekly_review_service = WeeklyReviewService(
            repository=SupabaseWeeklyReviewRepository(supabase_client),
            snapshot_aggregator=snapshot_aggregator,
        )
        personal_patterns_service = PersonalPatternsService(
            learning=learning_service,
            repository=SupabasePersonalPatternsRepository(supabase_client),
        )
        learned_timing = LearnedTimingResolver(
            learning=learning_service,
            patterns=personal_patterns_service,
            pilot_enabled=(
                settings.learned_focus_planning_pilot_enabled
                and settings.app_env != "production"
            ),
        )
        deadline_plan_service = DeadlinePlanService(
            repository=SupabaseDeadlinePlanRepository(supabase_client),
            learned_timing=learned_timing,
        )
        planner_repository = SupabasePlannerRepository(supabase_client)
        today_repository = SupabaseTodayOverviewRepository(supabase_client)
        today_planner_read_contexts = TodayPlannerReadContextFactory(
            repository=SupabaseTodayPlannerReadRepository(supabase_client),
            deadline_plans=deadline_plan_service,
        )
        planner_service = PlannerService(
            repository=planner_repository,
            deadline_plans=deadline_plan_service,
            learned_timing=learned_timing,
            read_context_factory=today_planner_read_contexts,
        )
        recommendation_engine = RecommendationEngine(
            user_context_repository=SupabaseUserContextRepository(supabase_client),
            recommendation_repository=SupabaseRecommendationRepository(
                supabase_client,
            ),
        )
        notification_repository = SupabaseNotificationRepository(supabase_client)
        notification_service = NotificationService(
            repository=notification_repository,
        )
        notification_generation_service = NotificationGenerationService(
            repository=notification_repository,
            weekly_review_reader=weekly_review_service,
        )
        coach_provider = _coach_provider(settings)
        coach_semaphore = asyncio.Semaphore(
            settings.local_codex_global_concurrency,
        )
        coach_evidence_service = CoachEvidenceService(
            repository=SupabaseCoachEvidenceRepository(supabase_client),
            learning=learning_service,
            semaphore=asyncio.Semaphore(
                settings.coach_evidence_global_concurrency,
            ),
            timeout_seconds=settings.coach_evidence_timeout_seconds,
        )
        coach_context_service = CoachContextService(
            repository=coach_context_repository,
            briefing_reader=briefing_service,
            weekly_review_reader=weekly_review_service,
            evidence_reader=coach_evidence_service,
        )
        coach_lifecycle = CoachTurnLifecycle(
            repository=coach_repository,
            profile_reader=coach_context_repository,
            now_provider=utc_now,
        )
        coach_services = CoachServices(
            current=CoachAgentService(
                settings=settings,
                repository=coach_repository,
                context_repository=coach_context_repository,
                snapshot_service=CoachSnapshotService(
                    repository=account_repository,
                ),
                provider=coach_provider,
                global_semaphore=coach_semaphore,
                lifecycle=coach_lifecycle,
            ),
            legacy=CoachService(
                settings=settings,
                repository=coach_repository,
                context_repository=coach_context_repository,
                context_service=coach_context_service,
                provider=coach_provider,
                global_semaphore=coach_semaphore,
                lifecycle=coach_lifecycle,
            ),
        )
        scheduled_refresh_service = ScheduledRefreshService(
            repository=SupabaseScheduledRefreshRepository(supabase_client),
            briefing_service=briefing_service,
            recommendation_engine=recommendation_engine,
            notification_generation_service=notification_generation_service,
        )

        return cls(
            supabase_client=supabase_client,
            account_service=AccountService(repository=account_repository),
            briefing_service=briefing_service,
            calendar_integration_service=CalendarIntegrationService(
                repository=SupabaseCalendarIntegrationRepository(supabase_client),
            ),
            coach_services=coach_services,
            daily_capture_service=DailyCaptureService(
                repository=SupabaseDailyCaptureRepository(supabase_client),
            ),
            deadline_plan_service=deadline_plan_service,
            feedback_service=FeedbackService(
                repository=SupabaseFeedbackRepository(supabase_client),
            ),
            focus_service=FocusService(
                repository=SupabaseFocusRepository(supabase_client),
            ),
            intake_service=IntakeService(
                repository=SupabaseIntakeRepository(supabase_client),
            ),
            learning_service=learning_service,
            notification_service=notification_service,
            personal_patterns_service=personal_patterns_service,
            planner_service=planner_service,
            recommendation_engine=recommendation_engine,
            scheduled_refresh_service=scheduled_refresh_service,
            snapshot_aggregator=snapshot_aggregator,
            today_overview_service=TodayOverviewService(
                repository=today_repository,
                deadline_plan_service=deadline_plan_service,
                planner_service=planner_service,
                read_context_factory=today_planner_read_contexts,
            ),
            weekly_review_service=weekly_review_service,
        )


def _coach_provider(settings: Settings) -> CoachProvider:
    if settings.coach_provider == "local_codex_oauth":
        return LocalCodexCoachProvider(settings)
    if settings.coach_provider == "fake":
        return FakeCoachProvider(settings)
    return DisabledCoachProvider()
