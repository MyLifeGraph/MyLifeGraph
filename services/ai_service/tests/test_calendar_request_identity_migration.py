from pathlib import Path


MIGRATION = (
    Path(__file__).resolve().parents[3]
    / "supabase"
    / "migrations"
    / "20260713143000_phase_9_calendar_request_identity_guard.sql"
)


def _migration_sql() -> str:
    return MIGRATION.read_text(encoding="utf-8")


def _function_sql(sql: str, function_name: str) -> str:
    start = sql.index(f"create or replace function public.{function_name}(")
    end = sql.index("\n$$;", start) + len("\n$$;")
    return sql[start:end]


def test_calendar_request_registry_is_global_minimal_and_backend_only() -> None:
    sql = _migration_sql()

    assert "create table public.calendar_request_identities" in sql
    assert "request_id uuid primary key" in sql
    assert "payload_fingerprint" not in sql
    assert "force row level security" in sql
    assert "calendar_request_identities_service_role_select" in sql
    assert "calendar_request_identities_service_role_insert" in sql
    assert "from public, anon, authenticated, service_role" in sql
    assert "grant select, insert\n" in sql
    assert "grant select, insert, update" not in sql
    assert "on table public.calendar_request_identities to service_role" in sql


def test_calendar_request_backfill_rejects_existing_cross_scope_collisions() -> None:
    sql = _migration_sql()

    assert "select create_request_id as request_id" in sql
    assert "select request_id\n      from public.calendar_imports" in sql
    assert "select disconnect_request_id" in sql
    assert "select delete_request_id" in sql
    assert "having count(*) > 1" in sql
    assert (
        "Existing calendar request identities conflict across owner, connection, "
        "or operation"
    ) in sql


def test_calendar_rpcs_use_pt409_and_claim_the_global_identity() -> None:
    sql = _migration_sql()
    function_names = [
        "create_calendar_connection_v1",
        "apply_calendar_import_v1",
        "disconnect_calendar_connection_v1",
        "delete_calendar_imported_data_v1",
    ]

    assert "using errcode = '40001'" not in sql
    for function_name in function_names:
        function = _function_sql(sql, function_name)
        assert "public.calendar_request_identities" in function
        assert "using errcode = 'PT409'" in function
        assert "hashtextextended(p_request_id::text, 9)" in function


def test_import_replay_requires_exact_content_connected_current_projection() -> None:
    function = _function_sql(_migration_sql(), "apply_calendar_import_v1")

    assert "existing_import.input_fingerprint <> p_input_fingerprint" in function
    assert "target_connection.status <> 'connected'" in function
    assert "target_connection.imported_data_deleted_at is not null" in function
    assert (
        "target_connection.last_import_id is distinct from existing_import.id"
        in function
    )
    assert "Calendar import request is no longer current" in function
