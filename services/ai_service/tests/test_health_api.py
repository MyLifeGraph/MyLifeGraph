import asyncio
from types import SimpleNamespace

import httpx
import pytest

from app import main
from app.core.config import Settings

HOSTED_DATABASE_HEAD = "20260820200000_account_deletion_replayer_role_guard_v2.sql"
HOSTED_DATABASE_MIGRATION_COUNT = 69
HOSTED_DATABASE_IDENTITY_SHA256 = (
    "e1c5fe56d8a359f4aa08248e5363a2cdbafd518c09e4046d48ccf1ae7f4f8ff9"
)


def _database_contract(
    *,
    head: str = HOSTED_DATABASE_HEAD,
    count: int = HOSTED_DATABASE_MIGRATION_COUNT,
    identity_sha256: str = HOSTED_DATABASE_IDENTITY_SHA256,
    prepared_guard: bool = True,
) -> dict[str, object]:
    return {
        "contract_version": "hosted-database-contract-v1",
        "migration_head": head,
        "migration_count": count,
        "migration_identity_sha256": identity_sha256,
        "prefix_head": head,
        "prefix_count": count,
        "prefix_identity_sha256": identity_sha256,
        "prepared_deletion_pending_guard": prepared_guard,
    }


async def _get(app, path: str) -> httpx.Response:
    async with httpx.AsyncClient(
        transport=httpx.ASGITransport(app=app),
        base_url="http://test",
    ) as client:
        return await client.get(path)


def test_health_is_cheap_and_exposes_only_release_identity(monkeypatch) -> None:
    monkeypatch.setattr(
        main,
        "settings",
        Settings(_env_file=None, APP_ENV="development"),
    )
    app = main.create_app()

    response = asyncio.run(_get(app, "/v1/health"))

    assert response.status_code == 200
    assert response.json() == {
        "status": "ok",
        "release_sha": "development",
        "release_tag": "development",
    }
    assert app.state.composition is None


def test_readiness_checks_core_configuration_without_coach_provider(
    monkeypatch,
) -> None:
    monkeypatch.setattr(
        main,
        "settings",
        Settings(
            _env_file=None,
            APP_ENV="development",
            SUPABASE_URL="http://127.0.0.1:54321",
            SUPABASE_SERVICE_ROLE_KEY="local-test-service-role",
        ),
    )
    app = main.create_app()

    unavailable = asyncio.run(_get(app, "/v1/ready"))
    assert unavailable.status_code == 503
    assert unavailable.json()["detail"]["code"] == "core_not_ready"

    class ReadySupabase:
        async def readiness_probe(self) -> None:
            return None

    app.state.composition = SimpleNamespace(supabase_client=ReadySupabase())
    ready = asyncio.run(_get(app, "/v1/ready"))
    assert ready.status_code == 200
    assert ready.json() == {"status": "ready"}


def test_readiness_sanitizes_supabase_probe_failure(monkeypatch) -> None:
    monkeypatch.setattr(
        main,
        "settings",
        Settings(
            _env_file=None,
            APP_ENV="development",
            SUPABASE_URL="http://127.0.0.1:54321",
            SUPABASE_SERVICE_ROLE_KEY="local-test-service-role",
        ),
    )
    app = main.create_app()

    class UnavailableSupabase:
        async def readiness_probe(self) -> None:
            raise OSError("private upstream detail")

    app.state.composition = SimpleNamespace(
        supabase_client=UnavailableSupabase(),
    )
    response = asyncio.run(_get(app, "/v1/ready"))

    assert response.status_code == 503
    assert response.json() == {
        "detail": {
            "code": "core_not_ready",
            "message": "Core service configuration is not ready.",
            "retryable": True,
        },
    }
    assert "private upstream detail" not in response.text


def test_hosted_health_returns_exact_manifest_identity(monkeypatch) -> None:
    settings = Settings(
        _env_file=None,
        APP_ENV="staging",
        APP_BUILD_SHA="a" * 40,
        APP_RELEASE_TAG="v0.1.0-pilot.1-rc.1",
        APP_MIGRATION_HEAD=HOSTED_DATABASE_HEAD,
        APP_MIGRATION_COUNT=HOSTED_DATABASE_MIGRATION_COUNT,
        APP_MIGRATION_IDENTITY_SHA256=HOSTED_DATABASE_IDENTITY_SHA256,
        ALLOWED_ORIGINS="https://app.example.test",
    )
    monkeypatch.setattr(main, "settings", settings)
    app = main.create_app()

    response = asyncio.run(_get(app, "/v1/health"))

    assert response.json() == {
        "status": "ok",
        "release_sha": "a" * 40,
        "release_tag": "v0.1.0-pilot.1-rc.1",
    }


