# Frontend Visual System V2

The Coach provider/key controls use the existing Settings card, field,
dropdown, button, spacing, and error-text primitives; they introduce no new
visual token or icon family.

Status: implemented repository visual contract for Flutter Web and Android as
of 2026-08-01.

## Product Intent

MyLifeGraph presents itself as a calm, precise personal operating system rather
than a generic Material or AI-wellness interface. The system is mobile-first at
390×844, remains fully usable at 320 logical pixels and 200% text, and uses the
same hierarchy on desktop at 1280×960.

This contract changes presentation only. It does not change navigation,
student-facing capability truth, product copy, data contracts, persistence,
backend APIs, or mutation authority. Dark remains the default. Light and Space
remain persisted, device-local manual choices rather than system-theme modes.
Space is a dark violet/cyan theme; it has no separate light variant.

The interface uses no code-generated gradients, shimmer loops, confetti,
illustrative scene decoration, or general-purpose blur-heavy glass system.
Space is the only bounded clear-material exception: it combines tinted
translucent surfaces and sparse HUD strokes with one of two approved local,
photorealistic deep-field WebP backdrops, a restrained looping star overlay,
and minimal closed-path camera drift on the photograph. Actual backdrop blur
is restricted to the one currently visible shell-navigation surface. Both
depth layers are presentation-only and change no content or layout; Reduced
Motion freezes them at the same deterministic phase. Brand mint in Dark/Light
and brand cyan in Space are the only solid call-to-action colors. Information
blue, attention amber, danger red, and supporting data colors never replace a
visible icon or text label.

## Brand

The brand mark is a path joining three explicit nodes on a 24×24 grid. Its
canonical source is
`apps/mobile/assets/brand/app_brand_mark.svg`; `AppBrandMark` renders it in the
app. It may appear once prominently on a screen and must not become a repeating
background pattern.

`scripts/generate_brand_assets.py` deterministically derives the Android
launcher sizes, PWA regular and maskable icons, and favicon from the same
geometry and palette. Android adaptive icon and splash vector resources repeat
that exact geometry. The launch background and default web chrome use the dark
background rather than Flutter blue.

The word `MyLifeGraph` remains live text. Sparkle icons are not part of the
brand.

## Palette

| Role | Dark | Light | Space |
| --- | --- | --- | --- |
| Background | `#08110F` | `#F6F6F1` | `#070814` |
| Base surface | `#101A17` | `#FFFFFF` | `#101329` |
| Subtle surface | `#15221E` | `#EEF2ED` | `#171A38` |
| Raised surface | `#1A2924` | `#E7ECE7` | `#20244A` |
| Interactive surface | `#1D302A` | `#E1E9E3` | `#292E5C` |
| Primary text | `#F2F6F3` | `#15201C` | `#F6F3FF` |
| Secondary text | `#A8B6B0` | `#53625C` | `#D4CFEA` |
| Brand | `#69E0BD` | `#087A65` | `#67E8F9` |
| On brand | `#07352B` | `#FFFFFF` | `#07272C` |
| Brand container | `#173B32` | `#D9F3EA` | `#20224A` |
| On brand container | `#B9F6E3` | `#075F50` | `#DCD4FF` |
| Strong focus | `#9AAEA6` | `#687B73` | `#C4B5FD` |
| Soft outline | `#2B3A35` | `#D5DDD8` | `#353B68` |
| Information / surface | `#9CB7FF` / `#1B2944` | `#3F6399` / `#E7EEFC` | `#A5B4FC` / `#1D254A` |
| Attention / surface | `#F2C470` / `#342918` | `#7A5700` / `#FFF1CF` | `#F6C76E` / `#352A18` |
| Danger / surface | `#FF8E86` / `#3B201F` | `#B23B36` / `#FFE9E6` | `#FF8E9E` / `#3B1D2A` |
| Success / surface | `#82DE9A` / `#183322` | `#1D7045` / `#E2F3E7` | `#7EE2B8` / `#14342D` |
| Data blue / violet / coral | `#75A7FF` / `#C8A5FF` / `#FF9E86` | `#416BA5` / `#72569A` / `#9A5547` | `#6CB6FF` / `#C4A7FF` / `#FF9CA8` |

`AppVisualTokens` owns these values plus derived status surfaces, success, soft
outline, shadow, and bounded data colors. Presentation code consumes
`Theme.of(context).colorScheme` or `context.visualTokens`; it does not add
route-local semantic colors.

