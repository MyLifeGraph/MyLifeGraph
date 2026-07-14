from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]
MIGRATION = (
    ROOT / "supabase/migrations/20260714130000_notification_delivery_v1.sql"
).read_text(encoding="utf-8")
NORMALIZED = " ".join(MIGRATION.lower().split())


def _function_body(name: str) -> str:
    start = MIGRATION.index(f"create or replace function public.{name}(")
    return MIGRATION[start : MIGRATION.index("\n$$;", start)]


def test_existing_preferences_default_to_no_delivery_consent() -> None:
    assert "add column in_app_delivery_enabled boolean not null default false" in (
        NORMALIZED
    )
    assert "in-app-notification-consent-v1" in MIGRATION
    assert "notification_preferences_delivery_consent_check" in MIGRATION
    assert (
        "existing reminder preferences are not delivery permission"
        in MIGRATION.lower()
    )


def test_settings_rpc_is_owner_locked_retry_checked_and_service_role_only() -> None:
    body = _function_body("update_notification_settings_v1")
    normalized = " ".join(body.lower().split())

    assert "pg_advisory_xact_lock(hashtextextended(p_user_id::text, 0))" in body
    assert "delivery_settings_request_id = p_request_id" in body
    assert "notification settings request id was already used" in body.lower()
    assert "notification settings changed since they were loaded" in body.lower()
    assert "'replayed', replayed" in body
    assert (
        "revoke all on function public.update_notification_settings_v1(" in (
            NORMALIZED
        )
    )
    assert "to service_role" in NORMALIZED
    assert "set search_path = pg_catalog, pg_temp" in normalized


def test_generation_rpc_revalidates_consent_timezone_quiet_hours_cap_and_dedupe() -> None:
    body = _function_body("create_generated_notification_v1")

    owner_lock = body.index(
        "pg_advisory_xact_lock(hashtextextended(p_user_id::text, 0))",
    )
    consent_check = body.index("not current_preferences.in_app_delivery_enabled")
    duplicate_check = body.index("generation_key = p_generation_key")
    quiet_check = body.index("in_quiet_hours := case")
    cap_check = body.index("generated_count >= current_preferences.daily_notification_limit")
    insert = body.index("insert into public.notifications")
    assert owner_lock < consent_check < duplicate_check < quiet_check < cap_check < insert
    assert "profile_timezone is distinct from p_timezone" in body
    assert "local_run_at::date is distinct from p_delivery_date" in body
    assert "'status', 'quiet_hours'" in body
    assert "'status', 'daily_limit'" in body
    assert "'status', 'duplicate'" in body
    assert "'origin', 'deterministic_backend'" in body
    assert "'sensitive_copy_excluded', true" in body
    assert "'llm_used', false" in body


def test_generated_rows_have_owner_dedupe_and_bounded_provenance_checks() -> None:
    assert "notifications_generation_shape_check" in MIGRATION
    assert "notifications_owner_generation_key_idx" in MIGRATION
    assert "on public.notifications (user_id, generation_key)" in NORMALIZED
    assert "length(generation_key) between 1 and 200" in NORMALIZED
    assert "metadata ->> 'contract_version' = 'notification-generation-v1'" in (
        NORMALIZED
    )


def test_delivery_ack_is_at_most_once_and_revalidates_current_permission() -> None:
    body = _function_body("acknowledge_in_app_notification_v1")

    assert "where id = p_notification_id and user_id = p_user_id" in body
    assert "in_app_delivered_at is not null" in body
    assert "'replayed', true" in body
    assert "in_app_delivery_enabled" in body
    assert "generation_category" in body
    assert "in_quiet_hours" in body
    assert "current_notification.due_at > clock_timestamp()" in body
    assert "in-app delivery is currently unavailable" in body.lower()
    assert "set in_app_delivered_at = delivered_at" in body


def test_application_roles_cannot_mutate_settings_or_call_delivery_rpcs() -> None:
    assert (
        "revoke insert, update, delete, truncate on table "
        "public.notification_preferences from public, anon, authenticated"
        in NORMALIZED
    )
    for name in (
        "update_notification_settings_v1",
        "create_generated_notification_v1",
        "acknowledge_in_app_notification_v1",
    ):
        start = NORMALIZED.index(f"revoke all on function public.{name}(")
        grant = NORMALIZED.index("to service_role", start)
        block = NORMALIZED[start:grant]
        assert "from public, anon, authenticated" in block
