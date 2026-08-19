import pytest

from app import main
from app.clients.supabase import SupabaseConfigurationError, SupabaseRestClient
from app.core.config import Settings


STAGING_REF = "abcdefghijklmnopqrst"
PILOT_REF = "bcdefghijklmnopqrstu"


def _settings(**overrides: str) -> Settings:
    values = {
        "APP_ENV": "staging",
        "SUPABASE_URL": f"https://{STAGING_REF}.supabase.co",
        "SUPABASE_SECRET_KEY": "sb_secret_test-value",
        "STAGING_SUPABASE_PROJECT_REF": STAGING_REF,
    }
    values.update(overrides)
    return Settings(_env_file=None, **values)


def test_current_backend_key_and_exact_staging_target_are_accepted() -> None:
    client = SupabaseRestClient.from_settings(_settings())

    assert client._rest_headers()["apikey"] == "sb_secret_test-value"
    assert client._rest_headers()["Authorization"] == (
        "Bearer sb_secret_test-value"
    )


def test_staging_allows_one_legacy_backend_key_during_transition() -> None:
    client = SupabaseRestClient.from_settings(
        _settings(
            SUPABASE_SECRET_KEY="",
            SUPABASE_SERVICE_ROLE_KEY="legacy-service-role-test-value",
        ),
    )

    assert client._rest_headers()["apikey"] == "legacy-service-role-test-value"


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


def test_interactive_docs_exist_only_in_development(monkeypatch) -> None:
    monkeypatch.setattr(main, "settings", _settings())
    assert main.create_app().docs_url is None

    monkeypatch.setattr(
        main,
        "settings",
        Settings(_env_file=None, APP_ENV="development"),
    )
    assert main.create_app().docs_url == "/docs"
