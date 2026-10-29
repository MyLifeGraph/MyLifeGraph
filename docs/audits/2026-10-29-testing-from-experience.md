# Experience-based testing — 2026-10-29

Status: historical run record; current checkout evidence is owned by
`docs/verification.md`. This dated record never proves a later checkout.

Task: 70 minutes of local experience-based testing; fix only reproduced bugs.
Base: `8805ab6867f84fbfedeb5cc246c4a8bf89751efd`.
Start: 2026-10-29 15:39:51 UTC (16:39:51 Europe/Berlin).
Planned end: 16:49:51 UTC. Final test result collected: 16:55:38 UTC.
Elapsed testing/fix/verification window: 75 minutes 47 seconds. The requested
70-minute work window was followed by completion of already-running checks;
no new search wave was started after it. Final documentation follows this window.
Catalog: [experience catalog](../testing/experience-catalog.md).

## Preflight and boundaries

Read AGENTS.md, the experience-testing skill/template, the existing twenty-category
catalog and October 27 audit. Owners selected: Android Focus Protection V1
(plan authority, editor lifecycle, gestures, status, usage, notifications and
Discipline); Phase 3 executable actions (Focus authority); mobile README;
visual system and UI copy contracts; local-dev (local tooling); verification
(Fast and Android gates). Additional owners will be recorded before expanding
into their implementation boundaries.

The four existing modified release-retention/local-dev files are unrelated and
will not be edited or included as test-task changes. Existing untracked output,
tmp and Flutter failure artifacts are preserved. No publication, remote mutation,
personal-account writes or physical-device claims are authorized by this run.

## Waves

| Wave | Categories | Additional scope | Evidence / outcome |
| --- | --- | --- | --- |
| 1 | EXP-001–020 | Current full Flutter baseline and Android JVM/lint | Completed; known six Windows goldens fail, native checks pass |
| 2 | EXP-003–019 | Short search after anchoring; two taps before a frame; adding custom website; native sequence oracles | Two independent picker bugs reproduced and fixed; focused regressions pass |
| 3 | EXP-004, 005, 013, 019, 020 | Shuffled check-ins, Coach scroll/follow, calendar, streak/sleep boundaries, real widget render inspection | Adjacent tests pass; final Flutter retains only six existing golden failures; analyzer has a local filesystem failure |

## Results

Two new reproduced bug groups, both locally fixed. Existing tests and historical reports are not counted as
newly found bugs. Hardware NFC, Samsung battery management and real notification
shade behavior require device evidence; simulations alone cannot prove them.

### BUG-001 — stale picker anchoring space after filtering

- EXP-007 / EXP-020; shared `BlockingTargetList` used by Apps and Websites.
- Select a bulk group while midway through 25 or 250 targets; clear it; then
  filter down to five rows in the 300px viewport. The old anchor spacer remains.
- Both sizes failed the new assertion with 56px of unnecessary scroll extent
  (`target-filter-before.log`). This is one mechanism, not two bugs.
- Reset temporary bottom anchoring space when the result IDs/order change.
  Ordinary partition changes preserve the existing viewport anchoring behavior.
- Targeted retest plus editor and icon regression suite: 20 passed.

### BUG-002 — rapid selections choose an already-moving viewport anchor

- EXP-007 / EXP-004; the same Apps/Websites picker.
- At a mid-list position, select target 12 and target 13 before a new frame.
  The second anchor scan sees the first selection's mutated set but its old
  rendered position. It picks that already-moving row and scrolls to the top.
- Reproduced at 25 and 250 items through the shared selection callback; then
  reproduced again with actual WidgetTester taps (`target-double-tap-before.log`).
  The unaffected target 11 moved from y=206 to y=879 (673px).
- Keep the union of moved IDs until the latest frame callback and exclude all
  of them when choosing the anchor. Registration/order/persistence is unchanged.
- New adjacent case adds a custom website (new source ID) while preserving the
  reading anchor. Targeted confirmation passes, including actual rapid taps.

### Additional owner coverage

For adjacent-surface transfer tests, read Coach's Flutter scroll/follow contract,
Daily Briefing's Capture editing/manual-date safeguards, Stabilization's draft
CAS/identity rules, Today's streak/grace rules, and Personal Learning's per-pair
fallback/source precedence and evidence gates. Existing fake repositories isolate
the checks; no authenticated API/database requests are needed.

## Final verification and changes

Execution logs are local under `.tools/experience-20261029/`; exact current
counts and gate state are recorded in `docs/verification.md`.

| Categories | Executed evidence / scope |
| --- | --- |
| EXP-001, 002 | Status color and plan capability regressions; native enabled/usage/permission rule gates |
| EXP-003, 004 | Editor pending-catalog and stale asynchronous replies; new actual rapid-tap reproduction |
| EXP-005, 006 | Pending Save, failed-write draft preservation, stale revision/deleted target tests |
| EXP-007, 008 | Immediate selected-first ordering, deselection, viewport anchors, app/site icon identity and fallback |
| EXP-009, 010 | Top-only modal dismissal; nested horizontal pager/section ownership and retained drafts |
| EXP-011 | Handle delay/reorder rollback; native stable-order policy |
| EXP-012, 013 | Explicit unlock intent, wait completion, route visibility versus notification-shade focus changes |
| EXP-014, 015 | NFC consumption/cancel/recovery policies; browser neutralization and app Return navigation |
| EXP-016, 017 | Per-visit notification dismissal tokens; generated usage interval oracle and budget limits |
| EXP-018, 019 | Foreground recovery eligibility, weekly/DST boundaries, 48-hour grace and sleep chronology |
| EXP-020 | Four-theme narrow/large-text editor tests, retained error/data state and eight actual widget renders |

The native generated usage oracle covers 300 seeded mixed-activity traces;
weekly rules include 500 generated cases. These are current executions of
existing regression tests, not newly discovered defects or physical-device tests.
New Insights tests shuffle sources with seed 20261029 and compare sample count,
evidence state, coefficient and ranking with/without Focus; no correlation
algorithm changed. Coach/calendar/backend tests use deterministic fixtures.

Eight render outputs are in `.tools/ui-catalog/experience-20261029/`.
No new severe clipping/overlap was observed. The synthetic Apps fixture has no
installed-package PNGs, so its generic fallback icons are expected; real icon
identity/fallback behavior is separately covered by widget tests.

An isolated read-only Pixel emulator was started without snapshots or personal
data. It did not complete Android boot; it was stopped with `emu kill`. No APK
installation or device acceptance was performed. Samsung foreground delivery,
NFC hardware, the real notification shade, live Coach and production state are
open coverage limits. Six pre-existing Windows component golden differences
remain; this run does not claim an entirely green release gate.
The dark-mobile failed component reference and current render were also inspected
side by side: minor text/raster differences remain, without a new overlapping
control. This standalone reference does not exercise the changed target picker;
its original failure was present before either task fix. No golden was blessed.

Final full Flutter: 2032 passed, six unchanged component golden failures. Fresh
native JVM: 137 passed; selected backend: 86 passed; final targeted widget checks
and adjacent transfer checks pass. Documentation, visual contract, formatting
and whitespace checks pass. Static analysis is incomplete: its server exits 4
while deleting its own local Dart performance file (Windows error 1920). This
tool failure is not counted as a product bug or a successful analysis run.

New product bug total: two independent groups, both fixed locally; zero confirmed
new product bugs remain open. Coverage gaps and existing golden failures above
remain explicit. No commits, push, release or deployment in this task.
