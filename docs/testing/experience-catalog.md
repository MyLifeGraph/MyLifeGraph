# MyLifeGraph experience-based regression catalog

Project: MyLifeGraph Flutter. Updated 2026-10-29.
Current run: [2026-10-29 18:37 continuation](../audits/2026-10-29-1837-testing-from-experience.md).

This catalog records mechanisms, not a count of current bugs. Historical evidence
comes from the existing regression tests, owning contracts, dated verification
entries and user reports in the current task history. Independent historical
case counts are unknown; repeated reports are not counted as separate cases.
The external examples in the skill are test ideas, not evidence about this app.

## Categories and invariants

| ID | Mechanism and historical evidence | Required behavior / new variants | Other plausible seams | Current check |
| --- | --- | --- | --- | --- |
| EXP-001 | Ambiguous status colors/labels; current Games report and Blocking UX tests | Native Tracking means remaining budget; Active means blocking; never infer working protection from an enabled flag | Plans, daily allowance, combined OR rules | 2026-10-29; see run evidence |
| EXP-002 | Missing/revoked capability presented as usable; Blocking consent regressions | Native master, Accessibility, usage and effective-target gates remain authoritative; no fabricated green state | Web-only plans, essential apps, revoked usage | 2026-10-29; see run evidence |
| EXP-003 | Slow catalog blocks opening; RC38 verified reproduction | Open editor while catalog is pending; Rules/name/sites remain usable | First Add, repeated Edit, Retry | 2026-10-29; see run evidence |
| EXP-004 | Late asynchronous completion belongs to obsolete visit; stress/page tests | Closed/replaced editor and older refresh responses cannot overwrite current state | Catalog, status, insights refresh | 2026-10-29; see run evidence |
| EXP-005 | Editing/dismissal during pending Save; Blocking picker/stress tests | Freeze inputs, prevent duplicate writes and retain drafts after failure | Keyboard, Back, scrim, pull-dismiss | 2026-10-29; see run evidence |
| EXP-006 | Stale revision or deleted ID resurrects definitions; page/stress tests | Preserve opening revision; fail stale saves, do not recreate a removed plan | Detail-to-edit, catalog latency, menu actions | 2026-10-29; see run evidence |
| EXP-007 | Selected targets fail to reorder or viewport jumps; target-list regressions | Current selections first, deselection restores source order, visible anchor stays stable | App/site lists, category presets, search | 2026-10-29; see run evidence |
| EXP-008 | Icons follow list indices rather than identity; target-icon tests | Package/domain image follows stable identity; corrupt/missing icon has safe fallback | Picker and usage Insights | 2026-10-29; see run evidence |
| EXP-009 | Mid-scroll reversal dismisses modal; RC38 gesture regressions | Only fresh vertical pull starting at top can dismiss; saving blocks it | Plan editor, Customize | 2026-10-29; see run evidence |
| EXP-010 | Horizontal swipe conflicts with nested/focused controls; root pager/section tests | Existing pager owns intended tab swipes, preserves drafts/independent offsets | Rules/Apps/Websites, Content/Style/Delay | 2026-10-29; see run evidence |
| EXP-011 | Reorder interferes with scrolling/refresh or rule authority; plans/reorder tests | Handle-only 500ms arm, stable ID permutation and rollback on rejected write | Long/offscreen lists, locked mode | 2026-10-29; see run evidence |
| EXP-012 | Unlock starts too early, wrong intent or extra completion; Strict request tests | Explicit choice starts wait; temporary/permanent intent stays bound; native completion only | Zero wait, unmet conditions, rapid taps | 2026-10-29; see run evidence |
| EXP-013 | Lifecycle resets/finishes wrong timer; Strict visibility/session regressions | Stay policy applies only when configured; route/app leave differs from notification shade | Tab switch, Back, background, resumed request | 2026-10-29; see run evidence |
| EXP-014 | NFC duplicate scan/cancel/replacement corrupts flow; NFC policy/request tests | Consume one request, require removal where applicable, cancellation retains locked idle state | Lost chip, eight-chip replacement, failed scan | 2026-10-29; see run evidence |
| EXP-015 | Returning reopens blocked app/browser loop; RC34 native regressions | App Return goes Home; denied tab neutralization cannot release rules or affect other tab/package | Browser adapters, stale window identity | 2026-10-29; see run evidence |
| EXP-016 | Notification shade mistaken for app exit; foreground/budget policy regressions | Shade open/close retains same visit notification; actual exit clears it; deliberate dismissal stays dismissed | Foreign windows, System UI, overlapping activities | 2026-10-29; see run evidence |
| EXP-017 | Usage intervals lost/double-counted; usage sequence/reducer regressions | Nonnegative bounded union of real foreground intervals; stale pause cannot erase current app | Same-package activities, day boundary, other blocker | 2026-10-29; see run evidence |
| EXP-018 | Service rebind/reboot loses foreground; RC30 recovery tests | Recover only eligible foreground observation; denied access never fabricates tracking | Startup, rebind, screen off, stale observation | 2026-10-29; see run evidence |
| EXP-019 | Time boundary/DST/expired plan mislabel; plan summary/timer tests | Exclusive end, overnight start-day and actual elapsed time; expired differs from future schedule | Daily reset, weekly boundary, shared budgets | 2026-10-29; see run evidence |
| EXP-020 | Layout/refresh hides control or discards valid data; polish/pull-refresh tests | Four themes, narrow/large text, reachable Save/error/Retry; failed refresh preserves prior data | Short pages, Customize, Insights | 2026-10-29; see run evidence |

