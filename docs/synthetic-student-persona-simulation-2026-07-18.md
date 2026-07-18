# Synthetic Student Persona Simulation — 2026-07-18

## Evidence status

This was a five-agent, source-backed persona walkthrough requested after the
real five-student study was deliberately skipped. It is **not** a usability
study, participant observation, longitudinal trial, or evidence of retention,
adherence, accessibility on installed devices, or learning benefit. Zero
students participated and no participant results, quotes, completion rates, or
SUS scores are claimed.

The baseline was commit `41673e98f4c495d20ae3371ba3e88c613a0d8d4e` on
`new_backend_gh`. Five independent agent roles inspected the repository,
contracts, flows, and focused tests. Because the execution environment allowed
four concurrent slots including the coordinating agent, P1–P3 ran first and
P4–P5 ran in a second wave. Agents made no edits; every code-backed report was
reproduced and classified by the coordinating review before a change was made.

`Day 0`, `Day 1`, and `Week 1/2/4/6/8` below are compressed scenario
checkpoints. Two months did not actually elapse. The agents did not preserve a
live app installation for eight weeks or experience human hesitation, memory,
fatigue, motivation, travel, assistive technology, or network conditions.

## Personas and checkpoints

| Code | Synthetic perspective | Main pressure cases |
| --- | --- | --- |
| P1 | First-year student with low planning confidence | First Setup, effort estimate, 320 px/200% text, near exam, missed block |
| P2 | Working student with a dense calendar and two deadlines | Per-plan workload, manual `.ics` freshness, Berlin/New York travel |
| P3 | Methodical master's student with an eight-week assignment | Prior preparation, linked Focus, replanning, concurrent devices, large history |
| P4 | Student using a small phone and accessibility settings | Keyboard, screen reader hypotheses, reduced motion, unstable network, reloads |
| P5 | Student using English as an additional language | Terminology, UTC/device changes, preview/rule/AI/example provenance |

Every persona followed the same compressed checkpoints: first account and
Setup at Day 0; Today, check-in, Quick actions, and Focus at Day 1; first
preparation plan and Calendar use at Week 1; tracked and prior work at Week 2;
Insights and Weekly review at Week 4; missed work, replanning, and response loss
at Week 6; and multiple plans, history, timezone, and capability-truth review at
Week 8.

## Classification rule

- **A — reproducible defect:** source, contract, or automated behavior proved a
  mismatch. These defects were fixed and regression-tested in this change.
- **B — code-backed product risk or hypothesis:** the behavior exists, but its
  usability impact or preferred product response needs human or product
  judgment. Small truthfulness improvements were made where they did not alter
  authority.
- **C — human/device evidence required:** an agent cannot establish the claim.
  These remain manual checks and are not converted into findings.

## Findings by severity

### Critical

No reproducible critical defect was found. This is not proof that no critical
issue exists outside the inspected local boundary.

### High — fixed

1. **A: bounded planner reads could silently stop at 1,000 rows.** The
   repository requested limits up to 10,001, but local PostgREST caps a response
   at 1,000. Long Focus history could disagree forever with the database, and
   schedule, confirmed-block, or imported-busy context could be incomplete.
   Stable ordered paging now reads in at-most-1,000-row pages and preserves the
   existing overflow sentinels and V1 bounds.
2. **A: terminal task history could displace every open task on Today.** One
   deadline-null-first query limited all task states to 100 before the UI split
   them. One hundred completed no-deadline rows could therefore hide an open
   future assignment. Today now loads bounded open and terminal projections
   separately.

### Major — fixed

1. **A: the prior-work question contradicted actual Focus eligibility.** The UI
   told students not to enter work already recorded as Focus, while the backend
   credits only completed Focus linked to the managed plan task and started
   after first activation. Earlier or differently linked Focus could be lost if
   the student followed the text. The editor now asks for preparation the plan
   will not credit automatically and names both cases explicitly.
2. **A: a new synced profile could accept UTC without acknowledgement.** UTC is
   a deliberate neutral database default, but it controls local dates,
   rule-based planning, briefings, reviews, and budgets. The first authenticated
   Setup save now requires an explicit `Keep UTC` or `Review in Settings`
   choice. Guest Setup and later Setup edits are unchanged.

### Moderate — fixed or clarified

1. **A: Weekly review disappeared from Today after Monday.** The account-only
   entry is now persistent; the review itself still selects the latest completed
   profile-local ISO week.
2. **A: an active missed-block warning disappeared while a replacement preview
   was pending.** The active reservations and warning now remain visible until
   confirmation replaces them.
3. **A: an uncredited block was still `upcoming` exactly at `ends_at`.** Public
   state now follows the half-open interval and becomes `missed` at the exact end
   instant.
4. **A: deterministic content carried blanket AI wording.** Daily briefings now
   visibly say `Rule-based · not AI-written`; stored Insight rows are called
   notes rather than all being called AI notes. `Home`/`Focus session` launcher
   labels were aligned with the canonical `Today`/`Focus` names.
5. **B: planning inputs were technically available but not sufficiently
   legible.** The surface now exposes the fixed ordered energy windows, states
   that estimate chips are optional and not an app estimate, labels the daily
   cap as per-plan, and says imported busy periods come from the latest manually
   imported file with no background sync.
