import asyncio
import re
from pathlib import Path

from fastapi import Request

from app.api.deps.auth import SupabaseTokenVerifier, UnconfiguredTokenVerifier
from app.api.deps.coach import get_coach_services
from app.api.deps.services import (
    get_deadline_plan_service,
    get_planner_service,
    get_scheduled_refresh_service,
    get_today_overview_service,
)
from app.clients.supabase import SupabaseConfigurationError, SupabaseRestClient
from app.composition import ApplicationComposition
from app.core.config import Settings
from app.main import create_app


APP_ROOT = Path(__file__).resolve().parents[1] / "app"


class _HttpPool:
    def __init__(self) -> None:
        self.close_calls = 0

    async def aclose(self) -> None:
        self.close_calls += 1


def test_app_lifespan_owns_one_supabase_pool(monkeypatch) -> None:
    http_pool = _HttpPool()
    supabase_client = SupabaseRestClient(
        url="http://supabase.test",
        service_role_key="service-role",
        http_client=http_pool,
    )
    monkeypatch.setattr(
        SupabaseRestClient,
        "pooled_from_settings",
        classmethod(lambda cls, settings: supabase_client),
    )
    app = create_app()

    async def exercise() -> None:
        async with app.router.lifespan_context(app):
            composition = app.state.composition
            assert isinstance(composition, ApplicationComposition)
            assert composition.supabase_client is supabase_client
            verifier = app.state.token_verifier
            assert isinstance(verifier, SupabaseTokenVerifier)
            assert verifier._client is supabase_client
            assert http_pool.close_calls == 0
            request = Request({"type": "http", "app": app})
            assert await get_deadline_plan_service(request) is (
                composition.deadline_plan_service
            )
            assert await get_planner_service(request) is composition.planner_service
            assert await get_today_overview_service(request) is (
                composition.today_overview_service
            )
            assert await get_scheduled_refresh_service(request) is (
                composition.scheduled_refresh_service
            )
            assert await get_coach_services(request) is composition.coach_services

        assert app.state.composition is None
        assert isinstance(app.state.token_verifier, UnconfiguredTokenVerifier)
        assert http_pool.close_calls == 1

    asyncio.run(exercise())


def test_app_lifespan_stays_fail_closed_without_supabase(monkeypatch) -> None:
    def unconfigured(cls, settings):
        raise SupabaseConfigurationError("missing test configuration")

    monkeypatch.setattr(
        SupabaseRestClient,
        "pooled_from_settings",
        classmethod(unconfigured),
    )
    app = create_app()

    async def exercise() -> None:
        async with app.router.lifespan_context(app):
            assert app.state.composition is None
            assert isinstance(
                app.state.token_verifier,
                UnconfiguredTokenVerifier,
            )

    asyncio.run(exercise())


def test_route_factories_do_not_create_settings_derived_transports() -> None:
    factory_sources = [
        *sorted((APP_ROOT / "api" / "deps").glob("*.py")),
        *sorted((APP_ROOT / "api" / "routes").glob("*.py")),
    ]

    offenders = [
        str(path.relative_to(APP_ROOT))
        for path in factory_sources
        if "SupabaseRestClient.from_settings" in path.read_text()
    ]

    assert offenders == []


def test_routes_do_not_construct_persistence_or_use_named_service_state() -> None:
    route_sources = sorted((APP_ROOT / "api" / "routes").glob("*.py"))
    repository_constructor = re.compile(r"Supabase[A-Za-z]+Repository\(")
    named_service_state = re.compile(r"\.state\.[a-z_]+(?:service|engine|aggregator)")

    assert [
        str(path.relative_to(APP_ROOT))
        for path in route_sources
        if repository_constructor.search(path.read_text())
    ] == []
    assert [
        str(path.relative_to(APP_ROOT))
        for path in route_sources
        if named_service_state.search(path.read_text())
    ] == []


def test_api_tests_override_typed_dependencies_instead_of_named_state() -> None:
    named_service_state = re.compile(
        r"\.state\.(?:token_verifier|[a-z_]+(?:service|engine|aggregator))",
    )
    test_sources = [
        path
        for path in sorted((APP_ROOT.parent / "tests").glob("test_*.py"))
        if path.name != "test_app_lifespan.py"
    ]

    assert [
        path.name
        for path in test_sources
        if named_service_state.search(path.read_text())
    ] == []


def test_application_composition_reuses_the_common_service_graph() -> None:
    supabase_client = SupabaseRestClient(
        url="http://supabase.test",
        service_role_key="service-role",
        http_client=_HttpPool(),
    )
    composition = ApplicationComposition.build(
        supabase_client=supabase_client,
        settings=Settings(
            _env_file=None,
            APP_ENV="test",
            COACH_PROVIDER="disabled",
            LEARNED_FOCUS_PLANNING_PILOT_ENABLED=False,
        ),
    )

    assert composition.deadline_plan_service is (
        composition.planner_service._deadline_plans
    )
    assert composition.planner_service is (
        composition.today_overview_service._planner_service
    )
    assert composition.deadline_plan_service is (
        composition.today_overview_service._deadline_plan_service
    )
    assert composition.snapshot_aggregator is (
        composition.briefing_service._snapshot_aggregator
    )
    assert composition.briefing_service is (
        composition.scheduled_refresh_service._briefing_service
    )
    assert composition.recommendation_engine is (
        composition.scheduled_refresh_service._recommendation_engine
    )
