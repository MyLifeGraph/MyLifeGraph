# Student Product Review Follow-up — 2026-07-18

This is the implementation-backed follow-up to
`docs/product-review-handoff.md`. The reviewed baseline was commit
`fce17b72a95bb386b2978cb658f06341809fc2bf` on branch `new_backend_gh`. The
checkout was clean before this review. No existing work was reset or discarded,
and no remote system was changed.

## Scope and method

The review followed a student journey from first Setup through Today, Quick
actions, Focus, Insights, Weekly review, Calendar, Inbox, Settings, and repeated
Deadline Planner use. It inspected calculation code, Flutter state handling,
FastAPI retry and conflict behavior, PostgreSQL/RLS contracts, copy boundaries,
small-screen behavior, and the existing automated coverage for loading, empty,
offline, error, and ambiguous-response states.

The prepared five-student study in `docs/student-usability-test-script.md` was
later deliberately skipped/deferred and has not been run. The subsequent
five-agent compressed walkthrough is documented in
`docs/synthetic-student-persona-simulation-2026-07-18.md`; it is not participant
evidence. The observations below are code-, contract-, and automation-based;
they are not invented participant findings or evidence of long-term learning
benefit.

## Findings, ordered by severity

### Critical or high

No reproducible critical or high-severity defect remained after the review and
the required local verification. This does not replace the manual and external
validation listed below.

### Medium — fixed

1. **Today could present yesterday's latest check-in as saved today.** The
   compact capture status did not compare `entryDate` with the loaded local
   date. Its icon opened Morning when no Morning capture existed, while its
   tooltip incorrectly announced “Add evening check-in.” Today now scopes the
   compact status and action to the current day; the older record remains
   available honestly under Latest check-in.
2. **Insights undercounted real work.** Completed legacy Focus rows with missing
   or invalid `metadata.entry_date` were silently dropped even though the
   contract requires the UTC date of `started_at` as fallback. Planned load also
   omitted confirmed Deadline Planner reservations. Insights now applies the
   documented fallback and includes only active, confirmed preparation blocks;
   proposed, superseded, malformed, and out-of-window blocks remain excluded.
3. **Long-lived replanning exposed an ineffective historical start.** A saved
   `planning_start_on` could remain months in the past although FastAPI clamps
   effective planning to the current profile-local day. The stale input could
   also consume the 366-day UI horizon and reject an otherwise valid replan.
   Opening a replan now normalizes a past saved start to the current device date,
   and the date picker no longer offers past starts.

### Low — fixed

1. **An in-progress calendar commitment disappeared from Today at its start
   time.** Schedule events now retain their end minute, so the compact card skips
   only events that have actually ended.
2. **Focus duration choices could crowd a 320 px display at 200% text.** The
   choices now stack vertically at narrow widths or large text. The countdown
   remains readable to assistive technology without marking every one-second
   update as a live-region announcement; the planned-time boundary is still
   announced.
3. **Planner buffer wording hid the actual deterministic rule.** `buffer_days=1`
   intentionally leaves the complete calendar day immediately before the
   deadline free, making the last preferred work date two dates before the
   deadline. The UI and contract now say “clear days” and explain that zero may
   use the finish-by day up to its exact time.
4. **Local development documentation contradicted draft cancellation.** The
   guide said both complete and cancel required an active revision. It now
   matches the API contract: completion requires the active current revision;
   cancellation also accepts a still-draft latest revision and creates or
   changes no managed task.

## Calculation assessment

Deadline Planner V1 remains deterministic and transparent. Its core remainder
is:

```text
max(0, estimated total - entered prior credit - eligible tracked Focus)
```

Eligible tracked Focus is limited to completed sessions linked to the stable
managed task and started after the plan's first activation. The planner then
uses the chosen session size, daily cap, current time, fixed commitments,
confirmed preparation reservations, and explicitly enabled current imported
busy periods. It uses bounded five-minute slots, spreads the first pass across
the runway, never places work past the aware deadline, avoids unsafe DST wall
times, and reports any shortfall as `unscheduled_minutes` rather than pretending
the estimate fits.

Those rules are suitable for V1 because students can inspect and change every
authoritative input. The estimate is necessarily subjective, and explicit
prior credit can be entered incorrectly; the UI names which Focus the plan
credits automatically and warns against entering that work a second time. This
review found no evidence that an LLM should own or
silently alter the arithmetic, schedule, estimate, or mutations. An LLM may
explain these rules or offer a separately accepted suggestion, but no such
authority was added.

