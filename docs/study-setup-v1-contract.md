# Study Setup V1 Contract

Status: implemented as of 2026-07-23.

Study Setup V1 adds optional focus-rhythm and semester-planning detail to the
existing revisioned Intake Setup. The required onboarding path remains
unchanged. Both optional sections can be omitted and later reviewed in Settings
Setup.

The feature is deterministic and no-LLM. It does not choose courses, change a
calendar, generate a notification, move a confirmed reservation, or replan in
the background.

## Intake Shape

`intake-v1` adds one optional `responses.study_setup` object. An old applied
Intake row without that key remains valid. Explicit `null`, an empty
`study_setup`, an unknown field, or a coercible value is invalid.

The exact complete shape is:

```json
{
  "study_setup": {
    "focus_rhythm": {
      "focus_minutes": 45,
      "recovery_minutes": 10,
      "preparation_items": [
        {
          "key": "1b4c8a1a-5c62-4ec0-9da2-01bf8309c6c6",
          "label": "Water",
          "active": true
        }
      ]
    },
    "semester_planning": {
      "current_semester": {
        "name": "Summer semester 2026",
        "starts_on": "2026-04-01",
        "ends_on": "2026-09-30"
      },
      "next_semester": {
        "name": "Winter semester 2026/27",
        "starts_on": "2026-10-01",
        "ends_on": "2027-03-31",
        "course_selection_starts_on": "2026-08-15",
        "course_selection_ends_on": "2026-09-15",
        "course_names": ["Algorithms", "Statistics"],
        "course_selection_completed": false
      }
    }
  }
}
```

Either `focus_rhythm` or `semester_planning` may be omitted, but at least one
must be present when `study_setup` is present.

Focus duration is an integer from 25 through 180 minutes and recovery is an
integer from 5 through 60 minutes. Both use five-minute increments. The ordered
preparation list has at most twelve entries. Each entry has one canonical
lowercase UUID, a trimmed non-empty label of at most 120 characters, and an
explicit boolean active state. Keys and case-insensitive labels are unique;
keys are also unique across Setup goals, routines, fixed commitments, and
preparation items.

Semester names and course names are trimmed, non-empty strings of at most 120
characters. Each semester end is on or after its start, and the next semester
starts after the current semester ends. The inclusive course-selection window
has an ordered start and end but may occur before the next semester begins.
There are at most twelve case-insensitively unique course names and one boolean
completion state for the whole selection. There are no priorities, credits, or
per-course states.

## Onboarding And Guest Boundary

`Focus setup` and `Semester planning` are collapsed optional sections. Enabling
Focus setup initializes 45 minutes of focus, 10 minutes of recovery, and these
active suggestions:

- Water
- Small snack
- Bathroom
- Flight or focus mode
- Study materials

Nicotine is not suggested. A student may still add any neutral custom label,
including nicotine, within the same validation rules. Entries can be reordered,
activated, deactivated, added, or removed.

Enabling Semester planning creates editors for exactly one current and one next
semester. A newly added Setup fixed commitment is prefilled with the current
semester's inclusive dates. The student reviews or changes those dates before
saving. Existing fixed commitments are never rewritten when semester values
change.

Guest/demo Setup uses the existing typed local persistence and makes no
FastAPI or Supabase product-data request. Its complete Study Setup value
survives local re-entry. There is no guest-to-account Study Setup migration.

## Projection And Authority

`20260723120000_study_setup_v1.sql` adds one owner-scoped
`study_setup_profiles` projection with:

- `contract_version = study-setup-v1`;
- nullable focus and recovery minutes plus bounded preparation-item JSON;
- nullable current- and next-semester JSON;
- the source `setup_revision`; and
- creation and update timestamps.

The table uses forced RLS. An authenticated owner or application admin may read
the projection. Anonymous and authenticated application roles cannot insert,
update, or delete it. Only the reviewed backend/service-role path writes it.
The profile foreign key cascades on account deletion.

The public `apply_intake_v1_setup_revision` RPC keeps the established owner lock
and request/revision behavior. After the existing Setup-owned projections have
been reconciled, its Study Setup wrapper reads the canonical applied Intake
revision and validates the exact Study shape again at the database boundary.
It then upserts the projection at that same Setup revision or deletes the
projection when `study_setup` was omitted. Any validation or projection failure
rolls back the complete Setup apply transaction, including mutations performed
by the wrapped Intake implementation.

An exact request replay remains idempotent. A stale `base_revision` cannot
overwrite a newer applied Setup. Omitting Study Setup in a newer explicitly
confirmed revision removes the projection; absence is not replaced by invented
defaults.

Account Export includes bounded owner rows from `study_setup_profiles`.
Account deletion removes the row through the existing profile cascade. No
request ledger or ritual-completion history is added.

## Focus Start And Recovery

For an authenticated real account, the Focus start duration resolves in this
order:

