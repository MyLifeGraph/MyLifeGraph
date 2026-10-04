# Frontend Visual System V2

Wearable metric cards use `AppFeaturePalette` moon/footsteps/heart/pulse accents
from the approved design, darkened on Light for contrast; surfaces still use the
existing theme. Optional missing metrics say Unavailable. Cards switch to one
column at narrow/large-text layouts rather than clipping data.
Blocking list cards align icon, title/status and six-dot reorder handle; active
status is conveyed by text and shape as well as color. Customize's fixed Save
is outside its bounded scroll region. Icon/accent/layout are draft-only and all
four backgrounds retain the shared native block-screen renderer.
The five existing accent choices fill equal-width slots across their row,
with symmetric outer spacing and a minimum 48px height. The three layout
choices have equal outer dimensions and centered artwork;
large text stacks them at full width. Morning's optional note is always visible
and two lines high; Evening retains its original four-line geometry. Both use
a right-side microphone instead of increasing footer padding. Coach phone-data
actions put Reload/Delete side by side, with Sync separate; the three categories
are directly visible, while saved sample data and
privacy detail are disclosures, while cloud/provider consent stays visible.

Blocking Strict separates the active idle state from an explicitly requested
unlock countdown; before Unblock no countdown or disabled completion is shown.
Its existing ornament remains decorative. Android Customize places its edit
action above the native preview. Taps retain preview interaction, while vertical
swipes scroll the containing page; the actual blocking overlay is unchanged.

The separate `apps/website` product tour defaults to Liquid Glass, with saved
Dark, Light and Space alternatives in a compact icon dropdown. It retains the
canonical brand mark. Responsive synthetic panels follow the app's desktop
sidebar and mobile bottom navigation, but remain labelled as a simplified demo,
not the actual Flutter UI. The hero has a decorative CSS-3D phone
with synthetic Today content and floating glass accents, not a video player.
It uses all four palettes. A separate wrapper provides a five-pixel/eight-second
float, paused offscreen/in background tabs, plus fine-pointer hover tilt.
There is no scroll rotation. Reduced motion disables both additions; missing
visibility observation keeps the loop paused. App themes/layouts are unchanged.
Hero, demo and phone ambient layers use an elliptical closest-side fade that
reaches transparency on all four edges, including on ultrawide screens. These
masks affect only decoration, never the phone, copy, controls or section geometry.

The website demo invitation is a non-scrolling, slightly dimmed snapshot of its
responsive synthetic panels with a central glass play pill. It opens a native
dialog (mobile fullscreen) with fixed close/navigation controls and scrollable
content. Closing restores page position and focus. Preview and dialog share
palettes and translated content; no Flutter or backend behavior changes.
The modal header carries a small muted simplified-demo disclaimer below its
title. It wraps at narrow widths without shrinking the close/reset controls.

Today shows last check-in metrics directly, with a small parenthesized saved date
and no disclosure arrow. Task/Habit outcome icons update immediately; a small
trailing Saving indicator distinguishes pending persistence without replacing
the new outcome icon. Existing error recovery and action locks remain.

Manual Capture date selection is a compact text/icon control; the selected date
stays visible and changing it confirms draft replacement. Focus preparation
uses a compact passive bullet list without per-item controls and a single
Cancel/Ready & start action row. Long lists scroll inside the dialog.
Plan removal keeps existing compact action styling and accessible descriptions.

Mobile Auth shows a larger brand heading and one short encouraging sentence,
with email fields directly visible. The page centers its content vertically
when it fits and scrolls when needed for smaller screens, keyboard, enlarged
text, errors or required privacy notices. Authentication actions are unchanged.

