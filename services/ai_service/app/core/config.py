from functools import lru_cache

from typing import Literal

from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict


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
    supabase_service_role_key: str = Field(
        default="",
        alias="SUPABASE_SERVICE_ROLE_KEY",
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
    coach_provider: Literal["disabled", "local_codex_oauth", "fake"] = Field(
        default="disabled",
        alias="COACH_PROVIDER",
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

    @property
    def allowed_origins(self) -> list[str]:
        return [
            origin.strip()
            for origin in self.allowed_origins_raw.split(",")
            if origin.strip()
        ]


@lru_cache
def get_settings() -> Settings:
    return Settings()


settings = get_settings()
