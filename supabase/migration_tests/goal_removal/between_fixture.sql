begin;

-- This current V2 turn can only be created after the original migration has
-- introduced the Goal-free claim pair. It must survive the follow-up cleanup.
select public.claim_coach_request_v5(
  'e2000000-0000-4000-8000-000000000001',
  'e2000000-0000-4000-8000-000000000803',
  encode(
    extensions.digest(
      convert_to('Current Goal-free Coach request.', 'UTF8'),
      'sha256'
    ),
    'hex'
  ),
  '2026-08-04',
  'fake',
  'deterministic_test_only',
  null,
  'not_applicable',
  '2026-08-04T10:07:00Z',
  '2026-08-04T10:09:00Z',
  20
);

commit;
