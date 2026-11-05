# Experience-based local test run — 2026-11-05

Status: complete, local only. Current verification authority: [Verification](../verification.md).
Requested duration: 40 minutes. Start: 2026-11-05 18:30:16 UTC / 19:30:16 CET.
End: 19:10:17 UTC / 20:10:17 CET; elapsed 40 minutes 1 second.
No delegation or publication. Final record/hygiene checks follow this test window.
Base: `c583d65f9183e8673dc45f00b3f60db100c90c16`, including the existing local
Focus foreground-display change. Unrelated retention edits and prior outputs
remain untouched. [Catalog](../testing/experience-catalog.md).

## Preflight and planned waves

Read AGENTS.md, skill and report template, prior run/catalog, product guide,
Verification current baseline and gate selection, mobile README, Phase 3 Focus
lifecycle authority, Android Focus Protection plan/usage/Discipline/NFC and
Focus seam, local-dev tooling, and existing visual/copy owners. Additional
feature owners are loaded before their tests or changes. This is the work note
for local test/report changes. No schema, provider or production authority.

| Wave | Categories | New variants |
| --- | --- | --- |
| 1 | EXP-004/005/006/013/019/020 | Retained Focus timer, delayed/reordered reads, modal confirmation after backgrounding, terminal/refresh races |
| 2 | EXP-001–020 | Existing Blocking baseline plus adjacent NFC, native usage, screen/notification and plan-editor combinations |
| 3 | EXP-004/007/009/010/019/020 | Transfer to Coach scrolling, capture date drafts, streak, correlations and Planner state; final checks |

## Results

Initial ADB sandbox startup fails; outside the sandbox ADB starts and lists no
physical device. An isolated read-only/no-snapshot AVD was started. The default
Android Studio Java 25 is incompatible with the pinned Gradle; the already
installed Java 21 is used instead. These are tooling findings, not product bugs.

Confirmed new EXP-004/005/013 transfer: open Focus Abandon or Emergency release,
background/resume while the dialog remains open, then receive another canonical
active session or leave the read pending. Confirming previously targets the new
session (or operates while revalidation is pending). Four deterministic widget
cases fail on the actual page/controller path; no timing sleeps or live account.
The confirmation is now bound to the opening session ID and must see a successful,
idle current read before issuing the existing command. Count this as one bug
group shared by the two dialogs. Red log: `focus-confirmation-red.log`.

Confirmed new EXP-004/006 transfer: leave a rating editor open while a foreground
history read is pending, then save a changed rating or delete it. Complete that
read with its old snapshot. Both deterministic controller cases restore the old
visible reflection before the fix, despite the durable source being correct.
The controller now preserves per-session mutations newer than the read, including
deletions, while merging unaffected rows. Fresh later reads remain authoritative;
failed reads still report incomplete availability. This is one second bug group,
not separate save/delete bugs. Red log: `reflection-race-red.log`.

Both groups have narrow production changes and permanent regressions. Added
counterexamples cover an ended session, read failure, a valid same-session
confirmation, unaffected ratings and a later update from another device.
No database, backend, native policy, dependency, navigation design or persistence
format changed. Existing faster Focus foreground display remains intact.

### Coverage and transfer evidence

| Categories | Actual checks and outcome |
| --- | --- |
| EXP-001/002 | Native status/permission and Flutter plan colors, unavailable access, retained targets; no new confirmed defect |
| EXP-003/004 | Deferred catalog and stale responses; confirmed transfer to Focus dialogs and reflection history |
| EXP-005/006 | Pending saves, revisions, deleted plans; Focus save/delete and obsolete confirmation regressions |
| EXP-007/008 | App/site selected-first ordering, rapid selections, viewport anchors and package/domain icon identity |
| EXP-009/010/011 | Nested scroll dismissal, horizontal sections, 120 tab changes, reorder handle and preserved drafts |
| EXP-012/013/014 | Discipline intent, timer policy, background/shade separation, NFC request/cancellation/recovery policies; physical NFC not exercised |
| EXP-015 | Existing browser-neutralization and app Return-loop native regressions; no new installed browser claim |
| EXP-016/017/018 | Native usage sequences plus actual emulator foreground measurements, shade/Home/sleep/wake, permissions, rebind and delayed reboot checks |
| EXP-019 | Streak 48-hour inclusive boundary, DST/local days, sleep, Focus duration and scheduled authority |
| EXP-020 | Four-theme/narrow/large-text controls, retained source data, Coach follow/scroll and Capture retry/date tests |

