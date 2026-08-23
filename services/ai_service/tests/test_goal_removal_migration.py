import re

from app.models.account import ACCOUNT_EXPORT_TABLE_NAMES
from app.owner_data_catalog import COACH_SNAPSHOT_TABLES
from tests.migration_source import extract_function, load_migration, normalize_sql


MIGRATION_NAME = (
    "20260804150153_remove_goals_and_make_weekly_review_observational.sql"
)
MIGRATION = load_migration(MIGRATION_NAME)
NORMALIZED = normalize_sql(MIGRATION)
FOLLOWUP_MIGRATION_NAME = "20260804192406_harden_goal_removal_dependencies.sql"
FOLLOWUP_MIGRATION = load_migration(FOLLOWUP_MIGRATION_NAME)
FOLLOWUP_NORMALIZED = normalize_sql(FOLLOWUP_MIGRATION)


def test_goal_table_is_dropped_explicitly_after_row_deletion() -> None:
    delete_at = NORMALIZED.rindex("delete from public.goals")
    drop_at = NORMALIZED.rindex("drop table public.goals")

    assert delete_at < drop_at
    assert "drop table public.goals cascade" not in NORMALIZED
    assert "drop table if exists public.goals" not in NORMALIZED
    assert "goals" not in ACCOUNT_EXPORT_TABLE_NAMES
    assert "goals" not in {table.name for table in COACH_SNAPSHOT_TABLES}


def test_cleanup_is_structural_and_preserves_untyped_prose() -> None:
    detector = extract_function(
        MIGRATION,
        "private.references_goal_feature_v1",
    ).lower()
    sanitizer = extract_function(
        MIGRATION,
        "private.remove_goal_keys_v1",
    ).lower()

    for key in (
        "'goal'",
        "'goals'",
        "'goal_id'",
        "'goal_ids'",
        "'goal_linked_completed'",
    ):
        assert key in detector
        assert key in sanitizer
    assert "jsonb_each" in detector
    assert "jsonb_each" in sanitizer
    assert " ilike " not in detector
    assert " lower(" not in detector
    assert "to_tsvector" not in detector


def test_cleanup_preserves_authoritative_rows_and_removes_dependent_history() -> None:
    cleanup = normalize_sql(
        extract_function(MIGRATION, "private.remove_goal_derived_history_v1"),
    )

    assert "update public.intake_responses" in cleanup
    assert "update public.tasks" in cleanup
    assert "where scope = 'onboarding'" in cleanup
    for table in (
        "decision_feedback",
        "notifications",
        "daily_briefings",
        "weekly_reviews",
        "recommendations",
        "user_state_snapshots",
        "ai_insights",
        "behavioral_events",
    ):
        assert f"delete from public.{table}" in cleanup
    assert "delete from public.coach_messages" in cleanup
    assert "set state = 'deleted'" in cleanup
    assert "response = null" in cleanup
    assert "used_context = '[]'::jsonb" in cleanup
    assert "evidence = null" in cleanup
    assert "agent_trace = null" in cleanup
    assert "delete from public.coach_usage_events" not in cleanup
    assert "delete from public.account_audit_events" not in cleanup


def test_surviving_reviews_migrate_in_place_without_touching_identity() -> None:
    review_update = NORMALIZED[
        NORMALIZED.index("update public.weekly_reviews") : NORMALIZED.index(
            "alter table public.weekly_reviews",
            NORMALIZED.index("update public.weekly_reviews"),
        )
    ]

    assert "- 'goal_linked_completed'" in review_update
    assert '"weekly-review-v2"' in review_update
    assert "narrative = format(" in review_update
    assert "proposals =" not in review_update
    assert "source_fingerprint =" not in review_update
    assert "period_key =" not in review_update
    assert "week_start =" not in review_update
    assert "week_end =" not in review_update
    assert "generated_at =" not in review_update
    assert "updated_at =" not in review_update


