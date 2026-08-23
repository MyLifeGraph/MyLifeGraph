from tests.migration_source import extract_function, load_migration, normalize_sql


MIGRATION = load_migration("20260819203000_coach_operator_pilot_v1.sql")
NORMALIZED = normalize_sql(MIGRATION)


def test_v4_constraints_add_operator_identity_and_no_secret_column() -> None:
    assert "'operator_codex_pilot'" in MIGRATION
    assert "'operator_subscription_pilot'" in MIGRATION
    assert "'coach-request-v4'" in MIGRATION
    assert "'coach-response-v4'" in MIGRATION
    assert "provider_dispatch_required boolean" in NORMALIZED
    assert "api_key" not in NORMALIZED


def test_global_provider_limit_is_a_persistable_terminal_error() -> None:
    validator = extract_function(MIGRATION, "private.coach_error_is_valid_v1")
    assert "'provider_limit'" in validator
    assert NORMALIZED.count("'provider_limit'") >= 2
    assert "drop constraint coach_usage_events_error_code" in NORMALIZED


def test_response_v4_normalizes_only_after_strict_operator_provenance() -> None:
    validator = extract_function(MIGRATION, "private.coach_response_is_valid_v4")
    for value in [
        "operator_codex_pilot",
        "operator_subscription_pilot",
        "gpt-5.5",
        "free-coach-agent-prompt-v5",
        "personal-snapshot-v3",
        "service_tier_status",
        "fast_mode",
    ]:
        assert value in validator
    assert "private.coach_response_is_valid_v3(" in validator


def test_v8_binds_contract_provider_and_dispatch_requirement_on_replay() -> None:
    claim = extract_function(MIGRATION, "public.claim_coach_request_v8")
    identity_checks = [
        "existing.contract_version <> p_contract_version",
        "existing.provider <> p_provider",
        "existing.provider_mode <> p_provider_mode",
        "existing.model_requested is distinct from p_model_requested",
        "existing.provider_dispatch_required",
        "is distinct from p_provider_dispatch_required",
    ]
    for value in identity_checks:
        assert value in claim
    assert claim.index("select * into existing") < claim.index(
        "public.claim_coach_request_v7("
    )
    assert "provider_used >= 5" in claim
    assert "total_used >= 20" in claim
    assert "grant execute on function public.claim_coach_request_v8(" in NORMALIZED
    assert "revoke all on function public.claim_coach_request_v7(" in NORMALIZED


def test_global_dispatch_budget_is_durable_append_only_and_service_role_only() -> None:
    record = extract_function(
        MIGRATION,
        "public.record_coach_operator_dispatch_v1",
    )
    finish = extract_function(
        MIGRATION,
        "public.finish_coach_operator_dispatch_v1",
    )
    assert "create table public.coach_operator_daily_budgets" in NORMALIZED
    assert "create table public.coach_operator_dispatches" in NORMALIZED
    assert "force row level security" in NORMALIZED
    assert "grant select, insert, update" in NORMALIZED
    assert "to service_role" in NORMALIZED
    assert "used_count >= p_global_limit" in record
    assert "p_global_limit <> 15" in record
    assert "select budget.dispatch_count into used_count" in record
    assert "insert into public.coach_operator_daily_budgets as budget" in record
    assert "budget.dispatch_count + 1" in record
    assert "target.provider_dispatch_required" in record
    assert "target.state <> 'pending'" in record
    assert "target.lease_expires_at <= p_dispatched_at" in record
    assert "target.state <> 'dispatched'" in finish
    assert "delete from public.coach_operator_daily_budgets" not in NORMALIZED
    assert "delete from public.coach_operator_dispatches" not in NORMALIZED


def test_startup_reconciliation_counts_dispatch_as_called_before_interrupting() -> None:
    reconcile = extract_function(
        MIGRATION,
        "public.reconcile_expired_coach_operator_dispatches_v1",
    )
    assert "'provider_called', true" in reconcile
    assert "public.fail_coach_request_v1(" in reconcile
    assert "state = 'interrupted'" in reconcile
    assert reconcile.index("hashtextextended(item.user_id::text, 11)") < (
        reconcile.index("hashtextextended(item.request_id::text, 10)")
    )


def test_v4_completion_requires_dispatch_truth_to_match_provenance() -> None:
    complete = extract_function(MIGRATION, "public.complete_coach_request_v3")
    assert "target.contract_version <> 'coach-request-v4'" in complete
    assert "target.provider_dispatch_required is distinct from" in complete
    assert "{provenance,provider_called}" in complete
    assert "private.coach_response_is_valid_v4(" in complete
    assert "public.complete_coach_request_v1(" in complete