6. **B: Insights `Planned load` sounded historical.** Replanning or completing a
   plan changes the active projection. The metric is now named `Current planned
   workload`; no historical fact or narrower confirmed-plan claim was invented.

### Remaining code-backed risks and hypotheses

1. **B: aggregate daily preparation is not account-capped.** Each plan enforces
   its own daily cap and avoids exact overlaps with confirmed blocks from other
   plans, but two plans can together exceed either individual cap. The UI and
   contract now say per-plan. An account-wide optimization policy would be a
   product change and was not added without evidence.
2. **B: a newly added commitment does not silently invalidate or replan an
   already active plan.** This preserves explicit mutation authority, but a
   student must deliberately review/replan after availability changes.
3. **B: calendar freshness has no age badge.** The planner uses the latest
   completed file import, not live provider state. The copy now says to
   re-import, but whether an age warning improves behavior needs observation.
4. **B: Today still uses device-local `DateTime.now()` in parts of its Flutter
   presentation while backend reviews/plans use the profile timezone.** The UTC
   confirmation removes the silent first-run default; real travel and
   near-midnight behavior still needs device testing before a broader date
   architecture change.
5. **B: unsubmitted editor drafts survive in-session retry paths but not a hard
   browser/app reload.** Adding durable draft persistence changes privacy and
   lifecycle behavior and was not inferred from a synthetic walkthrough.
6. **B: multi-device changes rely on explicit reload/conflict handling rather
   than realtime updates.** Exact request replay and optimistic conflicts remain
   the authority; no hidden background reconciliation was added.
7. **B/C: custom shell animation, chart equivalence, loading semantics, and some
   fixed-row layouts merit installed-device review with reduced motion,
   VoiceOver/TalkBack, keyboard-only use, and OS-level 200% text.** Existing
   widget coverage did not reproduce a new overflow in the inspected paths, but
   headless tests are not device acceptance evidence.

## Calculation assessment

Deadline Planner V1 remains suitable as transparent deterministic V1 logic:

```text
remaining = max(0, user estimate - entered prior credit
                   - eligible completed linked Focus)
```

Eligible Focus is owner-scoped, completed, linked to the stable managed task,
and started no earlier than first activation. Blocks use five-minute boundaries,
the selected session length, a per-plan daily cap, the captured current instant,
fixed commitments, other confirmed reservations, and optionally the latest
manual imported-busy projection. The first pass spreads sessions across the
runway; later passes fill remaining viable days. Clear days are hard, blocks do
not pass the aware deadline, unsafe DST wall intervals are skipped, and an
unfitted remainder stays visible as `unscheduled_minutes`.

Focus credit fills blocks chronologically as an accounting projection; it is
not proof that the student worked during a particular reservation. The revised
labels say credited rather than implying observed execution. The rules are
inspectable and every authoritative input remains user-accepted. An LLM could
explain them or offer a separately accepted estimate suggestion, but it has no
calculation, scheduling, confirmation, replanning, or mutation authority.

## Changes and regression coverage

- Added stable planner-context pagination and the exact block-end boundary.
- Separated open Today tasks from bounded terminal history.
- Corrected prior-credit, energy-window, per-plan-cap, calendar-snapshot, block
  credit, and pending-missed-state communication.
- Added first-Setup UTC confirmation and Settings timezone consequences.
- Kept Weekly review discoverable and aligned canonical surface names.
- Corrected Daily Briefing and Insights provenance/temporal labels.
- Updated the planner, architecture, and UI-copy contracts with matching tests.

## Verification results

All results below are from this local checkout on 2026-07-18 after the fixes:

- Changed-area regression set: `63` Flutter tests passed.
- Focused Deadline Planner backend set: `14 passed`.
- Browser source syntax: `node --check e2e/web/smoke.mjs` passed.
- Standard gate: migration-safety and hermetic stack tests passed, Flutter
  analysis reported no issues, all `591` Flutter tests passed, Python
  application sources compiled, and `git diff --check` passed.
- Complete FastAPI suite: `748 passed, 1 skipped`.
- Non-reset local Supabase verification: migration history matched the
  repository and all `591` Flutter tests passed with local configuration.
- Full non-reset Flutter/FastAPI/Supabase browser journey:
  `E2E browser smoke passed for e2e-1784413991@example.test`.

These are local current-checkout results. They do not turn the synthetic
personas into participant evidence or establish remote, deployed, provider,
installed-device, or long-term behavior.

## Manual evidence still required

1. If product usability evidence is wanted later, run the prepared real
   five-student moderated study. This synthetic run does not count toward its
   five participants.
2. Test physical phones and desktop browsers with OS-level 200% text,
   keyboard-only input, VoiceOver/TalkBack, reduced motion, and real offline/
   reconnect transitions.
3. Exercise travel, profile/device timezone disagreement, midnight, DST, two
   concurrent devices, several active plans, and newly added commitments over
   real elapsed time.
4. Observe actual students over months before claiming retention, adherence,
   wellbeing, or learning outcomes.
5. Verify remote migrations, deployment, provider calendar/OAuth, external
   email, scheduler operation, push/background notification delivery, and a
   production Coach provider separately if they enter scope.

There is no new evidence here for remote migration state, push/background
notifications, a production Coach provider, German localization, or long-term
learning success.
