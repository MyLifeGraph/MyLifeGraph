import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]
MIGRATION = (
    ROOT / "supabase/migrations/20260713233000_v1_account_delete.sql"
).read_text(encoding="utf-8")
PHASE_3 = (
    ROOT
    / "supabase/migrations/20260711120000_phase_3_executable_action_schema.sql"
).read_text(encoding="utf-8")
LEGACY_RLS = (
    ROOT / "supabase/migrations/20260613190000_restrict_security_definer_functions.sql"
).read_text(encoding="utf-8")
CALENDAR_GUARD = (
    ROOT
    / "supabase/migrations/20260713143000_phase_9_calendar_request_identity_guard.sql"
).read_text(encoding="utf-8")

LEGACY_CHILD_TABLES = (
    "FocusSession",
    "CoachMessage",
    "AIInsight",
    "ActivityLog",
    "DailyLog",
    "MemoryEntry",
    "MoodLog",
    "Notification",
    "ScheduleItem",
    "SleepLog",
    "Task",
    "Habit",
    "Goal",
)
AUTHENTICATED_READ_ONLY_OUTPUT_TABLES = (
    "notifications",
    "ai_insights",
    "recommendations",
    "skillset_profiles",
)


def _function_body() -> str:
    start = MIGRATION.index("create or replace function public.delete_account_v1(")
    return MIGRATION[start : MIGRATION.index("\n$$;", start)]


def _text_array(name: str) -> tuple[str, ...]:
    start = MIGRATION.index(f"{name} constant text[] := array[")
    end = MIGRATION.index("];", start)
    return tuple(re.findall(r"'([^']+)'", MIGRATION[start:end]))


def _calendar_function_body(name: str) -> str:
    start = CALENDAR_GUARD.index(f"create or replace function public.{name}(")
    return CALENDAR_GUARD[start : CALENDAR_GUARD.index("\n$$;", start)]


def test_account_delete_handles_the_two_restrict_linked_focus_targets_first() -> None:
    assert "constraint focus_sessions_task_id_fkey" in PHASE_3
    assert (
        "foreign key (task_id) references public.tasks (id) on delete restrict"
        in PHASE_3
    )
    assert "constraint focus_sessions_habit_id_fkey" in PHASE_3
    assert (
        "foreign key (habit_id) references public.habits (id) on delete restrict"
        in PHASE_3
    )

    body = _function_body()
    focus_delete = body.index(
        "delete from public.focus_sessions where user_id = p_user_id;",
    )
    auth_delete = body.index("delete from auth.users")
    assert focus_delete < auth_delete


def test_account_delete_is_confirmation_bound_owner_locked_and_atomic() -> None:
    body = _function_body()

    assert "p_confirmation is distinct from 'DELETE'" in body
    for namespace in [0, 11, 12]:
        assert (
            "pg_advisory_xact_lock("
            f"hashtextextended(p_user_id::text, {namespace}))"
        ) in body
    assert "perform 1 from auth.users where id = p_user_id for update;" in body
    assert "exists (select 1 from public.profiles where id = p_user_id)" in body
    assert "'deleted', true" in body
    assert "'not_found', false" in body
    assert "'user_id', deleted_user_id" in body


def test_account_delete_removes_every_known_legacy_owner_mapping() -> None:
    body = _function_body()
    first_array_start = LEGACY_RLS.index("foreach table_name in array array[")
    legacy_array_start = LEGACY_RLS.index(
        "foreach table_name in array array[",
        first_array_start + 1,
    )
    legacy_array_end = LEGACY_RLS.index("] loop", legacy_array_start)
    rls_tables = set(
        re.findall(
            r"'([A-Za-z]+)'",
            LEGACY_RLS[legacy_array_start:legacy_array_end],
        ),
    )
    assert rls_tables == set(LEGACY_CHILD_TABLES)
    table_names = _text_array("legacy_table_names")
    owner_columns = _text_array("legacy_owner_columns")
    assert set(table_names[:-1]) == set(LEGACY_CHILD_TABLES)
    assert table_names[-1] == "User"
    assert owner_columns == ("userId",) * len(LEGACY_CHILD_TABLES) + ("id",)
    assert len(table_names) == len(owner_columns)

    for table in LEGACY_CHILD_TABLES:
        assert f"'{table}'" in LEGACY_RLS
    assert '"userId" = auth.uid()::text' in LEGACY_RLS
    assert (
        "legacy_table := to_regclass(format('public.%I', legacy_table_name))"
        in body
    )
    assert "from pg_attribute" in body
    assert "attname = legacy_owner_column" in body
    assert "not attisdropped" in body
    assert "where lower(%I::text) = $1" in body
    assert "if legacy_rows_remain then" in body

    focus_delete = table_names.index("FocusSession")
    task_delete = table_names.index("Task")
    habit_delete = table_names.index("Habit")
    goal_delete = table_names.index("Goal")
    legacy_user_delete = table_names.index("User")
    auth_delete = body.index("delete from auth.users")
    assert focus_delete < task_delete < goal_delete < legacy_user_delete
    assert focus_delete < habit_delete < goal_delete
    assert body.index("delete from public.%I") < auth_delete


