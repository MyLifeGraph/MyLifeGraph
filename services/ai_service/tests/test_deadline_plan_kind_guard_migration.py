from tests.migration_source import extract_function, load_migration


MIGRATION = load_migration("20260812212833_deadline_plan_kind_guard.sql")
ASSIGNMENT_SERIES_MIGRATION = load_migration(
    "20260810092841_finite_assignment_series_v1.sql",
)


def test_kind_guard_wraps_the_final_timing_rpc_without_changing_its_signature() -> None:
    sql = MIGRATION
    signature = "uuid, uuid, text, uuid, int, jsonb, jsonb, timestamptz"
    assert "alter function public.propose_deadline_plan_with_timing_v1(" in sql
    assert "rename to propose_deadline_plan_with_timing_v1_without_kind_guard" in sql
    assert (
        "create or replace function public.propose_deadline_plan_with_timing_v1(" in sql
    )
    assert signature in sql
    assert (
        "grant execute on function public.propose_deadline_plan_with_timing_v1(" in sql
    )
    assert ") to service_role;" in sql


def test_kind_guard_preserves_lock_and_request_identity_precedence() -> None:
    wrapper = extract_function(
        MIGRATION,
        "public.propose_deadline_plan_with_timing_v1",
    )
    owner_lock = wrapper.index(
        "pg_advisory_xact_lock(hashtextextended(p_user_id::text, 0))",
    )
    request_lock = wrapper.index(
        "pg_advisory_xact_lock(hashtextextended(p_request_id::text, 13))",
    )
    request_lookup = wrapper.index(
        "from public.deadline_plan_request_identities",
    )
    replay_delegate = wrapper.index(
        "return public.propose_deadline_plan_with_timing_v1_without_kind_guard",
    )
    plan_lock = wrapper.index("from public.deadline_plans as plan")
    kind_guard = wrapper.index("p_proposal ->> 'kind' <> persisted_kind")
    new_request_delegate = wrapper.rindex(
        "return public.propose_deadline_plan_with_timing_v1_without_kind_guard",
    )
    assert (
        owner_lock
        < request_lock
        < request_lookup
        < replay_delegate
        < plan_lock
        < kind_guard
        < new_request_delegate
    )
    assert "plan.status in ('draft', 'active')" in wrapper
    assert "for update;" in wrapper
    assert "Deadline plan kind cannot be changed." in wrapper
    assert "using errcode = 'PT409'" in wrapper


def test_inner_rpc_is_uncallable_and_series_keeps_using_the_public_wrapper() -> None:
    assert (
        "revoke all on function\n"
        "  public.propose_deadline_plan_with_timing_v1_without_kind_guard(" in MIGRATION
    )
    assert "from public, anon, authenticated, service_role;" in MIGRATION
    assert "propose_deadline_plan_with_timing_v1_without_kind_guard" not in (
        ASSIGNMENT_SERIES_MIGRATION
    )
    assert "result := public.propose_deadline_plan_with_timing_v1(" in (
        ASSIGNMENT_SERIES_MIGRATION
    )


def test_unguarded_base_rpc_loses_all_application_execute_authority() -> None:
    assert (
        "revoke all on function public.propose_deadline_plan_v1(\n"
        "  uuid, uuid, text, uuid, int, jsonb, jsonb, timestamptz\n"
        ") from public, anon, authenticated, service_role;" in MIGRATION
    )
