# Frontend Visual System V2

Status: implemented repository visual contract for Flutter Web and Android as
of 2026-07-29.

## Product Intent

MyLifeGraph presents itself as a calm, precise personal operating system rather
than a generic Material or AI-wellness interface. The system is mobile-first at
390×844, remains fully usable at 320 logical pixels and 200% text, and uses the
same hierarchy on desktop at 1280×960.

This contract changes presentation only. It does not change navigation,
student-facing capability truth, product copy, data contracts, persistence,
backend APIs, or mutation authority. Dark remains the default. Light remains a
persisted manual choice rather than a new system-theme mode.

The interface uses no gradients, glass effects, shimmer loops, confetti,
decorative AI illustrations, or permanent animation. Mint is the only solid
call-to-action color. Information blue, attention amber, danger red, and
supporting data colors never replace a visible icon or text label.

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

| Role | Dark | Light |
| --- | --- | --- |
| Background | `#08110F` | `#F6F6F1` |
| Base surface | `#101A17` | `#FFFFFF` |
| Subtle surface | `#15221E` | `#EEF2ED` |
| Primary text | `#F2F6F3` | `#15201C` |
| Secondary text | `#A8B6B0` | `#53625C` |
| Brand mint | `#69E0BD` | `#087A65` |
| Strong focus | `#9AAEA6` | `#687B73` |
| Information | `#9CB7FF` | `#3F6399` |
| Attention | `#F2C470` | `#7A5700` |
| Danger | `#FF8E86` | `#B23B36` |

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
- `AppIconBadge`.

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
change. There is no looping decorative motion.

Controls use at least a 44×44 logical touch target. Keyboard focus uses a
two-pixel strong-focus outline, including buttons, icon buttons, fields,
switches, checkboxes, segmented controls, and interactive surfaces. Hover,
pressed, disabled, selected, and loading states remain visually distinct
without changing product truth.

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

`AppTheme.dark` and `AppTheme.light` remain the only theme entry points. They
fully define:

- app bars, cards, dividers, list rows, and scrollbars;
- inputs and validation;
- filled, outlined, text, icon, and floating buttons;
- shell navigation and segmented controls;
- chips, switches, checkboxes, radios, sliders, and progress;
- dialogs, sheets, popup menus, menus, tooltips, and snackbars;
- date and time pickers.

The normal content surface is borderless. Material splash is disabled; state
feedback comes from the explicit hover/press/focus layers and motion tokens.

## Responsive And Accessibility Gates

The objective gate is:

- text contrast at least 4.5:1;
- non-text and focus contrast at least 3:1;
- two-pixel keyboard focus ring;
- minimum 44×44 targets;
- no overflow or hidden action at 320 logical pixels and 2.0 text scale;
- representative checks at 390×844 and 1280×960;
- dark and light theme coverage;
- reduced-motion coverage;
- visible labels and semantics remain equivalent.

The reference slice is Shell, Auth/Recovery, first Setup, Today, Planner, and a
Planner form dialog. Today additionally covers local guest empty state and a
rich authenticated fixture. The full review matrix includes:

| Loop | Routes and states |
| --- | --- |
| Daily | Quick actions, Morning, Evening, Focus, Habits, Preparation |
| Reflection | Insights, Personal learning, Recommendations, Weekly review |
| Controls | Coach, Inbox, Reminder, Calendar, Settings, Account flows |
| Cross-cutting | loading, empty, error, stale, offline, conflict, disabled |

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
