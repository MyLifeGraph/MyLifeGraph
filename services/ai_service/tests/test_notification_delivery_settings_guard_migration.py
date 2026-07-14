from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]
MIGRATION = (
    ROOT
    / "supabase/migrations/20260714143000_notification_delivery_settings_guard.sql"
).read_text(encoding="utf-8")
NORMALIZED = " ".join(MIGRATION.lower().split())


def _function_body(name: str) -> str:
    start = MIGRATION.index(f"create or replace function public.{name}(")
    return MIGRATION[start : MIGRATION.index("\n$$;", start)]


def test_settings_replay_fingerprints_the_expected_revision_and_full_payload() -> None:
    body = _function_body("update_notification_settings_v1")

    assert "extensions.digest(" in body
    assert "'sha256'" in body
    for field in (
        "expected_updated_at_epoch",
        "in_app_delivery_enabled",
        "consent_version",
        "focus_prompt",
        "recovery_prompt",
        "weekly_summary",
        "quiet_hours_start",
        "quiet_hours_end",
        "daily_limit",
    ):
        assert f"'{field}'" in body
    assert (
        "current_preferences.delivery_settings_request_fingerprint\n"
        "         is distinct from request_fingerprint"
    ) in body
    assert "delivery_settings_request_fingerprint = request_fingerprint" in body


def test_incomplete_pre_guard_request_identities_are_forgotten_fail_closed() -> None:
    assert "set delivery_settings_request_id = null" in NORMALIZED
    assert "notification_preferences_delivery_request_identity_check" in MIGRATION
    assert "delivery_settings_request_fingerprint ~ '^[0-9a-f]{64}$'" in (
        NORMALIZED
    )


def test_cross_writer_guard_invalidates_replay_and_keeps_revision_monotone() -> None:
    body = _function_body("guard_notification_preferences_revision_v1")

    assert "new.delivery_settings_request_id := null" in body
    assert "new.delivery_settings_request_fingerprint := null" in body
    assert "old.updated_at + interval '1 microsecond'" in body
    assert "coalesce(new.in_app_delivery_consented_at, new.updated_at)" in body
    assert "coalesce(new.in_app_delivery_disabled_at, new.updated_at)" in body
    assert "notification_preferences_revision_guard_v1" in MIGRATION
    assert "before update on public.notification_preferences" in NORMALIZED


def test_database_enforces_consent_timestamp_order_and_rpc_authority() -> None:
    assert "notification_preferences_delivery_timestamp_order_check" in MIGRATION
    assert "in_app_delivery_consented_at <= updated_at" in NORMALIZED
    assert "in_app_delivery_disabled_at <= updated_at" in NORMALIZED
    assert (
        "revoke all on function public.update_notification_settings_v1(" in (
            NORMALIZED
        )
    )
    assert "to service_role" in NORMALIZED
