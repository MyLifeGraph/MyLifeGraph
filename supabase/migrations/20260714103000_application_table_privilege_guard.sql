-- Close unintended Supabase table grants on the complete repo-owned product
-- and backend-ledger surface. RLS does not authorize TRUNCATE, while REFERENCES
-- plus TRIGGER can create durable database objects outside the intended API
-- boundary. Guest/demo product state is local, so anon needs no product-table
-- privileges.

do $application_table_privilege_guard$
declare
  table_name text;
begin
  foreach table_name in array array[
    'profiles',
    'daily_logs',
    'behavioral_events',
    'lifestyle_entries',
    'tasks',
    'schedule_items',
    'notifications',
    'notification_action_requests',
    'coach_messages',
    'memory_entries',
    'ai_insights',
    'recommendations',
    'skillset_profiles',
    'notification_preferences',
    'goals',
    'habits',
    'habit_logs',
    'focus_sessions',
    'intake_responses',
    'user_state_snapshots',
    'daily_briefings',
    'decision_feedback',
    'weekly_reviews',
    'calendar_connections',
    'calendar_imports',
    'calendar_events',
    'calendar_request_identities',
    'coach_requests',
    'coach_usage_events',
    'coach_memory_selections'
  ]
  loop
    if to_regclass(format('public.%I', table_name)) is null then
      raise exception 'Application privilege guard is missing table public.%',
        table_name;
    end if;

    execute format(
      'revoke all privileges on table public.%I from public, anon',
      table_name
    );
    execute format(
      'revoke truncate, references, trigger on table public.%I '
      'from authenticated',
      table_name
    );
  end loop;
end;
$application_table_privilege_guard$;

-- Older remote databases can retain any subset of the CamelCase product
-- schema. Keep those optional tables application-role frozen without making a
-- fresh canonical database depend on their presence.
do $legacy_application_table_privilege_guard$
declare
  table_name text;
begin
  foreach table_name in array array[
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
    if to_regclass(format('public.%I', table_name)) is not null then
      execute format(
        'revoke all privileges on table public.%I from public, anon',
        table_name
      );
      execute format(
        'revoke insert, update, delete, truncate, references, trigger '
        'on table public.%I from authenticated',
        table_name
      );
    end if;
  end loop;
end;
$legacy_application_table_privilege_guard$;

-- Authenticated clients retain only owner/admin reads for these backend-owned
-- projections. Existing service-role grants and policies remain unchanged.
revoke insert, update, delete on table
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

-- Repo migrations run as postgres. Harden only that creator's future public
-- tables: changing another role's defaults requires membership that the
-- verified local migration role does not have. Service-role and postgres
-- defaults are deliberately untouched.
alter default privileges for role postgres in schema public
  revoke all privileges on tables from public, anon;
alter default privileges for role postgres in schema public
  revoke truncate, references, trigger on tables from authenticated;

-- PostgreSQL requires table TRIGGER and function EXECUTE privileges when a
-- trigger is created. Revoking EXECUTE after the existing auth.users triggers
-- were installed does not remove those catalog objects or disable their normal
-- firing; this prevents reusable SECURITY DEFINER trigger functions from being
-- attached to another table.
revoke execute on function public.handle_new_user()
  from public, anon, authenticated, service_role;
revoke execute on function public.handle_new_auth_user()
  from public, anon, authenticated, service_role;

-- Support the child-side lookup PostgreSQL needs when a notification deletion
-- cascades into the retry ledger.
create index if not exists notification_action_requests_notification_owner_idx
  on public.notification_action_requests (notification_id, user_id);

-- Remote notification rows may predate the timestamp contract. NOT VALID
-- avoids a blocking/failing legacy scan while PostgreSQL still enforces each
-- check for every subsequent insert or update. Validation of pre-existing rows
-- remains a separate, evidence-driven cleanup step.
alter table public.notifications
  add constraint notifications_created_updated_order_check
    check (created_at <= updated_at) not valid,
  add constraint notifications_read_updated_order_check
    check (read_at is null or read_at <= updated_at) not valid,
  add constraint notifications_dismissed_updated_order_check
    check (dismissed_at is null or dismissed_at <= updated_at) not valid;

alter table public.notification_action_requests
  add constraint notification_action_requests_expected_result_order_check
    check (expected_updated_at <= result_updated_at) not valid,
  add constraint notification_action_requests_read_result_order_check
    check (result_read_at is null or result_read_at <= result_updated_at)
    not valid,
  add constraint notification_action_requests_dismissed_result_order_check
    check (result_dismissed_at is null or result_dismissed_at <= result_updated_at)
    not valid;
