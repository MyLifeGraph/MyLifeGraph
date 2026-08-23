-- V1 account trust boundary: one service-role-only transactional account
-- deletion. Normal task/habit deletion keeps the Phase 3 RESTRICT contract;
-- only full account deletion removes focus history first so the profile/auth
-- cascade cannot be blocked by linked terminal focus rows.

-- Profile-local dates are backend-validated account state. New profiles use a
-- neutral UTC default instead of assuming a physical location, and normal
-- authenticated Data API callers can no longer bypass FastAPI's IANA check.
alter table public.profiles
  alter column timezone set default 'UTC';

revoke update (timezone)
  on table public.profiles
  from authenticated;

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  provider text;
  display_name text;
begin
  provider := coalesce(new.raw_app_meta_data->>'provider', 'email');
  display_name := coalesce(
    new.raw_user_meta_data->>'display_name',
    new.raw_user_meta_data->>'full_name',
    split_part(coalesce(new.email, 'New User'), '@', 1),
    'New User'
  );

  insert into public.profiles (
    id,
    email,
    display_name,
    timezone,
    role,
    auth_provider,
    updated_at
  )
  values (
    new.id,
    new.email,
    display_name,
    'UTC',
    case when provider = 'anonymous' then 'guest' else 'user' end,
    provider,
    now()
  )
  on conflict (id) do update
  set
    email = excluded.email,
    display_name = coalesce(public.profiles.display_name, excluded.display_name),
    auth_provider = excluded.auth_provider,
    role = coalesce(public.profiles.role, excluded.role),
    updated_at = now();

  insert into public.notification_preferences (user_id)
  values (new.id)
  on conflict (user_id) do nothing;

  return new;
end;
$$;

-- Older databases can still have the legacy auth projection trigger. Keep its
-- new-row default aligned without touching any existing legacy timezone.
create or replace function public.handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  provider text;
  display_name text;
  default_role text;
begin
  provider := coalesce(new.raw_app_meta_data->>'provider', 'email');
  display_name := coalesce(
    new.raw_user_meta_data->>'display_name',
    new.raw_user_meta_data->>'full_name',
    split_part(coalesce(new.email, 'New User'), '@', 1),
    'New User'
  );
  default_role := case when provider = 'anonymous' then 'guest' else 'user' end;

  if to_regclass('public."User"') is not null then
    execute '
      insert into public."User" (
        id,
        email,
        name,
        timezone,
        "authProvider",
        "onboardingDone",
        role,
        "updatedAt"
      )
      values ($1, $2, $3, ''UTC'', $4, false, $5, now())
      on conflict (id) do update
      set
        email = excluded.email,
        name = coalesce(public."User".name, excluded.name),
        "authProvider" = excluded."authProvider",
        role = coalesce(public."User".role, excluded.role),
        "updatedAt" = now()
    '
    using new.id::text, coalesce(new.email, ''), display_name, provider, default_role;
  end if;

  return new;
end;
$$;

-- Canonical V1 no longer writes the CamelCase schema. RLS ownership alone is
-- insufficient after Auth deletion because an already-issued JWT can remain
-- cryptographically valid until expiry and those legacy tables have no
-- canonical profile FK. Freeze application-role mutation so deleted legacy
-- owner rows cannot be recreated after this migration commits.
do $$
declare
  legacy_table_name text;
begin
  foreach legacy_table_name in array array[
    'FocusSession',
    'CoachMessage',
    'AIInsight',
    'ActivityLog',
    'DailyLog',
    'MemoryEntry',
    'MoodLog',
    'Notification',
    'ScheduleItem',
    'SleepLog',
    'Task',
    'Habit',
    'Goal',
    'User'
  ]
  loop
    if to_regclass(format('public.%I', legacy_table_name)) is not null then
      execute format(
        'revoke insert, update, delete, truncate on table public.%I '
        'from public, anon, authenticated',
        legacy_table_name
      );
    end if;
  end loop;
end;
$$;

-- Notifications and generated optimization outputs are read-only product
-- projections for authenticated clients in V1. Generation/mutation remains a
-- backend service-role responsibility; a future mark-read flow needs its own
-- explicit contract instead of retaining broad owner DML.
revoke insert, update, delete, truncate on table
  public.notifications,
  public.ai_insights,
  public.recommendations,
  public.skillset_profiles
from authenticated;

grant select on table
  public.notifications,
  public.ai_insights,
  public.recommendations,
  public.skillset_profiles
to authenticated;

grant select, insert, update, delete on table
  public.notifications,
  public.ai_insights,
  public.recommendations,
  public.skillset_profiles
