# Agent Instructions

These instructions are for coding agents working in this repository. They are
repo-local and must not depend on private skills, secrets, or machine-specific
profile configuration.

Read this file before changing code, schema, scripts, tests, or documentation.
Then follow the owning documents below. Current product inventories and exact
verification evidence deliberately live outside this file so these instructions
remain stable.

## Required Starting Documents

Read these for every repository change:

1. `README.md` for the repository and product overview.
2. `docs/local-dev.md` for supported local workflows and environment setup.
3. `docs/architecture.md` for system boundaries and dependency direction.
4. `docs/verification.md` before running, changing, or claiming verification.
5. `docs/current-contracts.json` for the scoped, machine-checked cross-runtime
   version registry, exact code selectors, and owning documents.

Read the additional owner before touching its area:

- Backend, AI, onboarding, or agent workflow direction:
  `docs/backend-roadmap.md`.
- The next product slice, Daily Capture, recommendation ranking, or dashboard
  decision loops: `docs/daily-briefing-implementation-plan.md`.
- Supabase schema, Auth, RLS, grants, RPCs, data sources, or migrations:
  `docs/supabase-current-state.md`.
- Local Supabase backup, reset, restore, destructive confirmation, or
  disposable migration-test isolation: `docs/local-database-safety.md`.
- Executable Tasks, Habits, Focus, or briefing action consumption:
  `docs/phase-3-executable-actions-contract.md`.
- Weekly Review facts, freshness, proposals, or confirmed Habit adaptation:
  `docs/phase-8-weekly-review-contract.md`.
- Calendar consent, `.ics` parsing, imported identity, disconnect, or deletion:
  `docs/phase-9-calendar-import-contract.md`.
- Coach routes, providers, context, memory, persistence, budgets, tools, local
  Codex, or safety: `docs/phase-10-controlled-coach-plan.md`.
- Inbox read/unread/dismiss and retry authority:
  `docs/notification-lifecycle-v1-contract.md`.
- Notification consent, generation, quiet hours, caps, local scheduling, or
  delivery provenance: `docs/notification-delivery-v1-contract.md`.
- Password recovery, timezone, export, or permanent account deletion:
  `docs/v1-account-controls-contract.md`.
- Deadline Planner estimates, revisions, reservations, managed Tasks, calendar
  availability, or tracked Focus: `docs/deadline-planner-v1-contract.md`.
- Daily Capture sleep planning or the Planner Exam-Week Outlook:
  `docs/exam-week-outlook-v1-contract.md`.
- Retired Setup goals/personalization, Daily State compatibility, Coach
  context, or Reminder ownership:
  `docs/setup-personalization-retirement-contract.md`.
- Student-facing names, capability claims, retry copy, localization, or
  large-text behavior: `docs/ui-language-and-copy-contract.md`.
- Today streak, progress, timeline, selection, or supporting sections:
  `docs/today-overview-v1-contract.md`.
- Planner navigation, availability, Action Plans, commitments, calendar busy
  time, or Today Overview: `docs/planner-v1-contract.md`.
- Study Setup focus rhythm, recovery, semester planning, or course-selection
  attention: `docs/study-setup-v1-contract.md`.
- Focus reflections, learning preferences, personal patterns, shared sleep
  parsing, learned timing, or recommendation cleanup:
  `docs/personal-learning-v1-contract.md`.
- Flutter theme, typography, icons, surfaces, motion, assets, or presentation
  styling: `docs/frontend-visual-system-v2.md`.
- Daily Capture write authority, revisioned settings, timezone-bound planning,
  observed projections, or post-mutation reload state:
  `docs/stabilization-consistency-contract.md`.
- Android Accessibility blocking, DND, local Focus leases, device-only settings,
  or protection reconciliation:
  `docs/android-focus-protection-v1-contract.md`.
- A fresh whole-product Deadline Planner/usability review:
  `docs/product-review-handoff.md`.

`docs/current-product-guide.md` is the concise current user-facing product
guide. Feature contracts remain authoritative when its summary is less precise.

## Stable Architecture And Safety Boundaries

