-- Phase 10 security follow-up: authorization reads only the protected
-- canonical profile projection. A mutable legacy "User" row must never become
-- a fallback source of admin authority, even if a canonical profile is absent.

create or replace function private.current_app_role()
returns text
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  result text;
begin
  if auth.uid() is null then
    return 'guest';
  end if;

  select role
  into result
  from public.profiles
  where id = auth.uid()
  limit 1;

  return coalesce(result, 'user');
end;
$$;

revoke all on function private.current_app_role() from public;
grant execute on function private.current_app_role()
  to anon, authenticated, service_role;

-- Profile removal is an account-lifecycle operation, not a direct Data API
-- mutation. Keeping the canonical row present also prevents legacy fallback or
-- an unrecoverable account after authenticated INSERT was revoked.
revoke delete on table public.profiles from authenticated;
