from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.api.routes import health, recommendations
from app.core.config import settings


def create_app() -> FastAPI:
    app = FastAPI(
        title="Personal Optimization AI Service",
        version="0.1.0",
        docs_url="/docs" if settings.app_env != "production" else None,
        redoc_url=None,
    )

    app.add_middleware(
        CORSMiddleware,
        allow_origins=settings.allowed_origins,
        allow_credentials=True,
        allow_methods=["GET", "POST"],
        allow_headers=["Authorization", "Content-Type"],
    )

    app.include_router(health.router, prefix=settings.api_prefix)
    app.include_router(recommendations.router, prefix=settings.api_prefix)

    return app


app = create_app()