MyLifeGraph is a Flutter web/mobile client backed by Supabase Auth/Postgres and
an authenticated FastAPI service. New application code uses the canonical
snake_case schema. The complete current table and migration inventory belongs
only in `docs/supabase-current-state.md`.

Preserve these boundaries unless an explicitly scoped contract change says
otherwise:

- Historical migrations are immutable. Add a migration for schema changes;
  never rewrite an applied migration to make a new checkout look clean.
- RLS, explicit grants, forced-RLS modes, service-role-only RPCs, advisory lock
  order, retry identities, and append-only usage/audit rows are security and
  concurrency boundaries.
- FastAPI derives owner identity from the verified bearer principal. Never
  accept a client-supplied owner id as mutation authority.
- The Flutter app may use only a publishable/anon Supabase key. Service-role
  credentials and scheduler tokens remain backend-only.
- Guest/mock mode stays local and makes zero authenticated product calls. A
  failed or empty real-account read must not silently become demo data.
- Read paths stay side-effect free unless their owning contract explicitly
  defines a deliberate generation command.
- Persisted wire formats, compatibility branches, public HTTP problems, retry
  semantics, and student-facing truth claims are contracts, not cleanup detail.
- Cross-feature Flutter imports may use application/domain seams, not another
  feature's private `data` or `presentation` internals.
- Do not claim remote deployment, provider freshness, installed-device
  behavior, push/background delivery, model availability, or live migration
  state from repository source alone.
- Dependency or SDK upgrades are separate compatibility work and must not be
  folded into an unrelated refactor.

`docs/current-contracts.json` tracks every current version declared through
named constants in both Flutter and FastAPI, plus the explicit single-runtime
or literal-based exceptions recorded there. It is a synchronization registry,
not a replacement for the complete wire formats in feature contracts. New
cross-runtime versions must use named constants in both runtimes and be added to
the registry with `coverage: shared_named`; existing deliberate exceptions use
`coverage: explicit`. Each source entry identifies the exact symbol or locator
that the documentation checker reads; when a tracked version changes, update
its code sources, metadata entry, and every listed owner in the same change.

## Documentation Ownership

Documentation is part of the Definition of Done. Before changing behavior,
identify the owning contract or runbook and update it with the implementation.

At minimum, keep these owners aligned:

- Schema, RLS, grants, RPCs, migration inventory, or reset boundary:
  `docs/supabase-current-state.md`.
- FastAPI/Flutter data flow or authority: `docs/architecture.md` and the owning
  feature contract.
- Public FastAPI route or payload: `services/ai_service/README.md` and the
  owning feature contract/client documentation.
- Flutter navigation, persistence, surface behavior, or copy:
  `apps/mobile/README.md` and the owning feature/copy contracts.
- Local environment, commands, or setup: `docs/local-dev.md`.
- Agent workflow or safety: this file.
- Verification automation or evidence: `docs/verification.md`.
- Scoped cross-runtime version synchronization and owner routing:
  `docs/current-contracts.json`.

Adding a Supabase migration normally updates
`docs/supabase-current-state.md`, `docs/verification.md`, and the affected
feature owner. Update this file only when the stable agent workflow or a safety
boundary itself changes; a new migration filename alone does not belong here.

`docs/verification.md#current-verified-baseline` is the sole current source for
exact test counts, commit ids, E2E identities, and checkout evidence. Other
current documents link to it instead of copying those values. A dated report may
retain checkout-local evidence only when its opening metadata explicitly says
`Status: historical`; that evidence never proves the current checkout.

Before handoff:

1. Review code, schema, scripts, tests, and docs together for documentation
   impact.
2. Update compatibility language, examples, non-claims, and owner routing.
3. Run `npm run verify:docs` plus the relevant product checks.
4. Run `git diff --check` and inspect both staged and unstaged changes.

The docs-impact checker compares the working tree with `HEAD` by default.
GitHub supplies `DOCS_BASE_REF`; use the same variable for a manual committed
branch audit.

## Supabase Workflow Safety

Use the repository scripts documented in `docs/local-dev.md` and
`docs/verification.md`. The normal local database verification is:

