-- Phase 3 executable task, habit-outcome, and focus-session foundations.

alter table public.tasks
  add column if not exists estimated_minutes int,
  add column if not exists completed_at timestamptz,
  add column if not exists cancelled_at timestamptz;

-- Project legacy terminal states into one exact lifecycle shape. A task can
-- have only the timestamp owned by its current terminal state.
update public.tasks
set
  completed_at = case
    when status = 'done' then coalesce(completed_at, updated_at, created_at)
    else null
  end,
  cancelled_at = case
    when status = 'cancelled' then coalesce(cancelled_at, updated_at, created_at)
    else null
  end
where
  (status = 'done' and (completed_at is null or cancelled_at is not null))
  or (status = 'cancelled' and (cancelled_at is null or completed_at is not null))
  or (
    status not in ('done', 'cancelled')
    and (completed_at is not null or cancelled_at is not null)
  );

do $$
begin
  if not exists (
    select 1
    from pg_catalog.pg_constraint
    where conname = 'tasks_estimated_minutes_check'
      and conrelid = 'public.tasks'::regclass
  ) then
    alter table public.tasks
      add constraint tasks_estimated_minutes_check
      check (
        estimated_minutes is null
        or estimated_minutes between 5 and 480
      );
  end if;

  if not exists (
    select 1
    from pg_catalog.pg_constraint
    where conname = 'tasks_lifecycle_shape_check'
      and conrelid = 'public.tasks'::regclass
  ) then
    alter table public.tasks
      add constraint tasks_lifecycle_shape_check
      check (
        (
          status = 'done'
          and completed_at is not null
          and cancelled_at is null
        )
        or (
          status = 'cancelled'
          and cancelled_at is not null
          and completed_at is null
        )
        or (
          status not in ('done', 'cancelled')
          and completed_at is null
          and cancelled_at is null
        )
      );
  end if;
end $$;

alter table public.habit_logs
  add column if not exists status text,
  add column if not exists updated_at timestamptz;

-- Existing clients interpreted every positive value as completion. Preserve
-- that meaning, but refuse to invent intentional skips from ambiguous legacy
-- zero/negative rows.
do $$
begin
  if exists (
    select 1
    from public.habit_logs
    where status is null
      and value <= 0
  ) then
    raise exception
      'Phase 3 cannot infer an intentional habit outcome from legacy value <= 0.'
      using errcode = '23514';
  end if;
end $$;

update public.habit_logs
set status = 'completed'
where status is null;

update public.habit_logs
set value = case status
  when 'skipped' then 0
  else 1
end
where status in ('completed', 'skipped');

update public.habit_logs
set updated_at = coalesce(updated_at, created_at)
where updated_at is null;

alter table public.habit_logs
  alter column status set default 'completed',
  alter column status set not null,
  alter column updated_at set default now(),
  alter column updated_at set not null;

do $$
begin
  if not exists (
    select 1
    from pg_catalog.pg_constraint
    where conname = 'habit_logs_status_check'
      and conrelid = 'public.habit_logs'::regclass
  ) then
    alter table public.habit_logs
      add constraint habit_logs_status_check
      check (status in ('completed', 'skipped'));
  end if;

  if not exists (
    select 1
    from pg_catalog.pg_constraint
    where conname = 'habit_logs_status_value_check'
      and conrelid = 'public.habit_logs'::regclass
  ) then
    alter table public.habit_logs
      add constraint habit_logs_status_value_check
      check (
        (status = 'completed' and value = 1)
        or (status = 'skipped' and value = 0)
      );
  end if;
end $$;

-- A historical row whose copied user_id disagrees with the habit owner is
-- ambiguous and security-sensitive. Stop with a diagnostic instead of
-- silently assigning the outcome to either account.
do $$
begin
  if exists (
    select 1
    from public.habit_logs as habit_log
    left join public.habits as habit on habit.id = habit_log.habit_id
    where habit.id is null
       or habit.user_id <> habit_log.user_id
  ) then
    raise exception
      'Phase 3 found a habit log whose user does not own its habit.'
      using errcode = '23514';
  end if;
end $$;

create or replace function private.enforce_habit_log_user_ownership()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, pg_temp
as $$
begin
  perform 1
  from public.habits as habit
  where habit.id = new.habit_id
    and habit.user_id = new.user_id
    and habit.active = true
    and coalesce(habit.metadata ->> 'lifecycle', 'active') = 'active'
    and coalesce(
      habit.metadata ->> 'setup_state',
      habit.metadata ->> 'status',
      ''
    ) not in ('candidate', 'archived')
    and (
      coalesce(habit.metadata ->> 'cadence', '') <> 'weekdays'
      or exists (
        select 1
        from jsonb_array_elements_text(
          coalesce(habit.metadata -> 'scheduled_weekdays', '[]'::jsonb)
        ) as scheduled(day)
        where scheduled.day::int = extract(isodow from new.entry_date)::int
      )
    )
  for no key update;

  if not found then
    raise exception 'Habit log target is unavailable for this user and date.'
      using errcode = '23514';
  end if;

  return new;