Today and Planner share one semantic category mapping:

| Category | Visual role |
| --- | --- |
| Task, Setup | Brand/primary |
| Habit, Preparation, Exam, Assignment | Information/secondary |
| Calendar | Attention/tertiary |
| Focus | Violet data role |
| Fixed commitment | Danger |

Exam and Assignment therefore share a color while retaining distinct labels
and icons. The mapping colors the entire Planner seven-day row—surface, border,
icon, and text—not only an avatar. It never replaces the visible category
label. Preparation status pills use Attention for Preview/Source changed,
Success for Active/Completed, Danger for Cancelled, and Information for the
Exam/Assignment type.
Status pills retain their full visible label at large text and may grow
vertically instead of clipping, shrinking, or overflowing it.

Planner `Next seven days` and Today `Full week` share the feature-neutral
day-card and appointment-row layout without sharing read authority. Full week
uses the same category tokens for all seven `today-week-agenda-v1` categories;
its status text remains a visible source fact and is never color-only. Static
Setup, Calendar, fixed-commitment, and non-current Habit rows expose no enabled
control semantics. Actionable Preparation, Task, Focus, or current-day Habit
rows contribute one combined title/detail/category label and one tap target.
That target covers the complete row, including the visual status box, and is at
least 44 logical pixels high; static rows expose no button semantics.
The retired two-source rating/`fullyRated` status box is not part of Full week.

Only Full week may widen beyond Today's compact column. Its normal mobile strip
uses 40 percent of the available viewport per card (two full plus one half);
the named narrow/large-text mode uses exactly 50 percent (two full). The initial
Saturday/Sunday offset is clamped to preserve two real cards, and horizontal
movement snaps by one day without phantom space past Monday/Sunday. At a
content width of `7 × 208 + 6 × gap` or greater, the strip becomes seven equal
columns; one logical pixel below that threshold remains horizontal. Cards have
no fixed content height, so dense agendas and 200-percent text remain uncut.

The `planner-overview-v2` Habit collection is one initially collapsed card,
not a second agenda. Its count remains readable at 320 logical pixels and
200-percent text. Row status, cadence, nullable duration, `Managed in Setup`,
and pending-preview labels wrap vertically rather than overflow. Setup-owned
definition review uses labelled readable text with one semantics group; it does
not encode immutable values as disabled form controls. Only duration remains a
normal editable field.

Normal content surfaces have no outline. An outline is reserved for inputs,
keyboard focus, selected state, a conflict/warning/danger state, or a genuine
interactive boundary. Shadows are quiet, low-spread depth cues on raised
surfaces only.

The only hard-color allowlist is:

- the official four-color Google sign-in glyph in `auth_page.dart`;
- the advanced Insights chart series in `insights_page.dart`, where stable
  cross-series differentiation is the data meaning.

## Typography

Instrument Sans is bundled under the SIL Open Font License with local 400, 500,
600, and 700 weights. No runtime font request is allowed.

| Role | Size / line height | Weight |
| --- | --- | --- |
| Page title, mobile | 32 / 36 | 700 |
| Page title, desktop | 36 / 42 | 700 |
| Section title | 24 / 29 | 600 |
| Component title | 18 / 23 | 600 |
| Body | 16 / 24 | 400 |
| Secondary body | 14 / 21 | 400 |
| Label | 13 / 16 | 600 |

Metrics, clocks, duration, progress, and other aligned numbers use tabular
figures through `AppMetric` or an equivalent themed style. Text is allowed to
wrap and surfaces are allowed to scroll; text must not be scaled down to hide
an overflow.

Main-page top actions use one shared wrapping group on Today, Insights, Quick
actions, Planner, Coach, and Settings. Page-specific actions come first, an
unread Coach action comes second when present, and Settings comes last. Every
icon action owns a 44 by 44 logical-pixel target and keyboard/semantic label.
At narrow width or 200-percent text, `AppPage` stacks the action group below the
title instead of shrinking or overflowing it. The selected Settings icon uses
the filled icon and selected surface without creating another route.

## Shape And Surface Roles

The radius scale is `8 / 12 / 16 / 20 / pill`, exposed through `AppRadii`.
Ordinary cards use 12, dialogs use 16, and large shell or hero surfaces never
exceed 20.

`AppSurfaceVariant` has these meanings:

