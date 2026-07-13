-- Complete the Phase 8 weekly-review provenance guard non-destructively.

alter table public.weekly_reviews
  drop constraint weekly_reviews_provenance_object;

alter table public.weekly_reviews
  add constraint weekly_reviews_provenance_object check (
    jsonb_typeof(provenance) = 'object'
    and octet_length(provenance::text) <= 32768
    and provenance @> '{
      "engine": "deterministic",
      "contract_version": "weekly-review-v1",
      "baseline": "none",
      "llm_used": false
    }'::jsonb
    and provenance ?& array[
      'source_snapshot_id',
      'source_snapshot_generated_at',
      'evidence_window',
      'source_fingerprint',
      'limitations'
    ]
    and jsonb_typeof(provenance -> 'evidence_window') = 'object'
    and provenance #>> '{evidence_window,starts_on}' = week_start::text
    and provenance #>> '{evidence_window,ends_on}' = week_end::text
    and provenance #>> '{evidence_window,days}' = '7'
    and jsonb_typeof(provenance -> 'limitations') = 'array'
    and provenance ->> 'source_fingerprint' = source_fingerprint
  );
