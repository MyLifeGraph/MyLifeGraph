-- Phase 10 security follow-up: onboarding eligibility is projected only by
-- the backend-owned atomic Intake apply RPC. An authenticated Data API caller
-- must not be able to opt itself into scheduler or weekly-review workflows by
-- writing profiles.onboarding_completed_at directly.

revoke update (onboarding_completed_at)
  on table public.profiles
  from authenticated;

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
       or old.auth_provider is distinct from new.auth_provider
       or old.onboarding_completed_at is distinct from new.onboarding_completed_at then
      raise insufficient_privilege
        using message = 'Profile eligibility fields are backend-owned.';
    end if;
  end if;

  return new;
end;
$$;

revoke all on function private.guard_profile_privileged_fields() from public;