Planner keeps its view toggle on its own row and uses an outlined `+ Add` in the
calendar heading (compact Add below the toggle in Planning), without
a separate creation card. Its existing modal retains all five creation choices.
That split is mobile/tablet only. At the existing desktop breakpoint, the
pre-split calendar-left/Add-new-below and compact-summary-right layout returns,
including the original bounded summary width and visible five creation actions.
Calendar import sits in the page header, beside Refresh when visible. Below 600px,
Planning's Add spans the content width. Desktop keeps its creation section.
Touch navigation supplements rather than replaces visible buttons: horizontal
main-page swipes are deliberate and nested scrollers retain gesture priority.
The root pager follows touch movement after the platform's horizontal touch slop.
Release commits at 22% width (48–120px), or after a 32px / 650px/s directional
flick; cancellation and diagonal movement snap back. No fixed time limit forces
users to rush. Navigation state changes only once the page settles. Reduced
motion retains the discrete shortcut instead of dragging page content.
Root-page transitions enter from the right for a later destination and from the
left for an earlier destination, consistently for buttons and swipes. Reduced
motion removes the slide; auxiliary push/back navigation is unchanged.
Incoming root pages cover outgoing content with the existing opaque background
token during the slide, then expose the unchanged shared backdrop once settled.
If an auxiliary page is pushed during swipe settlement, the covered pager restores
its routed page; it cannot navigate underneath that page or change the Back target.
Header Back visibility is route-local: opening Settings must not insert a Back
button into the page underneath or shift its title/actions on return.
Planner's upward creation shortcut starts only on the bottom navigation;
ordinary page scrolling must never open the menu.

Coach and Ultra Quick show a compact, directly toggleable UK/German flag in
their header actions, using existing icon-button targets and tooltips naming
the current and next language. No language dialog, additional panel, translated
navigation or new palette is introduced. The flags retain disabled state during
their in-flight operation; Coach also locks language for an exact retry.

Settings uses the compact page header without a redundant Settings cog on that
same page; optional Coach-result notices and Back remain. Other page header
actions are unchanged. Focus target menus cap their height to the usable
viewport and scroll their options rather than clipping the last entry.

The hosted Turnstile page includes padding inside its viewport width. At render,
containers below the provider's 300px flexible minimum use its supported compact
layout; wider containers use flexible sizing. Do not crop or scale the challenge.

Coach dictation uses the shared Phosphor microphone in a normal icon button
immediately before Send. Recording has a labelled stop action and semantic error
color; transcription shows a compact progress indicator with a cancellation label.

The permanent Coach outline encloses the timeline and bottom composer below the
fixed capability status card. Only the timeline scrolls on the main page;
the header, frame and composer stay fixed. Loaded history
starts at its newest message. The frame uses existing outline color and radius;
A circular tonal down-arrow floats at the bottom center of the timeline only
while scrolled above the latest message; it never displaces the composer.
message cards retain their existing styling. Empty-state typography is unchanged.
The frame retains an 8px top inset even while its timeline scrolls. The composer
model icon remains available when capability loading fails; errors stay above.
Optional Coach explanations open in a bounded, scrollable popover instead of expanding
the fixed panels, retaining access at large text sizes.

The Coach provider/key controls use the existing Settings card, field,
dropdown, button, spacing, and error-text primitives; they introduce no new
visual token or icon family.
Coach places a tune icon before the microphone, replacing the composer Info
icon. It opens the existing dropdown/key controls and explanations in a dialog,
with BYOK fields only when selected. Cost/data-sharing and errors remain visible.
The bottom composer starts at one text line, grows to four, and uses a Send
icon with a visible tooltip/semantic label; its zero character count is hidden.
The chat scrolls independently above it; the text field retains its own editing
scroll behavior. When the remaining frame is too short (for example at large
text sizes), the composer joins the same chat scroller so its controls stay
reachable. The main page has no additional composer/page scroll container.
User messages align right on the existing raised surface; Coach replies use
existing cards with uncertainty and expandable analysis details. No new colors,
fonts, radii, provider behavior, or chat-memory contract is introduced.

The hosted `pilot-participation-v1` /
`pilot-participation-notice-v1` adult/privacy gate and persistent staging identity use existing
`AppSurface`, checkbox, button, typography, spacing, and semantic-color
primitives and remain usable at the existing responsive/text-scale boundary.
The staging label is text, not color-only meaning. The implemented hosted
Project-Coach/BYOK choice, busy countdown, and secondary `Build identity`
diagnostic reuse the same cards, dropdowns, buttons, typography, wrapping, and
semantic-state text. The implemented Turnstile loading/cancel/retry/error
lifecycle and irreversible/pending restore-safe account-deletion surfaces reuse
these primitives,
responsive breakpoints, focus treatment, reduced-motion behavior, and 200%
text boundary. Busy, unavailable, expired challenge, invalid key, and
provider-disabled states need visible text rather than color-only meaning.
Repository presentation does not prove hosted/live acceptance.

