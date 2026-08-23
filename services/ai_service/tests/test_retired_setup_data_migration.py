from app.models.account import ACCOUNT_EXPORT_TABLE_NAMES
from app.services.account_service import ACCOUNT_EXPORT_TABLES
from tests.migration_source import extract_function, load_migration, normalize_sql


MIGRATION = load_migration(
    "20260725120000_retire_setup_goals_and_friction.sql",
)
NORMALIZED = normalize_sql(MIGRATION)


def _function_body(name: str) -> str:
    return extract_function(MIGRATION, f"public.{name}")


def test_compatibility_adapter_discards_reminder_and_goal_arguments() -> None:
    body = _function_body(
        "apply_intake_v1_setup_revision_without_study_setup",
    )
    call = body[body.index("result :=") :]

    assert "p_notification_preferences and p_goals deliberately remain" in body
    assert "'mylifegraph.preserve_notification_preferences'" in body
    assert "jsonb_build_object(" in call
    assert "'[]'::jsonb" in call
    assert "p_notification_preferences," not in call
    assert "p_goals," not in call


def test_notification_guard_suppresses_the_legacy_upsert_without_touching_row() -> None:
    body = _function_body("suppress_retired_intake_notification_write_v1")

    assert "= 'on' then" in body
    assert "return null;" in body
    assert (
        "before insert or update on public.notification_preferences"
        in NORMALIZED
    )
    assert (
        "revoke all on function "
        "public.apply_intake_v1_setup_revision_without_study_setup("
        in NORMALIZED
    )
    assert "from public, anon, authenticated, service_role" in NORMALIZED


def test_raw_intake_and_capture_cleanup_is_narrow_and_idempotent() -> None:
    for retired_key in (
        "primary_focus_areas",
        "goals",
        "friction_points",
        "coaching_style",
        "reminder_preference",
        "context_note",
    ):
        assert f"'{retired_key}'" in MIGRATION
    assert "where version = 'intake-v1'" in NORMALIZED
    assert "update public.daily_logs" in NORMALIZED
    assert "update public.behavioral_events" in NORMALIZED
    assert "(metadata #> '{captures,evening}')" in MIGRATION
    assert "?| array['main_friction', 'additional_frictions']" in MIGRATION


def test_cleanup_archives_only_setup_goals_and_deletes_only_retired_memories() -> None:
    goal_update = NORMALIZED[
        NORMALIZED.index("update public.goals") : NORMALIZED.index(
            "delete from public.memory_entries",
        )
    ]
    memory_delete = NORMALIZED[
        NORMALIZED.index("delete from public.memory_entries") : NORMALIZED.index(
            "update public.daily_logs",
        )
    ]

    assert "status = 'archived'" in goal_update
    assert "metadata ->> 'managed_by' = 'setup'" in goal_update
    assert "metadata ->> 'source' = 'intake-v1'" in goal_update
    assert "type = 'goal'" in memory_delete
    assert "'preferred coaching style'" in memory_delete
    assert "'intake context note'" in memory_delete
    assert "best energy window" not in memory_delete


def test_affected_derivations_are_deleted_without_hidden_generation() -> None:
    for table in (
        "daily_briefings",
        "weekly_reviews",
        "recommendations",
        "user_state_snapshots",
    ):
        assert f"delete from public.{table}" in NORMALIZED
    assert "goal_linked_completed" in MIGRATION
    assert "event.event_type = 'planning_friction'" in NORMALIZED
    assert "insert into public.daily_briefings" not in NORMALIZED
    assert "insert into public.weekly_reviews" not in NORMALIZED
    assert "insert into public.recommendations" not in NORMALIZED


def test_goals_are_removed_and_memories_remain_in_account_export() -> None:
    assert "goals" not in ACCOUNT_EXPORT_TABLE_NAMES
    assert "memory_entries" in ACCOUNT_EXPORT_TABLE_NAMES
    exported = {table.name for table in ACCOUNT_EXPORT_TABLES}
    assert "goals" not in exported
    assert "memory_entries" in exported