| Variant | Meaning |
| --- | --- |
| `plain` | normal base content |
| `subtle` | grouped supporting content |
| `raised` | an overlay, auth panel, or important shell region |
| `interactive` | a tappable/hoverable surface |
| `accent` | mint-associated information, not a solid CTA |
| `warning` | attention requiring icon/text explanation |
| `danger` | error or destructive context requiring icon/text explanation |

`AppCard` is a compatibility adapter over `AppSurface`. It has no independent
visual language: ordinary uses become subtle surfaces, and `onTap` becomes an
interactive surface. New presentation work should name the `AppSurface`
variant directly when the semantic role matters.

Shared primitives are:

- `AppBrandMark`;
- `AppSurface`;
- `AppSectionHeader`;
- `AppStatusPill`;
- `AppMetric`;
- `AppEmptyState`;
- `AppStatePanel`;
- `AppIconBadge`;
- `AppInfoDisclosure` and its section-heading adapter.

Settings uses visible `AppSectionHeader` groups for Profile, Planning and
learning, Tools and connections, and Account and appearance. These headings
organize the existing controls without adding another card style or changing
their authority. Feature panels, auth/recovery regions, Inbox groups, Weekly
facts, and Insights regions use the appropriate shared surface variant instead
of route-local borders, radii, and shadows.

Category color and status color are separate vocabularies. Data categories use
brand/data colors; they do not borrow success, attention, or danger merely to
distinguish one category from another. Freshness, stale,
unavailable, and destructive meaning uses `AppStatusPill`, `AppStatePanel`, or
another labelled semantic primitive.

## Icons

`phosphor_flutter` is pinned exactly to `2.1.0`. `AppIcons` is the product
vocabulary and the only student-facing icon source.

- Regular: default state.
- Fill: selected state only.
- Bold: compact checks and status marks only.

An icon never carries a status alone. Its visible label or adjacent status copy
remains authoritative. Icons retain the existing semantics label and touch
target.

`flutter_svg` is pinned exactly to `2.1.0` to preserve the repository's Dart
compatibility boundary.

## Motion And Interaction

`AppMotionTokens` owns:

- 120 ms for press and selection;
- 180 ms for state and navigation;
- 260 ms for progress and larger transitions;
- `easeOutCubic` as the normal curve.

Every non-essential custom transition resolves its duration through
`MediaQuery.disableAnimations`; reduced motion produces a zero-duration state
change. Space alone may render a deterministic overlay of `36..96` small cyan,
violet, and quiet white stars based on area, including a few subdued four-point
sparkles. The overlay uses a 24-second cycle; stars move by at most 14 logical
pixels vertically and four horizontally. Independently, the approved photo may
use one 48-second closed camera path: horizontal drift is at most six logical
pixels, vertical drift at most four, and scale remains `1.036..1.044` around a
`1.04` base. Only the image GPU layer moves; its readability scrim stays fixed.
The app pauses both controllers outside the active lifecycle. Reduced Motion
freezes photo and stars at deterministic phase `0.37` and replaces animated
ripple/press feedback with immediate state feedback. No drawn planets,
ribbons, orbits, constellations, input-driven parallax, mouse/scroll tracking,
device sensors, or other camera paths are permitted. No other theme gains
looping decorative motion.

Controls use at least a 44×44 logical touch target. Keyboard focus uses a
two-pixel strong-focus outline, including buttons, icon buttons, fields,
switches, checkboxes, segmented controls, and interactive surfaces. Hover,
pressed, disabled, selected, and loading states remain visually distinct
without changing product truth.

`AppInfoDisclosure` is the shared core behavior for optional explanatory copy.
It owns independent, route-local open state; removes a closed description from
semantics; exposes `Show information about <heading>` or
`Hide information about <heading>` with the matching expanded state; and uses
size plus opacity through `AppMotionTokens.stateFor`. Reduced Motion therefore
changes it immediately. Feature adapters may preserve stable test keys and
header composition, but must not reimplement toggle state, semantics, sizing,
or motion.

Only optional explanation or methodology belongs behind this control. Consent,
the consequence of a mutation, current/stale/error state, unavailable source
truth, required provenance, and the action needed to continue remain visible.
Several disclosures may stay open independently.

Every layout uses the global 44×44 hit/focus/semantics target around a visible
24×24 frame containing a 20×20 `AppIcons.infoOutline` icon. Daily Capture,
Today, Calendar import, Reminder settings, Personal learning, Weekly review,
and Preparation-plan explanations share that geometry. Section headings use
theme typography, including the compact `titleMedium` role where the disclosure
sits inside an existing card; they do not introduce raw font sizes. An
information control in an accordion header is a sibling of the explicit
44-pixel accordion button, never nested inside it; title/control/action groups
wrap rather than overflow at 320 logical pixels and 200-percent text. The
accordion button and every actionable shared schedule row expose the same
two-pixel `AppVisualTokens.focus` keyboard ring; static schedule facts remain
outside keyboard traversal.

