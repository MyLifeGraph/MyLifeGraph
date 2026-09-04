# Agent Instructions

These repository-local instructions apply to every coding agent working in this
repository. They must not depend on private skills, secrets, or machine-specific
profile configuration.

Read this file completely before changing code, schema, scripts, tests, or
documentation. This is the only repository document that is always required.
Load the task-specific context selected below before the first edit.

## Context Preflight

Before the first change:

1. Inspect the target paths, adjacent tests, imports, and public interfaces
   read-only.
2. Identify every affected product and system boundary.
3. Read every owner selected by the routing table and conditional triggers
   below. A task spanning multiple boundaries requires all corresponding owners.
4. Write a short work note naming the selected owners before editing.
5. If later inspection reveals another boundary, pause edits and load its owner
   before continuing.

For an unclear boundary, first search `docs/` and
`docs/current-contracts.json` with `rg` for the feature, route, contract, or
version name. If that search leaves no clear owner set because it finds no
owner or several plausible authorities, read `docs/architecture.md`. If
ownership remains ambiguous after those checks, ask the user before changing
code, tests, or documentation.

## Conditional Context

| Trigger | Read before acting |
| --- | --- |
| General orientation in an unfamiliar checkout | `README.md` |
| Broad or cross-product user-flow work | `docs/current-product-guide.md` |
| Tooling, startup, environment, local URLs, or configuration | `docs/local-dev.md` |
| Cross-system data flow, dependency direction, authority, or public architecture | `docs/architecture.md` |
| Selecting, running, changing, or claiming verification | `docs/verification.md` |
| Contract versions, wire shapes, public payloads, or cross-runtime compatibility | `docs/current-contracts.json` |
| Flutter navigation, persistence, or public surface behavior | `apps/mobile/README.md` |
| Public FastAPI routes or payloads | `services/ai_service/README.md` |
| Schema, Auth, RLS, grants, RPCs, data sources, or migrations | `docs/supabase-current-state.md` |
| Local database backup, reset, restore, or disposable migration-test isolation | `docs/local-database-safety.md` |

Read the applicable feature owner before changing code, tests, or documentation
inside its boundary. Presentation or student-facing copy changes additionally
load the copy and visual owners even when the feature row names another primary
contract.

## Product And Route Ownership

The paths in this table are routing signals, not permission to skip inspection.
Route names refer to modules below `services/ai_service/app/api/routes/`.

| Boundary | Flutter features / FastAPI routes | Required owners |
| --- | --- | --- |
| Daily Capture, Snapshots, Briefings, Recommendations, and Feedback | `quick_action`, `snapshots`, `briefings`, relevant `optimization`; `daily_capture.py`, `snapshots.py`, `briefings.py`, `recommendations.py`, `feedback.py`, `scheduled.py` | `docs/daily-briefing-implementation-plan.md`; add `docs/stabilization-consistency-contract.md` for Capture write authority, revision, timezone, projection, or reload behavior |
| Executable Tasks, Actions, Habits, and Focus | `tasks`, `actions`, `focus`, Habit execution inside `quick_action`; `focus.py` | `docs/phase-3-executable-actions-contract.md`; add `docs/personal-learning-v1-contract.md` for reflections or learned timing |
| Planner and Study Setup | `planner`; `planner.py` | `docs/planner-v1-contract.md`; add `docs/study-setup-v1-contract.md` for focus rhythm, recovery, semester, or course-selection behavior |
| Deadline Plans, Assignment Series, Preparation workload, and Exam Outlook | `deadline_plans`; `deadline_plans.py` | `docs/deadline-planner-v1-contract.md` and, for Capture sleep planning or outlook behavior, `docs/exam-week-outlook-v1-contract.md`; add Calendar or Study owners when those inputs are affected |
| Calendar consent, import, disconnect, and deletion | `calendar_integration`; `calendar_integrations.py` | `docs/phase-9-calendar-import-contract.md`; add `docs/stabilization-consistency-contract.md` for timezone-revision or planning-status authority |
| Insights, Personal Learning, and Recommendation cleanup | `insights`, `learning`, relevant `optimization`; `insights.py`, `learning.py`, relevant `recommendations.py`/`feedback.py` | `docs/personal-learning-v1-contract.md`; also load the Daily Briefing owner when recommendation ranking or feedback changes |
| Auth, Intake, Setup compatibility, and Account Settings | `auth`, relevant `settings`; `intake.py`, `account.py` | `docs/supabase-current-state.md`; `docs/setup-personalization-retirement-contract.md` or `docs/study-setup-v1-contract.md` for Intake/Setup; `docs/v1-account-controls-contract.md` for account controls |
| Notification lifecycle and delivery | `notifications`; `notifications.py`, notification work in `scheduled.py` | `docs/notification-lifecycle-v1-contract.md` and/or `docs/notification-delivery-v1-contract.md` according to the changed authority |
| Coach | `coach`, legacy empty `more`; `coach.py` | `docs/phase-10-controlled-coach-plan.md` |
| Weekly Review | `weekly_review`; `weekly_reviews.py` | `docs/phase-8-weekly-review-contract.md` |
| Today, app shell, dashboard, copy, and presentation | `dashboard`, `shell`, cross-feature presentation in `settings`; `today.py` | `docs/today-overview-v1-contract.md`, `docs/planner-v1-contract.md` where Planner facts appear, `docs/ui-language-and-copy-contract.md`, and `docs/frontend-visual-system-v2.md` |
| Android Focus Protection | `focus_protection` plus the synced Focus seam | `docs/android-focus-protection-v1-contract.md` and `docs/phase-3-executable-actions-contract.md` |
| Service health and route composition | `routes/__init__.py`, `health.py`, or `app/main.py` | `services/ai_service/README.md` and `docs/architecture.md` |

