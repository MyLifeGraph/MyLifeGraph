# MyLifeGraph

MyLifeGraph is a mobile-first personal coaching app that turns explicit setup,
daily check-ins, tasks, habits, focus sessions, and planning facts into an
honest day view and cautious deterministic guidance. The primary client is a
Flutter web/mobile app backed by Supabase Auth/Postgres and an authenticated
FastAPI service. Most product behavior is rule-based; the optional real-model
Coach is read-only and supports per-request user-supplied OpenAI or Gemini keys
when both client and backend explicitly enable BYOK. The local Codex OAuth
adapter remains development-only.

The easiest way to explore the product is the local guest/demo flow. Real
accounts use Supabase-backed data and never fall back to personalized-looking
demo content when a read fails.

## Repository Structure

- `apps/mobile` — Flutter client, feature modules, local guest state, Supabase
  boundaries, and FastAPI clients.
- `services/ai_service` — FastAPI routes and deterministic or controlled
  backend workflows.
- `supabase` — local configuration, immutable migrations, RLS, grants, RPCs,
  and pgTAP tests.
- `e2e` — Playwright browser journeys.
- `scripts` — supported local, verification, database-safety, and demo helpers.
- `docs` — architecture, product guide, feature contracts, and runbooks.
- `AGENTS.md` — repository-local workflow and safety instructions for coding
  agents.

## Guest Quick Start

Prerequisites are Flutter on `PATH` (or `FLUTTER_BIN` set to its executable),
Python 3.12+, and a current Node.js/npm installation for verification.

From the repository root:

```bash
cp .env.example .env
scripts/start_frontend.sh
```

Open `http://127.0.0.1:7357` and choose **Continue as guest**. This path needs
no Supabase credentials and makes no authenticated product calls.

For Supabase-backed accounts, FastAPI, seeded scenarios, Coach modes, Android,
and troubleshooting, follow the
[complete local-development runbook](docs/local-dev.md#complete-local-stack).
Never commit real credentials from `.env`.

## Vercel Deployment

The repository-root `vercel.json` builds Flutter Web through
`scripts/vercel_build.sh` and serves `apps/mobile/build/web`. Vercel previews
must provide the synchronized account configuration described in
`docs/local-dev.md`; secrets belong in Vercel environment variables and never
in the repository.

Hosted builds accept only the repository's canonical Flutter environment
names. `VITE_*` and `NEXT_PUBLIC_*` variables are not implicit aliases. Pilot
production builds additionally bind `main`, the exact source SHA, and an
annotated RC tag before Flutter compilation begins.

The intended first hosted pilot uses Vercel for Flutter Web, hosted Supabase
for Auth/Postgres, and a separately operated HTTPS FastAPI/Coach service on a
VPS. The repository now has fail-closed staging/pilot project-ref guards and
current Supabase publishable/secret-key configuration with bounded legacy
compatibility, but the complete topology is not yet implemented or deployed. Its
remaining
implementation, `main`/tag release, VPS, HTTPS, public-signup, Android, and
acceptance sequence is owned by the
[VPS pilot release plan](docs/vps-pilot-release-plan.md).

## Verification

Capture the task base before editing, then use it for affected-path selection:

```bash
git rev-parse HEAD
npm run verify:affected -- --base-ref <task-base-ref>
```

Common direct gates are:

```bash
npm run verify:docs
FLUTTER_BIN=/path/to/flutter npm run verify:fast
npm run verify:db
FLUTTER_BIN=/path/to/flutter npm run verify:web
git diff --check
```

Choose gates, prerequisites, and any database/browser work through the
[verification runbook](docs/verification.md). Exact current checkout evidence
lives in its [Current Verified Baseline](docs/verification.md#current-verified-baseline);
older results are retained only in the
[historical archive](docs/verification-history.md).

## Documentation Map

- [VPS pilot release plan](docs/vps-pilot-release-plan.md) — authoritative
  future delivery sequence for public signup, VPS/HTTPS, provider choices,
  protected `main`, tagged releases, Vercel, Android, and professor handoff;
  it is not evidence of a current deployment.
- [Current product guide](docs/current-product-guide.md) — concise user-facing
  map of navigation, features, data, learning behavior, and current limits.
- [Local development](docs/local-dev.md) and
  [local database safety](docs/local-database-safety.md) — supported startup,
  environment, backup, reset, restore, and migration-test workflows.
- [Architecture](docs/architecture.md) and
  [backend roadmap](docs/backend-roadmap.md) — current system boundaries and
  intended backend direction.
- [Verification](docs/verification.md) — current commands, selection rules,
  baseline, CI, and automation gaps; [verification history](docs/verification-history.md)
  is checkout-local archival evidence only.
- [Supabase current state](docs/supabase-current-state.md) — authoritative
  schema, migration, Auth, RLS, grant, and RPC inventory.
- [Cross-runtime contract registry](docs/current-contracts.json) — exact
  machine-checked versions, source selectors, and documentation owners.
- Daily experience: [Daily briefing and Capture](docs/daily-briefing-implementation-plan.md),
  [Today](docs/today-overview-v1-contract.md),
  [executable actions](docs/phase-3-executable-actions-contract.md), and
  [Weekly Review](docs/phase-8-weekly-review-contract.md).
- Planning and learning: [Planner](docs/planner-v1-contract.md),
  [Study Setup](docs/study-setup-v1-contract.md),
  [Deadline Planner](docs/deadline-planner-v1-contract.md),
  [Exam-Week Outlook](docs/exam-week-outlook-v1-contract.md), and
  [Personal Learning](docs/personal-learning-v1-contract.md).
- Integrations and account surfaces: [Calendar import](docs/phase-9-calendar-import-contract.md),
  [notification lifecycle](docs/notification-lifecycle-v1-contract.md),
  [notification delivery](docs/notification-delivery-v1-contract.md), and
  [account controls](docs/v1-account-controls-contract.md).
- Product truth and presentation: [Setup retirement](docs/setup-personalization-retirement-contract.md),
  [UI language and copy](docs/ui-language-and-copy-contract.md),
  [visual system](docs/frontend-visual-system-v2.md), and
  [Android Focus Protection](docs/android-focus-protection-v1-contract.md).
- [Controlled Coach](docs/phase-10-controlled-coach-plan.md) — read-only data,
  provider, tool, safety, persistence, and non-production boundaries.