## Journey and truthfulness assessment

- Setup requires explicit answers, keeps re-entry editable, and distinguishes
  loading, empty, error, and retry states. Today and Quick actions preserve one
  primary path while keeping full details reachable.
- Focus never completes a linked task or habit implicitly. Weekly review keeps
  fact categories distinct and applies only its explicitly supported Habit V1
  mutations. Calendar remains an explicit, read-only import rather than a
  provider sync or write-back surface.
- Inbox delivery remains foreground in-app delivery, not push or background
  delivery. Coach remains a gated development preview and is not a calculation
  or mutation authority. Guest/example content and deterministic output retain
  explicit provenance.
- Insights remains bounded correlation exploration, not causal or learned-
  baseline advice. Its new preparation-load input is a direct Supabase fact,
  not inferred or model-generated content.
- Owner filters, forced RLS, backend-only ledgers/RPCs, ambiguous retry identity,
  conflict reloads, and cross-user negative paths were covered by the local
  migration checks, unit/integration suites, and browser journey. This is local
  evidence only and does not prove a remote migration state.

## Changes and regression coverage

- Added date-scoped Today capture status, matching accessibility action labels,
  and end-aware current-event selection.
- Added an Insights correlation row mapper with legacy Focus fallback and active
  Deadline Planner reservation accounting.
- Normalized historical replanning starts and clarified clear-day semantics.
- Made Focus duration choices responsive at 320 px/200% text and reduced timer
  live-region noise.
- Corrected architecture, planner-contract, and local-development documentation.
- Added regression tests for each changed behavior.

## Verification results

All results below are from this local checkout on 2026-07-18:

- Baseline focused Deadline Planner FastAPI tests: `22 passed`.
- Baseline focused Flutter product/planner tests: `55 passed`.
- Changed-area Flutter regression suite: `46 passed`.
- Standard source gate, rerun after fixing one trailing-comma lint:
  migration/start-stack guards passed, Flutter analysis reported no issues, all
  `585` Flutter tests passed, and Python application sources compiled.
- Complete FastAPI suite: `745 passed, 1 skipped`.
- Non-reset local Supabase verification: the local migration history matched the
  repository and all `585` Flutter tests passed.
- Full non-reset Flutter/FastAPI/Supabase browser journey: exit code `0`,
  `E2E browser smoke passed for e2e-1784407319@example.test`.
- `git diff --check`: passed before finalization.

## Remaining manual or external validation

1. If real usability evidence is wanted later, run the prepared five-student
   usability study with
   `docs/student-usability-study/facilitator-runbook.md` and report only
   observed results. The current decision is to skip/defer it; the synthetic
   agent report does not count as five participants.
2. Test representative physical phones and desktop browsers with OS-level 200%
   text, keyboard-only navigation, VoiceOver/TalkBack, reduced motion, and real
   network transitions. Widget/headless coverage is not installed-device
   acceptance evidence.
3. Exercise travel and device/profile-timezone mismatch on real devices around
   midnight and DST boundaries, including an active multi-week plan.
4. Observe real student use over several months before making retention,
   adherence, wellbeing, or learning-outcome claims.
5. Verify remote migrations, deployment configuration, external email/OAuth,
   scheduler operation, and any production Coach provider separately if those
   systems are placed in scope. This review did not do so.

There is still no evidence of remote migration application, push/background
notifications, a production Coach provider, German localization, or long-term
learning success.

## Account-wide preparation capacity follow-up — 2026-07-19

This compatible improvement started from clean commit
`eb0863531a3a944ca03b744b7ece60e7d062490b` on `new_backend_gh`. It did not run
the deferred five-student study and does not reinterpret the synthetic persona
walkthrough as participant or two-month evidence.

### Additional findings, ordered by severity

#### Critical or high

No reproducible critical or high-severity defect remained after the final local
verification. This is not evidence about a remote deployment or longitudinal
student outcomes.

#### Medium — fixed

1. **Separate plans had no optional aggregate daily limit or compact forward
   view.** Each revision's daily cap was internally consistent, but several
   active exams could still create an unrealistic combined day and the student
   had to inspect plans individually. Settings now offers a nullable explicit
   `25..480` minute account-wide rule in five-minute increments. Today and
   Preparation plans show seven profile-local dates with confirmed preparation,
   active-plan count, remaining capacity/overage, and separately labelled
   weekly Setup commitments.
