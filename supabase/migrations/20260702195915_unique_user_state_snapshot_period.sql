with ranked_snapshots as (
  select
    id,
    row_number() over (
      partition by user_id, scope, period_key
      order by generated_at desc, id desc
    ) as row_number
  from public.user_state_snapshots
)
delete from public.user_state_snapshots
using ranked_snapshots
where public.user_state_snapshots.id = ranked_snapshots.id
  and ranked_snapshots.row_number > 1;

create unique index if not exists user_state_snapshots_user_scope_period_unique_idx
  on public.user_state_snapshots (user_id, scope, period_key);
