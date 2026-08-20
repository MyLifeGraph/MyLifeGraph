import asyncio
from pathlib import Path

import httpx
import pytest

from app import main
from app.clients.supabase import SupabaseConfigurationError, SupabaseRestClient
from app.core.config import Settings


STAGING_REF = "abcdefghijklmnopqrst"
PILOT_REF = "bcdefghijklmnopqrstu"
REPOSITORY_ROOT = Path(__file__).resolve().parents[3]


def _settings(**overrides: str) -> Settings:
    values = {
        "APP_ENV": "staging",
        "SUPABASE_URL": f"https://{STAGING_REF}.supabase.co",
        "SUPABASE_SECRET_KEY": "sb_secret_test-value",
        "STAGING_SUPABASE_PROJECT_REF": STAGING_REF,
        "ALLOWED_ORIGINS": "https://app.example.test",
        "APP_MIGRATION_HEAD": (
            "20260820200000_account_deletion_replayer_role_guard_v2.sql"
        ),
        "APP_MIGRATION_COUNT": "69",
        "APP_MIGRATION_IDENTITY_SHA256": "b" * 64,
    }
    values.update(overrides)
    return Settings(_env_file=None, **values)


def test_current_backend_key_and_exact_staging_target_are_accepted() -> None:
    client = SupabaseRestClient.from_settings(_settings())

    assert client._rest_headers()["apikey"] == "sb_secret_test-value"
    assert "Authorization" not in client._rest_headers()


def test_staging_allows_one_legacy_backend_key_during_transition() -> None:
    client = SupabaseRestClient.from_settings(
        _settings(
            SUPABASE_SECRET_KEY="",
            SUPABASE_SERVICE_ROLE_KEY="legacy-service-role-test-value",
        ),
    )

    assert client._rest_headers()["apikey"] == "legacy-service-role-test-value"
    assert client._rest_headers()["Authorization"] == (
        "Bearer legacy-service-role-test-value"
    )


def test_pilot_requires_current_key_and_distinct_exact_project() -> None:
    settings = _settings(
        APP_ENV="pilot",
        SUPABASE_URL=f"https://{PILOT_REF}.supabase.co/",
        PILOT_SUPABASE_PROJECT_REF=PILOT_REF,
    )
    client = SupabaseRestClient.from_settings(settings)
    assert client._rest_headers()["apikey"] == "sb_secret_test-value"

    with pytest.raises(SupabaseConfigurationError, match="SUPABASE_SECRET_KEY"):
        SupabaseRestClient.from_settings(
            _settings(
                APP_ENV="pilot",
                SUPABASE_URL=f"https://{PILOT_REF}.supabase.co",
                SUPABASE_SECRET_KEY="",
                SUPABASE_SERVICE_ROLE_KEY="legacy-service-role-test-value",
                PILOT_SUPABASE_PROJECT_REF=PILOT_REF,
            ),
        )
    with pytest.raises(SupabaseConfigurationError, match="must be distinct"):
        SupabaseRestClient.from_settings(
            _settings(
                APP_ENV="pilot",
                PILOT_SUPABASE_PROJECT_REF=STAGING_REF,
            ),
        )


def test_hosted_target_fails_closed_and_current_key_wins_rotation() -> None:
    with pytest.raises(SupabaseConfigurationError, match="project ref"):
        SupabaseRestClient.from_settings(
            _settings(SUPABASE_URL=f"https://{PILOT_REF}.supabase.co"),
        )
    rotating = SupabaseRestClient.from_settings(
        _settings(SUPABASE_SERVICE_ROLE_KEY="different-legacy-value"),
    )
    assert rotating._rest_headers()["apikey"] == "sb_secret_test-value"
    with pytest.raises(SupabaseConfigurationError, match="sb_secret_"):
        SupabaseRestClient.from_settings(
            _settings(SUPABASE_SECRET_KEY="not-a-current-secret-key"),
        )


def test_development_keeps_local_legacy_configuration_compatible() -> None:
    client = SupabaseRestClient.from_settings(
        Settings(
            _env_file=None,
            APP_ENV="development",
            SUPABASE_URL="http://127.0.0.1:54321",
            SUPABASE_SERVICE_ROLE_KEY="local-service-role-key",
        ),
    )

    assert client._rest_headers()["apikey"] == "local-service-role-key"


