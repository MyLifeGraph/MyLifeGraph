from tests.migration_source import load_migration


MIGRATION = load_migration("20260726170000_recommendation_refresh_v2.sql")


def _sql() -> str:
    return MIGRATION.lower()


def test_refresh_retires_old_new_rows_and_inserts_the_complete_new_set() -> None:
    sql = _sql()

    owner_lock = sql.index("pg_advisory_xact_lock")
    retire = sql.index("update public.recommendations")
    insert = sql.index("insert into public.recommendations", retire)
    assert owner_lock < retire < insert
    assert "status = 'dismissed'" in sql[retire:insert]
    assert "and status = 'new'" in sql[retire:insert]
    assert "'replaced_by_deliberate_refresh'" in sql[retire:insert]
    assert "from jsonb_array_elements(p_rows)" in sql[insert:]


def test_refresh_is_bounded_service_role_only_and_rejects_stale_writers() -> None:
    sql = _sql()

    assert "jsonb_array_length(p_rows) > 5" in sql
    assert "and generated_at > p_refreshed_at" in sql
    assert "using errcode = 'pt409'" in sql
    assert (
        "revoke all on function public.replace_current_recommendations_v2"
        in sql
    )
    assert "from public, anon, authenticated" in sql
    assert "to service_role" in sql
