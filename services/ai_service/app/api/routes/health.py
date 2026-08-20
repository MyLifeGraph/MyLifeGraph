import asyncio
import ipaddress
import re
from datetime import UTC, datetime, timedelta

import httpx
from fastapi import APIRouter, HTTPException, Request

from app.core.config import Settings
from app.models.account import (
    ACCOUNT_DELETION_RECOVERY_CONTRACT_VERSION,
    PILOT_PARTICIPATION_GATE_CONTRACT_VERSION,
)

router = APIRouter(tags=["health"])

HOSTED_DATABASE_CONTRACT_VERSION = "hosted-database-contract-v1"
HOSTED_DATABASE_CONTRACT_MINIMUM_HEAD = (
    "20260820190000_hosted_database_contract_v1.sql"
)


@router.get("/health")
async def health_check(request: Request) -> dict[str, str]:
    settings: Settings = request.app.state.settings
    release_sha, release_tag = settings.release_identity()
    return {
        "status": "ok",
        "release_sha": release_sha,
        "release_tag": release_tag,
    }


@router.get("/ready")
async def readiness_check(request: Request) -> dict[str, str | int]:
    settings: Settings = request.app.state.settings
    try:
        settings.release_identity()
        url, key = settings.supabase_backend_configuration()
        configured = bool(url.strip() and key.strip())
    except ValueError:
        configured = False
    composition = request.app.state.composition
    if composition is None or not configured:
        raise _not_ready()
    migration_head: str | None = None
    migration_count: int | None = None
    migration_identity_sha256: str | None = None
    try:
        async with asyncio.timeout(min(settings.supabase_timeout_seconds, 5)):
            await composition.supabase_client.readiness_probe()
            if settings.requires_pilot_participation:
                gate = await composition.supabase_client.pilot_participation_gate()
                if not _has_exact_participation_gate(
                    gate,
                    project_ref=settings.hosted_supabase_project_ref(),
                ):
                    raise ValueError("Hosted participation gate is not ready.")
                deletion_status = (
                    await composition.supabase_client.account_deletion_recovery_status()
                )
                if not _has_healthy_deletion_recovery(deletion_status):
                    raise ValueError("Hosted account deletion recovery is not ready.")
                database_contract = (
                    await composition.supabase_client.hosted_database_contract(
                        through_head=settings.release_migration_identity()[0],
                    )
                )
                (
                    migration_head,
                    migration_count,
                    migration_identity_sha256,
                ) = _exact_hosted_database_contract(
                    database_contract,
                    expected_prefix=settings.release_migration_identity(),
                )
    except (httpx.HTTPError, OSError, TimeoutError, ValueError):
        raise _not_ready() from None
    if migration_head is None:
        return {"status": "ready"}
    if migration_count is None or migration_identity_sha256 is None:
        raise _not_ready()
    return {
        "status": "ready",
        "migration_head": migration_head,
        "migration_count": migration_count,
        "migration_identity_sha256": migration_identity_sha256,
    }


@router.get("/internal/database-contract")
async def internal_database_contract(request: Request) -> dict[str, object]:
    client = request.client
    if client is None:
        raise HTTPException(status_code=404)
    try:
        if not ipaddress.ip_address(client.host).is_loopback:
            raise HTTPException(status_code=404)
    except ValueError:
        raise HTTPException(status_code=404) from None
    composition = request.app.state.composition
    if composition is None:
        raise _not_ready()
    settings: Settings = request.app.state.settings
    requested_head = request.query_params.get("through_head")
    try:
        expected_prefix = settings.release_migration_identity()
        through_head = requested_head or expected_prefix[0]
        async with asyncio.timeout(min(settings.supabase_timeout_seconds, 5)):
            value = await composition.supabase_client.hosted_database_contract(
                through_head=through_head,
            )
            _exact_hosted_database_contract(
                value,
                expected_prefix=expected_prefix if requested_head is None else None,
                requested_head=through_head,
            )
    except (httpx.HTTPError, OSError, TimeoutError, ValueError):
        raise _not_ready() from None
    return value


