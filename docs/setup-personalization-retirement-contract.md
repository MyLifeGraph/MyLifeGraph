# Setup Personalization Retirement Contract

Status: current; the original retirement landed on 2026-07-25 and Goals were
fully removed on 2026-08-04.

This contract supersedes older Setup, Daily Capture, Daily State, Coach, and
Weekly Review descriptions that refer to Setup Goals, focus areas, friction
answers, coaching style, or a Setup-owned Reminder preference.

## Product boundary

Setup asks for:

- an optional display name;
- the required typical weekday and best energy window;
- optional routines, fixed commitments, and Study Setup.

Setup does not show or persist focus areas, friction points, coaching
style, Reminder preference, or a free-form context note. Reminder consent,
categories, quiet hours, and daily limit remain independently editable in
Settings. Applying or editing Setup must leave the complete
`notification_preferences` row unchanged.

Real Setup requires the canonical profile that the backend-owned Auth trigger
creates with the authenticated identity. If that invariant is missing, Flutter
fails closed before Setup, performs no profile insert/upsert, and offers
sign-out before another sign-in attempt. Guest Setup remains local and does not
use this remote profile boundary.

Goals have no current schema, export entry, Setup field, product surface,
ranking role, Snapshot source, or Coach context. The removal migration deletes
the prior rows and structurally dependent derived data; recovery requires a
pre-existing database backup. Local backup verification, recovery sequencing,
and the distinction between reverting the operational safety patch and
reintroducing Goals are explicit in `docs/local-database-safety.md`.

Evening Capture requires mood, energy, and stress. Stress source and
controllability remain required when stress is elevated. Reflection and specific
blocker remain optional; possible priority is retained only when already present
on a compatibility branch. Primary and additional friction choices are retired.
Morning Capture no longer asks for the unrelated per-day
`normal|constrained|flexible` Day Shape.

## Contracts and compatibility

`intake-v1` keeps its HTTP, request-id, base-revision, replay, and conflict
identity. `responses.goals` is rejected. A compatibility normalizer removes the
other retired keys before validation, comparison, or persistence:

- `primary_focus_areas`
- `friction_points`
- `coaching_style`
- `reminder_preference`
- `context_note`

Required Intake answers are `weekday_shape` and `best_energy_window`. The Setup
Apply RPC has no Goal parameter. It reconciles only routines/Habits, fixed
commitments, Study Setup, and the `Best energy window` memory. The
onboarding snapshot contains that energy value plus routine/Habit/commitment
counters and has no personalization signals. Setup completion does not generate
Recommendations.

`weekday_shape` is the one-time Setup answer labelled `Typical weekday`. It is
not the retired Morning `day_shape`, and this Daily Capture change does not
rename, remove, or reinterpret it.

The retirement slice first introduced friction-free `daily-capture-v3`; current
new saves use additive `daily-capture-v5`. V2–V4 rows remain readable, friction
keys are ignored, and an untouched older opposite branch may remain explicitly
marked compatible until it is edited. Complete V4 writes remain accepted during
rollout, but a V5 Morning write rejects `day_shape` and a V5 container is never
downgraded. New Daily State projections use
`explainable-daily-state-v3`; V1/V2 snapshots remain readable after
sanitization. V3 has no friction or Day Shape context, risk, reason, or evidence;
`constrained_capacity` and the former Day-Shape gate for `push` are removed.
Stress, sleep, energy, workload, and active Tasks continue to drive
classification. `push` requires at least one active Task.

Current free questions use `free-coach-agent-prompt-v4` with a per-turn
`personal-snapshot-v3`. P7 erases pre-cutover free-agent content while
preserving required content-free usage/request identities.
The snapshot may include retained sanitized Intake, Memory, and Daily Capture
rows as untrusted data, but it cannot include Goals or resurrect removed
onboarding preference, coaching-style, or friction JSON. Weekly Review proposal
arrays are also removed before Coach use. Compatible V2 fixed-mode requests retain
`controlled-coach-prompt-v3`/`coach-context-v3`; V1 Today retains paired
`controlled-coach-prompt-v2`/`coach-context-v2`. Persisted V1/V2 responses and
history remain readable and replay-compatible.

