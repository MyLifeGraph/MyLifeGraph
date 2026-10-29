# Experience-based test continuation — 2026-10-29 18:37

Status: historical run record; current verification authority is
`docs/verification.md`. In-progress evidence never proves a later checkout.

Task: continue local experience-based testing until 20:10 Europe/Berlin.
Start: 2026-10-29 17:37:04 UTC (18:37:04 CET). Deadline: 19:10 UTC.
Base: `8805ab6867f84fbfedeb5cc246c4a8bf89751efd` plus the existing local fixes.
Verified execution/shutdown end: 2026-10-29 19:09:13 UTC (20:09:13 CET),
1h32m09s after start; final documentation handoff follows within the stop limit.
One newly confirmed bug group
is fixed; the two picker fixes from the earlier run are not counted again.
Catalog: [experience catalog](../testing/experience-catalog.md).

## Preflight and owners

Read AGENTS.md, skill/report template, previous audit and twenty-category catalog;
Verification Android/current-baseline gates; Android Focus Protection plan/editor,
usage and Discipline boundaries; Phase 3 Focus authority; product guide; visual
and copy owners; local-dev SDK instructions. Existing mobile owner guidance from
the preceding run remains applicable. Additional owners are loaded before wider
feature changes. No live data, remote services, personal device state or release
actions. Preserve all pre-existing changes, especially release-retention files.

## Planned waves

| Wave | Categories | New question |
| --- | --- | --- |
| 1 | EXP-003–010, 020 | Selection/search/disposal combinations beyond the preceding two fixed cases; isolate analyzer tooling failure |
| 2 | EXP-001, 002, 011–019 | Native rule/foreground/notification/Discipline event combinations and device feasibility |
| 3 | EXP-004–006, 009, 010, 019, 020 | Transfer stale completion, cancellation and time-boundary mechanisms to adjacent surfaces; final bounded verification |

No identical green suite repetition merely to consume time. New cases or changed
code justify each retest. Physical-device limitations are reported separately.

## Results

First wave: two deterministic mixed target-list scenarios pass, each with fifty
selections/scroll positions, fixed or variable row heights, actual rapid taps,
empty search replacement and disposal before a queued layout callback. These are
new variants of EXP-004/007/008/009; no additional functional defect reproduced.

The previous analyzer failure was isolated by giving only that process a fresh
LOCALAPPDATA beneath the ignored run directory. Analysis now reports normally.
It found an unnecessary non-null assertion introduced by the prior fix; removed
it without changing runtime behavior. Do not count this warning as a new product
bug. The isolated analyzer confirmation reports no issues.

Additional owners loaded: Planner optional-Habit/retry/overview/navigation
invariants and Deadline Planner source/credit/series/calendar-time boundaries.
The fake-repository Planner/Deadline service/model group passes. No service,
schema, planning policy or clock authority is changed.

Unlike the prior software-renderer attempt, the read-only/no-snapshot emulator
boots successfully using host GPU. A run-local debug instrumentation harness
extends the earlier synthetic status fixture with repeated shade/Home/sleep/wake
transitions. A fresh debug build is installed only in that isolated Android 17/API 37 emulator. The native five-case status matrix passes. Shade/Home/sleep/wake sequences pass eight diagnostic and then thirty-two stress cycles. An earlier single Home-clear timeout remains unconfirmed and is not a product bug claim.

Coach owner scroll/follow and Personal Learning boundaries were additionally read. Two mobile keyboard/late-reply cases pass: following stays at the bottom, manual reading position survives reply completion and keyboard dismissal, and the arrow reaches the final extent. Repository/provider responses are controlled local fakes.

Native app-return stress exposed a detection delay beyond the original 2.5-second assertion in one cycle. The timing-instrumented repeat passes ten launches/returns, including one 4.702-second detection. This agrees with the documented five-second UsageStats cache/recovery fallback; it does not prove permanent lost detection. No native change was made.

The real Android continuity fixture measured three twenty-second foreground intervals as 19.843, 19.914 and 20.024 seconds. Revoking/restoring Usage Access, disconnecting/rebinding Accessibility while the target remains open, explicit notification dismissal, shade changes after dismissal and the next visit all pass. These are actual emulator OS events; notification dismissal invokes the native delete Intent, not a physical finger gesture.

An actual emulator reboot passes (boot counter 2 to 3). The service is initially pending rather than running; the timer appears without opening MyLifeGraph, 14.77 seconds after opening the test target, then survives shade close and clears on Home. Boot startup is therefore not claimed instantaneous. The first screenshot was black/transitional and is not visual pass evidence.

