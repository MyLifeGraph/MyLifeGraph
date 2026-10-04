-- Optional context only; keep scalar Evening reflection and every numeric
-- projection unchanged. Older writers omit the field and preserve it.
do $migration$
declare
  target regprocedure := 'public.apply_daily_capture_branch_v1(uuid,date,text,uuid,text,jsonb,jsonb,timestamptz)'::regprocedure;
  definition text;
  anchor text := '  stored_capture := p_capture;';
begin
  definition := pg_get_functiondef(target);
  if position(anchor in definition) = 0 then
    raise exception 'Daily Capture function changed: review Morning note migration';
  end if;
  definition := replace(definition, anchor, $replacement$
  if p_branch = 'morning' and p_capture ? 'reflection_note' then
    if jsonb_typeof(p_capture -> 'reflection_note') not in ('string', 'null')
       or length(coalesce(p_capture ->> 'reflection_note', '')) > 500 then
      raise exception 'Invalid Morning note' using errcode = '22023';
    end if;
  end if;
  stored_capture := p_capture;
  if p_branch = 'morning' and not (p_capture ? 'reflection_note')
     and current_capture ? 'reflection_note' then
    stored_capture := stored_capture || jsonb_build_object(
      'reflection_note', current_capture -> 'reflection_note');
  end if;
$replacement$);
  execute definition;
end
$migration$;