Status: implemented repository visual contract for Flutter Web and Android as
of 2026-08-01.

## Product Intent

MyLifeGraph presents itself as a calm, precise personal operating system rather
than a generic Material or AI-wellness interface. The system is mobile-first at
390×844, remains fully usable at 320 logical pixels and 200% text, and uses the
same hierarchy on desktop at 1280×960.

This contract changes presentation only. It does not change navigation,
student-facing capability truth, product copy, data contracts, persistence,
backend APIs, or mutation authority. Dark remains the default. Light, Space and Liquid Glass
remain persisted, device-local manual choices rather than system-theme modes.
Space is a dark violet/cyan theme; it has no separate light variant.

Outside the opt-in Liquid Glass theme, the interface uses no code-generated gradients, shimmer loops, confetti,
illustrative scene decoration, or general-purpose blur-heavy glass system.
Space is a bounded clear-material exception: it combines tinted
translucent surfaces and sparse HUD strokes with one of two approved local,
photorealistic deep-field WebP backdrops, a restrained looping star overlay,
and minimal closed-path camera drift on the photograph. Actual backdrop blur
is restricted to the one currently visible shell-navigation surface. Both
depth layers are presentation-only and change no content or layout; Reduced
Motion freezes them at the same deterministic phase. Brand mint in Dark/Light
and brand cyan in Space remain their solid call-to-action colors; Liquid Glass
uses muted steel blue. Information
blue, attention amber, danger red, and supporting data colors never replace a
visible icon or text label.

## Brand

The brand mark is a path joining three explicit nodes on a 24×24 grid. Its
canonical source is
`apps/mobile/assets/brand/app_brand_mark.svg`; explicit-color `AppBrandMark`
instances and the Android notification silhouette retain that geometry.
The default app mark uses approved silver/ice-blue Liquid Glass artwork on a
dark blue/violet background (`app_icon_glass.png`), without recoloring other
themes. It may appear once prominently on a screen and must not become a repeating
background pattern.

`scripts/generate_brand_assets.py` resizes the tracked, approved
`app_icon_glass_source.png` with Pillow (no generation/network/secrets) into
the in-app tile, Android launcher/adaptive artwork, PWA icons and favicon.
The source has generous central safe margins for maskable/adaptive icons.
Android splash vector and monochrome notification icon retain the canonical
three-node geometry. The launch background and default web chrome use the dark
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
and icons. Default agenda cards color the row with category tokens. The Planner
reference layout instead uses neutral raised appointment surfaces, category
rails and icon badges, primary titles and secondary details. This opt-in skin
uses a rounded `outlineSoft` frame around all Days appointments, growing with
the day's content and using page scrolling rather than internal scrolling.
The date controls remain outside; the empty label remains explicit. Four or more
appointments are not capped or clipped. This presentation
does not alter Today. Color never replaces the visible category
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

Outside the Space/Liquid Glass material edge, normal content surfaces have no outline. An outline is reserved for inputs,
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

Main-page top actions use one shared collapsible group on Today, Insights, Quick
actions, Planner, Coach, and Settings. Page-specific actions come first, an
unread Coach action comes second when present, followed by Inbox and Settings. Every
icon action owns a 44 by 44 logical-pixel target and keyboard/semantic label.
Today, Insights, Planner, and Coach align title-left/icon-actions-right at the
same 16-pixel mobile top/right inset. Large text moves actions above the title.
Below 600px, ordinary Insights/Planner/Coach refresh icons are replaced by
pull-to-refresh at the primary scroller's top. Wider screens keep labelled
refresh icons; explicit failure/retry actions remain reachable at every width.
The shared AppPage refresh wrapper is opt-in and never wraps fixed viewport
controls. Today and Insights own their primary scrollers; Coach owns its chat
scroller. Each uses the theme's existing progress indicator and default primary
scroll-notification predicate, without intercepting nested horizontal gestures.
The selected Settings icon uses
the filled icon and selected surface without creating another route.

## Shape And Surface Roles

