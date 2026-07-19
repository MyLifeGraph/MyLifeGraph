# Product Review Handoff

Status: review entry point for the checkout containing this document.

## Objective

Review the implemented product as a student would experience it from first
Setup through several months of use. Re-evaluate the usability and calculation
choices, inspect the complete exam/assignment Preparation Plans contract, and
test all recent changes before proposing another feature. Fix proved defects in
the smallest owning contract; do not redesign the whole project by default.

## What The Current Slice Implements

The checkout combines Deadline Planner V1 with seven product-polish groups:

1. Evening check-in is a short two-step capture with optional detail and honest
   save recovery.
2. Today is decision-first and keeps secondary information compact.
3. Insights exposes data sufficiency and sources; correlations require shared
   observations rather than personalized-looking filler.
4. Focus has a real countdown, explicit finish/abandon behavior, and
   deterministic duration suggestions based on current state and the selected
   target.
5. Missed preparation work has an explicit recovery/replan path.
6. Unproved promises are absent or constrained: no real-account Skillset card,
   foreground-only in-app reminder copy, hard production Coach gate, and
   reminder preference separate from delivery consent.
7. Primary UI copy is English, student-facing, consistent, and tested at small
   viewport/large-text boundaries. See
   `docs/ui-language-and-copy-contract.md`.

Deadline Planner V1 asks the user—not an LLM—to estimate total active study
time and enter prior completed work. It proposes dated blocks, shows the staged
revision before applying anything, activates only after explicit confirmation,
creates one stable managed task, credits completed linked Focus sessions, and
can replan remaining work. A manual deadline or one deliberately selected
imported event may seed the plan. Optional imported busy time is read-only. A
student may now set a nullable account-wide daily preparation budget in
Settings; it constrains new cross-plan reservations without rewriting existing
plans, while Today and Preparation plans expose a truthful seven-day view.
There is no title inference, source-calendar write, autonomous mutation, hidden
proposal, LLM call, push notification, or background sync. The exact ownership,
retry, fingerprint, and database rules are in
`docs/deadline-planner-v1-contract.md`.

## Important Truth Boundaries

- Guest/demo stays local and must not call authenticated product APIs.
- A normal Today read does not generate or mutate recommendations, briefings,
  or preparation plans.
- Rule-based Daily State, briefings, reviews, plan blocks, Focus suggestions,
  and reminder copy do not need an LLM. LLM output may explain a result but must
  not become calculation or mutation authority.
- The daily preparation budget is explicit student input and the workload card
  is a deterministic reservation projection. Weekly Setup commitments are shown
  separately; neither surface claims inferred free time or full imported-
  calendar coverage.
- Controlled Coach cannot mutate product data. It is hidden in production and
  release builds; local Codex is a development-only, per-machine adapter.
- Notification Delivery V1 means stored Inbox rows plus acknowledged foreground
  banners while the app is open. It is not push, system, email, background, or
  deployed delivery.
- English is the only supported interface language in V1. German localization
  remains future work and must be implemented end-to-end before being claimed.
- The five-student test is prepared in
  `docs/student-usability-test-script.md`, with its execution kit in
  `docs/student-usability-study/`, but was deliberately skipped/deferred and
  must not be presented as completed evidence. The five-agent compressed
  walkthrough in
  `docs/synthetic-student-persona-simulation-2026-07-18.md` is not a substitute
  for participants or elapsed longitudinal use.

## Review Questions

Review code and behavior, not only screenshots:

- Can a new student understand what to do next in Setup, Today, Quick actions,
  Focus, Preparation plans, Weekly review, Calendar, Inbox, and Coach?
- Does every visible action either execute a real typed command, open a real
  flow, or clearly say that it is a preview?
- Are total preparation minutes, prior credit, block allocation, busy-period
  avoidance, focus credit, progress, missed-block recovery, and deadline edge
  cases internally consistent across Flutter, FastAPI, and PostgreSQL?
- Do multiple active plans respect an optional account-wide local-date budget,
  including earlier same-day reservations and a budget change between preview
  and confirmation, without silently rewriting existing plans?