def _has_exact_participation_gate(
    value: object,
    *,
    project_ref: str,
) -> bool:
    if not isinstance(value, dict) or set(value) != {
        "contract_version",
        "project_ref",
        "participation_required",
        "notice_version",
    }:
        return False
    return (
        value["contract_version"] == PILOT_PARTICIPATION_GATE_CONTRACT_VERSION
        and value["project_ref"] == project_ref
        and value["participation_required"] is True
        and value["notice_version"] == "pilot-participation-notice-v1"
    )


def _has_healthy_deletion_recovery(value: object) -> bool:
    if not isinstance(value, dict) or set(value) != {
        "contract_version",
        "legacy_direct_delete_revoked",
        "pending_count",
        "oldest_pending_at",
    }:
        return False
    pending_count = value["pending_count"]
    oldest_value = value["oldest_pending_at"]
    if (
        value["contract_version"] != ACCOUNT_DELETION_RECOVERY_CONTRACT_VERSION
        or value["legacy_direct_delete_revoked"] is not True
        or type(pending_count) is not int
        or pending_count < 0
        or (pending_count == 0) != (oldest_value is None)
    ):
        return False
    if oldest_value is None:
        return True
    if not isinstance(oldest_value, str):
        return False
    try:
        oldest = datetime.fromisoformat(oldest_value.replace("Z", "+00:00"))
    except ValueError:
        return False
    return oldest.tzinfo is not None and oldest >= datetime.now(UTC) - timedelta(
        minutes=15,
    )


def _exact_hosted_database_contract(
    value: object,
    *,
    expected_prefix: tuple[str, int, str] | None = None,
    requested_head: str | None = None,
) -> tuple[str, int, str]:
    if not isinstance(value, dict) or set(value) != {
        "contract_version",
        "migration_head",
        "migration_count",
        "migration_identity_sha256",
        "prefix_head",
        "prefix_count",
        "prefix_identity_sha256",
        "prepared_deletion_pending_guard",
    }:
        raise ValueError("Hosted database contract shape is invalid.")
    migration_head = value["migration_head"]
    migration_count = value["migration_count"]
    migration_identity_sha256 = value["migration_identity_sha256"]
    prefix_head = value["prefix_head"]
    prefix_count = value["prefix_count"]
    prefix_identity_sha256 = value["prefix_identity_sha256"]
    if (
        value["contract_version"] != HOSTED_DATABASE_CONTRACT_VERSION
        or value["prepared_deletion_pending_guard"] is not True
        or not isinstance(migration_head, str)
        or type(migration_count) is not int
        or migration_count < 1
        or migration_count > 50_000
        or not isinstance(migration_identity_sha256, str)
        or re.fullmatch(r"[0-9a-f]{64}", migration_identity_sha256) is None
        or not isinstance(prefix_head, str)
        or re.fullmatch(r"[0-9]{14}_[a-z0-9_]+\.sql", prefix_head) is None
        or type(prefix_count) is not int
        or prefix_count < 1
        or prefix_count > migration_count
        or not isinstance(prefix_identity_sha256, str)
        or re.fullmatch(r"[0-9a-f]{64}", prefix_identity_sha256) is None
        or re.fullmatch(r"[0-9]{14}_[a-z0-9_]+\.sql", migration_head) is None
        or migration_head < HOSTED_DATABASE_CONTRACT_MINIMUM_HEAD
        or prefix_head > migration_head
    ):
        raise ValueError("Hosted database contract is not current.")
    if requested_head is not None and prefix_head != requested_head:
        raise ValueError("Hosted database prefix is not the requested boundary.")
    if expected_prefix is not None and (
        prefix_head,
        prefix_count,
        prefix_identity_sha256,
    ) != expected_prefix:
        raise ValueError("Hosted database prefix differs from the release.")
    return migration_head, migration_count, migration_identity_sha256


def _not_ready() -> HTTPException:
    return HTTPException(
        status_code=503,
        detail={
            "code": "core_not_ready",
            "message": "Core service configuration is not ready.",
            "retryable": True,
        },
    )
