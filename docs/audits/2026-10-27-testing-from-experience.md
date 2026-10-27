# Experience-based test run — 2026-10-27

Project: MyLifeGraph Flutter. Task base
`309d66be7ffecb9f0b32b46c41b67f0022b1680c`.
Scope: approved plan status colors, diagnosis of Scheduled during a daily budget,
and 35 minutes of experience-based regression testing. Local changes only.
Catalog: [stable experience catalog](../testing/experience-catalog.md).

## Preflight work note

Selected owners: Android Focus Protection (Named Blocking Plans V2, plan authority,
status/usage/permission, native lifecycle and unlock compatibility); Phase 3
Executable Actions (unchanged Focus lease boundary); mobile README (Blocking
surface); UI language/copy (unchanged status vocabulary); Frontend Visual System
V2 (theme-owned semantic status accents); Verification (local gates and evidence
limits). Adjacent Flutter/native tests and channel interfaces inspected before
editing. Unrelated pre-existing retention source/docs and local media are preserved.

The approved design changes colors only: native tracking green, effective blocking
red, paused/expired/scheduled neutral. It must not infer native status from remaining
minutes, change enforcement, remove features, or alter storage/wire shape.

## Timing and execution

Preflight started 2026-10-27 00:18:01 Europe/Berlin (23:18:01 UTC previous date).
Initial color implementation and its targeted verification finished at 00:22:12
Europe/Berlin (23:22:12 UTC previous date). The requested 35-minute regression
window started then. The final evidence review ended at **00:57:09 Europe/Berlin**
(23:57:09 UTC previous date): **34 minutes 57 seconds**, approximately the requested
35 minutes. Preflight/initial implementation is outside that interval. No idle
waits were used to fill it; execution, new variants, inspection and reporting
continued throughout. Final bookkeeping checks follow without more test waves.

Planned waves: status decoding/rendering and permission truth; editor and gesture
regressions; native tracking/notification/unlock/time policies; transferred variants,
cross-theme captures and final source/docs checks. Category mapping EXP-001–020.

## Results

Confirmed new independent product bug groups: **0**. Locally fixed new product
bug groups: **0**. Confirmed-open product bug groups: **0**. The approved status
color change is a requested presentation change, not a newly discovered bug.
The personal Samsung Games report remains unconfirmed; its device state was not
available. Exact test totals and commands are centralized in
[Verification](../verification.md#current-verified-baseline).

### Waves and transferred variants

| Wave | Categories | Current production-path checks | Result / boundary |
| --- | --- | --- | --- |
| Initial status | EXP-001–002 | Existing UX regressions plus production MethodChannel decoding/rendering; four themes and enlarged text; remaining/exhausted, paused, missing access and mixed OR rules | Approved colors pass; no invented status from remaining minutes |
| Broad Flutter baseline | EXP-003–014, EXP-020 | Entire current Flutter suite: catalog latency, late replies, revision guards, save locks, target ordering/icons, editor swipes/dismissal, drag, Discipline/NFC cancel and lifecycle | Functional suite passes; unchanged component goldens have the known Windows discrepancies; not called a green full run |
| Native mechanisms | EXP-012–019 | App-module JVM tests and Lint; seeded chronological foreground oracle, budget threshold matrix and independent circular-week schedule oracle | Passes; no Samsung/OEM/NFC hardware delivery claim |
| Actual virtual Android | EXP-001–002, EXP-016–018 | Current guest/mock debug build on isolated read-only Pixel API37.1; real native status/capability, actual usage, exhausted limit and notification-shade cycle | Expected native flags; notification stays through shade open/close and clears on Home |
| Transferred races / visuals | EXP-004, EXP-020 | Failed status preserves valid Tracking then recovers; obsolete delayed Tracking reply cannot overwrite newer Active refresh; inspected actual Glass/Light/large-text renders | Passes; no new product bug |

### Games / Scheduled diagnosis

The actual Android experiment uses synthetic QA data only. With native protection,
Accessibility, effective targets and Usage Access available, Games returns
`tracking=true`, `active=false` with measured usage. With master protection off,
both flags are false **but previously observed day usage remains**. With usage
denied, no Tracking is promised and measured usage is unavailable. Restoring
access returns Tracking; reducing the QA budget below actually used time returns
`active=true`, `tracking=false`. These native values are checked independently
from the Flutter rendering tests.

Thus the reported appearance is reproducible when protection is actually disabled,
without a native calculation defect. That is one possible explanation, not proof
of the state on the user's Samsung. No wrong Scheduled state under verified
working native tracking was reproduced; no tracking/enforcement logic was changed.

The first instrumentation attempt lacked a stable enabled service during the
test process lifecycle and therefore correctly returned no Tracking. The controlled
matrix explicitly retains Accessibility during instrumentation and waits for
binding. This harness setup issue is not counted as a product bug.

### Environment and coverage limits

ADB had no physical device. The known QA AVD was started headless/read-only,
without snapshot load/save, and stopped after the experiments. Only its disposable
copy received synthetic plans/permissions. The original AVD and private accounts
were not changed. The normal guest entry and required local Setup were traversed;
the app correctly requires a synced account for its normal Blocking entry. The
Android experiment therefore exercises native status/notification authority via
QA instrumentation, not authenticated full-app Blocking acceptance.

The installed Studio Java25 could not execute the pinned Gradle setup. A temporary
official Java21 download was checksum-verified and used for tests/debug build only;
no project SDK/dependency was upgraded. An initial new test incorrectly required
different status words to have equal heights at 200% text; that test assumption
was corrected without changing the existing wrapping behavior. Static analysis
also found one missing brace in the new test, corrected locally.

The broad affected selector includes pre-existing unrelated retention edits/media
and selects Full. Its Windows source prerequisite is missing `setsid`, its backend
cannot find `python3`, and its Flutter branch retains the same Windows golden
failures. Final focused status tests and analysis pass; no successful
full/Linux/DB/browser gate is claimed. No remote DB, provider, deployment or
production account was changed. Six unchanged component-reference golden failures
are preserved rather than rewriting expected images.

## Local delivery

Actual before/after Flutter-widget captures, plus Light and enlarged-text checks,
are in `.tools/blocking-status-20261026/implemented.html`. The native matrix,
assertion script, notification evidence and command logs are in the same ignored
folder. No images in this implementation gallery are generated mockups.
The before/after pixel check confirms unchanged content and unchanged pixels
outside the three recolored cards. Names, rules, remaining time and target counts
inside those cards are also unchanged. Large-text wrapping is the existing
behavior, not a new design adjustment.
No commit, push, PR, APK publication or deployment is part of this local task.
The debug APK is a guest/mock QA build, not an installable release recommendation.
