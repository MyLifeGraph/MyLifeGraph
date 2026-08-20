from tests.migration_source import load_migration


MIGRATION = load_migration("20260820170000_account_deletion_recovery_v2.sql")
PREPARED_GUARD = load_migration(
    "20260820183000_account_deletion_prepared_pending_guard_v2.sql",
)
ROLE_GUARD = load_migration(
    "20260820200000_account_deletion_replayer_role_guard_v2.sql",
)


def test_deletion_recovery_ledger_is_minimal_forced_and_service_only() -> None:
    assert "create table public.account_deletion_intents" in MIGRATION
    assert "alter table public.account_deletion_intents force row level security" in (
        MIGRATION
    )
    assert "from public, anon, authenticated, service_role" in MIGRATION
    table_body = MIGRATION.split(
        "create table public.account_deletion_intents (",
        maxsplit=1,
    )[1].split(");", maxsplit=1)[0]
    assert "email" not in table_body
    assert "content" not in table_body
    assert "journal_payload_sha256" in MIGRATION
    assert "state in ('prepared', 'appending', 'accepted', 'completed')" in MIGRATION


def test_deletion_recovery_requires_journal_before_delete_and_supports_replay() -> None:
    accepted = MIGRATION.index("create function public.accept_account_deletion_journal_v2")
    completed = MIGRATION.index("create function public.complete_account_deletion_v2")
    assert accepted < completed
    assert "mark_account_deletion_appending_v2" in MIGRATION
    assert "intent.state <> 'accepted'" in MIGRATION
    assert "public.delete_account_v1(p_user_id, p_confirmation)" in MIGRATION
    assert "create function public.replay_account_deletion_v2" in MIGRATION
    assert "p_journal_object_key is distinct from expected_object_key" in MIGRATION
    assert "to service_role" in MIGRATION


def test_replayer_role_is_created_safe_and_preexisting_drift_fails_closed() -> None:
    normalized = " ".join(MIGRATION.lower().split())
    guard_normalized = " ".join(ROLE_GUARD.lower().split())

    assert (
        "create role mylifegraph_deletion_replayer with nologin nosuperuser "
        "nocreatedb nocreaterole noinherit noreplication nobypassrls "
        "connection limit 0"
    ) in normalized
    assert "role.rolconfig is null" in normalized
    assert "membership.roleid = target_role_oid" in normalized
    assert "membership.member = target_role_oid" in normalized
    assert "server_version_num" in normalized
    assert "set_config('createrole_self_grant', '', true)" in normalized
    assert "membership.member = current_user::regrole" in normalized
    assert "membership.grantor = 10" in normalized
    assert "membership.admin_option" in normalized
    assert "to_jsonb(membership) ->> 'inherit_option'" in normalized
    assert "to_jsonb(membership) ->> 'set_option'" in normalized
    assert "incident_membership_count <> 1" in normalized
    assert "allowed_membership_count <> 1" in normalized
    assert "has unsafe attributes" in normalized
    assert "has unsafe memberships" in normalized
    assert "alter role mylifegraph_deletion_replayer" not in normalized
    assert "alter role mylifegraph_deletion_replayer" not in guard_normalized
    assert "account_deletion_replayer_role_safe_v2" in guard_normalized
    assert "server_version_num" in guard_normalized
    assert "membership.member = current_user::regrole" in guard_normalized
    assert "membership.grantor = 10" in guard_normalized
    assert "membership_facts ->> 'inherit_option'" in guard_normalized
    assert "membership_facts ->> 'set_option'" in guard_normalized


def test_deletion_pending_is_a_restrictive_database_wide_boundary() -> None:
    assert "current_request_not_deletion_pending_v2" in MIGRATION
    assert "set row_security = off" in MIGRATION
    assert "class.relrowsecurity" in MIGRATION
    assert "as restrictive for all to authenticated" in MIGRATION
    assert "account_deletion_not_pending_v2" in MIGRATION


def test_prepared_deletion_is_pending_for_access_status_and_readiness() -> None:
    expected_states = "('prepared', 'appending', 'accepted')"
    assert PREPARED_GUARD.count(expected_states) == 3
    assert "create or replace function private.current_request_not_deletion_pending_v2" in (
        PREPARED_GUARD
    )
    assert "create or replace function public.get_account_deletion_pending_v2" in (
        PREPARED_GUARD
    )
    assert (
        "create or replace function public.get_account_deletion_recovery_status_v2"
        in PREPARED_GUARD
    )
    assert "to authenticated" in PREPARED_GUARD
    assert PREPARED_GUARD.count("to service_role") == 2