end;
$$;

revoke all on function private.enforce_habit_log_user_ownership()
  from public, anon, authenticated, service_role;

drop trigger if exists habit_logs_enforce_user_ownership
  on public.habit_logs;

create trigger habit_logs_enforce_user_ownership
before insert or update
on public.habit_logs
for each row
execute function private.enforce_habit_log_user_ownership();

alter table public.focus_sessions
  add column if not exists status text,
  add column if not exists task_id uuid,
  add column if not exists habit_id uuid,
  add column if not exists updated_at timestamptz;

-- A legacy row with an end timestamp was completed. An open legacy row remains
-- active until the deterministic duplicate reconciliation below.
update public.focus_sessions
set status = case
  when ended_at is null then 'active'
  else 'completed'
end
where status is null;

update public.focus_sessions
set updated_at = coalesce(updated_at, ended_at, started_at, created_at)
where updated_at is null;

-- New clients persist the user's explicit local start date. Older rows cannot
-- recover that timezone, so give every missing legacy value one deterministic
-- cross-service UTC fallback instead of letting Flutter and FastAPI disagree.
update public.focus_sessions
set metadata = jsonb_set(
  coalesce(metadata, '{}'::jsonb),
  '{entry_date}',
  to_jsonb(to_char(started_at at time zone 'UTC', 'YYYY-MM-DD')),
  true
)
where metadata ->> 'entry_date' is null;

-- Normalize every legacy lifecycle shape, including approximate durations,
-- ended-before-start rows, and stray duration values on open sessions.
update public.focus_sessions
set
  ended_at = null,
  actual_minutes = null
where status = 'active'
  and (ended_at is not null or actual_minutes is not null);

update public.focus_sessions
set
  ended_at = greatest(coalesce(ended_at, started_at), started_at),
  actual_minutes = greatest(
    0,
    floor(
      extract(
        epoch from (greatest(coalesce(ended_at, started_at), started_at) - started_at)
      ) / 60
    )::int
  )
where status in ('completed', 'abandoned');

-- Keep the most recently started legacy session active for each user. Close
-- older open rows deterministically without using migration wall-clock time.
with ranked_active as (
  select
    id,
    row_number() over (
      partition by user_id
      order by started_at desc, created_at desc, id desc
    ) as active_rank
  from public.focus_sessions
  where status = 'active'
), reconciled as (
  select
    focus.id,
    greatest(focus.started_at, focus.created_at) as reconciled_end
  from public.focus_sessions as focus
  join ranked_active as ranked on ranked.id = focus.id
  where ranked.active_rank > 1
)
update public.focus_sessions as focus
set
  status = 'abandoned',
  ended_at = reconciled.reconciled_end,
  actual_minutes = greatest(
    0,
    floor(
      extract(epoch from (reconciled.reconciled_end - focus.started_at)) / 60
    )::int
  ),
  updated_at = greatest(focus.updated_at, reconciled.reconciled_end)
from reconciled
where focus.id = reconciled.id;

-- A partially pre-provisioned database may already have populated target
-- columns. Refuse cross-owner historical linkage before installing constraints
-- and future-write triggers.
do $$
begin
  if exists (
    select 1
    from public.focus_sessions as focus
    left join public.tasks as task on task.id = focus.task_id
    where focus.task_id is not null
      and (task.id is null or task.user_id <> focus.user_id)
  ) or exists (
    select 1
    from public.focus_sessions as focus
    left join public.habits as habit on habit.id = focus.habit_id
    where focus.habit_id is not null
      and (habit.id is null or habit.user_id <> focus.user_id)
  ) then
    raise exception 'Phase 3 found a cross-owner focus target.'
      using errcode = '23514';
  end if;
end $$;

alter table public.focus_sessions
  alter column status set default 'active',
  alter column status set not null,
  alter column updated_at set default now(),
  alter column updated_at set not null;