Backend/AI/onboarding direction also loads `docs/backend-roadmap.md`. A fresh
whole-product Deadline Planner or usability review loads
`docs/product-review-handoff.md`.

For a new or otherwise unclassified public FastAPI route, read
`services/ai_service/README.md` and `docs/architecture.md`, then establish its
feature owner before changing behavior. Do not make an unowned public route.

## Task Authority

- For analysis, review, diagnosis, explanation, or planning, inspect and report;
  do not implement unless the request also asks for a change.
- For implementation, build, or fix requests, make the in-scope local changes,
  tests, and required documentation autonomously and run relevant
  non-destructive verification.
- Ask first when completion requires unspecified product semantics, a material
  scope expansion, a new architecture or security policy, a significant
  production dependency, or an external, remote, destructive, or otherwise
  hard-to-reverse action.

## Stable Architecture And Safety Boundaries

MyLifeGraph is a Flutter web/mobile client backed by Supabase Auth/Postgres and
an authenticated FastAPI service. New application code uses the canonical
snake_case schema. The complete current table and migration inventory belongs
only in `docs/supabase-current-state.md`.

Preserve these boundaries unless an explicitly scoped contract change says
otherwise:

- Historical migrations are immutable. Add a migration for schema changes;
  never rewrite an applied migration to make a checkout look clean.
- RLS, explicit grants, forced-RLS modes, service-role-only RPCs, advisory lock
  order, retry identities, and append-only usage/audit rows are security and
  concurrency boundaries.
- FastAPI derives owner identity from the verified bearer principal. Never
  accept a client-supplied owner id as mutation authority.
- Flutter may use only a publishable/anon Supabase key. Service-role credentials
  and scheduler tokens remain backend-only.
- Guest/mock mode stays local and makes zero authenticated product calls. A
  failed or empty real-account read must not silently become demo data.
- Read paths stay side-effect free unless their owning contract explicitly
  defines a deliberate generation command.
- Persisted wire formats, compatibility branches, public HTTP problems, retry
  semantics, and student-facing truth claims are contracts.
- Cross-feature Flutter imports may use application/domain seams, not another
  feature's private `data` or `presentation` internals.
- Do not claim remote deployment, provider freshness, installed-device
  behavior, push/background delivery, model availability, or live migration
  state from repository source alone.
- Dependency or SDK upgrades are separate compatibility work and must not be
  folded into an unrelated refactor.

`docs/current-contracts.json` is the machine-checked synchronization registry,
not the complete wire-format owner. New cross-runtime versions use named
constants in Flutter and FastAPI and `coverage: shared_named`; deliberate
single-runtime or literal exceptions use `coverage: explicit`. When a tracked
version changes, update its code sources, registry entry, and every listed owner
in the same change.

## Documentation Ownership

Documentation is part of the Definition of Done. Keep these owners aligned:

- Schema, RLS, grants, RPCs, migration inventory, or reset boundary:
  `docs/supabase-current-state.md`.
- Cross-system FastAPI/Flutter data flow or authority:
  `docs/architecture.md` plus the feature owner.
- Public FastAPI route or payload: `services/ai_service/README.md` plus the
  feature owner and client documentation.
- Flutter navigation, persistence, surface behavior, or copy:
  `apps/mobile/README.md` plus the feature/copy owners.
- Local environment or commands: `docs/local-dev.md`.
- Agent workflow or safety: this file.
- Verification automation, evidence, or gaps: `docs/verification.md`.
- Cross-runtime version synchronization: `docs/current-contracts.json`.

A Supabase migration normally updates `docs/supabase-current-state.md`,
`docs/verification.md`, and its feature owner. Update this file only when the
stable workflow or safety boundary changes.

`docs/verification.md#current-verified-baseline` is the sole current source for
exact test counts, commit ids, E2E identities, and checkout evidence.
`docs/verification-history.md` is explicitly historical and never proves the
current checkout.

