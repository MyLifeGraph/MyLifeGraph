-- Preserve learned evidence while recording that allocation used Setup timing.

alter table public.planner_action_plan_revisions
  drop constraint planner_action_revision_timing_check,
  add constraint planner_action_revision_timing_check check (
    (
      timing_preference_source = 'setup'
      and timing_preference_window is null
      and timing_evidence_count = 0
      and timing_evidence_starts_on is null
      and timing_evidence_ends_on is null
      and timing_evidence_fingerprint is null
      and (
        timing_warning is null
        or timing_warning = 'personal_patterns_unavailable'
      )
    )
    or (
      timing_preference_source = 'learned_personal_pattern'
      and target_payload ->> 'kind' = 'task'
      and timing_preference_window in ('05-09', '09-13', '13-18', '18-23')
      and timing_evidence_count between 1 and 10000
      and timing_evidence_starts_on is not null
      and timing_evidence_ends_on is not null
      and timing_evidence_starts_on <= timing_evidence_ends_on
      and timing_evidence_fingerprint ~ '^[0-9a-f]{64}$'
      and timing_warning is null
    )
  );

alter table public.deadline_plan_revisions
  drop constraint deadline_plan_revision_timing_check,
  add constraint deadline_plan_revision_timing_check check (
    (
      timing_preference_source = 'setup'
      and timing_preference_window is null
      and timing_evidence_count = 0
      and timing_evidence_starts_on is null
      and timing_evidence_ends_on is null
      and timing_evidence_fingerprint is null
      and (
        timing_warning is null
        or timing_warning = 'personal_patterns_unavailable'
      )
    )
    or (
      timing_preference_source = 'learned_personal_pattern'
      and timing_preference_window in ('05-09', '09-13', '13-18', '18-23')
      and timing_evidence_count between 1 and 10000
      and timing_evidence_starts_on is not null
      and timing_evidence_ends_on is not null
      and timing_evidence_starts_on <= timing_evidence_ends_on
      and timing_evidence_fingerprint ~ '^[0-9a-f]{64}$'
      and timing_warning is null
    )
  );
