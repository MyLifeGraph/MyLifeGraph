from tests.migration_source import extract_function, load_migration, normalize_sql


MIGRATION = load_migration("20260820120000_coach_terminal_replay_probe_v1.sql")
NORMALIZED = normalize_sql(MIGRATION)


def test_terminal_probe_is_service_role_only_and_uses_claim_lock_order() -> None:
    probe = extract_function(MIGRATION, "public.probe_coach_terminal_replay_v1")
    assert probe.index("hashtextextended(p_user_id::text, 11)") < probe.index(
        "hashtextextended(p_request_id::text, 10)"
    )
    assert "where request_id = p_request_id and user_id = p_user_id" in probe
    assert "for update" in probe
    assert "grant execute on function public.probe_coach_terminal_replay_v1" in (
        NORMALIZED
    )
    assert "to service_role" in NORMALIZED
    assert "from public, anon, authenticated, service_role" in NORMALIZED


def test_terminal_probe_matches_full_identity_and_never_claims_or_mutates() -> None:
    probe = extract_function(MIGRATION, "public.probe_coach_terminal_replay_v1")
    for identity_check in [
        "existing.contract_version <> p_contract_version",
        "existing.provider <> p_provider",
        "existing.provider_mode <> p_provider_mode",
        "existing.model_requested is distinct from p_model_requested",
        "existing.model_source <> p_model_source",
        "is distinct from p_provider_dispatch_required",
        "existing.message_fingerprint <> p_message_fingerprint",
    ]:
        assert identity_check in probe
    assert "existing.state <> 'deleted'" in probe
    for mutation in ["insert into", "update public", "delete from"]:
        assert mutation not in probe
    assert "public.claim_coach_request" not in probe
