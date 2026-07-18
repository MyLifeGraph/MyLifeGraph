import re
from pathlib import Path

from app.models.account import ACCOUNT_EXPORT_OMITTED_TABLES


ROOT = Path(__file__).resolve().parents[3]
MIGRATION = (
    ROOT
    / "supabase/migrations/20260714100000_notification_lifecycle_v1.sql"
).read_text(encoding="utf-8")


def _function_body() -> str:
    start = MIGRATION.index(
        "create or replace function public.apply_notification_action_v1(",
    )
    return MIGRATION[start : MIGRATION.index("\n$$;", start)]


def test_notification_lifecycle_adds_consistent_read_and_dismiss_timestamps() -> None:
    normalized = " ".join(MIGRATION.lower().split())

    assert "add column if not exists read_at timestamptz" in normalized
    assert "add column if not exists dismissed_at timestamptz" in normalized
    assert "where is_read and read_at is null" in normalized
    assert "notifications_read_state_check" in MIGRATION
    assert "notifications_dismissed_state_check" in MIGRATION


def test_notification_retry_ledger_is_bounded_forced_rls_and_backend_only() -> None:
    normalized = " ".join(MIGRATION.lower().split())

    assert "create table public.notification_action_requests" in normalized
    assert "request_id uuid primary key" in normalized
    assert "command in ('mark_read', 'mark_unread', 'dismiss')" in normalized
    assert (
        "alter table public.notification_action_requests force row level security"
        in normalized
    )
    assert (
        "revoke all on table public.notification_action_requests from public, "
        "anon, authenticated, service_role"
        in normalized
    )
    assert (
        "grant select on table public.notification_action_requests to service_role"
        in normalized
    )
    assert "on delete cascade" in normalized


def test_notification_rpc_replays_exact_request_and_rejects_reinterpretation() -> None:
    body = _function_body()
    normalized = " ".join(body.lower().split())

    owner_lock = body.index(
        "pg_advisory_xact_lock(hashtextextended(p_user_id::text, 0))",
    )
    request_lock = body.index(
        "pg_advisory_xact_lock(hashtextextended(p_request_id::text, 14))",
    )
    request_row_lock = body.index(
        "from public.notification_action_requests",
    )
    notification_row_lock = body.index("from public.notifications")
    assert owner_lock < request_lock < request_row_lock < notification_row_lock
    for field in (
        "existing_request.user_id is distinct from p_user_id",
        "existing_request.notification_id is distinct from p_notification_id",
        "existing_request.command is distinct from p_command",
        "existing_request.expected_updated_at is distinct from p_expected_updated_at",
    ):
        assert field in body
    assert "using errcode = 'PT409'" in body
    assert "'replayed', true" in body
    assert "'replayed', false" in body
    assert (
        "current_notification.updated_at is distinct from p_expected_updated_at"
        in body
    )
    assert "where id = p_notification_id and user_id = p_user_id" in normalized


def test_notification_commands_mutate_only_lifecycle_columns_and_never_delete() -> None:
    body = _function_body()

    assert "p_command = 'mark_read'" in body
    assert "p_command = 'mark_unread'" in body
    assert "p_command = 'dismiss'" in body
    assert "dismissed_at = changed_at" in body
    assert "delete from public.notifications" not in body.lower()
    assert "Notification is already dismissed" in body
    assert "using errcode = 'PT404'" in body


def test_notification_rpc_is_service_role_only_with_safe_search_path() -> None:
    normalized = " ".join(MIGRATION.lower().split())

    assert "set search_path = pg_catalog, pg_temp" in normalized
    assert (
        "revoke all on function public.apply_notification_action_v1( uuid, uuid, "
        "uuid, text, timestamptz ) from public, anon, authenticated"
        in normalized
    )
    assert (
        "grant execute on function public.apply_notification_action_v1( uuid, uuid, "
        "uuid, text, timestamptz ) to service_role"
        in normalized
    )


def test_authenticated_direct_notification_mutation_remains_forbidden() -> None:
    normalized = " ".join(MIGRATION.lower().split())

    assert (
        "revoke insert, update, delete, truncate on table public.notifications "
        "from public, anon, authenticated"
        in normalized
    )
    assert "grant select on table public.notifications to authenticated" in normalized


def test_account_export_truthfully_names_the_omitted_notification_ledger() -> None:
    assert ACCOUNT_EXPORT_OMITTED_TABLES == {
        "calendar_request_identities": "backend_only_anti_replay_ledger",
        "notification_action_requests": "backend_only_anti_replay_ledger",
        "deadline_plan_request_identities": "backend_only_anti_replay_ledger",
    }
    assert re.search(
        r"foreign key \(notification_id, user_id\).*?on delete cascade",
        MIGRATION,
        flags=re.DOTALL,
    )