def test_current_weekly_persistence_can_only_write_empty_proposals() -> None:
    body = normalize_sql(
        extract_function(MIGRATION, "public.persist_weekly_review_v2"),
    )

    assert "p_row -> 'proposals' <> '[]'::jsonb" in body
    assert "p_row #>> '{provenance,contract_version}'" in body
    assert "'weekly-review-v2'" in body
    assert "proposals = '[]'::jsonb" in body
    assert "goal_linked_completed" in body


def test_setup_rpc_and_coach_claim_advance_without_legacy_write_paths() -> None:
    setup = extract_function(
        MIGRATION,
        "public.apply_intake_v1_setup_revision",
    )
    coach_claim = normalize_sql(
        extract_function(MIGRATION, "public.claim_coach_request_v5"),
    )

    setup_signature = setup[: setup.index(")\nreturns")]
    assert "p_goals" not in setup_signature
    assert "p_notification_preferences jsonb" in setup_signature
    assert "target_intake.responses ? 'goals'" in setup
    assert "insert into public.goals" not in setup.lower()
    assert "update public.goals" not in setup.lower()
    assert "delete from public.goals" not in setup.lower()
    assert "public.claim_coach_request_v3(" in coach_claim
    assert "free-coach-agent-prompt-v3" in coach_claim
    assert "personal-snapshot-v2" in coach_claim
    assert "free-coach-agent-prompt-v2" in coach_claim
    assert "claim_coach_request_v4(" not in coach_claim


def test_migration_removes_cleanup_helpers_and_closes_old_claim_entrypoints() -> None:
    for function in (
        "private.remove_goal_derived_history_v1()",
        "private.references_goal_feature_v1(jsonb)",
        "private.remove_goal_keys_v1(jsonb)",
    ):
        assert f"drop function {function}" in NORMALIZED
    assert "revoke all on function public.claim_coach_request_v4(" in NORMALIZED
    assert "revoke all on function public.claim_coach_request_v3(" in NORMALIZED
    assert "grant execute on function public.claim_coach_request_v5(" in NORMALIZED


def test_followup_locks_the_complete_history_graph_before_reading_rows() -> None:
    locks = re.findall(
        r"lock table public\.([a-z_]+) in share row exclusive mode",
        FOLLOWUP_NORMALIZED,
    )
    assert FOLLOWUP_NORMALIZED.startswith("begin; set local lock_timeout = '5s';")
    assert locks == sorted(
        [
            "ai_insights",
            "behavioral_events",
            "coach_memory_selections",
            "coach_messages",
            "coach_requests",
            "coach_usage_events",
            "daily_briefings",
            "decision_feedback",
            "intake_responses",
            "memory_entries",
            "notification_action_requests",
            "notifications",
            "recommendations",
            "tasks",
            "user_state_snapshots",
            "weekly_reviews",
        ]
    )
    first_helper = FOLLOWUP_NORMALIZED.index(
        "create or replace function private.goal_path_references_feature_v2"
    )
    assert all(
        FOLLOWUP_NORMALIZED.index(f"lock table public.{table}") < first_helper
        for table in locks
    )


def test_followup_detector_handles_typed_arrays_and_field_paths_not_prose() -> None:
    detector = extract_function(
        FOLLOWUP_MIGRATION,
        "private.references_goal_feature_v2",
    ).lower()
    path_detector = extract_function(
        FOLLOWUP_MIGRATION,
        "private.goal_path_references_feature_v2",
    ).lower()
    reference_object = extract_function(
        FOLLOWUP_MIGRATION,
        "private.is_goal_reference_object_v2",
    ).lower()
    sanitizer = extract_function(
        FOLLOWUP_MIGRATION,
        "private.sanitize_goal_feature_v2",
    ).lower()

    assert "key in ('tables', 'sources')" in detector
    assert "metadata.goal_id" not in detector
    assert "private.goal_path_references_feature_v2" in reference_object
    assert "'field'" in reference_object
    assert "'goal_id'" in path_detector
    assert "key in ('tables', 'sources')" in sanitizer
    assert "jsonb_build_array" in sanitizer
    for body in (detector, path_detector, sanitizer):
        assert " ilike " not in body
        assert "to_tsvector" not in body


