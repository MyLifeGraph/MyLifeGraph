import re

from tests.migration_source import extract_function, load_migration, normalize_sql


MIGRATION_NAME = "20260813200057_retire_recommendations_and_decision_feedback.sql"
MIGRATION = load_migration(MIGRATION_NAME)
NORMALIZED = normalize_sql(MIGRATION)


def test_transition_locks_the_complete_graph_before_reading_rows() -> None:
    locks = re.findall(
        r"lock table public\.([a-z_]+) in "
        r"(share row exclusive|access exclusive) mode",
        NORMALIZED,
    )
    expected_modes = {
        "ai_insights": "share row exclusive",
        "behavioral_events": "share row exclusive",
        "coach_memory_selections": "share row exclusive",
        "coach_messages": "share row exclusive",
        "coach_requests": "access exclusive",
        "coach_usage_events": "share row exclusive",
        "daily_briefings": "access exclusive",
        "decision_feedback": "access exclusive",
        "intake_responses": "share row exclusive",
        "memory_entries": "share row exclusive",
        "notification_action_requests": "share row exclusive",
        "notifications": "share row exclusive",
        "recommendations": "access exclusive",
        "tasks": "share row exclusive",
        "user_state_snapshots": "share row exclusive",
        "weekly_reviews": "access exclusive",
    }

    assert NORMALIZED.startswith("begin; set local lock_timeout = '5s';")
    assert [name for name, _mode in locks] == sorted(expected_modes)
    assert dict(locks) == expected_modes
    first_read = NORMALIZED.index(
        "create temporary table _recommendation_retirement_counts"
    )
    assert all(
        NORMALIZED.index(f"lock table public.{name}") < first_read
        for name in expected_modes
    )


def test_cleanup_is_exactly_typed_and_preserves_independent_concepts() -> None:
    notification_delete = NORMALIZED[
        NORMALIZED.index("delete from public.notifications") : NORMALIZED.index(
            "delete from public.daily_briefings"
        )
    ]

    assert "contract_version' = 'notification-generation-v1'" in (notification_delete)
    assert "origin' = 'deterministic_backend'" in notification_delete
    assert "source_kind' = 'daily_briefing'" in notification_delete
    assert "where metadata ->> 'source_kind' = 'daily_briefing';" not in (
        notification_delete
    )
    assert "delete from public.coach_usage_events" not in NORMALIZED
    assert "delete from public.account_audit_events" not in NORMALIZED
    assert "where type = 'recommendation'" in NORMALIZED
    assert "where recommendation is not null" in NORMALIZED
    assert "to_regclass('public.skillset_profiles')" in NORMALIZED


def test_json_cleanup_is_structural_and_does_not_search_prose() -> None:
    detector = extract_function(
        MIGRATION,
        "private.references_retired_recommendation_v1",
    ).lower()
    sanitizer = extract_function(
        MIGRATION,
        "private.sanitize_retired_recommendation_v1",
    ).lower()

    for body in (detector, sanitizer):
        assert "jsonb_each" in body
        assert " ilike " not in body
        assert "to_tsvector" not in body
    for key in (
        "'decision_feedback'",
        "'feedback_id'",
        "'recommendation_id'",
        "'recommendation_ids'",
    ):
        assert key in detector
        assert key in sanitizer
    assert "update public.intake_responses set responses = coalesce(" in (NORMALIZED)
    assert "private.sanitize_retired_recommendation_v1(responses)" in (NORMALIZED)
    assert "'user_feedback'" not in sanitizer


def test_coach_content_is_tombstoned_but_usage_identity_is_retained() -> None:
    update = NORMALIZED[
        NORMALIZED.index("update public.coach_requests") : NORMALIZED.index(
            "alter function private.coach_evidence_is_valid_v1(jsonb)"
        )
    ]

    assert "set state = 'deleted'" in update
    assert "context_parameters = '{}'::jsonb" in update
    assert "message_fingerprint = null" in update
    assert "response = null" in update
    assert "used_context = '[]'::jsonb" in update
    assert "evidence = null" in update
    assert "agent_trace = null" in update
    assert "free-coach-agent-prompt-v4" in update
    assert "personal-snapshot-v3" in update
    assert "delete from public.coach_messages" in NORMALIZED
    assert "delete from public.coach_memory_selections" in NORMALIZED


