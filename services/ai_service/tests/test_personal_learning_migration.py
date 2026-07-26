import re
from pathlib import Path

from app.models.account import (
    ACCOUNT_EXPORT_OMITTED_TABLES,
    ACCOUNT_EXPORT_TABLE_NAMES,
)
from app.services.account_service import ACCOUNT_EXPORT_TABLES


ROOT = Path(__file__).resolve().parents[3]
MIGRATION = (
    ROOT / "supabase/migrations/20260726120000_personal_learning_v1.sql"
).read_text(encoding="utf-8")


def _function_body(name: str) -> str:
    start = MIGRATION.index(f"create or replace function public.{name}(")
    return MIGRATION[start : MIGRATION.index("\n$$;", start)]


def test_reflections_are_one_per_terminal_owned_session_with_exact_bounds() -> None:
    normalized = " ".join(MIGRATION.lower().split())
    assert "create table public.focus_session_reflections" in normalized
    assert "focus_session_id uuid primary key" in normalized
    assert "focus_quality smallint not null check (focus_quality between 1 and 5)" in normalized
    assert "useful_progress smallint not null check (useful_progress between 1 and 5)" in normalized
    assert "cardinality(obstacles) between 0 and 2" in normalized
    for obstacle in (
        "tired",
        "distracted",
        "interrupted",
        "unclear_goal",
        "material_too_difficult",
        "session_too_long",
        "environment",
        "other",
    ):
        assert f"'{obstacle}'" in MIGRATION
    assert re.search(
        r"foreign key \(focus_session_id, user_id\).*?"
        r"references public\.focus_sessions \(id, user_id\) on delete cascade",
        MIGRATION,
        flags=re.DOTALL,
    )
    assert "focus.status in ('completed', 'abandoned')" in MIGRATION
    assert "A terminal focus session is immutable" not in MIGRATION


def test_reflection_rls_is_forced_owner_crud_and_guest_has_no_grant() -> None:
    normalized = " ".join(MIGRATION.lower().split())
    assert (
        "alter table public.focus_session_reflections force row level security"
        in normalized
    )
    for operation in ("select", "insert", "update", "delete"):
        assert f"focus_session_reflections_owner_{operation}_v1" in normalized
    assert (
        "revoke all privileges on table public.focus_session_reflections "
        "from public, anon"
    ) in normalized
    assert (
        "grant select, insert, update, delete on table "
        "public.focus_session_reflections to authenticated"
    ) in normalized


def test_preferences_enforce_defaults_dependency_and_future_profile_creation() -> None:
    normalized = " ".join(MIGRATION.lower().split())
    assert "focus_reflection_prompt_enabled boolean not null default true" in normalized
    assert "personal_pattern_analysis_enabled boolean not null default true" in normalized
    assert "learned_focus_planning_enabled boolean not null default false" in normalized
    assert (
        "not learned_focus_planning_enabled or personal_pattern_analysis_enabled"
        in normalized
    )
    assert "insert into public.learning_preferences (user_id) select profile.id" in normalized
    assert "create trigger profiles_ensure_learning_preferences_v1" in normalized
    assert (
        "revoke all privileges on table public.learning_preferences "
        "from public, anon, authenticated"
    ) in normalized
    assert "grant select on table public.learning_preferences to authenticated" in normalized


def test_preference_rpc_is_revisioned_payload_bound_and_exactly_replayable() -> None:
    body = _function_body("update_learning_preferences_v1")
    assert body.index("hashtextextended(p_user_id::text, 0)") < body.index(
        "hashtextextended(p_request_id::text, 1)",
    )
    for field in (
        "'expected_revision', p_expected_revision",
        "'focus_reflection_prompt_enabled',",
        "'personal_pattern_analysis_enabled',",
        "'learned_focus_planning_enabled',",
    ):
        assert field in body
    assert "current_preferences.revision <> p_expected_revision" in body
    assert "current_preferences.revision + 1" in body
    assert "using errcode = 'PT409'" in body
    assert "'replayed', true" in body
    assert "'replayed', false" in body


def test_clear_is_retry_safe_revision_bound_and_deletes_only_reflections() -> None:
    body = _function_body("clear_focus_reflection_history_v1")
    normalized = " ".join(body.lower().split())
    assert "p_confirmation is distinct from 'CLEAR'" in body
    assert "current_preferences.revision <> p_expected_revision" in body
    assert (
        "delete from public.focus_session_reflections where user_id = p_user_id"
        in normalized
    )
    assert "delete from public.focus_sessions" not in normalized
    assert "get diagnostics deleted_count = row_count" in normalized
    assert "'replayed', true" in body
    assert "'deleted_count', deleted_count" in body


def test_learning_commands_are_service_role_only_and_ledger_is_omitted() -> None:
    normalized = " ".join(MIGRATION.lower().split())
    for signature in (
        "public.update_learning_preferences_v1( "
        "uuid, uuid, int, boolean, boolean, boolean )",
        "public.clear_focus_reflection_history_v1( uuid, uuid, int, text )",
    ):
        assert (
            f"revoke all on function {signature} "
            "from public, anon, authenticated"
        ) in normalized
        assert f"grant execute on function {signature} to service_role" in normalized
    assert (
        "alter table public.learning_request_identities force row level security"
        in normalized
    )
    assert "learning_request_identities" not in ACCOUNT_EXPORT_TABLE_NAMES
    assert ACCOUNT_EXPORT_OMITTED_TABLES["learning_request_identities"] == (
        "backend_only_anti_replay_ledger"
    )


def test_account_export_contains_reflections_and_preferences_exactly_once() -> None:
    assert ACCOUNT_EXPORT_TABLE_NAMES.count("learning_preferences") == 1
    assert ACCOUNT_EXPORT_TABLE_NAMES.count("focus_session_reflections") == 1
    configured = tuple(table.name for table in ACCOUNT_EXPORT_TABLES)
    assert configured == ACCOUNT_EXPORT_TABLE_NAMES
