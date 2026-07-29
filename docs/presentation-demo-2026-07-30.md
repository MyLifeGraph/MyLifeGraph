# Presentation Demo Runbook — 30 July 2026

This runbook prepares the 8–10 minute English presentation. Its central message
is:

> Use deterministic software where correctness matters and an LLM where
> flexible explanation creates value.

The demo uses two real local Supabase accounts in two browser origins. It makes
no production-provider claim; the free read-only Coach remains a local
development capability.

## Accounts

Run:

```bash
npm run seed:demo
```

All four local accounts use `DemoPass123!` unless `DEMO_PASSWORD` is explicitly
overridden:

| Purpose | Email | Expected state |
| --- | --- | --- |
| Fresh Setup | `onboarding@example.test` | Incomplete Setup, `Europe/Berlin`, no user-entered or generated product data |
| Populated Student | `student@example.test` | Maya's broad Today, Insights, planning, and Coach fixture |
| Busy worker | `worker@example.test` | Populated comparison fixture |
| Recovery builder | `recovery@example.test` | Populated comparison fixture |

Every seed run deletes and recreates these identities. It therefore resets the
fresh account and invalidates any open session for all four accounts. Do not
seed again after the presentation tabs have signed in.

The Auth/profile triggers create the fresh account's canonical profile plus
neutral notification and Personal Learning preference projections. The seed
verifies those defaults, keeps onboarding incomplete, and requires every
activity, Setup, planning, Coach, and retry-ledger table to be empty.

## Final Technical Setup

Run these steps in order:

1. Run the complete standard verification and browser E2E suite:

   ```bash
   FLUTTER_BIN=/path/to/flutter scripts/verify.sh
   FLUTTER_BIN=/path/to/flutter bash scripts/e2e_web.sh
   ```

2. Seed the presentation accounts:

   ```bash
   npm run seed:demo
   ```

3. Prepare the pinned analysis image:

   ```bash
   npm run prepare:coach-analysis
   ```

4. Confirm the local Codex login without inspecting or copying its auth files:

   ```bash
   codex login status
   ```

5. Start the real local Coach stack. It rechecks the image revision:

   ```bash
   npm run start:local:coach
   ```

6. Open `http://localhost:7357` and sign in as
   `onboarding@example.test`.
7. Open `http://127.0.0.1:7357` and sign in as
   `student@example.test`.
8. Reload both origins once. Confirm that each retains its own account and does
   not switch to the other identity.
9. Do not run the seed again.

`localhost` and `127.0.0.1` have separate browser storage origins, so the two
Supabase sessions remain independent without signing in and out.

## Student Coach Preflight

The seed deliberately includes deterministic fake-provider Coach history for
coverage. Before the presentation:

1. In the Student tab, open Coach and choose **Delete conversation**.
2. Confirm the capability says **Read-only Coach ready** and the summary says
   `Local development-only agent · gpt-5.5 · Fast configured`.
3. Send the prepared presentation prompt once through the live provider.
4. Verify the reply is concise English, names its uncertainty, and makes no
   product-data mutation claim.
5. Expand **Data and analysis details**. Confirm **Snapshot source coverage**
   with its conservative periods/counts, multiple completed SQL/Python steps,
   limitations, and `gpt-5.5 · Fast configured`; no plot or hidden reasoning
   is visible. Coverage may be broader than rows returned by one query.
6. Delete the conversation again.

Conversation deletion retains usage accounting and request tombstones. It does
not reset the Student's daily question budget.

Prepared prompt:

> Using all retained Focus reflections and the valid preceding sleep data,
> test whether Maya's focus rating was usually higher after at least 7.5 hours
> of estimated sleep. Look for counterexamples, distinguish observation from
> interpretation, and answer in no more than five sentences.

The Coach may inspect Planner, Preparation, and Calendar data when relevant,
but can never reschedule or mutate them.

## Live Presentation

| Time | Live action | Spoken message |
| --- | --- | --- |
| 0:00–0:40 | Introduce the problem | “Most of MyLifeGraph is deterministic. I use an LLM only where flexible explanation adds value.” |
| 0:40–2:10 | Complete the fresh user's minimal Setup | Show that only weekday structure and energy window are required; Study Setup remains optional. |
| 2:10–2:40 | Open Coach for the fresh account and ask what changed this month | Show that Coach reports missing data instead of fabricating a pattern; there is no mode or memory selector. |
| 2:40–5:10 | Switch to the populated Student tab | Show Today, current Tasks and Habits, then one stable Personal Learning insight. |
| 5:10–8:30 | Open Student Coach and send the prepared prompt | Show safe activity, the live answer, uncertainty, **Data and analysis details**, actual SQL/Python steps, and Fast provenance. Explain that Coach cannot mutate product data. |
| 8:30–9:30 | Conclude | “The goal is not to let AI run the product. It is to improve the experience without giving up control or transparency.” |

## Rehearsal Acceptance

Complete one uninterrupted timed rehearsal and keep it below 9:30. Confirm:

- Fresh: sign in → minimal Setup → Today → Coach shows
  **Read-only Coach ready**.
- Student: sign in → populated Today and Insights → Coach shows ready.
- Both sessions survive reload on their separate origins.
- The prepared prompt produces at most five English sentences grounded only in
  actual data, with explicit uncertainty, counterexample handling, and no
  mutation claim.
- **Data and analysis details** is expandable, labels conservative
  **Snapshot source coverage**, shows multiple actual tool steps, and provider
  provenance says `gpt-5.5 · Fast configured`.
- No plot, mode/horizon/Focus selector, prompt starter, memory selector, or
  structured action appears.

If model, Fast, login, Docker/image, network, or provider is unavailable, report
that state honestly. Do not enable the fake provider, silently change models,
or accept standard tier for the live presentation.

## Presentation-Day Checklist

- Connect power.
- Disable sleep and system notifications.
- Confirm WLAN or hotspot access.
- Confirm `mylifegraph-coach-analysis:1` was prepared.
- Run `codex login status`.
- Start the local Coach stack.
- Preload and reload both browser origins.
- Confirm the fresh and Student identities before presenting.