2. **A preview needed a database-boundary capacity recheck.** Proposal-time
   subtraction alone could be stale after another confirmation or budget edit.
   Budget writes and planner commands now share the owner lock, and confirmation
   rejects an over-cap candidate with an exact `409` while retaining the staged
   preview and active revision.
3. **Current-day capacity could have ignored an earlier confirmed block.** Time-
   interval conflict reads may ignore already ended intervals, but a daily
   minute rule must still count that reservation. Planning context now loads all
   active other-plan blocks on the relevant profile-local dates. Regression
   coverage uses an earlier same-day block explicitly.
4. **The first confirmation trigger draft could have been blocked by an
   unrelated historical overage.** The final trigger scopes aggregate checks to
   only the candidate revision's local dates, while still counting every active
   other-plan block on those dates.
5. **Date-only workload parsing was device-DST-sensitive.** Flutter initially
   represented profile-local dates as device-local midnights; consecutive days
   can then be 23 or 25 hours apart. Workload dates now use timezone-independent
   UTC calendar identities, with a spring-transition regression test.
6. **A missing RPC could have been reported as a missing profile.** PostgREST
   also uses HTTP 404 when a migration/function is unavailable. Budget
   persistence now treats only exact PostgreSQL `PT404` as an absent profile;
   `PGRST202` and other definite client errors remain honest persistence
   failures and cannot converge through an unrelated equal readback.

#### Low — fixed

1. Adding the Settings card invalidated an older widget test's above-the-fold
   assumption. The test now scrolls and checks the disabled guest control.
2. Flutter Web merges a clickable Settings tile's title and subtitle into one
   accessible button name, and the Today workload can sit below a large
   briefing. Browser helpers now accept the escaped composite button name and
   scroll to the Today card. No product copy or layout was distorted to satisfy
   the automation.

### Calculation and authority assessment

The account rule caps confirmed preparation reservations only. New proposals
use the smaller of the revision's per-plan daily cap and the account capacity
remaining after other plans. Recurring Setup commitments and explicitly enabled
current imported busy intervals still remove time windows, but they do not
pretend to be preparation minutes. The seven-day projection therefore labels
Setup commitments separately and does not claim complete calendar or free-time
coverage.

Completed qualifying Focus continues to reduce remaining plan effort on the
next explicit proposal. It does not silently release an existing reservation,
and lowering the account rule does not rewrite active blocks; resulting days
remain visible as `Needs review` until the student replans. These rules are
deterministic and inspectable. No LLM receives authority over the estimate,
capacity arithmetic, block placement, confirmation, or product mutation.

### Changes and regression coverage

- Added the owner-locked service-role budget setter, profile constraint/direct-
  write denial, and confirmation trigger in
  `20260719120000_account_preparation_budget_v1.sql`.
- Added strict FastAPI/Flutter budget and `preparation-workload-v1` contracts,
  other-plan capacity deduction, seven-day aggregation, Settings editing, and
  Today/Preparation-plans cards with honest loading/error/no-budget/overage
  states.
- Added model, service, repository, API, migration, widget, accessibility, DST,
  conflict, ambiguous-response, owner-isolation, and full browser regression
  coverage. Account Export includes the nullable profile field.

### Verification results

All results below are local to this checkout on 2026-07-19:

- Complete FastAPI suite: `763 passed, 1 skipped`.
- Standard source gate: migration/start-stack guards passed, Flutter analysis
  reported no issues, all `601` Flutter tests passed, Python application sources
  compiled, and `git diff --check` passed.
- The reviewed migration was explicitly applied to local Supabase without a
  reset. A subsequent non-reset preflight confirmed repository/database history
  equality and all `601` Flutter tests passed.
- Full non-reset Flutter/FastAPI/Supabase browser journey: exit code `0`,
  `E2E browser smoke passed for e2e-1784448992@example.test`.
- JavaScript syntax checking for `e2e/web/smoke.mjs` passed after its final
  semantic/viewport fixes.

### Remaining manual or external validation

The prepared five-student study remains deliberately skipped and unrun. Useful
future checks are representative physical-device keyboard, screen-reader,
200-percent text and offline transitions; real travel/device-versus-profile-
timezone behavior around midnight and both DST transitions; and observed use of
several overlapping plans over weeks or months. Remote migration/RLS state,
deployed scheduling, push/background notification delivery, a production Coach
provider, German localization, and long-term learning benefit also remain
unverified and are not claimed here.
