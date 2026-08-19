from functools import lru_cache
import re

from typing import Literal
from urllib.parse import urlsplit

from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict


_PROJECT_REF_PATTERN = re.compile(r"^[a-z]{20}$")


def _configured_value(name: str, value: str) -> str:
    if value and value.strip() != value:
        raise ValueError(f"{name} must not contain surrounding whitespace.")
    return value


def _project_ref(name: str, value: str, *, optional: bool = False) -> str:
    configured = _configured_value(name, value)
    if optional and not configured:
        return ""
    if _PROJECT_REF_PATTERN.fullmatch(configured) is None:
        raise ValueError(f"{name} must be an exact 20-letter project ref.")
    return configured


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        extra="ignore",
    )

    app_env: str = Field(default="development", alias="APP_ENV")
    api_prefix: str = Field(default="/v1", alias="API_PREFIX")
    allowed_origins_raw: str = Field(
        default="http://127.0.0.1:7357,http://localhost:7357",
        alias="ALLOWED_ORIGINS",
    )
    supabase_url: str = Field(default="", alias="SUPABASE_URL")
    supabase_secret_key: str = Field(default="", alias="SUPABASE_SECRET_KEY")
    supabase_service_role_key: str = Field(
        default="",
        alias="SUPABASE_SERVICE_ROLE_KEY",
    )
    staging_supabase_project_ref: str = Field(
        default="",
        alias="STAGING_SUPABASE_PROJECT_REF",
    )
    pilot_supabase_project_ref: str = Field(
        default="",
        alias="PILOT_SUPABASE_PROJECT_REF",
    )
    supabase_timeout_seconds: float = Field(
        default=10,
        alias="SUPABASE_TIMEOUT_SECONDS",
    )
    scheduled_refresh_token: str = Field(
        default="",
        alias="SCHEDULED_REFRESH_TOKEN",
    )
    use_mock_data: bool = Field(default=True, alias="USE_MOCK_DATA")
    learned_focus_planning_pilot_enabled: bool = Field(
        default=False,
        alias="LEARNED_FOCUS_PLANNING_PILOT_ENABLED",
    )
    coach_provider: Literal["disabled", "local_codex_oauth", "fake"] = Field(
        default="disabled",
        alias="COACH_PROVIDER",
    )
    coach_byok_providers_raw: str = Field(
        default="",
        alias="COACH_BYOK_PROVIDERS",
    )
    coach_fake_provider_enabled: bool = Field(
        default=False,
        alias="COACH_FAKE_PROVIDER_ENABLED",
    )
    local_codex_enabled: bool = Field(default=False, alias="LOCAL_CODEX_ENABLED")
    local_codex_bin: str = Field(default="codex", alias="LOCAL_CODEX_BIN")
    local_codex_model: str = Field(default="gpt-5.5", alias="LOCAL_CODEX_MODEL")
    local_codex_timeout_seconds: int = Field(
        default=45,
        ge=5,
        le=120,
        alias="LOCAL_CODEX_TIMEOUT_SECONDS",
    )
    coach_agent_timeout_seconds: int = Field(
        default=180,
        ge=180,
        le=180,
        alias="COACH_AGENT_TIMEOUT_SECONDS",
    )
    coach_analysis_docker_bin: str = Field(
        default="docker",
        alias="COACH_ANALYSIS_DOCKER_BIN",
    )
    coach_analysis_image: str = Field(
        default="mylifegraph-coach-analysis:1",
        alias="COACH_ANALYSIS_IMAGE",
    )
    local_codex_max_requests_per_user_per_day: int = Field(
        default=20,
        ge=1,
        le=100,
        alias="LOCAL_CODEX_MAX_REQUESTS_PER_USER_PER_DAY",
    )
    local_codex_global_concurrency: int = Field(
        default=2,
        ge=1,
        le=8,
        alias="LOCAL_CODEX_GLOBAL_CONCURRENCY",
    )
    coach_evidence_global_concurrency: int = Field(
        default=4,
        ge=1,
        le=16,
        alias="COACH_EVIDENCE_GLOBAL_CONCURRENCY",
    )
    coach_evidence_timeout_seconds: int = Field(
        default=15,
        ge=5,
        le=60,
        alias="COACH_EVIDENCE_TIMEOUT_SECONDS",
    )

    @property
    def allowed_origins(self) -> list[str]:
        return [
            origin.strip()
            for origin in self.allowed_origins_raw.split(",")
            if origin.strip()
        ]

    @property
    def normalized_app_env(self) -> str:
        return self.app_env.strip().lower()

    @property
    def is_hosted_environment(self) -> bool:
        return self.normalized_app_env in {"staging", "pilot"}

    def supabase_backend_configuration(self) -> tuple[str, str]:
        current_key = _configured_value(
            "SUPABASE_SECRET_KEY",
            self.supabase_secret_key,
        )
        legacy_key = _configured_value(
            "SUPABASE_SERVICE_ROLE_KEY",
            self.supabase_service_role_key,
        )
        if current_key and not current_key.startswith("sb_secret_"):
            raise ValueError(
                "SUPABASE_SECRET_KEY must use the current sb_secret_ format.",
            )
        if self.normalized_app_env == "pilot" and not current_key:
            raise ValueError("SUPABASE_SECRET_KEY is required for pilot.")

        url = _configured_value("SUPABASE_URL", self.supabase_url)
        if self.is_hosted_environment:
            staging_ref = _project_ref(
                "STAGING_SUPABASE_PROJECT_REF",
                self.staging_supabase_project_ref,
            )
            pilot_ref = _project_ref(
                "PILOT_SUPABASE_PROJECT_REF",
                self.pilot_supabase_project_ref,
                optional=self.normalized_app_env == "staging",
            )
            if pilot_ref and staging_ref == pilot_ref:
                raise ValueError(
                    "Staging and pilot Supabase project refs must be distinct.",
                )
            expected_ref = (
                staging_ref
                if self.normalized_app_env == "staging"
                else pilot_ref
            )
            parsed = urlsplit(url)
            if (
                parsed.scheme != "https"
                or parsed.username is not None
                or parsed.password is not None
                or parsed.port is not None
                or parsed.path not in {"", "/"}
                or parsed.query
                or parsed.fragment
                or parsed.hostname != f"{expected_ref}.supabase.co"
            ):
                raise ValueError(
                    "SUPABASE_URL must exactly match the configured hosted "
                    "project ref.",
                )
            url = f"https://{parsed.hostname}"

        return url, current_key or legacy_key

    @property
    def coach_byok_providers(self) -> frozenset[str]:
        values = {
            value.strip()
            for value in self.coach_byok_providers_raw.split(",")
            if value.strip()
        }
        return frozenset(values & {"openai", "gemini"})


@lru_cache
def get_settings() -> Settings:
    return Settings()


settings = get_settings()
