# Setup Personalization Retirement Contract

Status: implemented on 2026-07-25.

This contract supersedes older Setup, Daily Capture, Daily State, Coach, and
Weekly Review descriptions that refer to Setup Goals, focus areas, friction
answers, coaching style, or a Setup-owned Reminder preference.

## Product boundary

Setup asks for:

- an optional display name;
- the required typical weekday and best energy window;
- optional routines, fixed commitments, and Study Setup.

Setup does not show or persist focus areas, Goals, friction points, coaching
style, Reminder preference, or a free-form context note. Reminder consent,
categories, quiet hours, and daily limit remain independently editable in
Settings. Applying or editing Setup must leave the complete
`notification_preferences` row unchanged.

Real Setup requires the canonical profile that the backend-owned Auth trigger
creates with the authenticated identity. If that invariant is missing, Flutter
fails closed before Setup, performs no profile insert/upsert, and offers
sign-out before another sign-in attempt. Guest Setup remains local and does not
use this remote profile boundary.

The Goals table remains in the canonical schema and Account Export for
compatibility. Goals have no active product surface or ranking role. Setup-owned
Goal rows are archived; manual and foreign-managed rows are retained unchanged.

Evening Capture requires mood, energy, and stress. Stress source and
controllability remain required when stress is elevated. Reflection, possible
priority, and specific blocker remain optional. Primary and additional friction
choices are retired.

## Contracts and compatibility

`intake-v1` keeps its HTTP, request-id, base-revision, replay, and conflict
identity. A compatibility normalizer removes these keys before validation,
comparison, or persistence:

- `primary_focus_areas`
- `goals`
- `friction_points`
- `coaching_style`
- `reminder_preference`
- `context_note`

Required Intake answers are `weekday_shape` and `best_energy_window`. The Setup
Apply RPC retains its existing arguments, but ignores
`p_notification_preferences` and `p_goals`. It reconciles only routines/Habits,
fixed commitments, Study Setup, and the `Best energy window` memory. The
onboarding snapshot contains that energy value plus routine/Habit/commitment
counters and has no personalization signals. Setup completion does not generate
Recommendations.

The retirement slice first introduced friction-free `daily-capture-v3`; current
new saves use additive `daily-capture-v4`. V2/V3 rows remain readable, friction
keys are ignored, and an untouched older opposite branch may remain explicitly
marked compatible until it is edited. New
Daily State projections use `explainable-daily-state-v2`; V1 snapshots remain
readable after sanitization. V2 has no friction context, risk, reason, or
evidence. Stress, sleep, energy, day shape, workload, and active Tasks continue
to drive classification. `push` requires at least one active Task.

Current free questions use `free-coach-agent-prompt-v2` with a per-turn
`personal-snapshot-v1`; paired V1 prompt history and exact replay stay valid.
The snapshot may include retained sanitized Intake,
Goal, Memory, and Daily Capture rows as untrusted data, but the cleanup means it
cannot resurrect removed onboarding preference, coaching-style, friction, or
Setup-Goal JSON. Compatible V2 fixed-mode requests retain
`controlled-coach-prompt-v3`/`coach-context-v3`; V1 Today retains paired
`controlled-coach-prompt-v2`/`coach-context-v2`. Persisted V1/V2 responses and
history remain readable and replay-compatible.

Briefings and Weekly Reviews do not load Goals. The V1 Weekly Review field
`facts.tasks.goal_linked_completed` remains present and is always `0`.
Recommendations use runtime Tasks, check-ins, and other current signals rather
than onboarding personalization.

## Stored-data cleanup

Migration
`20260725120000_retire_setup_goals_and_friction.sql`:

- removes retired Intake and onboarding JSON fields;
- archives only Setup-owned Goals;
- deletes only Setup-derived Goal, coaching-style, and context-note memories;
- retains the best-energy memory and all manual/other memories;
- removes friction keys from Daily Logs and Behavioral Events;
- invalidates reproducible Snapshots, Briefings, Weekly Reviews, and
  Recommendations whose structured evidence uses retired data;
- advances new Coach claims to the paired V2 provenance while preserving V1
  rows;
- performs no hidden regeneration.

The cleanup routine is idempotent. Guest Setup and Capture stores apply the same
sanitization on first read and write the canonical value back locally.

The cleanup permanently removes historical JSON answers. A code rollback does
not restore them without a database backup.

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