```bash
scripts/verify_supabase_local.sh
```

The default path inspects migration history and fails closed on a mismatch. It
must not apply SQL, reset the database, or infer remote state. After reviewing
pending SQL and affected local rows, `APPLY_MIGRATIONS=true` is the explicit
opt-in for applying repository migrations. A pending migration may change or
delete local data.

Normal verification, local-stack, and E2E scripts have no reset authority and
must reject `RESET_DB=true`. Never run a raw `supabase db reset`, use reset with
`--db-url`/`--linked`, or create a destructive test target inside the normal
local Postgres cluster. If the user explicitly requests a local reset, follow
the two-phase `npm run db:reset:local` workflow in
`docs/local-database-safety.md`: preview the exact target, obtain the fresh
content-bound confirmation token, create and restore-verify the automatic full
backup, recheck target drift, and only then allow the wrapper's exact
`supabase db reset --local` invocation. A reset is a separate destructive
operation, never ordinary verification setup.

Use `npm run db:backup:local` for a full local archive. A backup counts as
verified only after its restore succeeds in the physically separate RAM-only
Postgres container. Do not restore an archive into the normal local database
without a new explicit user-approved recovery operation. Remove any external
persistent command approval for broad `supabase db reset`; repository guards
cannot revoke approvals stored by the caller environment.

Before using a Supabase CLI command, inspect its installed help rather than
guessing flags. Do not install replacement Node, Flutter, Docker, or Supabase
binaries inside the repository because an agent shell has a different `PATH`.
Use the actual installed tools or a narrow caller-supplied override.

Do not assume the live project matches local migrations. Inspect the remote
project through an authorized dashboard, CLI, or connector before making a
remote-state claim. Never paste, log, or commit Supabase keys.

## Local Application Workflow

Use `.env.example` as the shape for local configuration and keep `.env`
untracked. Supported start commands and loopback URLs are maintained in
`docs/local-dev.md`; prefer repository scripts over ad hoc process stacks.

For the normal local stack:

```bash
npm run start:local
```

The stack must keep service-role and scheduler credentials out of Flutter,
browser output, logs, status files, and command arguments. Ordinary automation
uses the deterministic fake Coach provider. A real local Codex provider is an
explicit machine/account-specific check and never a prerequisite for standard
verification.

## Verification

Choose checks according to the changed boundary; see `docs/verification.md`
for the current matrix and evidence.

Common non-destructive commands from the repository root are:

```bash
npm run verify:docs
npm run verify:fast
npm run verify:affected
scripts/verify.sh
git diff --check
```

Set `FLUTTER_BIN` in the caller environment when Flutter is not on `PATH`; do
not hard-code a workstation path in source or repository instructions.

Run `npm run verify:db` only when local Supabase verification is relevant. Run
browser suites only when the affected boundary and local prerequisites justify
them. Test source being present is not evidence that a command passed.

## Environment And Secrets

Treat `.env` and all local credential stores as secret material:

- Do not print or commit `.env` contents.
- Do not copy keys, bearer tokens, scheduler tokens, or database passwords into
  docs, fixtures, commands shown in chat, or client code.
- Pass required values through existing scripts or the process environment.
- Local anon keys belong only in local client configuration; service-role keys
  never belong in Flutter.
- Never read, print, copy, parse, commit, or move local Codex OAuth state such
  as `~/.codex/auth.json`. A sanitized login/capability status command is the
  maximum routine inspection.
- Any Codex subprocess receives an allowlisted environment that excludes
  Supabase and application secrets.

## Working Tree And Delivery Safety

The working tree may contain user changes. Before broad edits, inspect branch,
`HEAD`, status, staged/unstaged diffs, and untracked files. Preserve unrelated
work and never silently include it in a commit.

Do not use destructive Git commands to clean a worktree. Package managers may
change lockfiles; review and report those changes instead of discarding them.

Do not push, deploy, open a pull request, change remote state, or broaden a task
without explicit authorization. A requested implementation normally authorizes
the scoped local code, tests, documentation, and commit workflow only.