do $$
begin
  if exists (
    select 1
    from public.focus_sessions
    where planned_minutes not between 5 and 240
  ) then
    raise exception
      'Phase 3 found a focus session with planned_minutes outside 5..240.'
      using errcode = '23514';
  end if;

  if not exists (
    select 1
    from pg_catalog.pg_constraint
    where conname = 'focus_sessions_status_check'
      and conrelid = 'public.focus_sessions'::regclass
  ) then
    alter table public.focus_sessions
      add constraint focus_sessions_status_check
      check (status in ('active', 'completed', 'abandoned'));
  end if;

  if not exists (
    select 1
    from pg_catalog.pg_constraint
    where conname = 'focus_sessions_planned_minutes_check'
      and conrelid = 'public.focus_sessions'::regclass
  ) then
    alter table public.focus_sessions
      add constraint focus_sessions_planned_minutes_check
      check (planned_minutes between 5 and 240);
  end if;

  if not exists (
    select 1
    from pg_catalog.pg_constraint
    where conname = 'focus_sessions_lifecycle_shape_check'
      and conrelid = 'public.focus_sessions'::regclass
  ) then
    alter table public.focus_sessions
      add constraint focus_sessions_lifecycle_shape_check
      check (
        (
          status = 'active'
          and ended_at is null
          and actual_minutes is null
        )
        or (
          status in ('completed', 'abandoned')
          and ended_at is not null
          and ended_at >= started_at
          and actual_minutes is not null
          and actual_minutes >= 0
          and actual_minutes = floor(
            extract(epoch from (ended_at - started_at)) / 60
          )::int
        )
      );
  end if;

  if not exists (
    select 1
    from pg_catalog.pg_constraint
    where conname = 'focus_sessions_single_target_check'
      and conrelid = 'public.focus_sessions'::regclass
  ) then
    alter table public.focus_sessions
      add constraint focus_sessions_single_target_check
      check (task_id is null or habit_id is null);
  end if;

  if not exists (
    select 1
    from pg_catalog.pg_constraint
    where conname = 'focus_sessions_task_id_fkey'
      and conrelid = 'public.focus_sessions'::regclass
  ) then
    alter table public.focus_sessions
      add constraint focus_sessions_task_id_fkey
      foreign key (task_id) references public.tasks (id) on delete restrict;
  end if;

  if not exists (
    select 1
    from pg_catalog.pg_constraint
    where conname = 'focus_sessions_habit_id_fkey'
      and conrelid = 'public.focus_sessions'::regclass
  ) then
    alter table public.focus_sessions
      add constraint focus_sessions_habit_id_fkey
      foreign key (habit_id) references public.habits (id) on delete restrict;
  end if;
end $$;

create unique index if not exists focus_sessions_one_active_per_user_idx
  on public.focus_sessions (user_id)
  where status = 'active';

create or replace function private.enforce_focus_session_target()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, pg_temp
as $$
begin
  if new.task_id is not null and new.habit_id is not null then
    raise exception 'A focus session may link at most one target.'
      using errcode = '23514';
  end if;

  if new.task_id is not null then
    perform 1
    from public.tasks as task
    where task.id = new.task_id
      and task.user_id = new.user_id
      and task.status in ('todo', 'in_progress')
    for no key update;

    if not found then
      raise exception 'Focus task target is unavailable.'
        using errcode = '23514';
    end if;
  end if;

  if new.habit_id is not null then
    perform 1
    from public.habits as habit
    where habit.id = new.habit_id
      and habit.user_id = new.user_id
      and habit.active = true
      and coalesce(habit.metadata ->> 'lifecycle', 'active') = 'active'
      and coalesce(
        habit.metadata ->> 'setup_state',
        habit.metadata ->> 'status',
        ''
      ) not in ('candidate', 'archived')
    for no key update;

    if not found then
      raise exception 'Focus habit target is unavailable.'
        using errcode = '23514';
    end if;
  end if;

  return new;
end;
$$;

revoke all on function private.enforce_focus_session_target()
  from public, anon, authenticated, service_role;

drop trigger if exists focus_sessions_enforce_target
  on public.focus_sessions;

create trigger focus_sessions_enforce_target
before insert or update of user_id, task_id, habit_id
on public.focus_sessions
for each row
execute function private.enforce_focus_session_target();

create or replace function private.enforce_focus_session_transition()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, pg_temp
as $$
begin
  if new.started_at is distinct from old.started_at then
    raise exception 'A focus session start timestamp is immutable.'
      using errcode = '23514';
  end if;

  if old.status in ('completed', 'abandoned') then
    raise exception 'A terminal focus session is immutable.'
      using errcode = '23514';
  end if;

  if old.status = 'active'
     and new.status not in ('active', 'completed', 'abandoned') then
    raise exception 'Focus session transition is invalid.'
      using errcode = '23514';
  end if;

  return new;
end;
$$;

revoke all on function private.enforce_focus_session_transition()
  from public, anon, authenticated, service_role;

drop trigger if exists focus_sessions_enforce_transition
  on public.focus_sessions;

create trigger focus_sessions_enforce_transition
before update
on public.focus_sessions
for each row
execute function private.enforce_focus_session_transition();

create index if not exists focus_sessions_task_started_idx
  on public.focus_sessions (task_id, started_at desc)
  where task_id is not null;

create index if not exists focus_sessions_habit_started_idx
  on public.focus_sessions (habit_id, started_at desc)
  where habit_id is not null;