def test_learned_focus_planning_is_fail_closed_in_pilot() -> None:
    assert (
        _settings(
            LEARNED_FOCUS_PLANNING_PILOT_ENABLED="true",
        ).learned_focus_planning_runtime_enabled
        is True
    )
    assert (
        _settings(
            APP_ENV="pilot",
            SUPABASE_URL=f"https://{PILOT_REF}.supabase.co",
            PILOT_SUPABASE_PROJECT_REF=PILOT_REF,
            LEARNED_FOCUS_PLANNING_PILOT_ENABLED="true",
        ).learned_focus_planning_runtime_enabled
        is False
    )
    assert (
        Settings(
            _env_file=None,
            APP_ENV="development",
            LEARNED_FOCUS_PLANNING_PILOT_ENABLED=True,
        ).learned_focus_planning_runtime_enabled
        is True
    )
    assert _settings().learned_focus_planning_runtime_enabled is False


@pytest.mark.parametrize(
    "app_env",
    ["", "pilto", "Pilot", " pilot", "pilot ", "production"],
)
def test_unknown_or_noncanonical_application_environment_is_rejected(
    app_env: str,
) -> None:
    with pytest.raises(ValueError, match="APP_ENV"):
        Settings(_env_file=None, APP_ENV=app_env)


def test_interactive_docs_exist_only_in_development(monkeypatch) -> None:
    monkeypatch.setattr(main, "settings", _settings())
    assert main.create_app().docs_url is None

    monkeypatch.setattr(
        main,
        "settings",
        Settings(_env_file=None, APP_ENV="development"),
    )
    assert main.create_app().docs_url == "/docs"


def test_hosted_cors_requires_one_canonical_https_hostname() -> None:
    assert _settings().allowed_origins == ["https://app.example.test"]

    for value in [
        "",
        "*",
        "http://app.example.test",
        "https://localhost",
        "https://127.0.0.1",
        "https://app.example.test/",
        "https://user@app.example.test",
        "https://app.example.test:443",
        "https://app.example.test,https://preview.example.test",
        " https://app.example.test",
    ]:
        with pytest.raises(ValueError, match="Hosted ALLOWED_ORIGINS"):
            _ = _settings(ALLOWED_ORIGINS=value).allowed_origins

    local = Settings(_env_file=None, APP_ENV="development")
    assert local.allowed_origins == [
        "http://127.0.0.1:7357",
        "http://localhost:7357",
    ]


def test_hosted_cors_wraps_admission_rate_and_body_errors(monkeypatch) -> None:
    async def scenario() -> None:
        monkeypatch.setattr(
            main,
            "settings",
            _settings(PUBLIC_READ_IP_REQUESTS_PER_MINUTE="1"),
        )
        app = main.create_app()
        async with httpx.AsyncClient(
            transport=httpx.ASGITransport(app=app),
            base_url="https://api.example.test",
            headers={"Origin": "https://app.example.test"},
        ) as client:
            missing = await client.get("/v1/not-a-route")
            limited = await client.get("/v1/not-a-route")
            oversized = await client.post(
                "/v1/not-a-route",
                content=b"x" * (1_048_576 + 1),
            )
        assert missing.status_code == 404
        assert limited.status_code == 429
        assert oversized.status_code == 413
        for response in [limited, oversized]:
            assert response.headers["access-control-allow-origin"] == (
                "https://app.example.test"
            )
        assert "Retry-After" in limited.headers["access-control-expose-headers"]

    asyncio.run(scenario())


def test_operator_subscription_pilot_is_fail_closed_by_environment() -> None:
    for app_env in ["development", "test"]:
        with pytest.raises(ValueError, match="staging or pilot"):
            Settings(
                _env_file=None,
                APP_ENV=app_env,
                OPERATOR_CODEX_PILOT_ENABLED=True,
            )

    staging = _settings(OPERATOR_CODEX_PILOT_ENABLED=True)
    assert staging.operator_codex_pilot_enabled is True
    assert staging.coach_operator_global_concurrency == 1
    assert staging.coach_operator_requests_per_user_per_day == 5
    assert staging.coach_operator_global_requests_per_day == 15


