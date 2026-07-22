from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.api.routes import (
    account,
    briefings,
    calendar_integrations,
    coach,
    deadline_plans,
    feedback,
    health,
    intake,
    notifications,
    planner,
    recommendations,
    scheduled,
    snapshots,
    today,
    weekly_reviews,
)
from app.core.config import settings


def create_app() -> FastAPI:
    app = FastAPI(
        title="MyLifeGraph AI Service",
        version="0.1.0",
        docs_url="/docs" if settings.app_env != "production" else None,
        redoc_url=None,
    )

    app.add_middleware(
        CORSMiddleware,
        allow_origins=settings.allowed_origins,
        allow_credentials=True,
        allow_methods=["GET", "POST", "PATCH", "DELETE"],
        allow_headers=["Authorization", "Content-Type"],
        expose_headers=["Content-Disposition"],
    )

    app.include_router(health.router, prefix=settings.api_prefix)
    app.include_router(account.router, prefix=settings.api_prefix)
    app.include_router(intake.router, prefix=settings.api_prefix)
    app.include_router(notifications.router, prefix=settings.api_prefix)
    app.include_router(recommendations.router, prefix=settings.api_prefix)
    app.include_router(snapshots.router, prefix=settings.api_prefix)
    app.include_router(today.router, prefix=settings.api_prefix)
    app.include_router(briefings.router, prefix=settings.api_prefix)
    app.include_router(feedback.router, prefix=settings.api_prefix)
    app.include_router(scheduled.router, prefix=settings.api_prefix)
    app.include_router(weekly_reviews.router, prefix=settings.api_prefix)
    app.include_router(calendar_integrations.router, prefix=settings.api_prefix)
    app.include_router(deadline_plans.router, prefix=settings.api_prefix)
    app.include_router(planner.router, prefix=settings.api_prefix)
    app.include_router(coach.router, prefix=settings.api_prefix)

    return app


app = create_app()