Briefings and Weekly Reviews have no Goal source. `weekly-review-v3` removes the
former Task Goal counter, contains no Feedback facts, and always generates an
empty proposal array. The generic Today Recommendation/Decision Feedback stack
is retired; the independent Sleep Recommendation and ordinary Coach advice
remain.

## Stored-data cleanup

Migration
`20260804150153_remove_goals_and_make_weekly_review_observational.sql`:

- removes structured Goal keys while preserving unrelated JSON;
- deletes all Goal rows, Goal memories, and structurally Goal-dependent derived
  rows without heuristically matching ordinary prose;
- tombstones structurally Goal-dependent Coach turns while retaining append-only
  usage and audit rows;
- removes the Goals table explicitly without `CASCADE`;
- replaces the backend-only Setup RPC with a Goal-free signature;
- migrates surviving Weekly Reviews in place to V2, preserving historical
  proposal arrays but requiring `[]` for every new or refreshed row;
- advances new Coach claims to prompt V3/snapshot V2 while preserving valid
  historical provenance pairs;
- performs no hidden regeneration.

The already-applied migration above is immutable. Additive migration
`20260804192406_harden_goal_removal_dependencies.sql` closes the remaining
cleanup graph without changing a public payload or version:

- it takes every read/changed application-table lock in alphabetical order as
  `SHARE ROW EXCLUSIVE`, with `lock_timeout='5s'`, before inspecting rows;
- its temporary V2 detector recognizes exact Goal keys, typed singular and
  plural source/table/type references, and exact Goal path segments such as
  `metadata.goal_id`, while never searching ordinary prose;
- it sanitizes Intake, Task, and onboarding snapshots in place and asserts that
  their authoritative JSON contains no recognized Goal structure;
- it computes complete temporary dependency sets before deletion, including
  foreign keys, recommendation ids, snapshot provenance, feedback evidence,
  and generated-notification source identities;
- it removes reviews whose source snapshot or referenced feedback is missing or
  retired, while leaving every clean review—including historical proposals,
  identity, period, fingerprint, and timestamps—unchanged;
- it tombstones direct structured Coach dependencies and every V1 turn whose
  evidence says `source=personal_snapshot`, deletes only their messages, clears
  response/evidence/trace/context, and retains append-only usage/audit facts;
- it asserts the final graph and removes every migration-only helper. It adds no
  permanent generic JSON constraint.

The cleanup routine is idempotent. Guest Setup and Capture stores apply the same
sanitization on first read and write the canonical value back locally.

The cleanup permanently removes historical JSON answers. A code rollback does
not restore them without a database backup. Removing or editing the applied
migration files is forbidden and would not recover rows; reintroducing the
feature requires a new forward migration and an explicit product-contract
change.

## Stabilized Setup errors

Flutter maps Setup load/save, HTTP, and contract failures through one
student-facing message boundary. Widgets never display URLs, status codes,
transport dumps, exception causes, or internal contract text. Unknown failures
use short English retry guidance and explicitly retain the current draft.
After a successful Setup apply, one typed app-composition impact invalidates
Today, Daily Briefing, Recommendations, Planner, Preparation Workload, and Exam
Outlook reads. Onboarding does not import or enumerate those foreign providers,
and cache invalidation never repeats the applied Setup mutation.

The FastAPI Intake route now delegates its existing structured revision
conflict to a typed feature-owned HTTP problem translator. The `409` detail
object, strict request validation, replay semantics, and bearer-derived owner
boundary are unchanged.

The adjacent account entry uses `Sign in` and `Create account`, and its
configuration or OAuth failures stay provider-neutral. Recovery uses the same
student language and shared surfaces. These authentication-copy changes occur
before Setup and do not restore retired personalization inputs or grant a
client-side profile-repair path.