Additional read-only owners: Today source-projection invariants, Phase 3 terminal Focus, Weekly Review period/read/write separation and Setup guest isolation. Twenty-six fake-repository Focus/Review/shared-read tests pass. Actual guest Setup was completed in the read-only emulator copy only; its gated App-Blocking entry remains unavailable by design. A separate ignored native/widget test entry is prepared without Auth or backend. The underlying AVD has a device account; Chrome stays signed out, and no account data is used for testing.

Confirmed new EXP-015 variant: real Chrome exposes `qa-blocked.invalid. Connection is not secure` from its allowlisted unfocused URL bar. The native strict URI parser returns null, so the configured domain is not intercepted. Captured actual browser failure and a deterministic JVM regression: expected host, actual null. Only that new regression fails; adjacent malformed/search/domain-entry checks pass. Selected change owners: Android Focus Protection website-observation/neutralization/privacy boundaries, mobile README and verification; no new permissions, wire fields, remote calls or domain rule semantics.

The narrow Chrome-only normalization also applies to recognizing completed
`about:blank` navigation. Actual Chrome exposes the identical annotation there,
otherwise completion waits for the bounded timeout even after navigation. This
is the same address representation cause, not a second bug group. An initial
installed recheck inspected after a fixed short wait and expected an unannotated
label; the independent harness now waits for a nonediting neutral address and
accepts the two observed exact labels. The product still has its original
bounded navigation timeout and does not inspect page content.

Minimal reproduction: enable a website-only rule for `qa-blocked.invalid`, grant
website observation and Accessibility, then visit that host in English Chrome
with the address bar unfocused and visible. On this Android/Chrome combination,
the observed node text includes the security annotation. Before the fix the
parsed host is null and no website interception occurs; after it the configured
host is intercepted and Return leaves the tab at `about:blank`. Do not add a
whole-Chrome app rule to this reproduction: that would mask domain recognition.
The deterministic regression class is `BlockingBrowserAddressTest`; the initial
red test result is preserved separately from the final green native XML output.

Final Dart analysis passes with process-local analyzer storage. The complete
Flutter run passes all functional cases and retains the six known Windows
golden differences, with exactly the preceding pixel counts. Native unit checks
pass; lint initially reports two generated local SDK-property escape errors.
These local properties are corrected without weakening lint. Flutter CLI also
selected an incompatible machine JDK despite JAVA_HOME; the direct documented
Gradle/Java-21 path builds successfully. These are local-tooling findings, not
product bugs or dependency upgrades.

The final native JVM/lint/debug-build group passes. Installed Chrome then passes
three configured-domain interceptions, Return/reopen to the nonediting local
blank page, an allowed-host visit, and three app Return cycles. Final plan and
Discipline state are unchanged. Reopen observations take approximately half a
second in this fixture; this is not a universal device performance guarantee.

Actual Android UI checks additionally cover first catalog consent, selecting
Chrome, selecting Gmail mid-list with unchanged neighboring Files/Drive bounds,
reverse scrolling without dismissing the editor, horizontal section swipes,
Save/reopen, website consent, website selection/deselection restoring original
order, category changes, and the native Customize preview. Icon/accent edits,
Content/Style/Delay swipes, expanded preview, inert preview Return and saving a
three-second delay pass. Fixtures remain in the emulator; no user account writes.

Tooling caveat: `uiautomator dump` suppresses accessibility services while
inspecting the tree, leaving the fixture service disconnected. Its resulting
unavailable-capability UI is not a product failure. The later UI reader targets
its own QA package and explicitly uses
`FLAG_DONT_SUPPRESS_ACCESSIBILITY_SERVICES`; an independent OS snapshot confirms
the service remains bound and the crashed-services set is empty. Discipline
acceptance uses that reader, not the interfering one.

Discipline UI/native acceptance: with the default background policy, an actual
three-minute permanent unlock completes while the app is on Home. The persisted
flag is already off before reopening the app, with no temporary-release record.
With Stay on screen enabled while off and a thirty-second wait configured, shade
expand/collapse preserves the countdown (thirty to nineteen seconds), while a
tab switch clears the request and retains the lock. Stay focused independently
cancels the request. Attempting to change the stay policy while Discipline is on
leaves the setting unchanged. These checks use the actual Flutter controls and
Android persistence; `discipline-native-proof.jsonl` contains only allowlisted
synthetic-state fields, not account credentials or NFC identifiers.

## Final checks and handoff