- Do retries preserve exact request identity without duplicating a plan, task,
  block, outcome, or Focus session? Do reload/conflict paths avoid overwriting
  newer state?
- Can one user read or mutate another user's plans or request ledger? Can direct
  application DML bypass backend plan authority?
- Are stale imported-event fingerprints and disconnected/deleted calendar data
  rejected before plan creation?
- Are loading, empty, offline, invalid-data, stale, failure, ambiguous-save, and
  small-screen states usable and honest?
- Would a student still find Today, Insights, Inbox, and Weekly review useful
  after months, or do any surfaces become repetitive or empty?
- Is an LLM being suggested where a transparent rule is safer, cheaper, and
  easier to test? Keep calculation authority deterministic unless evidence
  proves a model is needed.

## Required Reading And Verification

Start with `AGENTS.md` and all documents it requires. For this review, read at
minimum:

- `README.md`
- `docs/architecture.md`
- `docs/backend-roadmap.md`
- `docs/daily-briefing-implementation-plan.md`
- `docs/deadline-planner-v1-contract.md`
- `docs/ui-language-and-copy-contract.md`
- `docs/verification.md`
- the Phase 3, Phase 9, Phase 10, notification lifecycle, notification delivery,
  and account-control contracts named by `AGENTS.md`

Then inspect `git status --short --branch`, the latest commit, its complete diff,
and every untracked file. Preserve user work and never reset the checkout.

Run the standard source gate:

```bash
FLUTTER_BIN=/home/gregor/tools/flutter/bin/flutter scripts/verify.sh
```

Run exact local migration verification and the full browser journey as defined
in `docs/verification.md`. A reset is appropriate only for a deliberately
disposable local test database and must never be inferred as permission for a
remote database. Standard Coach automation uses the fake provider; do not claim
a live local-Codex result unless it was separately opted into and run on the
current machine.

## Verification Recorded For This Handoff

The local current checkout completed these checks on 2026-07-18 before its
handoff commit:

- `scripts/verify.sh`: migration/start-stack guards passed, Flutter analysis
  reported no issues, all `579` Flutter tests passed, and Python application
  sources compiled.
- Complete FastAPI suite: `745 passed, 1 skipped`.
- Local Supabase migration history matched the repository without a reset.
- Full non-reset Flutter/FastAPI/Supabase browser journey:
  `E2E browser smoke passed for e2e-1784404040@example.test`.

These are local checkout results, not evidence of remote migration state,
deployed scheduling, push/background delivery, installed-device acceptance,
long-term learning benefit, or the still-unrun five-student usability study.

The requested implementation follow-up from this handoff is recorded separately
in `docs/product-review-followup-2026-07-18.md`; the counts above remain the
historical pre-handoff results rather than being rewritten after the fact.

## Prompt For A New Chat

```text
Work in /home/gregor/projects/ai-personal-coach. First read AGENTS.md completely
and every required document for the files you may touch, then read
docs/product-review-handoff.md completely. Inspect the current branch, latest
commit, full diff, and untracked files without discarding anything.

Act as a critical product, UX, Flutter, FastAPI, and PostgreSQL reviewer. Walk
the app mentally and through tests from Setup to months of student use. Review
all seven polish groups and Deadline Planner V1, especially estimate capture,
block calculations, calendar isolation, focus credit, missed-work replanning,
retry identity, RLS, capability truth, small screens, and ambiguous failures.
Check whether any LLM addition would actually improve the product without
making calculation or mutation authority opaque. Prefer small compatible fixes
over a broad redesign.

Run focused tests while reviewing, then the repository verification and full
local browser E2E from docs/verification.md. Fix every proved in-scope defect
with a regression test and update contract/docs when behavior changes. Do not
fabricate the five-student usability study, a live provider result, push or
background delivery, deployed scheduling, remote database state, or German
localization. Do not reset user work, access remote systems, deploy, push, or
open a PR unless explicitly requested.

Finish with concrete findings ordered by severity, exact fixes, test results,
the reviewed commit id, and the remaining manual/external validation items.
```
