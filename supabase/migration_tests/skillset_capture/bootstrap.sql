-- Isolated RPC unit-test substrate, not a production schema migration.
create role anon;
create role authenticated;
create role service_role;
create table public.daily_logs (
 id uuid primary key default gen_random_uuid(), user_id uuid, entry_date date,
 source text, metadata jsonb, created_at timestamptz, updated_at timestamptz,
 sleep_hours numeric, energy_level int, stress_level int, mood_score int,
 mood_label text, reflection text, unique(user_id,entry_date)
);
create table public.daily_capture_request_identities (
 request_id uuid primary key, user_id uuid, entry_date date, branch text,
 request_fingerprint text, capture_id text, captured_at timestamptz,
 result_daily_log_id uuid, result_updated_at timestamptz, created_at timestamptz
);
create table public.behavioral_events (
 id uuid primary key, user_id uuid, daily_log_id uuid, event_type text,
 value numeric, unit text, occurred_at timestamptz, source text,
 metadata jsonb, created_at timestamptz
);
