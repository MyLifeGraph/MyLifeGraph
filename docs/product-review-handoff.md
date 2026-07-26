# Product Review Handoff

Status: current whole-product review entry point for the checkout containing
this document, updated through Today Overview V2, Planner V1, Study Setup V1,
the Coach-enabled shell navigation, Setup personalization retirement, Daily
Capture V4, and Exam-Week Outlook V1 on 2026-07-26.

## Objective

Review MyLifeGraph as a student would experience it from first Setup through
repeated daily use, planning, execution, recovery, reflection, and account
control. Test the implemented boundaries before proposing another feature. Fix
proved defects in the smallest owning contract; do not redesign the product or
introduce model authority by default.

## Current Product Slice

The current checkout combines these implemented loops:

1. Revision-safe Setup requires only Typical weekday and Best energy window,
   with optional name, routines/Habits, fixed commitments, and Study Setup.
   Goals and retired personalization answers are absent; Reminder settings are
   independently owned by Settings. Study Setup may define focus/recovery
   rhythm, a transient start checklist, and current/next semester facts.
2. Evening Shutdown persists an explicit personal sleep plan; Morning
   Calibration persists corrected estimated sleep instants and their derived
   duration under Daily Capture V4. Deterministic Daily State classifies
   freshness and capacity without an LLM or raw sleep-clock propagation.
3. Today Overview V2 is a read-only projection with a strict both-capture
   streak, transparent progress, Setup/Planner/Preparation/Calendar/Focus
   timeline facts, selected Tasks/Habits, and isolated partial failures.
4. Quick actions owns capture, Habit completion, and Focus. Focus has a durable
   single-session lifecycle and may credit a linked open Task without completing
   it automatically.
5. Planner V1 is the authenticated planning home. Task and Habit changes use
   immutable previews and explicit confirmation; fixed commitments are
   authoritative; exam/assignment creation delegates to Deadline Planner. An
   active exam may add the read-only 14-/7-day sleep-capacity outlook before
   ordinary attention.
6. Deadline Planner uses the student's estimate and prior credit to stage dated
   preparation blocks. Confirmation alone activates the plan and managed Task.
   Study rhythm adds recovery reservations without counting recovery as study.
7. Insights, Weekly Review, Inbox lifecycle, foreground-only notification
   delivery, optional `.ics` import, account controls, and the bounded
   development Coach retain their separate contracts and authority limits.
8. With the development Coach gate enabled, Coach is the fifth shell
   destination. Settings remains available from Today; a disabled gate does not
   restore a redundant Settings shell item.

## Important Truth Boundaries

- Guest/demo stays local and must not call authenticated product APIs.
- Normal Today and Planner reads are side-effect free. Preview, generation,
  confirmation, delivery acknowledgement, and lifecycle mutation remain
  separate deliberate commands.
- Rule-based state, rankings, reviews, plan blocks, focus suggestions, recovery
  reservations, semester attention, and reminder copy do not require an LLM.
- Coach cannot mutate product data. Its local Codex adapter is development-only,
  per-machine, explicitly enabled, and separate from standard fake-provider
  automation.
- Imported calendar events are consented, read-only product copies. The app has
  no live provider OAuth, source-calendar write, hidden sync, or automatic move.
- Notifications are stored Inbox rows and acknowledged foreground banners while
  the app is open. They are not push, system, email, or background delivery.
- Setup semester dates and Study rhythm invalidate or mark affected staged plans
  honestly; they never silently rewrite active reservations.
- Setup edits never change Reminder consent/categories/quiet hours/daily cap.
  Evening Capture stores no primary/additional friction, and Goals have no
  active product surface or evaluation role.
- Exam-Week Outlook is a Planner-only read. It does not create a preview,
  change an active plan, add a Today item, or generate a Notification. Raw
  sleep instants remain in `daily_logs.metadata`.
- English is the only supported V1 interface language.
- The prepared five-student study has not been run. Synthetic personas and test
  automation are not participant or longitudinal evidence.

## Review Questions

- Can a new student understand Setup, optional Study Setup, Today, Quick
  actions, Planner, Focus, Preparation plans, Weekly Review, Inbox, and Coach?