Android App blocking reuses these surfaces and all four current themes for
Plans / Strict / Insights / Customize, named plan tiles and compact sheets.
The shared-header shield sits before Settings. The dedicated device-tool route
uses its own tab bar without stacking the main shell bar. Native overlay/offline
pages use a bounded background/icon palette rather than Flutter blur shaders;
this is a platform-specific block-screen choice, not a change to app theme tokens.

Blocking target selection uses a bounded app list and fixed Save footer with
count/disclosure. Selected checks are slightly larger and use primary/on-primary
contrast; preset chips use existing selected colors. No new palette or Liquid
Glass material is introduced. Large text may wrap the count but never hides Save
or the accessible disclosure control.
The selected blocking tab uses its theme's primary-container pill and contrasting
icon/label. Cards show compact timing summaries; detailed weekly windows remain
in the editor/details. Usage magnitudes appear above
bars where they fit, with wrapped labelled values for longer/enlarged text and
compact range total/peak for dense Month charts. Strict adds no explanatory row.
Blocking cards align compact text beside their icon with flexible wrapping. Customize
uses matching centered return/edit action widths in its labelled non-Android
approximation, capped at 286px with 48px minimum heights. Android uses the real
native app-screen renderer inside a bounded 9:16 frame (maximum 340px width).
Saved custom tone/icon/text/delay and Strict state are creation parameters;
the interactive preview never mutates protection. Native app overlays and preview
share centered scrollable content, system insets and an oval left-to-right return
fill (minimum 60dp height, wrapping text). Reduced animation settings disable
interpolation; readiness snaps immediately and leaves no animation running.
Native light pools and fill colors stay within the existing bounded tone palette;
Shield, work, games, social, sleep and study use fixed 24-unit outline paths,
rendered at 48dp in the native preview/overlay and 48px in offline SVG. The
foreground follows the saved Glass/Dark/Light/Space background. Unknown icon
IDs render a shield; no user markup or font-dependent substitute is rendered.
Flutter palette/material tokens remain unchanged. Offline website pages retain
their separate document renderer.

Watch, Calendar import and the Exam wizard use compact shared surfaces:
primary actions first, optional details collapsed, source actions in a labelled
overflow, and paired controls only when width/text scale allows. This layout
polish does not change any palette, glass opacity, backdrop, shadow or shared
theme token. Consent, errors, replacement consequences and all inputs remain.

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

A compact `Website` ListTile under Tools and connections uses the existing
globe and external-link icons with no subtitle, matching adjacent settings.

Android `Updates` uses the same compact ListTile/shared subtle surface, under
Account and appearance. Version/check controls and the one-time notice use themed
scrollable AlertDialogs with wrapping actions; no new palette or decoration.

Inbox uses three equal-width compact counters, smaller category icons and a
shared top-right icon-action row on mobile and desktop, stacked below the title
when narrow or text is enlarged. Allowlisted cards use the interactive surface.
Preserve accessible touch targets,
tooltips, scalable text, item provenance and visible lifecycle feedback.

Category color and status color are separate vocabularies. Data categories use
brand/data colors; they do not borrow success, attention, or danger merely to
distinguish one category from another. Freshness, stale,
unavailable, and destructive meaning uses `AppStatusPill`, `AppStatePanel`, or
another labelled semantic primitive.

## Icons

Today check-in buttons use muted attention/success surfaces and matching
outlines for pending/saved states. Labels and existing saved-check icons remain;
pending is not an error and does not use a red cross.

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
looping decorative motion outside the explicitly requested Strict status ring.
That feature-local ornament uses the current theme accent and a static shader
defined by the Liquid Glass optical owner; only its isolated render layer turns
once per four seconds. The central lock stays fixed. Motion requires actual
locked state, foreground lifecycle and visible TickerMode; Reduced Motion
freezes it. It is never styled or announced as countdown progress.
Wearables retains its existing controls and adds an enlarged Phosphor watch
with a short, state-derived connection label. Its finite state fade uses the
shared state token; no continuous watch motion or new palette is introduced.

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

Every layout uses the global 44×44 hit/focus/semantics target around a
24×24 container containing a quiet 20×20 `AppIcons.infoOutline` icon. The
container is frameless at rest; its two-pixel focus outline remains visible.
Daily Capture,
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

