-- Phase 10 security follow-up: profile eligibility and admin status are
-- backend-owned. Owner-writable role/auth-provider fields would otherwise let
-- an authenticated or anonymous principal self-promote before reading
-- own-or-admin Coach policies.

create or replace function private.guard_profile_privileged_fields()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if auth.role() in ('anon', 'authenticated') then
    if tg_op = 'INSERT' then
      raise insufficient_privilege
        using message = 'Profile identity fields are backend-owned.';
    end if;

    if old.role is distinct from new.role
       or old.auth_provider is distinct from new.auth_provider then
      raise insufficient_privilege
        using message = 'Profile identity fields are backend-owned.';
    end if;
  end if;

  return new;
end;
$$;

revoke all on function private.guard_profile_privileged_fields() from public;

drop trigger if exists guard_profile_privileged_fields
  on public.profiles;
create trigger guard_profile_privileged_fields
  before insert or update on public.profiles
  for each row execute function private.guard_profile_privileged_fields();

-- Auth creation already materializes profiles through the security-definer
-- auth-user trigger. Application users may edit only non-identity projection
-- fields; service_role retains the table privileges granted by the canonical
-- schema and Phase 0C Setup RPC.
revoke insert, update on table public.profiles from authenticated;
grant update (
  display_name,
  timezone,
  onboarding_completed_at,
  updated_at
) on table public.profiles to authenticated;