Evening pressure-source help is a separate accessible info control: hover opens
the tooltip on web, tap opens it on touch, and neither path changes the
selection. The three influence choices remain equal-width/equal-height in one
row at 320 logical pixels and 200% text. Focus reflection ratings use five equal
columns; the low/middle/high anchors align under values 1, 3, and 5.

`AppPage` owns the top-left route back control. It pops actual pushed history
and uses an explicit feature fallback for a direct deep link. Shell navigation,
auth redirects, and completed flows replace history; in-page CTAs push it.
Primary shell destinations do not show a meaningless fallback back button.

## Material Coverage

`AppThemeId.dark`, `.light`, and `.space` are resolved through
`AppTheme.resolve`; `AppTheme.dark`, `.light`, and `.space` remain direct test
and component entry points. All three fully define:

- app bars, cards, dividers, list rows, and scrollbars;
- inputs and validation;
- filled, outlined, text, icon, and floating buttons;
- shell navigation and segmented controls;
- chips, switches, checkboxes, radios, sliders, and progress;
- dialogs, sheets, popup menus, menus, tooltips, and snackbars;
- date and time pickers.

Settings exposes one `Appearance` row and a vertically scrollable
`Choose appearance` dialog: Dark — `Calm dark default`, Light —
`Bright neutral`, and Space — `Animated violet and cyan`. Each choice has a
visible icon and three palette swatches and remains usable at 320 logical
pixels with 200-percent text. Selection closes the dialog and changes the theme
optimistically. The device-local `app_theme_mode` preference accepts exactly
`dark`, `light`, or `space`; missing or unknown values resolve to Dark. Writes
remain ordered, and a failed latest write rolls back to the last confirmed
selection and reports the existing appearance-save failure.

The normal Dark and Light content surfaces remain opaque and borderless. Space
uses the following bounded clear-material alpha values; the underlying token
color remains the tint:

| Space material role | Alpha |
| --- | --- |
| Plain surface | `0.48` |
| Subtle surface and idle interactive surface | `0.52` |
| Raised and hovered interactive surface | `0.58` |
| Pressed interactive surface and dense input/chip surface | `0.60` |
| Semantic information, attention, danger, and success surface | `0.70` |
| Dialog, menu, sheet, snackbar, and tooltip overlay | `0.82` |
| Shell navigation | `0.52` |

Space may add one hairline soft-violet depth edge to shared surfaces, cards,
overlays, pickers, and mobile navigation; hover shifts that edge toward cyan
and raised surfaces may carry one quiet violet ambient shadow. Plain and subtle
`AppSurface` roles add two short opposing HUD corner strokes: `18` logical
pixels in cyan and `12` in violet at one-pixel width. Raised and interactive
roles use `24` and `16` logical pixels at `1.25` width; hover strengthens cyan
and press makes violet primary. Accent, warning, and danger surfaces do not use
the HUD frame. These presentation-only edges do not change layout or replace
the stronger focus, selection, warning, or danger boundaries.

No content card or `AppSurface` owns a `BackdropFilter`. The responsive shell
owns exactly one filter at a time—desktop rail or mobile bottom navigation—with
sigma `8`; no extra filter is retained behind the inactive layout. Card depth
is tint, opacity, strokes, and existing shadows only. High Contrast replaces
all Space material alpha with opaque `1.0`, disables HUD strokes, and sets the
navigation blur to zero. This is a presentation fallback and leaves Dark and
Light pixel output unchanged.

Dark and Light keep Material splash disabled and retain their existing
hover/press/focus layers. Space uses a cyan `InkRipple`, a violet press
highlight, and short token-owned hover/press glows on shared interactive
surfaces, buttons, shell navigation, and the Quick-action button. Button
content compresses to `0.96` only while an enabled Space control is pressed;
the Quick-action button retains its stronger `0.94` press scale. Interactive
Space surfaces lift one logical pixel on hover and return to their base plane
while pressed. Selected shell destinations use a cyan `3×28` desktop or `24×3`
mobile signal with an 180 ms Reduced-Motion-aware fade. Disabled controls stay
flat and glow-free.

