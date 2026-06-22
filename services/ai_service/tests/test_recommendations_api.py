import asyncio
from datetime import date

import pytest
from fastapi import HTTPException

from app.api.deps.auth import Principal, extract_bearer_token
from app.api.routes.recommendations import (
    generate_recommendations,
    list_recommendations,
)
from app.main import create_app
from app.models.recommendations import RecommendationGenerateRequest
from app.services.recommendation_engine import (
    RecommendationEngine,
    current_period_key,
)


def collect_route_methods(app) -> set[tuple[str, tuple[str, ...]]]:
    route_methods: set[tuple[str, tuple[str, ...]]] = set()

    for route in app.routes:
        path = getattr(route, "path", None)
        methods = getattr(route, "methods", None)
        if path and methods:
            route_methods.add((path, tuple(sorted(methods))))
            continue

        include_context = getattr(route, "include_context", None)
        original_router = getattr(route, "original_router", None)
        if include_context is None or original_router is None:
            continue

        prefix = include_context.prefix
        for nested_route in original_router.routes:
            nested_path = getattr(nested_route, "path", None)
            nested_methods = getattr(nested_route, "methods", None)
            if nested_path and nested_methods:
                route_methods.add(
                    (f"{prefix}{nested_path}", tuple(sorted(nested_methods))),
                )

    return route_methods


def fake_principal() -> Principal:
    return Principal(user_id="user-test-123")


def test_recommendation_routes_are_registered() -> None:
    route_methods = collect_route_methods(create_app())

    assert ("/v1/recommendations", ("GET",)) in route_methods
    assert ("/v1/recommendations/generate", ("POST",)) in route_methods


def test_get_recommendations_without_authorization_returns_401() -> None:
    with pytest.raises(HTTPException) as exc_info:
        extract_bearer_token(None)

    assert exc_info.value.status_code == 401
    assert exc_info.value.headers == {"WWW-Authenticate": "Bearer"}


def test_generate_recommendations_without_authorization_returns_401() -> None:
    with pytest.raises(HTTPException) as exc_info:
        extract_bearer_token("")

    assert exc_info.value.status_code == 401
    assert exc_info.value.headers == {"WWW-Authenticate": "Bearer"}


def test_get_recommendations_with_fake_principal_matches_contract() -> None:
    response = asyncio.run(
        list_recommendations(
            principal=fake_principal(),
            engine=RecommendationEngine(),
        ),
    )

    assert response.model_dump(mode="json") == {
        "items": [],
        "needs_generation": True,
        "generated_at": None,
        "period_key": current_period_key(date.today()),
        "stale_reason": "no_current_recommendations",
    }


def test_generate_recommendations_with_fake_principal_matches_contract() -> None:
    with pytest.raises(ValueError):
        RecommendationGenerateRequest(
            window_days=28,
            force=False,
            allow_llm_wording=False,
            user_id="attacker-controlled",
        )

    response = asyncio.run(
        generate_recommendations(
            request=RecommendationGenerateRequest(
                window_days=28,
                force=False,
                allow_llm_wording=False,
            ),
            principal=fake_principal(),
            engine=RecommendationEngine(),
        ),
    )

    assert response.model_dump(mode="json") == {
        "generated": 0,
        "reused": 0,
        "items": [],
        "needs_generation": True,
        "generated_at": None,
        "period_key": current_period_key(date.today()),
        "stale_reason": "not_implemented_in_pr1",
    }
