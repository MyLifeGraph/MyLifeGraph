-- Phase 6 bounded, owner-scoped decision feedback history.

create table public.decision_feedback (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  request_id uuid not null,
  briefing_id uuid not null references public.daily_briefings (id) on delete cascade,
  recommendation_id uuid references public.recommendations (id) on delete set null,
  action_id text not null check (length(trim(action_id)) between 1 and 200),
  action_kind text not null check (
    action_kind in ('task', 'habit', 'focus', 'planning', 'recovery', 'capture')
  ),
  feedback_type text not null check (
    feedback_type in ('done', 'later', 'not_helpful', 'too_much', 'does_not_fit')
  ),
  context_mode text not null check (
    context_mode in ('push', 'steady', 'recover', 'plan')
  ),
  estimated_minutes int check (
    estimated_minutes is null or estimated_minutes between 1 and 480
  ),
  rule_key text not null check (length(trim(rule_key)) between 1 and 100),
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  constraint decision_feedback_user_request_key unique (user_id, request_id),
  constraint decision_feedback_metadata_object check (
    jsonb_typeof(metadata) = 'object'
  )
);

create index decision_feedback_user_created_idx
  on public.decision_feedback (user_id, created_at desc, id desc);
create index decision_feedback_user_context_idx
  on public.decision_feedback (
    user_id,
    context_mode,
    action_kind,
    created_at desc
  );

alter table public.decision_feedback enable row level security;
alter table public.decision_feedback force row level security;

grant usage on schema public to authenticated, service_role;
revoke all on table public.decision_feedback
  from anon, authenticated, service_role;
grant select, delete on table public.decision_feedback to authenticated;
grant select, insert, update, delete on table public.decision_feedback
  to service_role;

create policy "decision_feedback_own_or_admin_select"
  on public.decision_feedback
  for select
  to authenticated
  using (
    user_id = (select auth.uid())
    or (select private.current_app_role()) = 'admin'
  );

create policy "decision_feedback_own_or_admin_delete"
  on public.decision_feedback
  for delete
  to authenticated
  using (
    user_id = (select auth.uid())
    or (select private.current_app_role()) = 'admin'
  );

create policy "decision_feedback_service_role_all"
  on public.decision_feedback
  for all
  to service_role
  using (true)
  with check (true);
