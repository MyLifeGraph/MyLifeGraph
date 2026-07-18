# Next Chat Prompt

This prompt starts a critical review of the committed Deadline Planner and
product-polish slice. The complete context and review checklist are in
`docs/product-review-handoff.md`.

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