- Can Setup be completed with only weekday/energy, and can it be edited without
  changing independently personalized Reminder settings?
- Can the student distinguish a preview from a confirmed mutation everywhere?
- Do Planner and Deadline Planner agree on Setup commitments, manual
  commitments, imported busy time, preparation reservations, recovery time,
  semester bounds, daily capacity, and stale fingerprints?
- Does Exam-Week Outlook activate only from exams, count competing assignments,
  preserve at least one warning buffer day, distinguish unknown capacity, and
  leave every revision untouched?
- Are Task/Habit lifecycle release, Focus credit, missed-work recovery, and
  replanning consistent across Flutter, FastAPI, and PostgreSQL?
- Do retries preserve exact request identity without duplicating targets,
  revisions, blocks, outcomes, notifications, or Coach turns?
- Can one owner read or mutate another owner's data, or bypass backend-owned
  mutation through direct application DML?
- Are loading, empty, stale, offline, invalid-data, ambiguous-save, small-screen,
  and large-text states usable and honest?
- Is any proposed LLM feature replacing a transparent deterministic rule without
  evidence that the tradeoff is worthwhile?

## Required Reading And Verification

Read `AGENTS.md` first and follow its complete document routing. For a current
whole-product review, the minimum set includes:

- `README.md`
- `docs/architecture.md`
- `docs/backend-roadmap.md`
- `docs/daily-briefing-implementation-plan.md`
- `docs/today-overview-v1-contract.md`
- `docs/planner-v1-contract.md`
- `docs/study-setup-v1-contract.md`
- `docs/deadline-planner-v1-contract.md`
- `docs/exam-week-outlook-v1-contract.md`
- `docs/setup-personalization-retirement-contract.md`
- `docs/phase-3-executable-actions-contract.md`
- `docs/phase-8-weekly-review-contract.md`
- `docs/phase-9-calendar-import-contract.md`
- `docs/phase-10-controlled-coach-plan.md`
- both notification contracts, the account-control contract, the UI-copy
  contract, `docs/supabase-current-state.md`, and `docs/verification.md`

Inspect the branch, latest commit, complete working-tree diff, and untracked
files without discarding user work. Run focused tests first, then the standard
non-destructive source gate:

```bash
FLUTTER_BIN=/home/gregor/tools/flutter/bin/flutter scripts/verify.sh
```

Follow `docs/verification.md` for local migration/advisor checks and browser
E2E. A database reset is appropriate only for a deliberately disposable local
test database. Do not infer permission to touch a remote database, deploy,
push, or run a live model.

## Evidence Boundary

Verification counts in dated contract sections belong to their recorded
checkout. Exact current results live only in
[Current Verified Baseline](verification.md#current-verified-baseline). That
local deterministic evidence is not remote, installed-device, live-provider,
clinical, longitudinal, deployed, or participant evidence. Record a new commit,
exact commands, counts, and environment in `docs/verification.md` before calling
any later checkout fully verified.

## Prompt For A New Review Chat

```text
Work in /home/gregor/projects/ai-personal-coach. Read AGENTS.md completely and
every document it requires for the files you may touch, then read
docs/product-review-handoff.md completely. Inspect the branch, latest commit,
full diff, and untracked files without discarding anything.

Act as a critical product, UX, Flutter, FastAPI, and PostgreSQL reviewer. Walk
the current product from revision-safe Setup and optional Study Setup through
Today V2, Quick actions, Planner, Focus, Deadline preparation, recovery,
Insights, Weekly Review, Inbox, Calendar, Coach, and account controls. Verify
calculation, authority, retry, RLS, capability-truth, small-screen, large-text,
and ambiguous-failure boundaries. Prefer small compatible fixes over redesign.

Run focused tests and the non-destructive source gate. Run the full local
browser journey only under the explicit local-data conditions in
docs/verification.md. Fix proved in-scope defects with regression tests and
update the owning contract when behavior changes. Do not fabricate participant
evidence, live-provider results, remote state, push/background delivery,
deployed scheduling, or localization. Do not deploy, push, or open a PR unless
explicitly requested.

Finish with findings ordered by severity, exact fixes, verification results,
the reviewed commit id, and remaining manual or external validation.
```