The final full Flutter run covers the existing Coach, Capture, Planner and
Insights tests as well as the new Focus regressions. The separate deterministic
Insights probe uses seed `20261105 + trial`, eight source sizes, four windows and
with/without a sparse Focus source. Its 64 cases contain 320 invalid-value,
duplicate-day and shuffled-input variants, with an independent expected paired
count. No extra product change was needed. Probe source/log remain in the ignored
run directory (`correlation_probe_test.dart`, `correlation-transfer.log`).

### Emulator evidence and limits

Isolated `Pixel_10_Pro`, `emulator-5582`, read-only/no-snapshot; no physical phone.
The installed debug QA build predates this turn's Dart Focus edits and bypasses
login into Blocking. Android/Blocking production source is unchanged. Thus it
tests the existing Blocking native paths, **not the new Focus UI or a signed APK**.

Three measured 20-second foreground intervals produce 19,924 / 20,082 / 20,110 ms.
Usage Access revoke/restore, Accessibility rebind while the target stays open,
explicit notification dismissal and fresh-visit reappearance pass. Thirty-two
shade/Home/revisit cycles, including sixteen screen sleep/wake cycles, pass.
These use real emulator events, a synthetic probe app and native notifications.

Reboot exceeds the harness's 100-second boot limit. Android later boots with its
boot counter incremented; the MyLifeGraph service is running before opening the
app. A notification appears after the probe launch (4.92 seconds). The initial
screenshot shows a System UI ANR, so notification-manager assertions alone are
not treated as visual acceptance. Once System UI recovers, a separate real UI
read/capture confirms `MLG QA`, `Remaining`, the live countdown and `Plan · Games`.
Evidence: `emulator-reboot.log`, `emulator-postboot.log`,
`reboot-system-ui-anr.png`, `budget-after-recovered-ui.xml/.png`.

An additional unresolved observation: after this emulator reboot Android's own
usage event inventory no longer includes the preceding QA visits. Its remaining
QA total is 70.501 seconds, matching MyLifeGraph's native `usedMs` (Android's
formatted summary rounds it to 01:10). There is no demonstrated reducer loss
relative to the available source; the platform/history-retention cause is not
established. Do not claim preserved whole-day accounting across reboot from this
run. A Samsung before/after-reboot comparison with an exact version and system
usage events is still needed. Evidence: `postboot-usage-events.txt` and
`native-postboot-status.log`. This is not counted as a confirmed new app bug.

The final direct editor check reaches the real installed-app-list consent and
then the Rules editor with its saved 45-minute synthetic plan. Further gesture
acceptance is inconclusive: selected-tab state does not establish the requested
transition and the UI probe intermittently reports `No root`. The app process
remains alive and no crash/Flutter error is logged. This is not counted as a
passed installed gesture test or a confirmed app defect. Existing current-source
gesture widget regressions pass in the complete Flutter suite.

### Verification and non-product failures

Exact current counts are recorded in the Verification owner. Logs include
`focus-expanded.log`, `flutter-final.log`, `native-fresh.log`, `native-app.log`,
`backend-selected-elevated.log`, `analyze.log`, and `affected.log`.
No persistent test fixture or golden tolerance was weakened.

- The first broad run overlapped a newly authored test with a mistyped helper
  reference. That test-authoring error was corrected; a later command also named
  a nonexistent domain-test filename and was corrected. Neither is an app bug.
- Six existing Windows component golden comparisons remain failing; current
  master/test images were inspected. Their source/themes are unchanged by this
  task, and the references were not regenerated to make the gate pass.
- The broader dependency-owned Gradle suite fails twelve DataStore rename cases
  inside `shared_preferences_android`. Fresh app-owned tests and app lint pass.
  No dependency patch, upgrade or filesystem bypass was attempted.
- Restricted SDK/cache/Python access required local test escalation. The affected
  dry-run selects Full due to existing unrelated retention edits and untracked
  media. No database reset, browser E2E, full release gate or live provider turn
  is claimed.

Documentation consistency passes (19 checker tests), visual-source policy passes
(one checker test), and diff hygiene passes. Final working-tree review preserves
all pre-existing retention changes and leaves the index untouched.

## Final state

Two new independent bug groups, both fixed locally. No other confirmed new
product bug remains open. Emulator usage-history retention is an unconfirmed
platform/device question; physical Samsung, NFC chips, OEM energy management,
live Coach/provider behavior and cold-process Focus restoration remain gaps.
No commit, push, PR, APK publication, VPS/Vercel or database mutation. Unrelated
retention work remains untouched. Closing documentation, visual policy and diff
checks pass. The isolated emulator was stopped and the empty ADB inventory
confirmed. Source and log hashes are recorded in the local `evidence.json`.
Logs and temporary fixtures: `.tools/experience-20261105/`.