1. an explicit duration carried by a selected Planner or Preparation block;
2. the current Study Setup focus duration;
3. the most recent terminal Focus session duration; or
4. the existing 25-minute fallback.

An explicit block recovery value takes precedence over the current Study Setup
recovery value. Without either, recovery is zero. A student may choose a custom
5-through-240-minute duration for one manual Focus session without changing
Study Setup.

Before start, every active preparation item is shown in order. Each can be
marked `Ready` or `Not needed today`; the student may also choose
`Skip remaining and start`. These transient choices are neither persisted nor
evaluated. Only the saved item definitions and active states belong to Setup.

At Focus creation, the chosen recovery duration is stored as
`metadata.recovery_minutes` on the existing `focus_sessions` row. A completed
session starts a skippable device-local countdown. Its session id and end
instant are retained in local preferences so an unexpired countdown can be
restored after a reload. Completion, expiration, or `Skip recovery` clears
that local state. Abandoned sessions do not start recovery.

Recovery creates no row of its own and contributes no Focus progress, Task
progress, Deadline Plan progress, or preparation budget. The existing one-
active-Focus-session and immutable terminal-history rules remain unchanged.

## Planner And Deadline Planning

Deadline Planner always uses the current Study rhythm when a Focus rhythm is
configured. An ordinary Planner Task has an explicit `use_study_rhythm`
boolean, defaulting to false. When true, a current rhythm is required and the
submitted preferred session duration must equal its focus duration. Planner
Habits never accept Study rhythm.

With Study rhythm enabled:

- every normal block is exactly the configured focus duration;
- only the final remainder may be shorter;
- a smaller otherwise usable gap is not filled and remains transparently
  unscheduled;
- every block reserves the full configured recovery interval immediately after
  focus; and
- the preview and agenda show focus minutes, recovery minutes, and the complete
  reserved end.

The focus interval counts toward planned active minutes, progress, the
per-plan daily cap, and the optional account-wide preparation budget. Recovery
counts only as unavailable time. Conflict and availability calculations use
the half-open reservation interval `[starts_at, reserved_ends_at)`, so another
Planner, Preparation, Setup, commitment, or consented Calendar interval cannot
occupy recovery.

Deadline and Planner revision rows store nullable `study_setup_revision` plus
`recovery_minutes`. Their Task block rows store `recovery_minutes` and
`reserved_ends_at`. Existing revisions remain compatible with a null Study
revision and zero recovery; existing blocks are backfilled with zero recovery
and `reserved_ends_at = ends_at`.

Planning fingerprints cover the Study revision and recovery reservation.
Proposal RPCs require exact block sizing and recovery bounds. Confirmation
rechecks the current Study Setup revision and recovery duration under the
existing owner lock, and database conflict guards use the full reserved
interval. A changed or removed rhythm therefore makes a pending Study preview
stale and confirmation returns a conflict without changing active
reservations.

Changing Study Setup never edits an active plan. Active Deadline Plans and
active Planner Tasks that explicitly use Study rhythm appear under
`Needs attention`; only a newly proposed and explicitly confirmed revision may
replace their reservations. Ordinary Planner Tasks, Habits, and all plans made
without a Study rhythm retain their previous behavior.

## Course Selection Attention

Planner evaluates the next semester's course-selection window using the
profile-local calendar date:

- before its inclusive start: no item;
- from start through end: `course_selection_open`;
- after its end: `course_selection_overdue`; and
- after explicit completion: no item.

The item appears only under `Needs attention` and targets `study_setup`.
Flutter opens Settings Setup directly with Semester planning expanded. The
student saves edits or the semester-wide completion state through the existing
revisioned, retry-safe Intake flow.

This attention fact creates no Task, Today item, Calendar row, recommendation,
briefing, notification, or delivery attempt.

## Verification Contract

Focused coverage must prove:

- old Intake compatibility and exact rejection of null, coercion, unknown
  keys, invalid UUIDs, range/step errors, duplicates, and date-order errors;
- Guest local round-trip, collapsed onboarding sections, 45/10 defaults,
  custom ritual entries, and new-commitment-only semester prefill;
- atomic projection, replay, omission, stale revision, forced-RLS ownership,
  direct-write denial, rollback, export, and deletion boundaries;
- duration priority, transient checklist decisions, manual overrides, Focus
  metadata, completed-only local recovery, restoration, and skip;
- exact Study blocks, final short remainder, honest unscheduled minutes,
  recovery conflicts, unchanged active-minute/budget arithmetic, Planner Task
  opt-in, Habit exclusion, stale previews, and active-plan attention; and
- profile-local course-selection states, Settings navigation, and absence of
  Notification, Today, Calendar, or background-planning side effects.

Repository tests and local Supabase/browser verification establish only the
current local checkout. They do not prove remote migration state, installed-
device timer behavior, longitudinal study outcomes, or production scheduling.