Shared section headings and Today headings additionally open the same explanation
in a compact anchored popover on long press. It has no repeated title or Close
button; outside tap, Back or Escape dismisses it without triggering underlying
actions. It stays readable without a timer and scrolls if text is long. This is applied only to the heading, not surrounding
cards or actions. The visible information button remains available to touch,
keyboard and assistive technology. Useful rules are retained, not hidden solely
behind an undiscoverable gesture.

Settings offers device-local `Haptic feedback`, default on. Deliberate Capture
choices/ratings, Today task/habit check-offs and heading long-press may produce
one subtle selection pulse on Android/iOS. No pulses run during scrolling,
preference restoration, or on web/desktop. Repeated pulses are bounded to one
per 100ms; hardware failure never blocks an action. This is interaction feedback,
not a guarantee of a successful backend save. The switch controls this app's
added feedback, not operating-system keyboard or accessibility feedback.

Evening stress-source selection first highlights the row and reveals a chevron.
The header uses a subtle brand tint; its chevron uses primary text contrast
(near-white in dark themes). The expanded input uses the separate subtle surface.
A second tap toggles the optional blocker; selection and typed text are retained.
When expanded, the optional blocker remains inside the same
outline at the choice width, with the Info action outside to its right. A subtle
separator joins header and borderless input; no nested card frames. The expansion
uses state motion, or no animated wrapper under reduced motion. Capture rating
hover is neutral rather than brand-tinted; keyboard focus retains a two-pixel
outline. Stress chips use explicit selected fills and no green hover/focus wash.

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

`AppThemeId.dark`, `.light`, `.space`, and `.liquidGlass` are resolved through
`AppTheme.resolve`; corresponding `AppTheme` properties remain direct test
and component entry points. All four fully define:

- app bars, cards, dividers, list rows, and scrollbars;
- inputs and validation;
- filled, outlined, text, icon, and floating buttons;
- shell navigation and segmented controls;
- chips, switches, checkboxes, radios, sliders, and progress;
- dialogs, sheets, popup menus, menus, tooltips, and snackbars;
- date and time pickers.

Settings exposes one `Appearance` row and a vertically scrollable
`Choose appearance` dialog: Dark — `Calm dark default`, Light —
`Bright neutral`, Space — `Animated violet and cyan`, and Liquid Glass —
`Dark glass, soft light`. Each choice has a
visible icon and three palette swatches and remains usable at 320 logical
pixels with 200-percent text. Selection closes the dialog and changes the theme
optimistically. The device-local `app_theme_mode` preference accepts exactly
`dark`, `light`, `space`, or `liquidGlass`; missing or unknown values resolve to Dark. Writes
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

### Liquid Glass

Liquid Glass is an additional dark, graphite/silver Flutter appearance inspired
by optical glass, not Apple's native rendering API. Existing Dark, Light and
Space definitions, component geometry, typography, navigation and content remain
unchanged. Palette ownership remains `AppVisualTokens.liquidGlass` (background
`#080A0E`, surface `#10141B`, primary text `#E5E9EF`, secondary text `#ADB7C4`,
brand `#A5B8CF`). All Material controls, overlays and pickers use that palette.
Content is near-black rather than frosted gray; steel-blue actions avoid large
white fills. Attention uses muted champagne `#CDBE9E` over `#211F1B`, not bright
orange. Success/error remain distinct and retain their visible labels/icons.

`core/theme/app_liquid_glass.dart` alone owns static gradient definitions:
a dark graphite/charcoal backdrop, localized cool highlights fading toward a
nearly unlit center, and a one-pixel rim with alternating light and quiet edges.
Two stationary, diffuse blue/violet light pools sit behind content. The shared
paint-only accent wrapper is used by both the app backdrop and opaque page
backing; cards reveal these lights through their tint as content scrolls.
Surface lighting is blended with the actual semantic tint. Shared surfaces and Material
overlay shapes consume these without changing content padding or touch targets.
Warning, danger, selection and keyboard-focus boundaries take precedence over
decorative edges; status labels and colors remain meaningful.
Glass AppPage routes paint their own opaque backdrop so auxiliary navigation
does not expose the previous page's text through the new page's material.