## Transfer limits

### Current continuation evidence — 2026-10-29 18:37

The Android emulator now boots with a host GPU in a read-only/no-snapshot copy.
EXP-016–018 were expanded to actual notification-shade/Home/sleep/wake events,
Usage Access revocation, Accessibility rebind, timed foreground intervals and a
real reboot. Startup recovery is delayed and is not claimed instantaneous.
Physical Samsung/OEM behavior and NFC hardware remain unverified.

EXP-015 transfer found a distinct website-recognition cause: Chrome's known
unfocused address-bar node appends `. Connection is not secure` to the visible
host in the tested English configuration. Strict URI parsing rejects that value.
An actual failed interception and a failing deterministic JVM test confirm it.
The narrow parser strips only that observed Chrome suffix before normal domain
validation; saved-domain input, search text and other browsers retain their
existing parsing. Native unit rechecks pass; final installed recheck is recorded
in the continuation audit. Other localized annotations are not claimed covered.

EXP-007/009/010/011 also have actual native UI evidence: selected targets reorder
without moving neighboring visible rows, deselected sites regain their original
position, reverse scrolling keeps the sheet open, section swipes preserve edits,
and handle drag changes plan order without changing rule payloads. Customize
keyboard Save/reopen and delayed native Return are checked as EXP-005/015/020
variants. An early Home press leaves the countdown overlay; ready Return exits
the denied target without a loop.

EXP-012/013 actual acceptance covers automatic permanent unlock in the background,
automatic temporary unlock, shade preservation, tab-reset, Stay focused
cancellation, and locked-policy immutability. Temporary-release persistence also
survives sleep/wake. Full fifteen-minute device expiry and physical NFC remain
outside the timed run. Use a UI reader that preserves Accessibility services;
`uiautomator dump` suppressing the service is a tooling effect, not an app defect.

Two new seeded picker sequences and two keyboard/late-Coach-reply variants pass.
They transfer anchoring, cancellation and stale-completion checks without
introducing additional product changes. Exact final results belong to the
Verification owner and the linked continuation audit.

### Earlier run evidence — 2026-10-29

EXP-007/020 transfer: selection anchoring followed by a shorter search result
set exposed stale bottom slack. Reproduced with 25 and 250 targets; reset the
temporary spacer when source result IDs/order change.

EXP-007/004 transfer: two actual row taps before layout picked a row already
moving from the first selection as anchor, jumping the viewport to the top.
Track all pending moving IDs until the latest layout callback. Apps and Websites
share this widget; these are two independent causes, not separate bugs per list.
Both fixes pass their regression and adjacent editor/icon checks.

All twenty categories were exercised by current Flutter and native test runs.
Additional transfer checks cover shuffled check-in input, Coach scroll/follow,
calendar status, streak grace and sleep boundaries. Actual synthetic-widget
renderings were inspected. No installed Samsung, physical NFC, real notification
shade, live Coach or production data claim follows from these tests. The isolated
emulator did not complete boot. Exact counts and final gate state belong to
`docs/verification.md`; execution details and remaining gaps are in the run audit.

### Historical run evidence — 2026-10-27

All twenty categories were exercised through the broad Flutter run, native
regressions and selected transferred variants described in the linked audit.
Color/status channel races, usage/budget/window oracles and actual virtual
Android status/shade behavior were specifically expanded. No newly confirmed
product bug was found. The approved red/green presentation is local only.
The whole Flutter run retains the known Windows component-golden discrepancies;
the broad affected gate is not green on this Windows environment. Exact counts,
commands and the final checked state belong to the current Verification owner.

These are historical regression categories, not twenty newly confirmed bugs.
The current specific cause of Games showing Scheduled is unconfirmed until a
real production-path mismatch is reproduced. Mock channel data proves decoding
and presentation, not installed Android permission/service state. Native JVM
policy tests do not prove Samsung/OEM or hardware NFC behavior. See the run
report for actual executions and unresolved coverage.