def test_current_coach_claim_and_validators_are_strict_and_service_only() -> None:
    claim = normalize_sql(extract_function(MIGRATION, "public.claim_coach_request_v6"))
    used_context = extract_function(
        MIGRATION,
        "private.coach_used_context_is_valid_v1",
    ).lower()

    assert "'coach-request-v3'" in claim
    assert "'free-coach-agent-prompt-v4'" in claim
    assert "'personal-snapshot-v3'" in claim
    assert "claim_coach_request_v5" not in claim
    assert "decision_feedback" not in used_context
    assert "'recommendations'" not in used_context
    assert "grant execute on function public.claim_coach_request_v6(" in (NORMALIZED)
    assert "to service_role" in NORMALIZED
    assert "revoke all on function public.claim_coach_request_v5(" in (NORMALIZED)
    assert "contract_version = 'coach-request-v1'" in NORMALIZED
    assert "contract_version = 'coach-request-v2'" in NORMALIZED
    assert "'coach-response-v1'" in NORMALIZED
    assert "grant execute on function public.claim_coach_request_v1(" in (NORMALIZED)
    assert "grant execute on function public.claim_coach_request_v2(" in (NORMALIZED)
    assert "private.coach_response_is_valid_before_free_agent(" in NORMALIZED


def test_daily_briefing_and_weekly_review_advance_atomically() -> None:
    weekly = normalize_sql(
        extract_function(MIGRATION, "public.persist_weekly_review_v3")
    )

    assert '"daily-briefing-v2"' in NORMALIZED
    assert '"deterministic-briefing-ranker-v3"' in NORMALIZED
    assert "'weekly-review-v3'" in weekly
    assert "p_row -> 'proposals' <> '[]'::jsonb" in weekly
    assert "goal_linked_completed" in weekly
    assert "set search_path = pg_catalog, pg_temp" in NORMALIZED
    assert "grant execute on function public.persist_weekly_review_v3(" in (NORMALIZED)
    assert "drop function public.persist_weekly_review_v2(" in NORMALIZED


def test_notification_writer_keeps_only_current_sources() -> None:
    temporary_definition_at = MIGRATION.lower().index(
        "create function public.create_generated_notification_v1("
    )
    final_definition_at = MIGRATION.lower().rindex(
        "create or replace function public.create_generated_notification_v1("
    )
    temporary_notification = normalize_sql(
        extract_function(
            MIGRATION[temporary_definition_at:final_definition_at],
            "public.create_generated_notification_v1",
        )
    )
    final_notification = normalize_sql(
        extract_function(
            MIGRATION[final_definition_at:],
            "public.create_generated_notification_v1",
        )
    )

    for notification in (temporary_notification, final_notification):
        for field in (
            "p_category",
            "p_type",
            "p_priority",
            "p_action_url",
            "p_source_kind",
        ):
            assert f"{field} is null" in notification
        assert "p_source_kind not in ('daily_state', 'weekly_review')" in (notification)
        assert "'daily_briefing'" not in notification
        assert "set search_path = pg_catalog, pg_temp" in notification


def test_drop_order_is_explicit_restrict_and_asserted() -> None:
    feedback_drop = NORMALIZED.rindex("drop table public.decision_feedback")
    recommendation_rpc_drop = NORMALIZED.rindex(
        "drop function public.replace_current_recommendations_v2"
    )
    recommendation_drop = NORMALIZED.rindex("drop table public.recommendations")
    briefing_column_drop = NORMALIZED.rindex(
        "alter table public.daily_briefings drop column recommendation_ids"
    )

    assert feedback_drop < recommendation_rpc_drop < recommendation_drop
    assert recommendation_drop < briefing_column_drop
    assert not re.search(
        r"\b(?:drop table|drop function)[^;]*\bcascade\b",
        NORMALIZED,
    )
    assert "drop table if exists" not in NORMALIZED
    assert "recommendation retirement left a retired database object" in (NORMALIZED)
    assert "recommendation retirement left coach content" in NORMALIZED
    assert NORMALIZED.endswith("commit;")