def test_followup_precomputes_every_dependency_set_before_deletion() -> None:
    cleanup = normalize_sql(
        extract_function(
            FOLLOWUP_MIGRATION,
            "private.remove_goal_derived_history_v2",
        )
    )
    dependency_sets = (
        "recommendations",
        "snapshots",
        "briefings",
        "feedback",
        "reviews",
        "memories",
        "insights",
        "events",
        "notifications",
    )
    for dependency in dependency_sets:
        assert f"create temporary table _goal_{dependency}" in cleanup
        assert f"insert into pg_temp._goal_{dependency}" in cleanup
    assert "on commit drop" in cleanup
    assert "briefing.recommendation_ids" in cleanup
    assert "briefing.provenance ->> 'source_snapshot_id'" in cleanup
    assert "feedback.briefing_id" in cleanup
    assert "feedback.recommendation_id" in cleanup
    assert "snapshot.period_key = review.period_key" in cleanup
    assert "in ('decision_feedback', 'feedback')" in cleanup
    assert "snapshot.period_key = 'setup:intake-v1'" in cleanup
    assert "exit when total_added = 0" in cleanup


def test_followup_preserves_reviews_and_audit_rows_that_are_not_doomed() -> None:
    cleanup = normalize_sql(
        extract_function(
            FOLLOWUP_MIGRATION,
            "private.remove_goal_derived_history_v2",
        )
    )
    assert "update public.weekly_reviews" not in cleanup
    assert "delete from public.weekly_reviews" in cleanup
    assert "delete from public.coach_usage_events" not in cleanup
    assert "delete from public.account_audit_events" not in cleanup
    assert "add constraint" not in FOLLOWUP_NORMALIZED


def test_followup_tombstones_full_snapshot_coach_turns_and_legacy_metadata() -> None:
    cleanup = normalize_sql(
        extract_function(
            FOLLOWUP_MIGRATION,
            "private.remove_goal_derived_history_v2",
        )
    )
    assert "request.context_version = 'personal-snapshot-v1'" in cleanup
    assert "evidence.value ->> 'source' = 'personal_snapshot'" in cleanup
    assert "message.request_id is null" in cleanup
    assert "private.references_goal_feature_v2(message.metadata)" in cleanup
    assert "context_parameters = '{}'::jsonb" in cleanup
    assert "response = null" in cleanup
    assert "used_context = '[]'::jsonb" in cleanup
    assert "evidence = null" in cleanup
    assert "agent_trace = null" in cleanup


def test_followup_asserts_final_state_and_removes_every_helper() -> None:
    assert "Goal cleanup left a structured Goal trace." in FOLLOWUP_MIGRATION
    assert "Goal cleanup left a dangling Weekly Review dependency." in (
        FOLLOWUP_MIGRATION
    )
    assert "Goal cleanup left a V1 full-snapshot Coach turn." in (
        FOLLOWUP_MIGRATION
    )
    for function in (
        "private.remove_goal_derived_history_v2()",
        "private.sanitize_goal_feature_v2(jsonb)",
        "private.references_goal_feature_v2(jsonb)",
        "private.is_goal_reference_object_v2(jsonb)",
        "private.goal_path_references_feature_v2(text)",
    ):
        assert f"drop function {function}" in FOLLOWUP_NORMALIZED
    assert (
        "drop function private.references_doomed_goal_record_v2(jsonb, uuid)"
        in FOLLOWUP_NORMALIZED
    )
    assert FOLLOWUP_NORMALIZED.endswith("commit;")
