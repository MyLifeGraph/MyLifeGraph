# Five-student Usability Test Script

Status: ready for recruitment and moderated two-part sessions; no participant
sessions or results are claimed yet.

Run this script with:

- `docs/student-usability-study/facilitator-runbook.md`
- `docs/student-usability-study/recruitment-message-template.md`
- `docs/student-usability-study/session-notes-template.md`
- `docs/student-usability-study/synthesis-template.md`

## Goal

Test whether a student can understand the core loop without explanation:
complete Setup, record an evening check-in, start and finish Focus, create and
confirm an exam or assignment preparation plan, then replan after falling
behind. The test also checks whether the student can tell what changes
automatically and what is only a preview.

## Study Design

Run five moderated think-aloud studies with five distinct current students.
Use the same app build and task wording for all five whenever possible. Record
the exact commit, environment, device or viewport, text scale, and moderator in
every session summary.

The study has two contacts:

- Part A: 35–45 minutes for Setup, daily use, Focus, plan creation, capability
  truth, and discovery probes.
- Part B: 10–15 minutes after the participant's first confirmed preparation
  block has actually ended without linked Focus credit. This is the only honest
  way to test the real missed-block recovery state without backdating or
  corrupting planner data.

At the end of Part A, explicitly ask the participant not to complete the first
confirmed block and record that this was a study instruction. The result is
evidence about recovery usability, not natural adherence. If Part B never
happens, record `not observed`; do not turn a hypothetical walkthrough into a
completed Replan task.

A developer or teammate may do a dry run of the materials, but that person does
not count toward the five students. If the script or build changes materially
after a participant, record the change and do not silently aggregate unlike
sessions.

## Participants And Evidence

Recruit five adult current students who plan coursework, exams, or assignments
and can use the English V1 interface. Aim for variation in study habits and
self-reported planning confidence. Friends or classmates are acceptable
relevant participants; do not invent formal research distance that does not
exist. Follow any applicable institutional research or consent rules.

Before each session, obtain permission to take anonymized notes. Ask
participants to use realistic but fictional coursework, wellbeing, and calendar
data. Record only:

- participant code (`S1` through `S5`), student context, and session date;
- remote, phone, or in-person contact channel;
- task completion, hesitation, wrong turns, and direct feedback;
- optional redacted screenshot or call/chat evidence with consent.

Do not collect names in the presentation artifact. A dated, anonymized session
summary plus the researcher's contemporaneous notes is acceptable evidence;
label any summary reconstructed after an earlier conversation honestly as
retrospective. Keep the code-to-identity/contact mapping, credentials, raw
recordings, and unredacted captures outside the repository. Do not record audio
or video without separate explicit consent.

## Session Script

Use one fresh local real account per participant; a demo account cannot test the
real Setup-to-Planner journey. Read:

> Please think aloud. I am testing the product, not you. Use realistic but
> fictional information. I will not explain controls unless you become fully
> blocked. You can pause or stop at any time.

Record the first wrong turn before intervening. A reminder to think aloud or a
verbatim repeat of the task is neutral. If the moderator explains a control,
route, term, or next action, mark that task `blocked`, record the intervention,
and continue only so later tasks can still be observed.

### Part A

1. Complete Setup with realistic sleep, workload, routines, and one fixed
   commitment.
2. Record how today felt using the evening check-in.
3. Find Focus, choose a useful length, start it, and finish it.
4. Add an upcoming exam or assignment. Enter the total active preparation time
   you believe you need and any work already completed.
5. Review the proposed preparation blocks. Explain what will and will not
   happen before confirmation, then confirm the plan.
6. Open Inbox and Coach. Explain, in your own words, what kind of notifications
   and Coach access the current app actually provides.
7. Without changing anything, show where you would look for a Weekly review, a
   calendar import, and timezone or account settings.

Record the first confirmed preparation block's end time. Ask the participant
not to start linked Focus for that block, explain that this is only to create the
study's recovery state, and schedule Part B after the block ends.

### Part B

8. Sign in again or reload the app. Without navigation hints, find what happened
   to the passed preparation block.
9. Explain what remains uncredited, what completed Focus still counts, and what
   will change only as a preview.
10. Use the recovery path to update the remaining plan, review the new proposal,
    and decide whether to confirm it.

After Part B, or after Part A if Part B cannot be scheduled, ask:

- What felt most useful?
- What felt slow, confusing, or unnecessary?
- At any point did you think the app had changed something when it had only
  shown a preview?
- When would you realistically stop using this app after a few weeks?
- What is the one improvement that would make you keep using it?

## Observation Sheet

| Participant | Setup | Evening | Focus | Plan | Inbox/Coach | Discovery | Replan | Automatic vs preview understood | Main friction | Evidence reference |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| S1 | Not run | Not run | Not run | Not run | Not run | Not run | Not run | Not run | — | — |
| S2 | Not run | Not run | Not run | Not run | Not run | Not run | Not run | Not run | — | — |
| S3 | Not run | Not run | Not run | Not run | Not run | Not run | Not run | Not run | — | — |
| S4 | Not run | Not run | Not run | Not run | Not run | Not run | Not run | Not run | — | — |
| S5 | Not run | Not run | Not run | Not run | Not run | Not run | Not run | Not run | — | — |

Use `completed`, `completed with hesitation`, `blocked`, or `not observed` for
each task. `Not observed` is missing evidence, not success or failure. Note the
first wrong turn rather than coaching around it.

## Synthesis And Shipping Gate

Group findings by repeated problem, severity, and affected journey. A critical
issue blocks a core task or creates a false belief about an automatic change. A
major issue requires help or repeated backtracking. A minor issue slows the
participant without changing the outcome.

Before claiming this study in a presentation, attach the five anonymized
summaries, identify repeated findings, list product changes or justified
non-changes, and mark which changes were retested. Do not convert “Not run” into
evidence based on automated tests or the development team's own walkthrough.
Report counts as `x/5` or `x/n observed`, keep direct observation separate from
interpretation, and preserve one-person accessibility or safety problems even
when they are not repeated.