def test_executor_socket_path_is_always_absolute() -> None:
    with pytest.raises(ValueError, match="absolute path"):
        _settings(COACH_EXECUTOR_SOCKET_PATH="relative/executor.sock")


def test_rootless_docker_host_accepts_only_exact_user_socket() -> None:
    accepted = _settings(
        COACH_ANALYSIS_DOCKER_HOST="unix:///run/user/1234/docker.sock",
    )
    assert accepted.coach_analysis_docker_host == ("unix:///run/user/1234/docker.sock")

    for value in [
        "unix:///var/run/docker.sock",
        "tcp://127.0.0.1:2375",
        "unix:///run/user/0/docker.sock",
        "unix:///run/user/1234/../docker.sock",
    ]:
        with pytest.raises(ValueError, match="rootless Unix socket"):
            _settings(COACH_ANALYSIS_DOCKER_HOST=value)


def test_codex_cli_version_pin_is_exact_when_configured() -> None:
    assert (
        _settings(LOCAL_CODEX_EXPECTED_VERSION="0.147.0").local_codex_expected_version
        == "0.147.0"
    )
    for value in ["latest", "v0.147.0", "0.147"]:
        with pytest.raises(ValueError, match="exact numeric version"):
            _settings(LOCAL_CODEX_EXPECTED_VERSION=value)
    with pytest.raises(ValueError, match="surrounding whitespace"):
        _settings(LOCAL_CODEX_EXPECTED_VERSION=" 0.147.0")


def test_hosted_release_identity_is_exact_and_local_has_safe_defaults() -> None:
    hosted = _settings(
        APP_BUILD_SHA="a" * 40,
        APP_RELEASE_TAG="v0.1.0-pilot.1-rc.1",
        APP_MIGRATION_HEAD="20260820200000_account_deletion_replayer_role_guard_v2.sql",
        APP_MIGRATION_COUNT="69",
        APP_MIGRATION_IDENTITY_SHA256="b" * 64,
    )
    assert hosted.release_identity() == (
        "a" * 40,
        "v0.1.0-pilot.1-rc.1",
    )
    assert Settings(_env_file=None).release_identity() == (
        "development",
        "development",
    )
    assert hosted.release_migration_identity() == (
        "20260820200000_account_deletion_replayer_role_guard_v2.sql",
        69,
        "b" * 64,
    )

    with pytest.raises(ValueError, match="APP_BUILD_SHA"):
        _settings(
            APP_BUILD_SHA="short", APP_RELEASE_TAG="v0.1.0-pilot.1"
        ).release_identity()
    with pytest.raises(ValueError, match="APP_RELEASE_TAG"):
        _settings(APP_BUILD_SHA="a" * 40, APP_RELEASE_TAG="latest").release_identity()
    for values, message in [
        ({"APP_MIGRATION_HEAD": "latest"}, "APP_MIGRATION_HEAD"),
        ({"APP_MIGRATION_COUNT": "0"}, "APP_MIGRATION_COUNT"),
        ({"APP_MIGRATION_IDENTITY_SHA256": "short"}, "APP_MIGRATION_IDENTITY"),
    ]:
        with pytest.raises(ValueError, match=message):
            _settings(**values).release_migration_identity()


def test_render_staging_portability_uses_main_and_live_release_identity() -> None:
    blueprint = (REPOSITORY_ROOT / "render.yaml").read_text(encoding="utf-8")

    assert "branch: main" in blueprint
    assert "branch: new_backend_gh" not in blueprint
    assert 'APP_BUILD_SHA="$RENDER_GIT_COMMIT"' in blueprint
    assert "- key: APP_MIGRATION_HEAD\n        sync: false" in blueprint
    assert "healthCheckPath: /v1/ready" in blueprint
    assert "- key: COACH_PROVIDER\n        value: disabled" in blueprint
    assert "OPERATOR_CODEX_PILOT_ENABLED" not in blueprint
