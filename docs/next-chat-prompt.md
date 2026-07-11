# Next Chat Prompt

Use this prompt when starting a new implementation chat after Phase 1,
Lightweight Evening And Morning Capture.

Recommended reasoning level: **high**. This work turns explicit sensitive daily
context into deterministic state, freshness, and risk summaries. It must stay
explainable and must not become briefing ranking or pseudo-clinical advice.

Prompt:

```text
We are in /home/gregor/projects/ai-personal-coach.

Use high reasoning. First read completely:

1. AGENTS.md
2. README.md
3. docs/architecture.md
4. docs/backend-roadmap.md
5. docs/daily-briefing-implementation-plan.md
6. docs/supabase-current-state.md
7. docs/local-dev.md
8. docs/verification.md

Goal: implement Phase 2, Explainable Daily State. Phase 0A, 0B, 0C, and Phase
1 are implemented. Preserve their contracts. In particular, do not change the
Phase-0C request/base-revision/pending/applied Setup contract or the
service-role-only `apply_intake_v1_setup_revision` RPC. Guest Setup remains
local and is not automatically migrated.

Phase 1 now has separate typed Evening Shutdown and Morning Calibration flows
over one `DailyCaptureEntry`. Same-day writes replace only their owned
`daily_logs.metadata.captures.evening` or `.morning` object. Numeric projection
uses Morning energy when present, otherwise Evening energy; Evening owns mood
and stress; Morning owns sleep. Supabase rebuilds a dynamic deterministic set of
at most four linked mood/energy/stress/sleep events. Guest JSON V2 retains V1
read and best-effort check-in migration compatibility. Capture snapshot refresh
sends its local `target_date`, and backend event filtering prefers
`metadata.entry_date` over the UTC timestamp inside a broadened read window.
Dashboard reads remain direct and nullable.

Phase 1 itself contains no Daily Mode, briefing/action ranking, briefing
persistence, save-time recommendation generation, or LLM usage. Phase 2 is the
first slice allowed to classify a deterministic explainable Daily Mode inside
the snapshot contract. Do not turn that classification into ranked actions or a
new Today dashboard in this slice.

Start by walking these cases against daily and weekly snapshot generation:

1. Current Morning only: sleep, energy, and constrained day shape, with no
   Evening capture.
2. Current Evening only: high workload stress that is mostly controllable.
3. High private/emotional stress that is hardly controllable, followed by a
   low-energy constrained Morning.
4. High avoidable pressure with unclear priorities but otherwise adequate
   recovery.
5. Missing capture, partial legacy V1 signals, stale Evening, stale Morning, and
   conflicting recovery/productivity signals.
6. Re-generating the same user/scope/period after a same-day edit without
   duplicate snapshots or stale evidence.
7. Guest/mock mode remaining local and making no snapshot, recommendation, or
   LLM request.

Inspect at minimum:

- `DailyCaptureEntry`, its V2 metadata shape, numeric projection, and V1 mapper
- `SupabaseSnapshotRepository` input selection and local-date event filtering
- `SnapshotAggregator` summary, signals, risk flags, evidence refs, period
  upsert, and current tests
- recommendation context consumers, to ensure Phase 2 does not silently change
  recommendation ranking
- scheduled refresh and authenticated capture refresh triggers
- Dashboard source-truth mapping; do not replace it with an unproven Today UI
- Flutter snapshot API tests, FastAPI tests, and `e2e/web/smoke.mjs`

Required product contract:

- Parse only explicit Phase-1 metadata. Validate object/type/enum boundaries and
  ignore or downgrade malformed optional context; never invent a stress source,
  controllability, day shape, focus band, note, or numeric value.
- Preserve numeric compatibility and the existing Evening/Morning ownership
  merge. Phase 2 reads capture state; it does not rewrite `daily_logs` or
  `behavioral_events`.
- Add an explicit data-quality state for at least `missing`, `partial`,
  `current`, and `stale`. Define deterministic, documented freshness thresholds
  from capture `entry_date`/`captured_at`, target date, and capture presence.
- Summarize the latest explicit stress intensity, source, controllability,
  focus band, day shape, current energy, and sleep without exposing optional
  sensitive free text in generic summaries or notification-ready fields.
- Add bounded deterministic risk flags for private/emotional stress, physical
  recovery, avoidable pressure, workload pressure, low controllability,
  constrained capacity, low sleep, low energy, and stale/missing calibration.
  Emit a flag only when its required explicit evidence exists.
- Add deterministic `push`, `steady`, `recover`, and `plan` classification with
  ordered rules. Private/emotional or physical-recovery stress, low
  controllability, poor sleep, and low energy must prevent aggressive `push`.
  Avoidable pressure or unclear priorities may support `plan`. Insufficient or
  stale data must choose a conservative result and expose low data quality; it
  must not imply a learned baseline.
- Include concise machine-stable reason codes plus user-readable explanations,
  evidence refs, source/provenance, target date, generated time, and freshness.
  Do not claim diagnosis, causation, optimization, or clinical advice.
- Keep daily/weekly snapshot upsert idempotent by
  `(user_id, scope, period_key)`. Derive `user_id` only from the verified bearer
  principal or the existing backend scheduler selection.
- Normal dashboard and recommendation reads remain read-only. Phase 2 must not
  call recommendation generation on capture save or dashboard load.
- Guest/demo stays local. Do not send guest capture or sensitive context to
  FastAPI, Supabase, notifications, memory entries, tasks, recommendations, or
  schedule items.

Implementation guidance:

1. Write the snapshot input/output and precedence matrix before editing:
   current/stale/missing Evening and Morning, legacy numeric fallback, risk
   flags, data quality, mode, reasons, and evidence.
2. Add typed internal snapshot-state helpers instead of spreading raw JSON
   lookups across rules. Keep parsing and classification pure and unit-testable.
3. Extend existing `user_state_snapshots.summary` and `.signals`; do not add a
   new table or columns unless a query/index requirement makes it demonstrably
   necessary.
4. Keep Phase-1 capture metadata immutable. Unknown future metadata keys should
   not crash aggregation, while invalid known values must not become trusted
   evidence.
5. Use deterministic rule precedence and expose it in tests. Recovery and
   low-control safeguards override productivity-oriented classification.
6. Keep recommendation rules unchanged in this slice. If they read the new
   snapshot fields, they may persist them as context only; do not change ranking
   or wording behavior.
7. Keep the existing best-effort refresh boundary: the original Supabase write
   succeeds even when snapshot refresh fails.
8. Extend browser E2E with exact database assertions for the Phase-2 daily
   snapshot after distinctive Evening/Morning inputs. Do not claim the browser
   path passed unless it was actually run successfully in the current checkout.
9. Update architecture, roadmap, Supabase-state, verification, and continuation
   docs to match the implemented contract.

Focused tests must cover:

- every stress source and controllability code during state parsing
- missing, partial, current, and stale data quality
- all four modes and their ordered precedence
- private/emotional plus hardly-controllable stress forcing a lower-load result
- physical recovery and poor sleep preventing `push`
- avoidable pressure supporting `plan` without blame-oriented copy
- Morning-only, Evening-only, merged, and legacy V1 numeric input
- malformed/unknown metadata without invented fallback values
- metadata entry-date filtering around UTC/local-day boundaries
- daily and weekly period upsert idempotency and explicit user scoping
- guest/mock locality and authenticated refresh failure remaining best-effort

Run focused tests while implementing, then at minimum:

- Flutter analyze and the complete Flutter test suite
- the complete FastAPI test suite
- `scripts/verify.sh`
- non-destructive local Supabase verification if schema/client integration is
  affected
- Browser E2E
- `git diff --check`

Do not implement briefing/action ranking, `daily_briefings` persistence, the
decision-first Today dashboard, broad Habit V1 cadence, Coach/LLM, calendar
import, notifications, weekly review, vector search, wearables, or autonomous
workers in Phase 2.

Do not commit unless explicitly asked.
```
