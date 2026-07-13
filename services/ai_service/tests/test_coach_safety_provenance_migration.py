from pathlib import Path


MIGRATION = (
    Path(__file__).resolve().parents[3]
    / "supabase"
    / "migrations"
    / "20260713220000_phase_10_coach_safety_provenance_guard.sql"
)


def _migration_sql() -> str:
    return MIGRATION.read_text(encoding="utf-8")


def test_follow_up_replaces_only_the_private_response_validator() -> None:
    sql = _migration_sql()

    assert "create or replace function private.coach_response_is_valid_v1(" in sql
    assert "create table" not in sql
    assert "drop table" not in sql
    assert "delete from" not in sql
    assert "truncate " not in sql


def test_safety_source_and_provider_call_truth_are_cross_validated() -> None:
    sql = _migration_sql()

    assert "provenance ->> 'source' = 'model'" in sql
    assert "(provenance ->> 'provider_called')::boolean is not true" in sql
    assert "safety ->> 'classification' = 'safety_redirect'" in sql
    assert "provenance ->> 'source' = 'deterministic_safety'" in sql
    assert "safety ->> 'classification' <> 'safety_redirect'" in sql
    assert "provenance ->> 'provider' = 'disabled'" in sql


def test_post_provider_and_pre_provider_deterministic_redirects_are_both_allowed() -> None:
    sql = _migration_sql()

    old_rejection = """provenance ->> 'source' = 'deterministic_safety'
       and (provenance ->> 'provider_called')::boolean is not false"""
    assert old_rejection not in sql
    assert "provider_called distinguishes them" in sql
