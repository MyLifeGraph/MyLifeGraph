-- Public-pilot participation is a versioned adult self-attestation. It is
-- deliberately separate from editable Auth metadata. Application roles may
-- read the accepted notice on their own canonical profile, while only the
-- verified-bearer FastAPI path may change these backend-owned fields.

alter table public.profiles
  add column pilot_participation_notice_version text,
  add column pilot_participation_accepted_at timestamptz;

alter table public.profiles
  add constraint profiles_pilot_participation_pair_check check (
    (pilot_participation_notice_version is null
      and pilot_participation_accepted_at is null)
    or
    (pilot_participation_notice_version = 'pilot-participation-notice-v1'
      and pilot_participation_accepted_at is not null)
  );

comment on column public.profiles.pilot_participation_notice_version is
  'Backend-owned version of the adult pilot notice accepted by this account.';
comment on column public.profiles.pilot_participation_accepted_at is
  'Backend-owned UTC time of the adult pilot self-attestation; no birth date is collected.';

revoke update (
  pilot_participation_notice_version,
  pilot_participation_accepted_at
) on table public.profiles from anon, authenticated;

create or replace function private.guard_profile_privileged_fields()
returns trigger
language plpgsql
set search_path = pg_catalog, public, pg_temp
as $$
begin
  if current_user in ('anon', 'authenticated') then
    if tg_op = 'INSERT' then
      raise insufficient_privilege
        using message = 'Profile identity fields are backend-owned.';
    end if;

    if old.role is distinct from new.role
       or old.auth_provider is distinct from new.auth_provider
       or old.onboarding_completed_at is distinct from new.onboarding_completed_at
       or old.pilot_participation_notice_version
         is distinct from new.pilot_participation_notice_version
       or old.pilot_participation_accepted_at
         is distinct from new.pilot_participation_accepted_at then
      raise insufficient_privilege
        using message = 'Profile eligibility fields are backend-owned.';
    end if;
  end if;

  return new;
end;
$$;

revoke all on function private.guard_profile_privileged_fields() from public;

create or replace function public.accept_pilot_participation_v1(
  p_user_id uuid,
  p_notice_version text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  profile_row public.profiles%rowtype;
  accepted_at_value timestamptz;
  replayed_value boolean;
begin
  if p_user_id is null then
    raise sqlstate '22023' using message = 'A user id is required.';
  end if;
  if p_notice_version is distinct from 'pilot-participation-notice-v1' then
    raise sqlstate '22023' using message = 'Unsupported participation notice.';
  end if;

  select profile.*
  into profile_row
  from public.profiles as profile
  where profile.id = p_user_id
  for update;

  if not found then
    raise sqlstate 'PT404' using message = 'Account profile is unavailable.';
  end if;

  replayed_value :=
    profile_row.pilot_participation_notice_version = p_notice_version
    and profile_row.pilot_participation_accepted_at is not null;

  if replayed_value then
    accepted_at_value := profile_row.pilot_participation_accepted_at;
  else
    accepted_at_value := clock_timestamp();
    update public.profiles
    set
      pilot_participation_notice_version = p_notice_version,
      pilot_participation_accepted_at = accepted_at_value,
      updated_at = greatest(updated_at, accepted_at_value)
    where id = p_user_id;
  end if;

  return jsonb_build_object(
    'contract_version', 'pilot-participation-v1',
    'notice_version', p_notice_version,
    'accepted_at', accepted_at_value,
    'replayed', replayed_value
  );
end;
$$;

revoke all on function public.accept_pilot_participation_v1(uuid, text)
  from public, anon, authenticated;
grant execute on function public.accept_pilot_participation_v1(uuid, text)
  to service_role;