`AppThemeEffects` owns these differences. The app-level backdrop is behind the
Navigator. It paints Space's fixed background, selects the approved portrait or
landscape deep-field asset from the viewport aspect ratio, applies one uniform
readability scrim at alpha `0.40`, and finally paints the deterministic star
overlay while Space Scaffolds remain transparent. The two versioned local WebP
files are the only decorative raster-asset exception and together remain below
two megabytes; the app never fetches a runtime backdrop from the network. Their
photographic tonal falloff and the clear material do not relax the ban on Dart
gradients, shaders, `saveLayer`, shimmer, or route-local decorative images.
Image and painter layers are pointer-ignoring, semantics-free
`RepaintBoundary` content. Contrast tests use an all-white pre-scrim source as
the conservative luminance bound for every possible backdrop pixel.

## Responsive And Accessibility Gates

`exam-plan-health-v1` uses an icon plus text status pill for every state.
Preparation's value grid uses wrapping layout; Planner and Today use wrapping
titles/status and vertically growing subtitles rather than fixed-width trailing
metrics. All Health states, the transport error, and the editor preview must
remain readable and scrollable at a 320 px viewport and 200% text. Unknown and
transport error require distinct words and semantics, not merely distinct
colors.

`multi-exam-plan-v1` uses real expandable review semantics, icon-plus-text
status, wrapping before/after metrics, and full-width batch actions with at
least 44×44 targets labelled exactly `Confirm all` and `Discard`; essential
review text is never ellipsized. Target selection, history,
saved-refresh-failed truth, and stale review remain usable at 320 px and 200%
text. Keyboard focus, screenreader labels/live failure and saved-refresh status,
Light/Dark/Space themes, and current-profile-timezone time labels follow the
same objective gate; change state is never color-only.

The objective gate is:

- text contrast at least 4.5:1;
- non-text and focus contrast at least 3:1;
- two-pixel keyboard focus ring;
- minimum 44×44 targets, including information disclosures whose visible frame
  remains 24×24 around a 20×20 icon;
- no overflow or hidden action at 320 logical pixels and 2.0 text scale;
- representative checks at 390×844 and 1280×960;
- dark, light, and Space theme coverage;
- reduced-motion coverage;
- visible labels and semantics remain equivalent.

The reference slice is Shell, Auth/Recovery, first Setup, Today, Planner, and a
Planner form dialog. Today additionally covers local guest empty state, a rich
authenticated fixture, the compact check-in inset, independently expanded
supporting sections, and every Full-week status level. The full review matrix
includes:

| Loop | Routes and states |
| --- | --- |
| Daily | Quick actions, Morning, Evening, Focus, Habits, Preparation |
| Reflection | Insights, Personal learning, Weekly review |
| Controls | Coach, Inbox, Reminder, Calendar, Settings, Account flows |
| Cross-cutting | loading, empty, error, stale, offline, conflict, disabled |

The tracked component-reference suite includes frozen Space goldens at
390×844 and 1280×960; the existing Dark/Light goldens remain unchanged.
Baseline screenshots from the pre-V2 build and generated review screenshots
belong under ignored `.tools/visual-baseline/` and `.tools/visual-review/`.
They are local review artifacts, not participant evidence and not substitutes
for installed-device acceptance.

## Source Gate

Run:

```bash
npm run verify:visual
```

`scripts/check_frontend_visual_contract.mjs` rejects:

- Material icons in presentation code;
- gradients, shader decoration, and shimmer;
- raw numeric radii;
- uncontrolled named or hard colors outside the two documented exceptions;
- route-local fonts;
- route-local `TextStyle` outside the Insights canvas allowlist;
- any production `BackdropFilter` or `ImageFilter.blur` outside the single
  responsive shell-navigation owner, a missing Space HUD painter, blur sigma
  other than `8`, or a High-Contrast path that leaves clear materials enabled;
- canvas `saveLayer` in shared presentation code;
- missing exact package pins, font weights, license, mark, icons, or manifest
  colors.

The standard repository gate runs this check before Flutter analysis and tests.
The source gate prevents visual-system drift; it does not itself score visual
quality.

## Visual Review Rubric

A route is accepted only when every category independently reaches at least
8/10:

1. distinctiveness and brand restraint;
2. typography and hierarchy;
3. color and surface discipline;
4. component coherence;
5. state and motion polish;
6. responsive and accessibility behavior.

Objective gates must pass in full. The score is a deliberate review judgment,
not a claim inferred from source compilation or golden pixel equality.
