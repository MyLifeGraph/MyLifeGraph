from functools import lru_cache

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
