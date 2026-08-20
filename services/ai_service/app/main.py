import asyncio
import logging
from contextlib import asynccontextmanager
from datetime import UTC, datetime

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.api.deps.auth import SupabaseTokenVerifier, UnconfiguredTokenVerifier
from app.api.routes import (
    account,
    briefings,
    calendar_integrations,
    coach,
    daily_capture,
    deadline_plans,
    focus,
    health,
    intake,
    insights,
    learning,
    notifications,
    planner,
    scheduled,
    snapshots,
    today,
    weekly_reviews,
)
from app.clients.supabase import SupabaseConfigurationError, SupabaseRestClient
from app.composition import ApplicationComposition
from app.core.config import settings
from app.public_admission import PublicAdmissionController, PublicAdmissionMiddleware


logger = logging.getLogger(__name__)
_DELETION_RECONCILE_STALE_SECONDS = 15 * 60


@asynccontextmanager
async def _lifespan(app: FastAPI):
    if settings.is_hosted_environment:
        settings.release_identity()
        settings.release_migration_identity()
    try:
        supabase_client = SupabaseRestClient.pooled_from_settings(settings)
    except SupabaseConfigurationError:
        if settings.is_hosted_environment:
            raise
        app.state.composition = None
        app.state.token_verifier = UnconfiguredTokenVerifier()
        yield
        return

    app.state.composition = None
    app.state.token_verifier = UnconfiguredTokenVerifier()
    try:
        app.state.composition = ApplicationComposition.build(
            supabase_client=supabase_client,
            settings=settings,
        )
        await app.state.composition.coach_services.current.reconcile_startup()
        deletion_reconcile_task = asyncio.create_task(
            _reconcile_account_deletions(app),
        )
        app.state.token_verifier = SupabaseTokenVerifier(supabase_client)
        try:
            yield
        finally:
            deletion_reconcile_task.cancel()
            try:
                await deletion_reconcile_task
            except asyncio.CancelledError:
                pass
    finally:
        await supabase_client.aclose()
        app.state.composition = None
        app.state.token_verifier = UnconfiguredTokenVerifier()


async def _reconcile_account_deletions(app: FastAPI) -> None:
    delay_seconds = 0
    while True:
        if delay_seconds:
            await asyncio.sleep(delay_seconds)
        composition = app.state.composition
        if composition is not None:
            try:
                async with asyncio.timeout(20):
                    result = await (
                        composition.account_service.reconcile_account_deletions(
                            limit=5,
                        )
                    )
            except asyncio.CancelledError:
                raise
            except Exception:
                logger.error(
                    "account_deletion_reconcile unhealthy %s",
                    {
                        "examined": None,
                        "completed": None,
                        "failures": 1,
                        "pending_count": None,
                        "oldest_age_seconds": None,
                    },
                )
                delay_seconds = min(300, max(60, delay_seconds * 2))
                continue
            _log_deletion_reconcile_result(result)
            delay_seconds = min(300, delay_seconds * 2) if result.failures else 60


def _log_deletion_reconcile_result(result) -> None:
    oldest_age_seconds = None
    if result.oldest_pending_at is not None:
        oldest_age_seconds = max(
            0,
            int((datetime.now(UTC) - result.oldest_pending_at).total_seconds()),
        )
    fields = {
        "examined": result.examined,
        "completed": result.completed,
        "failures": result.failures,
        "pending_count": result.pending_count,
        "oldest_age_seconds": oldest_age_seconds,
    }
    if (
        result.failures
        or result.pending_count is None
        or (
            oldest_age_seconds is not None
            and oldest_age_seconds > _DELETION_RECONCILE_STALE_SECONDS
        )
    ):
        logger.error("account_deletion_reconcile unhealthy %s", fields)
    elif result.examined or result.pending_count:
        logger.info("account_deletion_reconcile %s", fields)


def create_app() -> FastAPI:
    app = FastAPI(
        title="MyLifeGraph AI Service",
        version="0.1.0",
        docs_url=("/docs" if settings.normalized_app_env == "development" else None),
        redoc_url=None,
        lifespan=_lifespan,
    )
    app.state.settings = settings
    app.state.composition = None

    if settings.is_hosted_environment:
        public_admission = PublicAdmissionController(settings)
        app.state.public_admission = public_admission
        app.add_middleware(
            PublicAdmissionMiddleware,
            controller=public_admission,
        )
    else:
        app.state.public_admission = None

    app.add_middleware(
        CORSMiddleware,
        allow_origins=settings.allowed_origins,
        allow_credentials=True,
        allow_methods=["GET", "POST", "PUT", "PATCH", "DELETE"],
        allow_headers=[
            "Authorization",
            "Content-Type",
            "X-MyLifeGraph-Coach-Provider",
            "X-MyLifeGraph-Coach-Api-Key",
        ],
        expose_headers=["Content-Disposition", "Retry-After"],
    )

    app.include_router(health.router, prefix=settings.api_prefix)
    app.include_router(account.router, prefix=settings.api_prefix)
    app.include_router(daily_capture.router, prefix=settings.api_prefix)
    app.include_router(intake.router, prefix=settings.api_prefix)
    app.include_router(learning.router, prefix=settings.api_prefix)
    app.include_router(insights.router, prefix=settings.api_prefix)
    app.include_router(notifications.router, prefix=settings.api_prefix)
    app.include_router(snapshots.router, prefix=settings.api_prefix)
    app.include_router(today.router, prefix=settings.api_prefix)
    app.include_router(briefings.router, prefix=settings.api_prefix)
    app.include_router(focus.router, prefix=settings.api_prefix)
    app.include_router(scheduled.router, prefix=settings.api_prefix)
    app.include_router(weekly_reviews.router, prefix=settings.api_prefix)
    app.include_router(calendar_integrations.router, prefix=settings.api_prefix)
    app.include_router(deadline_plans.router, prefix=settings.api_prefix)
    app.include_router(planner.router, prefix=settings.api_prefix)
    app.include_router(coach.router, prefix=settings.api_prefix)

    return app


app = create_app()