to service_role;

drop policy if exists "notifications_own_or_admin_all"
  on public.notifications;
drop policy if exists "ai_insights_own_or_admin_all"
  on public.ai_insights;
drop policy if exists "recommendations_own_or_admin_all"
  on public.recommendations;
drop policy if exists "skillset_profiles_own_or_admin_all"
  on public.skillset_profiles;
drop policy if exists "recommendations_update_own"
  on public.recommendations;
drop policy if exists "recommendations_select_own"
  on public.recommendations;
drop policy if exists "skillset_profiles_select_own"
  on public.skillset_profiles;

drop policy if exists "notifications_own_or_admin_select"
  on public.notifications;
create policy "notifications_own_or_admin_select"
  on public.notifications
  for select
  to authenticated
  using (
    user_id = (select auth.uid())
    or (select private.current_app_role()) = 'admin'
  );

drop policy if exists "ai_insights_own_or_admin_select"
  on public.ai_insights;
create policy "ai_insights_own_or_admin_select"
  on public.ai_insights
  for select
  to authenticated
  using (
    user_id = (select auth.uid())
    or (select private.current_app_role()) = 'admin'
  );

drop policy if exists "recommendations_own_or_admin_select"
  on public.recommendations;
create policy "recommendations_own_or_admin_select"
  on public.recommendations
  for select
  to authenticated
  using (
    user_id = (select auth.uid())
    or (select private.current_app_role()) = 'admin'
  );

drop policy if exists "skillset_profiles_own_or_admin_select"
  on public.skillset_profiles;
create policy "skillset_profiles_own_or_admin_select"
  on public.skillset_profiles
  for select
  to authenticated
  using (
    user_id = (select auth.uid())
    or (select private.current_app_role()) = 'admin'
  );

drop policy if exists "notifications_service_role_all"
  on public.notifications;
create policy "notifications_service_role_all"
  on public.notifications
  for all
  to service_role
  using (true)
  with check (true);

drop policy if exists "ai_insights_service_role_all"
  on public.ai_insights;
create policy "ai_insights_service_role_all"
  on public.ai_insights
  for all
  to service_role
  using (true)
  with check (true);

drop policy if exists "recommendations_service_role_all"
  on public.recommendations;
create policy "recommendations_service_role_all"
  on public.recommendations
  for all
  to service_role
  using (true)
  with check (true);

drop policy if exists "skillset_profiles_service_role_all"
  on public.skillset_profiles;
create policy "skillset_profiles_service_role_all"
  on public.skillset_profiles
  for all
  to service_role
  using (true)
  with check (true);

