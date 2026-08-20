from functools import lru_cache
import ipaddress
import re

from typing import Literal
from urllib.parse import urlsplit

from pydantic import Field, model_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


_PROJECT_REF_PATTERN = re.compile(r"^[a-z]{20}$")
_RELEASE_SHA_PATTERN = re.compile(r"^[0-9a-f]{40}$")
_RELEASE_TAG_PATTERN = re.compile(
    r"^v[0-9]+\.[0-9]+\.[0-9]+-pilot\.[0-9]+(?:-rc\.[0-9]+)?$",
)
_MIGRATION_HEAD_PATTERN = re.compile(r"^[0-9]{14}_[a-z0-9_]+\.sql$")
_DIGEST_PATTERN = re.compile(r"^[0-9a-f]{64}$")
_ROOTLESS_DOCKER_HOST_PATTERN = re.compile(
    r"^unix:///run/user/([1-9][0-9]*)/docker\.sock$",
)
_CODEX_VERSION_PATTERN = re.compile(r"^[0-9]+\.[0-9]+\.[0-9]+$")


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

    app_env: Literal["development", "test", "staging", "pilot"] = Field(
        default="development",
        alias="APP_ENV",
    )
    api_prefix: str = Field(default="/v1", alias="API_PREFIX")
    app_build_sha: str = Field(default="", alias="APP_BUILD_SHA")
    app_release_tag: str = Field(default="", alias="APP_RELEASE_TAG")
    app_migration_head: str = Field(default="", alias="APP_MIGRATION_HEAD")
    app_migration_count: int = Field(default=0, alias="APP_MIGRATION_COUNT")
    app_migration_identity_sha256: str = Field(
        default="",
        alias="APP_MIGRATION_IDENTITY_SHA256",
    )
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
    account_deletion_journal_s3_url: str = Field(
        default="",
        alias="ACCOUNT_DELETION_JOURNAL_S3_URL",
    )
    account_deletion_journal_s3_region: str = Field(
        default="",
        alias="ACCOUNT_DELETION_JOURNAL_S3_REGION",
    )
    account_deletion_journal_s3_access_key_id: str = Field(
        default="",
        alias="ACCOUNT_DELETION_JOURNAL_S3_ACCESS_KEY_ID",
    )
    account_deletion_journal_s3_secret_access_key: str = Field(
        default="",
        alias="ACCOUNT_DELETION_JOURNAL_S3_SECRET_ACCESS_KEY",
    )
    account_deletion_journal_s3_kms_key_arn: str = Field(
        default="",
        alias="ACCOUNT_DELETION_JOURNAL_S3_KMS_KEY_ARN",
    )
    account_deletion_journal_timeout_seconds: float = Field(
        default=10,
        ge=2,
        le=30,
        alias="ACCOUNT_DELETION_JOURNAL_TIMEOUT_SECONDS",
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
    operator_codex_pilot_enabled: bool = Field(
        default=False,
        alias="OPERATOR_CODEX_PILOT_ENABLED",
    )
    coach_executor_socket_path: str = Field(
        default="/run/mylifegraph-coach/executor.sock",
        alias="COACH_EXECUTOR_SOCKET_PATH",
    )
    coach_executor_allowed_api_uid: int = Field(
        default=0,
        ge=0,
        alias="COACH_EXECUTOR_ALLOWED_API_UID",
    )
    coach_operator_model: Literal["gpt-5.5"] = Field(
        default="gpt-5.5",
        alias="COACH_OPERATOR_MODEL",
    )
    coach_operator_requests_per_user_per_day: Literal[5] = Field(
        default=5,
        alias="COACH_OPERATOR_REQUESTS_PER_USER_PER_DAY",
    )
    coach_operator_global_requests_per_day: Literal[15] = Field(
        default=15,
        alias="COACH_OPERATOR_GLOBAL_REQUESTS_PER_DAY",
    )
    coach_operator_global_concurrency: Literal[1] = Field(
        default=1,
        alias="COACH_OPERATOR_GLOBAL_CONCURRENCY",
    )
    coach_operator_retry_after_seconds: Literal[15] = Field(
        default=15,
        alias="COACH_OPERATOR_RETRY_AFTER_SECONDS",
    )
    local_codex_bin: str = Field(default="codex", alias="LOCAL_CODEX_BIN")
    local_codex_expected_version: str = Field(
        default="",
        alias="LOCAL_CODEX_EXPECTED_VERSION",
    )
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
    coach_analysis_docker_host: str = Field(
        default="",
        alias="COACH_ANALYSIS_DOCKER_HOST",
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
    public_admission_wait_milliseconds: int = Field(
        default=50,
        ge=10,
        le=1_000,
        alias="PUBLIC_ADMISSION_WAIT_MILLISECONDS",
    )
    public_ready_ip_requests_per_minute: int = Field(
        default=60,
        ge=1,
        le=600,
        alias="PUBLIC_READY_IP_REQUESTS_PER_MINUTE",
    )
    public_ready_concurrency: int = Field(
        default=4,
        ge=1,
        le=16,
        alias="PUBLIC_READY_CONCURRENCY",
    )
    public_read_ip_requests_per_minute: int = Field(
        default=300,
        ge=1,
        le=3_000,
        alias="PUBLIC_READ_IP_REQUESTS_PER_MINUTE",
    )
    public_read_owner_requests_per_minute: int = Field(
        default=180,
        ge=1,
        le=1_000,
        alias="PUBLIC_READ_OWNER_REQUESTS_PER_MINUTE",
    )
    public_read_concurrency: int = Field(
        default=32,
        ge=4,
        le=128,
        alias="PUBLIC_READ_CONCURRENCY",
    )
    public_mutation_ip_requests_per_minute: int = Field(
        default=120,
        ge=1,
        le=1_000,
        alias="PUBLIC_MUTATION_IP_REQUESTS_PER_MINUTE",
    )
    public_mutation_owner_requests_per_minute: int = Field(
        default=60,
        ge=1,
        le=600,
        alias="PUBLIC_MUTATION_OWNER_REQUESTS_PER_MINUTE",
    )
    public_mutation_concurrency: int = Field(
        default=8,
        ge=2,
        le=32,
        alias="PUBLIC_MUTATION_CONCURRENCY",
    )
    public_coach_ip_requests_per_minute: int = Field(
        default=60,
        ge=1,
        le=600,
        alias="PUBLIC_COACH_IP_REQUESTS_PER_MINUTE",
    )
    public_coach_owner_requests_per_minute: int = Field(
        default=12,
        ge=1,
        le=120,
        alias="PUBLIC_COACH_OWNER_REQUESTS_PER_MINUTE",
    )
    public_coach_concurrency: int = Field(
        default=4,
        ge=1,
        le=16,
        alias="PUBLIC_COACH_CONCURRENCY",
    )

    @model_validator(mode="after")
    def validate_operator_pilot(self) -> "Settings":
        if self.operator_codex_pilot_enabled and self.normalized_app_env not in {
            "staging",
            "pilot",
        }:
            raise ValueError(
                "OPERATOR_CODEX_PILOT_ENABLED is allowed only in staging or pilot.",
            )
        socket_path = _configured_value(
            "COACH_EXECUTOR_SOCKET_PATH",
            self.coach_executor_socket_path,
        )
        if not socket_path.startswith("/") or "/../" in f"{socket_path}/":
            raise ValueError("COACH_EXECUTOR_SOCKET_PATH must be an absolute path.")
        docker_host = _configured_value(
            "COACH_ANALYSIS_DOCKER_HOST",
            self.coach_analysis_docker_host,
        )
        if docker_host and _ROOTLESS_DOCKER_HOST_PATTERN.fullmatch(docker_host) is None:
            raise ValueError(
                "COACH_ANALYSIS_DOCKER_HOST must be an exact rootless Unix socket."
            )
        codex_version = _configured_value(
            "LOCAL_CODEX_EXPECTED_VERSION",
            self.local_codex_expected_version,
        )
        if codex_version and _CODEX_VERSION_PATTERN.fullmatch(codex_version) is None:
            raise ValueError(
                "LOCAL_CODEX_EXPECTED_VERSION must be an exact numeric version."
            )
        return self

    @property
    def allowed_origins(self) -> list[str]:
        origins = [
            origin.strip()
            for origin in self.allowed_origins_raw.split(",")
            if origin.strip()
        ]
        if self.normalized_app_env not in {"staging", "pilot"}:
            return origins
        if len(origins) != 1 or origins[0] != self.allowed_origins_raw:
            raise ValueError(
                "Hosted ALLOWED_ORIGINS must contain one exact origin without spaces.",
            )
        origin = origins[0]
        parsed = urlsplit(origin)
        hostname = parsed.hostname
        try:
            if hostname is not None:
                ipaddress.ip_address(hostname)
                is_ip = True
            else:
                is_ip = False
        except ValueError:
            is_ip = False
        if (
            parsed.scheme != "https"
            or hostname is None
            or is_ip
            or "." not in hostname
            or hostname == "localhost"
            or parsed.username is not None
            or parsed.password is not None
            or parsed.port is not None
            or parsed.path
            or parsed.query
            or parsed.fragment
            or parsed.netloc != hostname
            or origin != f"https://{hostname}"
        ):
            raise ValueError(
                "Hosted ALLOWED_ORIGINS must be one canonical HTTPS hostname origin.",
            )
        return [origin]

    @property
    def normalized_app_env(self) -> str:
        return self.app_env

    @property
    def is_hosted_environment(self) -> bool:
        return self.normalized_app_env in {"staging", "pilot"}

    @property
    def learned_focus_planning_runtime_enabled(self) -> bool:
        return (
            self.learned_focus_planning_pilot_enabled
            and self.normalized_app_env != "pilot"
        )

    @property
    def requires_pilot_participation(self) -> bool:
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
            expected_ref = self.hosted_supabase_project_ref()
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

    def hosted_supabase_project_ref(self) -> str:
        if not self.is_hosted_environment:
            raise ValueError(
                "A hosted Supabase project ref exists only in staging or pilot.",
            )
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
        return staging_ref if self.normalized_app_env == "staging" else pilot_ref

    def release_identity(self) -> tuple[str, str]:
        sha = _configured_value("APP_BUILD_SHA", self.app_build_sha)
        tag = _configured_value("APP_RELEASE_TAG", self.app_release_tag)
        if self.is_hosted_environment:
            if _RELEASE_SHA_PATTERN.fullmatch(sha) is None:
                raise ValueError(
                    "APP_BUILD_SHA must be an exact lowercase 40-character SHA.",
                )
            if _RELEASE_TAG_PATTERN.fullmatch(tag) is None:
                raise ValueError("APP_RELEASE_TAG must be an exact pilot release tag.")
        return sha or "development", tag or "development"

    def release_migration_identity(self) -> tuple[str, int, str]:
        head = _configured_value("APP_MIGRATION_HEAD", self.app_migration_head)
        digest = _configured_value(
            "APP_MIGRATION_IDENTITY_SHA256",
            self.app_migration_identity_sha256,
        )
        count = self.app_migration_count
        if self.is_hosted_environment:
            if _MIGRATION_HEAD_PATTERN.fullmatch(head) is None:
                raise ValueError("APP_MIGRATION_HEAD is invalid.")
            if count < 1 or count > 50_000:
                raise ValueError("APP_MIGRATION_COUNT is invalid.")
            if _DIGEST_PATTERN.fullmatch(digest) is None:
                raise ValueError("APP_MIGRATION_IDENTITY_SHA256 is invalid.")
        return head, count, digest

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