Plain/subtle content alpha is 0.56/0.60; raised 0.76; interactive 0.62/0.74/0.84
(idle/hover/pressed); dense controls 0.92; semantic surfaces 0.94; overlays 0.97.
Menus/dialogs deliberately remain nearly opaque for readable overlapping content.
Navigation uses alpha 0.62 and the existing single clipped sigma-8 blur. There
are no per-card backdrop filters, new dependencies, remote assets or continuous
animations. High Contrast removes glass lighting, rim and blur, using opaque
surfaces. Reduced Motion retains existing immediate state transitions.

Nested plain/subtle glass surfaces omit their second decorative rim and sheen;
interactive/selected/focus/warning edges remain intact. Planner's timeline rows
use a quiet translucent tint without an extra inner outline in Liquid Glass.
Category color paints only the narrow left accent, never a full opaque layer
under that translucent row; primary/secondary text retains its dark-surface contrast.
Shared header actions form one rounded, softly raised glass island in Liquid Glass,
with clear individual icons and unchanged 44px targets, focus and navigation.
The resting state is a 48px circle with a menu icon. Opening reveals the existing
actions right-to-left in the same header row, with a fixed title and anchor throughout.
Horizontal clipping and a subtle fade use the shared 260ms emphasis curve;
glyphs are not scaled. Reverse animation closes it; outside tap, Back, Escape,
activation or leaving the page dismisses it. Outside swipe/scroll also closes it
without consuming the underlying gesture. Reduced Motion is immediate.
Selection haptics obey the existing toggle. The overlay has a legible surface,
title-bounded width and horizontally scrollable 44px targets rather than
wrapping or shrinking icons. Scrolling icons inside the capsule leaves it open.
Icon targets use 44px and consume the full title-bounded capacity; no fixed icon
count or arbitrary desktop width cap is imposed. Only measured overflow adds an
accessible end-scroll chevron. It changes direction at the end, leaves the menu
open on pointer/keyboard activation and disappears when resizing lets all icons
fit. At widths below two targets, the existing swipe gets a passive edge cue
instead of sacrificing an action's target. Title, palette and reveal remain.
Loaded Today/Insights headings reserve the same title space as loading/error
pages. Activation dismissal also applies to screenreader actions, not only
pointer/keyboard input, without excluding native focus/tap semantics (including
the unread Coach notice); tab departure is observed independently of open state.
An unread Coach dot remains visible on the closed circle.
Inside the island, icons omit individual sheen/background tiles and resting
borders. Circular press/hover feedback and a two-pixel keyboard focus ring
identify the active control without adding permanent dividers or a white wash.
Dark, Light and Space share the rounded island geometry and frameless icons,
using their own unchanged palette and surface effects. Backdrops and light pools
are unchanged. Compare's heading spans the card width. Below it, correlation
values and insufficient-data status sit beside the explanation/action for every
7/14/30/90-day window on normal phone sizes; large text stacks without clipping.
Fixed commitments use a neutral category accent, not the error palette, in all
themes; actual conflicts retain their status color and text.

This bounded gradient exception does not permit decorative gradients in feature
pages or change the existing Space rendering contract. Mobile and desktop keep
their existing layout and controls.

Coach recording uses compact theme-colored PCM-level bars plus remaining seconds
between Discard and Stop/Send. Display-only logarithmic scaling makes normal
speech visible and leaves silence flat. Bars animate only as audio levels change;
reduced motion updates levels immediately without interpolation. The countdown remains readable without a per-second
live-region announcement. Existing recording controls retain their target sizes.

Color, typography, icons, and surface treatments stay consistent between mobile
and desktop; responsive positioning and layout may differ. Today uses one
1080-pixel maximum content width, including Weekly review and Full week.

Planner uses the supplied mobile/desktop references through existing tokens:
mobile weekday underlines, desktop date chips, wide event rows, compact icon-led
summary cards. `This week` shows the calendar and Days/List; `Planning` shows
supporting sections, with a desktop creation/summary split. Both use the existing
segmented-control vocabulary and preserve the calendar's selected date/view.
Existing shell navigation/FAB remains authoritative; large mobile text gets
additional bottom clearance and full-width stacked appointment text.

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
- gradients outside the exact Liquid Glass theme owner, shader decoration in
  feature/shared-widget code, and shimmer;
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