create or replace function public.delete_account_v1(
  p_user_id uuid,
  p_confirmation text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, pg_temp
as $$
declare
  auth_user_found boolean;
  deleted_user_id uuid;
  legacy_index int;
  legacy_owner_column text;
  legacy_owner_column_exists boolean;
  legacy_owner_columns constant text[] := array[
    'userId',
    'userId',
    'userId',
    'userId',
    'userId',
    'userId',
    'userId',
    'userId',
    'userId',
    'userId',
    'userId',
    'userId',
    'userId',
    'id'
  ];
  legacy_rows_remain boolean;
  legacy_table_name text;
  legacy_table_names constant text[] := array[
    'FocusSession',
    'CoachMessage',
    'AIInsight',
    'ActivityLog',
    'DailyLog',
    'MemoryEntry',
    'MoodLog',
    'Notification',
    'ScheduleItem',
    'SleepLog',
    'Task',
    'Habit',
    'Goal',
    'User'
  ];
  legacy_table regclass;
  legacy_tables regclass[] := array[]::regclass[];
begin
  if p_user_id is null or p_confirmation is distinct from 'DELETE' then
    raise exception 'Exact account deletion confirmation is required'
      using errcode = '22023';
  end if;

  -- Converge with every existing owner-scoped backend workflow before taking
  -- the auth/profile cascade. Locks are acquired in a fixed order.
  perform pg_advisory_xact_lock(hashtextextended(p_user_id::text, 0));
  perform pg_advisory_xact_lock(hashtextextended(p_user_id::text, 11));
  perform pg_advisory_xact_lock(hashtextextended(p_user_id::text, 12));

  -- Calendar replay RPCs lock request identities before their connection.
  -- Match that row-lock order before the profile cascade: otherwise deletion
  -- could hold a connection row while an exact replay holds its child request
  -- identity and waits for that connection. New request identities either
  -- finish before the connection lock or block behind it and fail after the
  -- owner cascade; no reverse wait remains.
  perform 1
  from public.calendar_request_identities
  where user_id = p_user_id
  order by request_id
  for update;

  perform 1
  from public.calendar_connections
  where user_id = p_user_id
  order by id
  for update;

  perform 1 from auth.users where id = p_user_id for update;
  auth_user_found := found;

  -- Lock the canonical owner row before deleting focus history. Every new
  -- canonical child insert must take a profile-key lock for its owner FK, so
  -- no focus row can appear after the cleanup and block the later cascade.
  perform 1 from public.profiles where id = p_user_id for update;

  if cardinality(legacy_table_names) <> cardinality(legacy_owner_columns) then
    raise exception 'Legacy account owner mapping is invalid'
      using errcode = 'P0001';
  end if;

  -- Validate and write-block every legacy table before deleting any legacy
  -- row. Locks are held to transaction end in this one fixed order, so an old
  -- client cannot insert a row after cleanup or between the total postchecks.
  for legacy_index in 1..cardinality(legacy_table_names)
  loop
    legacy_table_name := legacy_table_names[legacy_index];
    legacy_owner_column := legacy_owner_columns[legacy_index];
    legacy_table := to_regclass(format('public.%I', legacy_table_name));
    legacy_tables[legacy_index] := legacy_table;
    continue when legacy_table is null;

    execute format(
      'lock table public.%I in share row exclusive mode',
      legacy_table_name
    );

    select exists (
      select 1
      from pg_attribute
      where attrelid = legacy_table
        and attname = legacy_owner_column
        and attnum > 0
        and not attisdropped
    )
    into legacy_owner_column_exists;

    if not legacy_owner_column_exists then
      raise exception 'Legacy owner mapping is unavailable for table %',
        legacy_table_name
        using errcode = 'P0001';
    end if;
  end loop;

  -- Phase 3 intentionally prevents application deletion of a task/habit that
  -- is referenced by focus history. Remove those owner rows only inside this
  -- full-account transaction, then let auth.users -> profiles and all
  -- canonical owner tables cascade normally.
  delete from public.focus_sessions where user_id = p_user_id;

  -- Every known CamelCase owner mapping was established by the legacy RLS
  -- migrations: child rows use text "userId" and "User" uses text id. Remove
  -- dependents first, validate each mapped column before dynamic SQL, and fail
  -- the whole transaction rather than silently retaining an unknown shape.
  -- FocusSession precedes Task/Habit, and Task/Habit precede Goal, so possible
  -- legacy target links cannot block their owner's full-account cleanup.
  for legacy_index in 1..cardinality(legacy_table_names)
  loop
    legacy_table_name := legacy_table_names[legacy_index];
    legacy_owner_column := legacy_owner_columns[legacy_index];
    legacy_table := legacy_tables[legacy_index];
    continue when legacy_table is null;

    execute format(
      'delete from public.%I where lower(%I::text) = $1',
      legacy_table_name,
      legacy_owner_column
    ) using p_user_id::text;
  end loop;

  -- All legacy tables remain write-blocked while this complete owner
  -- postcondition is evaluated.
  for legacy_index in 1..cardinality(legacy_table_names)
  loop
    legacy_table_name := legacy_table_names[legacy_index];
    legacy_owner_column := legacy_owner_columns[legacy_index];
    legacy_table := legacy_tables[legacy_index];
    continue when legacy_table is null;
    execute format(
      'select exists (select 1 from public.%I where lower(%I::text) = $1)',
      legacy_table_name,
      legacy_owner_column
    ) into legacy_rows_remain using p_user_id::text;

    if legacy_rows_remain then
      raise exception 'Legacy account deletion did not complete for table %',
        legacy_table_name
        using errcode = 'P0001';
    end if;
  end loop;

  if not auth_user_found then
    if exists (select 1 from public.profiles where id = p_user_id) then
      raise exception 'Account deletion cascade did not complete'
        using errcode = 'P0001';
    end if;
    return jsonb_build_object(
      'deleted', false,
      'not_found', true,
      'user_id', p_user_id
    );
  end if;

  delete from auth.users
  where id = p_user_id
  returning id into deleted_user_id;

  if deleted_user_id is null
     or exists (select 1 from public.profiles where id = p_user_id) then
    raise exception 'Account deletion cascade did not complete'
      using errcode = 'P0001';
  end if;

  return jsonb_build_object(
    'deleted', true,
    'not_found', false,
    'user_id', deleted_user_id
  );
end;
$$;

revoke all on function public.delete_account_v1(uuid, text)
  from public, anon, authenticated;
grant execute on function public.delete_account_v1(uuid, text)
  to service_role;