def test_account_delete_blocks_focus_and_legacy_insert_races() -> None:
    body = _function_body()

    profile_lock = body.index(
        "perform 1 from public.profiles where id = p_user_id for update;",
    )
    legacy_lock = body.index("lock table public.%I in share row exclusive mode")
    focus_delete = body.index(
        "delete from public.focus_sessions where user_id = p_user_id;",
    )
    legacy_delete = body.index("delete from public.%I")
    total_postcheck = body.index("if legacy_rows_remain then")
    auth_delete = body.index("delete from auth.users")

    assert profile_lock < focus_delete < auth_delete
    assert legacy_lock < legacy_delete < total_postcheck < auth_delete


def test_account_delete_matches_calendar_identity_then_connection_lock_order() -> None:
    body = _function_body()
    identity_lock_sql = (
        "from public.calendar_request_identities\n"
        "  where user_id = p_user_id\n"
        "  order by request_id\n"
        "  for update;"
    )
    connection_lock_sql = (
        "from public.calendar_connections\n"
        "  where user_id = p_user_id\n"
        "  order by id\n"
        "  for update;"
    )
    delete_identity_lock = body.index(identity_lock_sql)
    delete_connection_lock = body.index(connection_lock_sql)
    profile_lock = body.index(
        "perform 1 from public.profiles where id = p_user_id for update;",
    )
    assert delete_identity_lock < delete_connection_lock < profile_lock

    for function_name in (
        "apply_calendar_import_v1",
        "disconnect_calendar_connection_v1",
        "delete_calendar_imported_data_v1",
    ):
        calendar_body = _calendar_function_body(function_name)
        identity_lock = calendar_body.index(
            "from public.calendar_request_identities",
        )
        connection_lock = calendar_body.index("from public.calendar_connections")
        assert identity_lock < connection_lock


def test_not_found_result_still_converges_legacy_cleanup_first() -> None:
    body = _function_body()

    legacy_loop = body.index("for legacy_index in")
    not_found_result = body.index("'not_found', true")
    assert legacy_loop < not_found_result


def test_account_delete_rpc_is_service_role_only() -> None:
    normalized = " ".join(MIGRATION.lower().split())

    assert (
        "revoke all on function public.delete_account_v1(uuid, text) "
        "from public, anon, authenticated"
        in normalized
    )
    assert (
        "grant execute on function public.delete_account_v1(uuid, text) "
        "to service_role"
        in normalized
    )


def test_legacy_application_mutation_is_frozen_before_account_deletion() -> None:
    freeze_start = MIGRATION.index(
        "Canonical V1 no longer writes the CamelCase schema",
    )
    freeze_end = MIGRATION.index(
        "Notifications and generated optimization outputs are read-only",
    )
    freeze = MIGRATION[freeze_start:freeze_end]

    assert set(re.findall(r"'([A-Za-z]+)'", freeze)) == {
        *LEGACY_CHILD_TABLES,
        "User",
    }
    assert (
        "revoke insert, update, delete, truncate on table public.%I "
        in freeze
    )
    assert "from public, anon, authenticated" in freeze


def test_generated_outputs_and_notifications_are_authenticated_read_only() -> None:
    start = MIGRATION.index(
        "Notifications and generated optimization outputs are read-only",
    )
    end = MIGRATION.index(
        "create or replace function public.delete_account_v1(",
    )
    hardening = MIGRATION[start:end]
    normalized = " ".join(hardening.lower().split())

    assert (
        "revoke insert, update, delete, truncate on table "
        "public.notifications, public.ai_insights, public.recommendations, "
        "public.skillset_profiles from authenticated"
        in normalized
    )
    assert (
        "grant select on table public.notifications, public.ai_insights, "
        "public.recommendations, public.skillset_profiles to authenticated"
        in normalized
    )
    assert (
        "grant select, insert, update, delete on table public.notifications, "
        "public.ai_insights, public.recommendations, public.skillset_profiles "
        "to service_role"
        in normalized
    )
    for table in AUTHENTICATED_READ_ONLY_OUTPUT_TABLES:
        assert f'drop policy if exists "{table}_own_or_admin_all"' in hardening
        assert (
            f'create policy "{table}_own_or_admin_select" on public.{table} '
            "for select to authenticated"
            in normalized
        )
        assert (
            f'create policy "{table}_service_role_all" on public.{table} '
            "for all to service_role using (true) with check (true)"
            in normalized
        )
    assert 'drop policy if exists "recommendations_update_own"' in hardening
    assert 'drop policy if exists "recommendations_select_own"' in hardening
    assert 'drop policy if exists "skillset_profiles_select_own"' in hardening


def test_timezone_is_backend_validated_without_rewriting_existing_profiles() -> None:
    normalized = " ".join(MIGRATION.split())
    trigger_start = MIGRATION.index(
        "create or replace function public.handle_new_user()",
    )
    trigger_end = MIGRATION.index("\n$$;", trigger_start)
    trigger_body = MIGRATION[trigger_start:trigger_end]
    legacy_trigger_start = MIGRATION.index(
        "create or replace function public.handle_new_auth_user()",
    )
    legacy_trigger_end = MIGRATION.index("\n$$;", legacy_trigger_start)
    legacy_trigger_body = MIGRATION[legacy_trigger_start:legacy_trigger_end]

    assert "alter column timezone set default 'UTC'" in normalized
    assert (
        "revoke update (timezone) on table public.profiles from authenticated"
        in normalized
    )
    assert "'UTC'," in trigger_body
    assert "timezone = excluded.timezone" not in trigger_body
    assert "''UTC''" in legacy_trigger_body
    assert '"User".timezone' not in legacy_trigger_body
    assert not re.search(
        r"update\s+public\.profiles\s+set\s+timezone",
        MIGRATION,
        flags=re.IGNORECASE,
    )
