from pathlib import Path

import pytest

from tests.migration_source import (
    MIGRATIONS_DIR,
    extract_dropped_policy_names,
    extract_function,
    extract_grants,
    extract_policy,
    extract_revokes,
    load_migration,
    migration_path,
    normalize_sql,
)


def test_migration_loader_accepts_only_a_versioned_sql_basename() -> None:
    filename = "20260802111518_privileged_function_lint_cleanup.sql"

    assert migration_path(filename) == MIGRATIONS_DIR / filename
    assert "create or replace function public.current_app_role(" in load_migration(
        filename,
    )
    with pytest.raises(ValueError, match="one SQL basename"):
        migration_path(f"nested/{filename}")


def test_normalizer_is_case_and_layout_insensitive() -> None:
    assert normalize_sql(" GRANT\n  SELECT  To ROLE; ") == "grant select to role;"


def test_function_extractor_supports_replace_and_tagged_bodies() -> None:
    sql = """
create or replace function private.first() returns void
language plpgsql as $body$
begin
  perform ';';
end;
$body$;

create function public.second() returns void language sql as $$ select null; $$;
"""

    first = extract_function(sql, "private.first")
    second = extract_function(sql, "public.second")

    assert first.startswith("create or replace function private.first(")
    assert first.endswith("$body$;")
    assert second.startswith("create function public.second(")
    assert second.endswith("$$;")


def test_policy_and_grant_extractors_return_complete_statements() -> None:
    sql = """
create policy "records_owner_select"
  on public.records for select to authenticated
  using ((select auth.uid()) = user_id);
grant select,
  update (title) on table public.records to authenticated;
revoke all on table public.records from anon;
grant execute on function public.refresh_records(uuid) to service_role;
drop policy if exists "records_old_select" on public.records;
"""

    policy = extract_policy(sql, "records_owner_select")
    grants = extract_grants(sql)
    revokes = extract_revokes(sql)

    assert policy.endswith("((select auth.uid()) = user_id);")
    assert len(grants) == 2
    assert normalize_sql(grants[0]) == (
        "grant select, update (title) on table public.records to authenticated;"
    )
    assert "public.refresh_records(uuid)" in grants[1]
    assert revokes == ("revoke all on table public.records from anon;",)
    assert extract_dropped_policy_names(sql) == ("records_old_select",)


def test_extractors_fail_loudly_when_historical_identity_drifts() -> None:
    with pytest.raises(ValueError, match="function declaration not found"):
        extract_function("select 1;", "public.missing")
    with pytest.raises(ValueError, match="policy declaration not found"):
        extract_policy("select 1;", "missing")


def test_migrations_directory_is_a_real_repository_location() -> None:
    assert isinstance(MIGRATIONS_DIR, Path)
    assert MIGRATIONS_DIR.is_dir()