Three-plan actual handle drag changes only the ID order. Per-plan payload hashes
remain identical through reorder, pull-refresh and an unsaved edit cancellation.
Keyboard editing keeps Customize Save accessible; saving and reopening retains
the edited title. The native block overlay uses that title, icon and accent.
With a saved three-second delay, Home while the timer is still at one second
leaves the overlay visible; Return after expiry reaches a safe destination
without reopening the denied app. A second Customize keyboard edit is cancelled;
both the restored preview and reopened input retain the previously saved title,
with the unsaved marker absent. These captures are actual emulator output,
not generated mockups (`ui-journey.jsonl` and named PNG/XML pairs).
Tree and PNG capture are sequential: the one-second remaining tree can therefore
be followed by a screenshot already showing the ready Return button. Timing
claims use the tree/event sequence, not an assumed atomic image/tree snapshot.

A thirty-second request automatically grants the selected fifteen-minute
temporary unlock. Screen sleep/wake retains the same persisted release deadline.
The entire fifteen-minute expiry is not claimed as device-tested in this run;
its deadline falls just beyond the user's stop time. Unit boundary coverage is
separate evidence. NFC hardware, Samsung/OEM startup and power policies, live
Coach/Auth/database integration and other browser languages remain unverified.

One new independent product bug group was reproduced, fixed and rechecked:
Chrome's annotated address representation, including neutral-page completion.
No confirmed product bug is left open from this continuation. The earlier
unconfirmed Home-clear timeout and tooling failures are not counted as bugs.
The prior run's two picker fixes remain in the candidate and passed again in
the broader suite. Exact final counts and gate status belong to
`docs/verification.md`; six pre-existing Windows goldens still prevent a fully
green Flutter gate. Their references were not replaced.

Code, new regression tests and owners were reviewed together. No schema, wire
format, provider, plan rule, Discipline policy or permissions changed, so their
existing contracts remain accurate. Browser address handling is documented in
its feature owner and mobile README. Unrelated release-retention changes and
pre-existing untracked outputs remain untouched. Work stays local: no commit,
push, pull request, signed release or deployment.

The last debug APK uses the ignored direct BlockingPage test entry. It must not
be distributed as the normal app. A later authorized release must rebuild the
normal production entry with the standard release configuration and signing.

Documentation consistency passes after these audit updates; the visual contract
and whitespace check also pass. The affected selector was a dry-run with the
captured task base and selected the broad gate because of the complete dirty
checkout. No full-gate or release-readiness claim follows from that selection.

The final evidence cross-check confirms native XML totals, unchanged per-plan
payload hashes across reorder/cancel, and absence of the unsaved Customize
marker after cancellation/reopening. A local SHA-256 evidence manifest is saved
as `.tools/experience-20261029-1837/handoff-evidence-sha256.json`.

### Category-to-evidence cross-check

| Categories | Executed evidence, not only source inspection |
| --- | --- |
| EXP-001/002 | Flutter status/consent suites; native five-case capability/status matrix and actual red Active/green Tracking screen |
| EXP-003–006 | Flutter editor/catalog, stress/revision, admission and Save-error suites; new seeded disposal sequence; native Save/cancel/reopen |
| EXP-007/008 | Target list/icon suites, two generated fifty-step sequences, actual app/site reorder and viewport checks |
| EXP-009/010 | Customize/editor route and section suites; actual reverse scroll and horizontal section swipes |
| EXP-011 | Reorder suite plus native three-plan long-hold drag, refresh and unchanged payload proof |
| EXP-012/013 | Native intent/settings/screen-session tests plus actual background unlock, shade, tab reset, cancellation and temporary unlock |
| EXP-014 | Native NFC/recovery-policy and Flutter Strict suites; no physical chip claim |
| EXP-015 | Red/green Chrome address regression, installed denied/neutral/allowed transitions and app/delayed Return |
| EXP-016–018 | Native usage/foreign-window/recovery suites, real shade/Home/sleep/rebind/permission/reboot sequences |
| EXP-019/020 | Weekly/budget/time and Flutter summary/layout suites; actual Customize keyboard, preview and retained data; six known Windows goldens remain failing |

Adjacent mechanism transfers cover fake-repository Planner/Deadline/Focus/Review,
Coach keyboard/late replies and the preceding source-order correlation tests.
No additional product bug was reproduced in those transferred cases.

At 19:09:13 UTC the final documentation check passed and `adb devices` confirmed
that the isolated emulator had stopped. It was closed with `emu kill` from its
read-only/no-snapshot launch; no user device or original AVD snapshot was changed.
The local candidate source hashes are recorded in
`.tools/experience-20261029-1837/candidate-source-sha256.json` for the next handoff.
The final documentation log is `docs-closeout.log`; no tests or builds are left
running by this audit. The work ends before the requested 20:10 CET cutoff.