Before handoff, review code, schema, scripts, tests, and docs together; update
compatibility language and owner routing; run `npm run verify:docs` plus the
relevant product checks; run `git diff --check`; and inspect staged, unstaged,
and untracked changes.

## Verification Base Reference

Before the first task change, capture the task base with `git rev-parse HEAD`.
Run affected verification only as:

```bash
npm run verify:affected -- --base-ref <task-base-ref>
```

The selector deliberately fails closed without `--base-ref`. `HEAD` covers only
current working-tree changes; after task commits it omits earlier changes from
the same task. Use the commit captured before work began so committed, staged,
unstaged, and untracked task paths are classified together. GitHub supplies the
equivalent base commit to CI. The docs-impact checker itself compares
uncommitted work with `HEAD` unless `DOCS_BASE_REF` is supplied.

Read `docs/verification.md` before choosing, running, changing, or claiming a
gate. Run database or browser checks only when their affected boundary and
prerequisites justify them. Test source being present is not pass evidence.

## Supabase Workflow Safety

Use the repository workflows documented in `docs/local-dev.md`,
`docs/verification.md`, and `docs/local-database-safety.md`.

Normal local database verification is `scripts/verify_supabase_local.sh`. Its
default path inspects migration history and fails closed on a mismatch; it must
not apply SQL, reset the database, or infer remote state. After reviewing
pending SQL and affected local rows, `APPLY_MIGRATIONS=true` is the explicit
opt-in. A pending migration may change or delete local data.

Normal verification, local-stack, and E2E scripts have no reset authority and
must reject `RESET_DB=true`. Never run a raw `supabase db reset`, use reset with
`--db-url`/`--linked`, or create a destructive test target inside the normal
local Postgres cluster. If the user explicitly requests a local reset, follow
the two-phase `npm run db:reset:local` workflow in
`docs/local-database-safety.md`: preview the exact target, obtain the fresh
content-bound token, create and restore-verify the automatic full backup,
recheck target drift, and only then allow the wrapper's exact
`supabase db reset --local` invocation. A reset is a separate destructive
operation, never verification setup.

Use `npm run db:backup:local` for a full local archive. A backup counts as
verified only after restore succeeds in a physically separate RAM-only Postgres
container. Do not restore into the normal local database without a new explicit
user-approved recovery operation. Repository guards cannot revoke broad reset
approvals stored by the caller environment.

Before a Supabase CLI command, inspect its installed help instead of guessing
flags. Do not install replacement Node, Flutter, Docker, or Supabase binaries
inside the repository. Do not assume the live project matches local migrations;
inspect it through an authorized dashboard, CLI, or connector before making a
remote-state claim. Never paste, log, or commit Supabase keys.

## Local Workflow And Secrets

Treat `.env` and all local credential stores as secret material. Use
`.env.example` as the shape for local configuration and keep `.env` untracked.
Supported commands and loopback URLs live in `docs/local-dev.md`; prefer
repository scripts over ad hoc process stacks. The normal local stack is
`npm run start:local`. It must keep backend credentials out of Flutter, browser
output, logs, status files, and command arguments. Standard automation uses the
deterministic fake Coach provider; real local Codex is an explicit
machine/account-specific check.

- Do not print or commit `.env` contents.
- Do not copy keys, bearer tokens, scheduler tokens, or database passwords into
  docs, fixtures, chat commands, or client code.
- Pass required values through existing scripts or the process environment.
- Never read, print, copy, parse, commit, or move local Codex OAuth state such
  as `~/.codex/auth.json`; a sanitized login/capability status is the maximum
  routine inspection.
- Give any Codex subprocess an allowlisted environment that excludes Supabase
  and application secrets.

## Working Tree And Delivery Safety

The working tree may contain user changes. Before broad edits, inspect branch,
`HEAD`, status, staged/unstaged diffs, and untracked files. Preserve unrelated
work and never silently include it in a commit.

Do not use destructive Git commands to clean a worktree. Package managers may
change lockfiles; review and report those changes instead of discarding them.
Do not push, deploy, open a pull request, mutate remote state, or perform a
destructive action without explicit authorization.

### Confirmation Before Updating Main

Before every push or merge targeting local or remote `main`, finish the
candidate and verification first, then explicitly ask the user to confirm the
concrete update. Name the repository, current `main` commit, proposed commit,
operation, and check results. Wait for an affirmative response before changing
`main`; a general implementation or publishing request is not that confirmation.
One confirmation may cover an explicitly described local fast-forward and its
matching remote push. If either commit changes, obtain a new confirmation.

A pull request is optional. Required GitHub checks, administrator enforcement,
the force-push prohibition, and branch deletion protection remain mandatory.
Prepare and check candidates on a working branch; the complete manual CI run
documented in `docs/verification.md` supports promotion without a pull request.
The confirmation is an agent workflow requirement, not a GitHub-enforced chat
approval. Do not create a pull request unless the user asks for one.