def _hosted_settings() -> Settings:
    return Settings(
        _env_file=None,
        APP_ENV="staging",
        APP_BUILD_SHA="a" * 40,
        APP_RELEASE_TAG="v0.1.0-pilot.1-rc.1",
        APP_MIGRATION_HEAD=HOSTED_DATABASE_HEAD,
        APP_MIGRATION_COUNT=HOSTED_DATABASE_MIGRATION_COUNT,
        APP_MIGRATION_IDENTITY_SHA256=HOSTED_DATABASE_IDENTITY_SHA256,
        ALLOWED_ORIGINS="https://app.example.test",
        SUPABASE_URL="https://abcdefghijklmnopqrst.supabase.co",
        SUPABASE_SECRET_KEY="sb_secret_test",
        STAGING_SUPABASE_PROJECT_REF="abcdefghijklmnopqrst",
    )


def test_hosted_readiness_requires_exact_database_participation_gate(
    monkeypatch,
) -> None:
    monkeypatch.setattr(main, "settings", _hosted_settings())
    app = main.create_app()

    class ReadySupabase:
        async def readiness_probe(self) -> None:
            return None

        async def pilot_participation_gate(self) -> dict[str, object]:
            return {
                "contract_version": "pilot-participation-gate-v1",
                "project_ref": "abcdefghijklmnopqrst",
                "participation_required": True,
                "notice_version": "pilot-participation-notice-v1",
            }

        async def account_deletion_recovery_status(self) -> dict[str, object]:
            return {
                "contract_version": "account-deletion-recovery-v2",
                "legacy_direct_delete_revoked": True,
                "pending_count": 0,
                "oldest_pending_at": None,
            }

        async def hosted_database_contract(
            self,
            *,
            through_head: str,
        ) -> dict[str, object]:
            assert through_head == HOSTED_DATABASE_HEAD
            return _database_contract()

    app.state.composition = SimpleNamespace(supabase_client=ReadySupabase())

    response = asyncio.run(_get(app, "/v1/ready"))

    assert response.status_code == 200
    assert response.json() == {
        "status": "ready",
        "migration_head": HOSTED_DATABASE_HEAD,
        "migration_count": HOSTED_DATABASE_MIGRATION_COUNT,
        "migration_identity_sha256": HOSTED_DATABASE_IDENTITY_SHA256,
    }

    class MissingIntermediateMigration(ReadySupabase):
        async def hosted_database_contract(
            self,
            *,
            through_head: str,
        ) -> dict[str, object]:
            value = _database_contract()
            value["prefix_count"] = HOSTED_DATABASE_MIGRATION_COUNT - 1
            value["prefix_identity_sha256"] = "4" * 64
            return value

    app.state.composition = SimpleNamespace(
        supabase_client=MissingIntermediateMigration(),
    )
    drifted = asyncio.run(_get(app, "/v1/ready"))
    assert drifted.status_code == 503
    assert drifted.json()["detail"]["code"] == "core_not_ready"


def test_hosted_readiness_fails_closed_on_database_gate_drift(monkeypatch) -> None:
    monkeypatch.setattr(main, "settings", _hosted_settings())
    app = main.create_app()

    class DriftedSupabase:
        async def readiness_probe(self) -> None:
            return None

        async def pilot_participation_gate(self) -> dict[str, object]:
            return {
                "contract_version": "pilot-participation-gate-v1",
                "project_ref": "zyxwvutsrqponmlkjihg",
                "participation_required": False,
                "notice_version": None,
            }

    app.state.composition = SimpleNamespace(supabase_client=DriftedSupabase())

    response = asyncio.run(_get(app, "/v1/ready"))

    assert response.status_code == 503
    assert response.json()["detail"]["code"] == "core_not_ready"


def test_hosted_readiness_fails_closed_without_deletion_recovery_v2(
    monkeypatch,
) -> None:
    monkeypatch.setattr(main, "settings", _hosted_settings())
    app = main.create_app()

    class MissingDeletionRecovery:
        async def readiness_probe(self) -> None:
            return None

        async def pilot_participation_gate(self) -> dict[str, object]:
            return {
                "contract_version": "pilot-participation-gate-v1",
                "project_ref": "abcdefghijklmnopqrst",
                "participation_required": True,
                "notice_version": "pilot-participation-notice-v1",
            }

        async def account_deletion_recovery_status(self) -> dict[str, object]:
            raise ValueError("missing migration")

    app.state.composition = SimpleNamespace(
        supabase_client=MissingDeletionRecovery(),
    )

    response = asyncio.run(_get(app, "/v1/ready"))

    assert response.status_code == 503
    assert response.json()["detail"]["code"] == "core_not_ready"


