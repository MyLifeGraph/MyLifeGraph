# Five-student Study Facilitator Runbook

Use this runbook with `docs/student-usability-test-script.md`. It prepares a
consistent local product study without creating participant results in advance.

## Before recruitment

- Recruit five distinct adult current students who plan exams, assignments, or
  coursework and can use the English V1 interface.
- Decide compensation, scheduling, note ownership, retention, and deletion
  before contacting anyone. Mention compensation only if it is real.
- Keep the participant-code/contact mapping outside the repository. Repository
  artifacts use only `S1` through `S5`.
- Do one non-counted dry run with a teammate. If it causes a material script or
  product change, finish that change before S1 and record the final build.

The recommended contact pattern is 35–45 minutes for Part A and 10–15 minutes
for Part B after the first confirmed preparation block has passed. Do not
describe this as an unmoderated study: the script requires a moderator to record
wrong turns and intervention levels.

## Freeze and record the test build

Before S1, confirm that the intended checkout is clean and record its commit:

```bash
git status --short --branch
git rev-parse HEAD
```

Use the same commit for all five participants when possible. If a blocking fix
requires a new commit, record the exact participant boundary and treat the
sessions as different build cohorts during synthesis.

Start the real local stack with Coach visible but no provider connected:

```bash
LOCAL_STACK_COACH_PROVIDER=disabled \
FLUTTER_BIN=/home/gregor/tools/flutter/bin/flutter \
scripts/start_local_stack.sh
```

This keeps Supabase, FastAPI, and Flutter on loopback, uses real local account
paths, and lets participants see the honest “no Coach provider” boundary. Do
not enable local Codex or the fake provider for this study unless that is a
separately declared research question. Do not reset the database merely to
prepare a session.

For a remote session, share and, if approved, remotely control the facilitator's
browser. Do not bind Supabase, FastAPI, or Flutter to a public interface and do
not send local service-role credentials to a participant.

## Prepare one clean account per participant

Before each Part A:

1. In local Supabase Studio at `http://127.0.0.1:54323`, create one confirmed
   Auth user with a unique local-only address such as
   `study-s1-YYYYMMDD@example.test` and a temporary unique password.
2. Confirm that the new profile has not completed Setup. Do not seed demo data;
   seeded accounts cannot test first Setup honestly.
3. Give the temporary credentials to the participant privately. Never place a
   password, access token, real email address, or code-to-identity mapping in
   study notes or Git.
4. Open `http://127.0.0.1:7357` in a fresh browser profile or private window.
   Confirm only that the sign-in screen loads; do not navigate or prefill the
   product for the participant.
5. Record browser/device, viewport, OS-level text scale, app commit, local date,
   timezone, moderator, and contact channel in a fresh copy of the session-notes
   template.

Retain the local account only until Part B and evidence checks are complete.
Delete it afterward according to the chosen retention plan. Account deletion is
not a study task unless explicitly added to a separate protocol.

## Consent and privacy

Before product use, say:

> With your permission I will take anonymized notes about where the product is
> clear or confusing. I am testing the product, not you. Please use fictional
> coursework, wellbeing, and calendar details rather than private real data.
> You may skip a question, pause, or stop at any time. May I take anonymized
> notes for this product study?

Record `yes`, the date, and the allowed evidence types. Do not continue if the
participant does not consent. Audio, video, screenshots, or chat exports need
their own explicit permission. Institutional requirements take precedence over
this project template.

## Moderation rules

Read each task exactly once and ask the participant to think aloud. Use this
intervention scale:

- `0 — none`: silence beyond the task and general encouragement to continue.
- `1 — neutral`: ask “What are you looking for?” or repeat the task verbatim.
- `2 — scenario clarification`: clarify fictional scenario facts without naming
  a control, route, or product concept.
- `3 — product help`: explain a control, route, term, or next action. Mark the
  task `blocked`, record the first wrong turn and help, then continue only to
  preserve later observations.

Do not celebrate a click, defend copy, explain deterministic rules, or correct a
participant's interpretation before it has been recorded. Ask “What do you
expect will happen?” immediately before consequential actions and “What changed
just now?” immediately afterward.

After each task, ask: “Overall, how easy or difficult was that task?” Record a
Single Ease Question score from `1 — very difficult` to `7 — very easy`. The
score supplements behavior; it does not replace the observed outcome.

## Creating the real missed-block state

Do not backdate rows, edit planner tables, change the system clock, or show a
fixture while claiming it is the participant's plan.

After the participant confirms a plan in Part A:

1. Record the earliest confirmed preparation block and its displayed timezone.
2. Ask the participant not to start linked Focus for that one block. Record that
   the miss is instructed and cannot measure natural adherence.
3. Schedule Part B after the block's end time. Keep the same local account and
   app build.
4. At Part B, let the participant sign in or reload, then read tasks 8–10 without
   navigation hints.

If no block was scheduled, the block lies outside the participant's available
follow-up window, or the participant does not return, record Replan as
`not observed`. That is a study limitation and must not be repaired by database
manipulation.

## After each contact

- Complete contemporaneous notes before discussing interpretations with the
  team.
- Separate observed action, direct quote, and moderator interpretation.
- Redact any accidental real title, note, email, screenshot, or notification.
- Store raw identifiable evidence outside Git. Add only an anonymized session
  summary to the repository if consent and the retention plan allow it.
- Record partial sessions honestly. Part A completion does not imply Part B
  completion.
- Do not change product copy between participants for a minor issue. Finish the
  five sessions first unless a safety, privacy, data-loss, or core-task blocker
  requires stopping the study.

## Completion gate

The study is complete only when S1–S5 each have an anonymized dated summary,
their build and evidence boundary are known, missing Part B contacts are marked
`not observed`, and `docs/student-usability-study/synthesis-template.md` has
been populated from actual observations. Automated tests and the moderator's
own walkthrough do not fill participant rows.
