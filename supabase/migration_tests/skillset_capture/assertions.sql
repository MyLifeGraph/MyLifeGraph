-- Isolated unit proof: bootstrap.sql, the additive migration, then this file.
-- Requires a fresh RAM-only test container, never a normal/local/Cloud database.
-- Minimal fixtures do not replace the full migration-chain or RLS gate.
begin;
do $$
declare
 owner_id uuid := 'abc00000-0000-4000-8000-000000000001';
 test_day date := '2026-09-13';
 test_now timestamptz := '2026-09-13T20:00:00Z';
 capture jsonb;
 expected jsonb;
 saved jsonb;
 extras jsonb;
 request_id uuid;
 result jsonb;
 choice int;
begin
 for choice in 0..2 loop
   capture := jsonb_build_object(
     'branch_version','daily-capture-v5','capture_kind','evening',
     'entry_date',test_day,'capture_id','evening:test','captured_at',test_now,
     'mood',7,'energy',6,'stress_intensity',3,
     'planned_sleep_time','23:00','sleep_target_minutes',480,
     'skillset',jsonb_build_object('version','skillset-capture-v1','sport',choice,'social',choice)
   );
   select metadata->'captures'->'evening' into expected from daily_logs where user_id=owner_id;
   request_id := gen_random_uuid();
   perform apply_daily_capture_branch_v1(owner_id,test_day,'evening',request_id,repeat('a',64),expected,capture,test_now);
   select metadata->'captures'->'evening' into saved from daily_logs where user_id=owner_id;
   assert saved->'skillset'=capture->'skillset', 'New choices must be stored exactly';
   result := apply_daily_capture_branch_v1(owner_id,test_day,'evening',request_id,repeat('a',64),expected,capture,test_now);
   assert result->>'replayed'='true', 'Exact retry must replay';
   begin
     perform apply_daily_capture_branch_v1(owner_id,test_day,'evening',request_id,repeat('b',64),expected,capture,test_now);
     raise exception 'Reused request identity was accepted';
   exception when sqlstate 'PT409' then null;
   end;
   extras := saved->'skillset';
   capture := (capture-'skillset') || '{"branch_version":"daily-capture-v4"}'::jsonb;
   perform apply_daily_capture_branch_v1(owner_id,test_day,'evening',gen_random_uuid(),repeat('c',64),saved,capture,test_now);
   select metadata->'captures'->'evening' into saved from daily_logs where user_id=owner_id;
   assert saved->'skillset'=extras, 'Old V4 writer must not erase optional evidence';
   assert saved->>'compatibility'='true', 'Old compatibility semantics stay intact';
 end loop;
 capture := jsonb_build_object(
   'branch_version','daily-capture-v5','capture_kind','morning','entry_date',test_day,
   'capture_id','morning:test','captured_at',test_now,'sleep_hours',8,
   'sleep_quality',7,'current_energy',4,
   'skillset',jsonb_build_object('version','skillset-capture-v1','motivation',0)
 );
 perform apply_daily_capture_branch_v1(owner_id,test_day,'morning',gen_random_uuid(),repeat('d',64),null,capture,test_now);
 select metadata->'captures'->'evening' into saved from daily_logs where user_id=owner_id;
 assert saved->'skillset'=extras, 'Other branch must not overwrite evidence';
 assert (select energy_level=4 and mood_score=7 and stress_level=3 and sleep_hours=8
         from daily_logs where user_id=owner_id), 'Legacy projections must remain exact';
 assert (select count(*)=4 from behavioral_events where user_id=owner_id), 'No duplicate or new event types';
 capture := saved || '{"branch_version":"daily-capture-v5","skillset":{"version":"skillset-capture-v1","sport":null,"social":2}}'::jsonb;
 perform apply_daily_capture_branch_v1(owner_id,test_day,'evening',gen_random_uuid(),repeat('e',64),saved,capture,test_now);
 select metadata->'captures' into saved from daily_logs where user_id=owner_id;
 assert saved->'evening'->'skillset'->'sport'='null'::jsonb, 'Explicit clearing must persist';
 assert saved->'morning'->'skillset'->'motivation'='0'::jsonb, 'Zero is real, not missing';
 assert not has_function_privilege('anon','public.apply_daily_capture_branch_v1(uuid,date,text,uuid,text,jsonb,jsonb,timestamptz)','execute');
 assert not has_function_privilege('authenticated','public.apply_daily_capture_branch_v1(uuid,date,text,uuid,text,jsonb,jsonb,timestamptz)','execute');
 assert has_function_privilege('service_role','public.apply_daily_capture_branch_v1(uuid,date,text,uuid,text,jsonb,jsonb,timestamptz)','execute');
end $$;
rollback;