def test_hosted_readiness_rejects_the_pre_guard_database_boundary(
    monkeypatch,
) -> None:
    monkeypatch.setattr(main, "settings", _hosted_settings())
    app = main.create_app()

    class PreGuardDatabase:
        async def readiness_probe(self) -> None:
            return None

        async def pilot_participation_gate(self) -> dict[str, object]:
            return {
                "contract_version": "pilot-participation-gate-v1",
                "project_ref": "abcdefghijklmnopqrst",
                "participation_required": True,
                "notice_version": "pilot-participation-notice-v1",
            }

        async def account_deletion_recovery_status(self) -> dict[str, object]:
            return {
                "contract_version": "account-deletion-recovery-v2",
                "legacy_direct_delete_revoked": True,
                "pending_count": 0,
                "oldest_pending_at": None,
            }

        async def hosted_database_contract(
            self,
            *,
            through_head: str,
        ) -> dict[str, object]:
            return _database_contract(
                head="20260820170000_account_deletion_recovery_v2.sql",
                count=64,
                identity_sha256="0" * 64,
                prepared_guard=False,
            )

    app.state.composition = SimpleNamespace(
        supabase_client=PreGuardDatabase(),
    )

    response = asyncio.run(_get(app, "/v1/ready"))

    assert response.status_code == 503
    assert response.json()["detail"]["code"] == "core_not_ready"


def test_loopback_database_contract_stays_available_when_general_ready_is_stale(
    monkeypatch,
) -> None:
    monkeypatch.setattr(main, "settings", _hosted_settings())
    app = main.create_app()

    class StaleRecovery:
        async def readiness_probe(self) -> None:
            return None

        async def pilot_participation_gate(self) -> dict[str, object]:
            return {
                "contract_version": "pilot-participation-gate-v1",
                "project_ref": "abcdefghijklmnopqrst",
                "participation_required": True,
                "notice_version": "pilot-participation-notice-v1",
            }

        async def account_deletion_recovery_status(self) -> dict[str, object]:
            return {
                "contract_version": "account-deletion-recovery-v2",
                "legacy_direct_delete_revoked": True,
                "pending_count": 1,
                "oldest_pending_at": "2026-08-20T00:00:00Z",
            }

        async def hosted_database_contract(
            self,
            *,
            through_head: str,
        ) -> dict[str, object]:
            return _database_contract()

    app.state.composition = SimpleNamespace(supabase_client=StaleRecovery())

    ready = asyncio.run(_get(app, "/v1/ready"))
    contract = asyncio.run(_get(app, "/v1/internal/database-contract"))

    assert ready.status_code == 503
    assert contract.status_code == 200
    assert contract.json() == {
        "contract_version": "hosted-database-contract-v1",
        "migration_head": HOSTED_DATABASE_HEAD,
        "migration_count": HOSTED_DATABASE_MIGRATION_COUNT,
        "migration_identity_sha256": HOSTED_DATABASE_IDENTITY_SHA256,
        "prefix_head": HOSTED_DATABASE_HEAD,
        "prefix_count": HOSTED_DATABASE_MIGRATION_COUNT,
        "prefix_identity_sha256": HOSTED_DATABASE_IDENTITY_SHA256,
        "prepared_deletion_pending_guard": True,
    }


def test_database_contract_route_rejects_a_non_loopback_client(monkeypatch) -> None:
    monkeypatch.setattr(main, "settings", _hosted_settings())
    app = main.create_app()
    app.state.composition = SimpleNamespace(supabase_client=object())

    async def request() -> httpx.Response:
        async with httpx.AsyncClient(
            transport=httpx.ASGITransport(
                app=app,
                client=("203.0.113.10", 4444),
            ),
            base_url="http://test",
        ) as client:
            return await client.get("/v1/internal/database-contract")

    response = asyncio.run(request())

    assert response.status_code == 404


def test_deletion_reconcile_loop_survives_an_unexpected_cycle_failure(
    monkeypatch,
) -> None:
    calls = 0

    class RecoveryService:
        async def reconcile_account_deletions(self, *, limit: int):
            nonlocal calls
            assert limit == 5
            calls += 1
            if calls == 1:
                raise RuntimeError("private failure detail")
            return SimpleNamespace(
                examined=0,
                completed=0,
                failures=0,
                pending_count=0,
                oldest_pending_at=None,
            )

    async def bounded_sleep(_seconds: float) -> None:
        if calls >= 2:
            raise asyncio.CancelledError

    monkeypatch.setattr(main.asyncio, "sleep", bounded_sleep)
    app = SimpleNamespace(
        state=SimpleNamespace(
            composition=SimpleNamespace(account_service=RecoveryService()),
        ),
    )

    with pytest.raises(asyncio.CancelledError):
        asyncio.run(main._reconcile_account_deletions(app))

    assert calls == 2
