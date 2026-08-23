begin;

-- Preparing the stable retry identity is already the start of an irreversible
-- account-deletion workflow from the product's perspective. A process crash
-- between prepare and mark-appending must therefore remain visible to the
-- reconciler, lock product access, and age readiness just like later states.
create or replace function private.current_request_not_deletion_pending_v2()
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public, pg_temp
set row_security = off
as $$
  select auth.uid() is not null
    and not exists (
      select 1
      from public.account_deletion_intents as intent
      where intent.user_id = auth.uid()
        and intent.state in ('prepared', 'appending', 'accepted')
    )
$$;

revoke all on function private.current_request_not_deletion_pending_v2()
  from public, anon, service_role;
grant execute on function private.current_request_not_deletion_pending_v2()
  to authenticated;

create or replace function public.get_account_deletion_pending_v2(p_user_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = pg_catalog, public, pg_temp
set row_security = off
as $$
  select jsonb_build_object(
    'contract_version', 'account-deletion-pending-v2',
    'pending', exists (
      select 1 from public.account_deletion_intents
      where user_id = p_user_id
        and state in ('prepared', 'appending', 'accepted')
    )
  )
$$;

revoke all on function public.get_account_deletion_pending_v2(uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.get_account_deletion_pending_v2(uuid)
  to service_role;

create or replace function public.get_account_deletion_recovery_status_v2()
returns jsonb
language sql
stable
security definer
set search_path = pg_catalog, public, pg_temp
set row_security = off
as $$
  select jsonb_build_object(
    'contract_version', 'account-deletion-recovery-v2',
    'legacy_direct_delete_revoked', not has_function_privilege(
      'service_role',
      'public.delete_account_v1(uuid,text)',
      'EXECUTE'
    ),
    'pending_count', count(*)::bigint,
    'oldest_pending_at', min(accepted_at)
  )
  from public.account_deletion_intents
  where state in ('prepared', 'appending', 'accepted')
$$;

revoke all on function public.get_account_deletion_recovery_status_v2()
  from public, anon, authenticated, service_role;
grant execute on function public.get_account_deletion_recovery_status_v2()
  to service_role;

commit;
