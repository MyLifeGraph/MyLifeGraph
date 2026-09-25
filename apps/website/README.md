# MyLifeGraph product website

Isolated, bilingual static product site, separate from Flutter and its production
Vercel project. English is the default; German is toggled in the header. Only
language and appearance preferences persist locally (`mylifegraph.website.language`
and `mylifegraph.website.appearance`). Liquid Glass is the initial appearance;
Dark, Light and Space are available in an icon dropdown that closes on selection,
outside interaction or Escape. Invalid saved values fall back to Liquid Glass.

## Public surface and truth boundary

`public/` contains HTML, CSS, native ES modules and the canonical brand SVG.
No dependencies, external fonts, analytics, cookies, API routes or secrets.
CSP denies all connection and form submission requests. Hosting still handles
ordinary HTTP requests; this is not a claim of anonymous server logs.

The four-tab demonstration uses invented in-memory data: reversible task checks,
sleep/energy curves, selectable days including an empty Sunday, and explicitly
scripted Coach replies. It never reads/writes product data or calls an AI.
Reset clears demo state, not language or appearance. Reload clears demo state too.
Desktop uses a sidebar and side-by-side Planner summaries; mobile uses bottom
tabs and This week/Planning views. Today puts last-check-in metrics before the
check-in controls. Insights has Overview/Advanced; Coach remains scripted.

Public copy follows `docs/current-product-guide.md`,
`docs/ui-language-and-copy-contract.md` and `docs/frontend-visual-system-v2.md`.
It distinguishes Android-only capabilities, optional imports/permissions,
review-before-save, correlation versus causation and the English app interface
versus bilingual Coach/voice guides. It does not advertise the pending local
Morning/Evening push migration as deployed. This is a simplified product tour,
not a pixel-identical embedded Flutter build.

## Design and accessibility

Independent marketing presentation: four coordinated palettes, transparent
Liquid Glass surfaces, large editorial headings, compact feature cards and
native expandable FAQs. No changes to any Flutter theme or layout.
Responsive desktop/mobile layouts, reduced-motion support, visible keyboard
focus, keyboard-operated demo tabs, labelled charts, translated accessible names,
and live announcements for demo actions. No autoplay or microphone permission.

The hero includes a decorative CSS-3D smartphone with synthetic Today content,
light reflections and two floating glass cards. There is no scroll rotation.
A separate wrapper floats five pixels over an eight-second loop, paused by
IntersectionObserver offscreen and by Page Visibility in background tabs.
Reduced-motion settings disable it; absent IntersectionObserver keeps it paused.
Fine-pointer hover adds a six-degree tilt with a smooth return. No timer,
scroll handler, video download or WebGL dependency is needed. Content
and palette follow the existing language/theme controls. The scene is hidden
from assistive technology; only its decorative phone accepts pointer hover,
without click handlers or touch gesture interception. The accessible interactive
demo immediately below supplies the actual controls. No real account is shown.

## Run, verify, publish

From repository root:

```sh
python -m http.server 7360 --bind 127.0.0.1 --directory apps/website/public
node --test apps/website/website.test.mjs
```

Open `http://127.0.0.1:7360`. Inspect EN/DE at narrow and wide widths. Exercise
all tabs, task toggle/undo, Sunday, both Coach replies, reset, preference reload,
all four appearance options, menu keyboard dismissal, hero hover/idle motion
and the reduced-motion/static fallback.

The dedicated Vercel project is `mylifegraph-website` in the existing
`my-life-graph-s-projects` scope. Deployment uploads only the allowlisted
public/config files, not the repository, `.env`, tests or Flutter output:

```sh
cd apps/website
vercel deploy --dry --project mylifegraph-website --scope my-life-graph-s-projects --local-config vercel.json --yes
vercel deploy --prod --project mylifegraph-website --scope my-life-graph-s-projects --local-config vercel.json --yes
```

Publishing requires explicit user authorization. Inspect the dry-run file list
first. Run from this directory with the explicit local config: using only
`--cwd` from the root may pick up the app's root headers in the installed CLI.
Check the public response's CSP for `connect-src 'none'` after deployment.
No Git push, app redeployment, Supabase migration or VPS change is needed.
`/website` on this site's own host redirects to `/`; the existing app hostname
and its SPA routes are untouched. A shared app-host path is not configured.
Actual deployed URL and verification evidence belong in `docs/verification.md`.
