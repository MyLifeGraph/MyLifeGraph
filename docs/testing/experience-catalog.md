# MyLifeGraph experience-based regression catalog

Project: MyLifeGraph Flutter. Updated 2026-10-27.
Current run: [2026-10-27](../audits/2026-10-27-testing-from-experience.md).

This catalog records mechanisms, not a count of current bugs. Historical evidence
comes from the existing regression tests, owning contracts, dated verification
entries and user reports in the current task history. Independent historical
case counts are unknown; repeated reports are not counted as separate cases.
The external examples in the skill are test ideas, not evidence about this app.

## Categories and invariants

| ID | Mechanism and historical evidence | Required behavior / new variants | Other plausible seams | Current check |
| --- | --- | --- | --- | --- |
| EXP-001 | Ambiguous status colors/labels; current Games report and Blocking UX tests | Native Tracking means remaining budget; Active means blocking; never infer working protection from an enabled flag | Plans, daily allowance, combined OR rules | 2026-10-27; see run evidence |
| EXP-002 | Missing/revoked capability presented as usable; Blocking consent regressions | Native master, Accessibility, usage and effective-target gates remain authoritative; no fabricated green state | Web-only plans, essential apps, revoked usage | 2026-10-27; see run evidence |
| EXP-003 | Slow catalog blocks opening; RC38 verified reproduction | Open editor while catalog is pending; Rules/name/sites remain usable | First Add, repeated Edit, Retry | 2026-10-27; see run evidence |
| EXP-004 | Late asynchronous completion belongs to obsolete visit; stress/page tests | Closed/replaced editor and older refresh responses cannot overwrite current state | Catalog, status, insights refresh | 2026-10-27; see run evidence |
| EXP-005 | Editing/dismissal during pending Save; Blocking picker/stress tests | Freeze inputs, prevent duplicate writes and retain drafts after failure | Keyboard, Back, scrim, pull-dismiss | 2026-10-27; see run evidence |
| EXP-006 | Stale revision or deleted ID resurrects definitions; page/stress tests | Preserve opening revision; fail stale saves, do not recreate a removed plan | Detail-to-edit, catalog latency, menu actions | 2026-10-27; see run evidence |
| EXP-007 | Selected targets fail to reorder or viewport jumps; target-list regressions | Current selections first, deselection restores source order, visible anchor stays stable | App/site lists, category presets, search | 2026-10-27; see run evidence |
| EXP-008 | Icons follow list indices rather than identity; target-icon tests | Package/domain image follows stable identity; corrupt/missing icon has safe fallback | Picker and usage Insights | 2026-10-27; see run evidence |
| EXP-009 | Mid-scroll reversal dismisses modal; RC38 gesture regressions | Only fresh vertical pull starting at top can dismiss; saving blocks it | Plan editor, Customize | 2026-10-27; see run evidence |
| EXP-010 | Horizontal swipe conflicts with nested/focused controls; root pager/section tests | Existing pager owns intended tab swipes, preserves drafts/independent offsets | Rules/Apps/Websites, Content/Style/Delay | 2026-10-27; see run evidence |
| EXP-011 | Reorder interferes with scrolling/refresh or rule authority; plans/reorder tests | Handle-only 500ms arm, stable ID permutation and rollback on rejected write | Long/offscreen lists, locked mode | 2026-10-27; see run evidence |
| EXP-012 | Unlock starts too early, wrong intent or extra completion; Strict request tests | Explicit choice starts wait; temporary/permanent intent stays bound; native completion only | Zero wait, unmet conditions, rapid taps | 2026-10-27; see run evidence |
| EXP-013 | Lifecycle resets/finishes wrong timer; Strict visibility/session regressions | Stay policy applies only when configured; route/app leave differs from notification shade | Tab switch, Back, background, resumed request | 2026-10-27; see run evidence |
| EXP-014 | NFC duplicate scan/cancel/replacement corrupts flow; NFC policy/request tests | Consume one request, require removal where applicable, cancellation retains locked idle state | Lost chip, eight-chip replacement, failed scan | 2026-10-27; see run evidence |
| EXP-015 | Returning reopens blocked app/browser loop; RC34 native regressions | App Return goes Home; denied tab neutralization cannot release rules or affect other tab/package | Browser adapters, stale window identity | 2026-10-27; see run evidence |
| EXP-016 | Notification shade mistaken for app exit; foreground/budget policy regressions | Shade open/close retains same visit notification; actual exit clears it; deliberate dismissal stays dismissed | Foreign windows, System UI, overlapping activities | 2026-10-27; see run evidence |
| EXP-017 | Usage intervals lost/double-counted; usage sequence/reducer regressions | Nonnegative bounded union of real foreground intervals; stale pause cannot erase current app | Same-package activities, day boundary, other blocker | 2026-10-27; see run evidence |
| EXP-018 | Service rebind/reboot loses foreground; RC30 recovery tests | Recover only eligible foreground observation; denied access never fabricates tracking | Startup, rebind, screen off, stale observation | 2026-10-27; see run evidence |
| EXP-019 | Time boundary/DST/expired plan mislabel; plan summary/timer tests | Exclusive end, overnight start-day and actual elapsed time; expired differs from future schedule | Daily reset, weekly boundary, shared budgets | 2026-10-27; see run evidence |
| EXP-020 | Layout/refresh hides control or discards valid data; polish/pull-refresh tests | Four themes, narrow/large text, reachable Save/error/Retry; failed refresh preserves prior data | Short pages, Customize, Insights | 2026-10-27; see run evidence |

## Transfer limits

### Current run evidence — 2026-10-27

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
