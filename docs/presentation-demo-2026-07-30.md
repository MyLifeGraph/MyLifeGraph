# Presentation Demo Runbook — 30 July 2026

This runbook prepares the 8–10 minute English presentation. Its central message
is:

> Use deterministic software where correctness matters and an LLM where
> flexible explanation creates value.

The demo uses two real local Supabase accounts in two browser origins. It makes
no production-provider claim and adds no Coach, schema, API, or model-contract
capability.

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

3. Confirm the local Codex login without inspecting or copying its auth files:

   ```bash
   codex login status
   ```

4. Start the real local Coach stack:

   ```bash
   npm run start:local:coach
   ```

5. Open `http://localhost:7357` and sign in as
   `onboarding@example.test`.
6. Open `http://127.0.0.1:7357` and sign in as
   `student@example.test`.
7. Reload both origins once. Confirm that each retains its own account and does
   not switch to the other identity.
8. Do not run the seed again.

`localhost` and `127.0.0.1` have separate browser storage origins, so the two
Supabase sessions remain independent without signing in and out.

## Student Coach Preflight

The seed deliberately includes deterministic fake-provider Coach history for
coverage. Before the presentation:

1. In the Student tab, open Coach and choose **Delete conversation**.
2. Confirm the capability says **Development Coach ready**.
3. Send the prepared presentation prompt once through the live provider.
4. Verify the reply is concise English, names its uncertainty, and makes no
   product-data mutation claim.
5. Expand **Data used** and technical provenance. Confirm the provider is the
   local-development connection and the requested model is `gpt-5.5`.
6. Delete the conversation again.

Conversation deletion retains usage accounting and request tombstones. It does
not remove the Student's explicit memory selections, so those remain available
for the live presentation.

Prepared prompt:

> Answer in no more than five sentences and use only the data you can actually
> see: What are the two most sensible priorities for Maya today, and what are
> you uncertain about?

Do not ask Coach to reschedule exact exam, essay, Planner, Preparation, or
Calendar blocks. Those details are outside the current bounded Coach context.

## Live Presentation

| Time | Live action | Spoken message |
| --- | --- | --- |
| 0:00–0:40 | Introduce the problem | “Most of MyLifeGraph is deterministic. I use an LLM only where flexible explanation adds value.” |
| 0:40–2:10 | Complete the fresh user's minimal Setup | Show that only weekday structure and energy window are required; Study Setup remains optional. |
| 2:10–2:40 | Open Coach for the fresh account | Show that Coach does not pretend to know a new user. Memory use requires explicit selection. |
| 2:40–5:10 | Switch to the populated Student tab | Show Today, current Tasks and Habits, then one stable Personal Learning insight. |
| 5:10–8:30 | Open Student Coach and send the prepared prompt | Show the live answer, uncertainty, **Data used**, and `gpt-5.5` provenance. Explain that Coach cannot mutate product data. |
| 8:30–9:30 | Conclude | “The goal is not to let AI run the product. It is to improve the experience without giving up control or transparency.” |

## Rehearsal Acceptance

Complete one uninterrupted timed rehearsal and keep it below 9:30. Confirm:

- Fresh: sign in → minimal Setup → Today → Coach shows
  **Development Coach ready**.
- Student: sign in → populated Today and Insights → Coach shows ready.
- Both sessions survive reload on their separate origins.
- The prepared prompt produces at most five English sentences grounded only in
  visible sources, with explicit uncertainty and no mutation claim.
- **Data used** is expandable and provider provenance shows the explicitly
  requested `gpt-5.5`.

If the model, login, network, or provider is unavailable, report that state
honestly. Do not enable the fake provider or silently change models for the
live presentation.

## Presentation-Day Checklist

- Connect power.
- Disable sleep and system notifications.
- Confirm WLAN or hotspot access.
- Run `codex login status`.
- Start the local Coach stack.
- Preload and reload both browser origins.
- Confirm the fresh and Student identities before presenting.
