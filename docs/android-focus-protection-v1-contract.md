# Android Focus Protection V1 Contract

Customize adds bounded `accent` (`theme`, `mint`, `blue`, `violet`, `rose`) and
`layout` (`compact`, `balanced`, `spacious`) fields to the existing custom map.
Missing fields retain theme/balanced defaults. Its native draft preview uses the
same renderer as the overlay, six icon choices, four backgrounds, unchanged
title/message limits and Return delays. Save stays outside the scroll area.
Cancel writes nothing; native revision and Strict/Focus edit locks still apply.

Status: implemented repository boundary, 2026-08-01.

## Named Blocking Plans V2

The current Android surface is **App blocking**, reached from the header shield
or existing Settings entry. Its four local tabs are Plans, Strict, Insights and
Customize. This route hides the main shell navigation to avoid stacked bars.
Flutter uses existing themes, icon, spacing and surface tokens.
The header keeps only Permissions & limits at the right. Top-edge pull-to-refresh
uses a theme-owned progress indicator on all four local tabs, including short
contents. It reads local native status, additionally reloading usage on Insights;
it makes no cloud call or Strict visibility change. Explicit refresh is
single-flight and suppressed during writes, editors and active plan reordering.
Failed reads retain the previous view and can be retried with another pull.
Compact plan cards open their editor on one tap when editable; locked cards
retain read-only details. Dedicated six-dot handles reorder plans, with
accessible Move up/down menu alternatives. Hold the handle for one second to
arm dragging; only a successfully armed drag uses the saved subtle-haptic
preference. Earlier swipes remain ordinary scrolling. Plans use one page-owned
sliver viewport so edge dragging can reach offscreen cards. The saved plan-array order is
presentation-only: it never changes OR-combined enforcement. Reordering uses
the opening revision and preserves the prior view on failure. Its native
`reorder` command accepts only `revision` and an exact ID permutation, retaining
every saved definition/customization; it may run under Strict or a Focus lease
without permitting rule edits. Edit, Pause,
Resume and temporary Pause replace a plan in place rather than moving it.
The selected local tab adds a quiet palette-owned pill behind its unchanged
icon/label and selected semantics; large text retains the two-column wrap.
Plan cards show short rule labels, native active status, a finite end for
single-rule timers/weekly windows, or daily allowance remaining. Missing usage
access is unavailable, not unused allowance. Combined OR rules conservatively
retain Active rather than promising one rule's end is the end of protection.
Details/editors show every stored weekly window, with start weekdays, local wall
times and an explicit next-day end where needed. `Device time` distinguishes
these native schedules from profile-timezone Planner facts; no inferred or
example windows are displayed.
Detailed weekly clock/text groups wrap without dropping weekdays or overnight
information. Compact cards retain status pills, target counts and plan menus.
Customize embeds a bounded interactive Android preview
using the same `BlockingScreenView` as the app Accessibility overlay. Its timer
and Return replay are preview-local: no rules, attempts, lease or release change.
Changing saved appearance recreates the view. Unsupported/web surfaces retain a
clearly labelled approximate Flutter preview and matching centered edit action.
The embedded Android preview accepts taps, while vertical drags belong to the
containing page rather than its native inner scroller. Its Customize action is
above the tall preview so editing remains reachable on short screens. The actual
blocking overlay retains its native scrolling and return authority unchanged.
The native effective `active` flag controls the accent rim, icon and summary;
an explicit shield/status pill supplements color. Paused, expired and scheduled
cards remain neutral. Neither a saved rule nor an enabled plan alone claims
protection: native master, Accessibility and effective-target gates still apply.

`blocking-plans-v2` is a device-channel contract, not FastAPI/Supabase. It has
explicit registry coverage because its named constants are Kotlin/Dart, not
Flutter/FastAPI. The private `com.mylifegraph.app/blocking_v2` channel returns
that version; Flutter rejects incompatible responses. V1 Focus lease/DND
channels remain unchanged. No cloud table, route, upload or analysis input is added.

### Plan authority and compatibility

Plans hold id/name/icon, app/domain sets, enabled/paused state, up to twelve
weekly windows, a timer, shared daily minute budget, Focus and Always selections.
Rules combine with OR; overlapping plans also combine with OR. Editing,
pausing or deleting one cannot clear another. Menus provide Edit, Duplicate,
Pause/Resume, ten-minute pause and confirmed Delete. Quick Block creates a
normal plan with an initial one-hour timer; custom timers/budgets accept
1–1440 minutes. Names are limited to sixty characters. Weekly windows retain
V1 device-zone/DST, overnight/start-day and exclusive-end semantics. Focus
uses only the existing real lease; no synthetic session is created.

Native writes validate targets/rules, exclude essential packages and reject
stale revisions. Editors keep their opening revision. Cancel writes nothing.
Opening Edit from a retained detail resolves its ID against the current status
snapshot; removed IDs cannot be recreated. The resolved definition and revision
remain paired while the catalog loads and throughout saving.
Save sheets remain open on failure and cannot be dragged away during persistence.
Revoked website/usage access stops enforcement/observation, not plan management:
unchanged retained targets and budgets can be saved, reduced, paused or deleted;
new website targets and new/increased budgets require the relevant access.
`mylifegraph_blocking_v2` private preferences hold plans, website/usage consent,
Strict, customization and local counters. Until first plan save, read-only
compatibility projects V1 selections into named plans preserving each app's
Focus/weekly/Always/timer choices. First save establishes V2 authority without
deleting V1 settings or lease/DND state. Thereafter legacy Permissions manages
master/app-blocking/DND switches only; named plans own targets and rules.
Active Focus leases still prevent configuration changes. Master, app-blocking
and granted Accessibility gate protection/status.

Rapid Add/catalog and Strict Wi-Fi/NFC setup opens are single-flight, including
repeated taps before the next rendered frame. Status and usage loads have independent
generation guards, including failures; denied usage is unavailable, never zero.
Editors retain drafts after failed persistence and freeze focused keyboard input
while saving. Strict setup advances its expected revision only for its own
successful enrollment, not unrelated page reloads. Foreground refresh tracks timer,
pause, budget and weekly boundaries and stops on background/disposal. Expired
timer-only plans say `Expired`, not `Scheduled`. Active status requires an effective
app or consented website target as well as the protection gates.

Legacy selections above the new-plan bounds remain compatible without discarded
targets or truncated labels: an existing set above one hundred plans can be
retained/reduced, but cannot add new IDs until it is within that bound. Existing
overlength names/IDs/packages are grandfathered only unchanged; new values retain
the normal V2 bounds.

The disclosed launcher picker uses native icons, search, Clear, Social media,
and Games (Android-declared category). Its bounded, independently scrolling list
keeps the Apps disclosure reachable; a fixed footer repeats the disclosure and
selection count beside Save, above keyboard/navigation insets. Checks use the
current theme's primary/on-primary contrast. Preset chips reflect whether all
their installed apps are selected; tapping remains additive and never removes
manual choices. Collapse and search preserve the draft; only Save persists it.
Missing categories are not guessed. Domains match exact host or subdomain boundaries;
optional common-site chips never silently select websites.

### Local timer notifications

Saved, enabled, unpaused plans with a future timer show their name and Android's
live countdown in a separate silent `Blocking timers` notification channel.
The large artwork decodes the dedicated PNG drawable, not adaptive launcher XML;
the small status-bar icon remains the monochrome graph required by Android.
Master/app protection, Accessibility and effective app/consented-site targets
must still be available. Multiple plans use independent stable notification tags;
pause, deletion, disable, consent/access loss and expiry remove only this feature's
notifications. A tap opens MyLifeGraph, with no command or Strict shortcut.
Android 13+ notification permission is requested once after saving a timer;
denial leaves the saved plan and enforcement unchanged. Users can disable the
channel in Android notification settings independently of Cloud push consent.

The OS chronometer renders seconds, not per-second notify calls. Existing service
ticks, mutation/resume, clock/package/boot broadcasts and an inexact expiry alarm
reconcile persisted truth. API 26+ also sets a notification timeout. On API 24–25,
hard process death/Doze can delay cleanup until an allowed alarm/service/app path.
Clock changes rebuild the countdown; no fixed timezone offset is used.
Plan names are private on the lockscreen, with generic public copy.
No FCM, Supabase row, Focus lifecycle, DND policy or analysis input changes.
Own DND and OEM/system notification settings can hide this optional display.

### Usage budgets and charts

Budgets require separately disclosed Android Usage Access. Native reduction
tracks resumed activity class through the public UsageEvents API, ignores
pauses for different classes, clips to the current
device-local day and stops at screen-off. Denied access is not zero usage and
cannot authorize a budget. App usage refreshes within five seconds while the
service runs. Today/Week/Month ranges use calendar days, not fixed 24-hour
offsets. OS foreground history is not proof of attention and may include time
under an accessibility overlay. Same-class multi-window instances cannot be
distinguished by this public API. Histories remain on-device.

Website budget time measures only observable foreground time for selected
budget domains **since both website and usage consent/access**, not reconstructed historical or universal
browser usage. Hidden/unsupported address bars cannot be metered. When a browser
is an app target, its site time is not added again. Only selected budget
domains are stored, without paths/queries, for at most thirty-two days. Site
persistence batches at five seconds and flushes on service interruption or
destruction; abrupt process death may lose the last unflushed interval.
Returning to MyLifeGraph clears browser meter state. Attempts count blocking
entries, not every redraw, with today/total counters.
Usage charts display a range total from the returned daily measurements.
Today/Week additionally show each daily magnitude directly; enlarged text wraps
dated values rather than shrinking them. Month keeps its thirty bars and
individual accessible tooltips, with a compact total and peak scale instead of
thirty cramped value labels. App rows, totals, peaks and daily labels share
compact measured durations (`30m`, `2h 30m`, `1d 9h 20m`), using the largest
applicable units and up to three components without changing stored milliseconds.
These are elapsed days of 24 hours, not calendar-day or timezone arithmetic.
Durations use the measured whole seconds/minutes,
with a nonzero subsecond value shown as `<1s`; unavailable data remains unavailable.
Insights app rows reuse the catalog's local PackageManager PNG renderer (64px
source on the existing worker). The optional base64 `icon` field is additive to
`insights.apps`: missing, uninstalled or failed icons return an empty string;
older responses may omit it. Flutter retains its existing IconTheme-sized
leading slot, spacing and generic fallback for absent or invalid images. No full
catalog/extra consent, remote icon lookup or cloud upload is introduced, and
the bounded top-twenty ranking, measurements and channel version stay unchanged.
Plans omits the redundant permanent browser list; the explicit website-consent
dialog still explains address-bar-only detection, unsupported/hidden bars and
no page-content or browsing-data upload.

### Strict and customization

The Strict status ornament keeps its lock fixed while a theme-owned light arc
turns once per four seconds only while actually locked. This is decoration,
not unlock progress; the existing labelled countdown remains authoritative.
Reduced Motion freezes the ring. Hidden routes, other tabs and inactive app
lifecycle stop its ticker; disposal releases the controller and observer.
The user-approved feature-local motion does not change any rule or permission.

Strict guards weakening mutations natively, including V1 master/configuration,
emergency and app-blocking release. Unlock requirements combine with AND:
immediate or 10s/30s/1m/3m/5m/10m/15m wait, connected charger, enrolled current
Wi-Fi name and enrolled NFC tag. Wi-Fi setup requests location permission to
obtain an unredacted SSID; unknown/disconnected networks fail closed. During an
authorized editing window, a retained Wi-Fi condition can still be removed
while disconnected; adding or re-enabling it requires an available SSID. NFC
enrollment requires two matching scans; changing IDs are rejected. Only the
tag-ID hash is stored. SSIDs and NFC IDs are self-control checks, not strong
authentication. The unlock request uses monotonic time/boot identity and belongs
to one visible Strict screen. A transient inactive/window-focus loss such as
the notification shade suspends completion and display polling, but retains
the chosen request. Actual stopped/hidden/background lifecycle, Home/app leaving,
screen-off/keyguard or Activity recreation cancels it. Leaving that tab or
route, opening Permissions, backgrounding, locking the screen, or recreating the
Android Activity cancels the request and NFC proof. Reboot never completes it.
Returning shows Unblock and requires a new deliberate request; it does not
automatically start a new countdown. Native bridge visibility/foreground gates
also guard request, NFC scan and completion, independently of Flutter display.
The in-app NFC scan dialog belongs to the same visible unlock screen; closing it
does not itself reset the wait, while backgrounding during it still does.
Completion rechecks all
conditions natively and consumes recent NFC proof. `Unblock` first opens a
compact choice: `15 minutes` or `Turn off Strict`. Cancelling starts nothing;
choosing starts the monotonic request with immutable `temporary`/`off` intent.
Missing intent retains the legacy temporary behavior. Duplicate requests with
the same intent preserve the deadline; a different intent is rejected.
Flutter polls only on the foreground visible Strict screen and invokes
`tryFinishUnlock` automatically after zero. Native suspended focus or unmet
charger/Wi-Fi/NFC conditions return unchanged status, not successful completion.
Temporary completion permits changes for fifteen minutes, then relocks; Lock
now closes the window. Permanent completion disables Strict while preserving
plans, customization and configured unlock requirements; the active-Focus
configuration guard still applies. Neither choice releases blocked apps/rules.
Enabling Strict clears the old request and locks indefinitely; no unlock countdown
starts until the explicit `Unblock` action. Before that request, the surface shows
only Active, the configured method and Unblock, not a countdown, completion button
or NFC scan. After choosing, the countdown and any required NFC scan become
available subject to the wait/conditions; there is no second completion button.
Merely waiting without a request, refreshing or reopening cannot start a request.
Late pre-exit command/status
responses cannot restore cancelled countdowns in Flutter. Duplicate requests preserve its
original deadline. A request is valid only with a known matching boot identity and
a non-future monotonic start; unknown boot cannot start a new request. Invalid or
rebooted requests require a new deliberate Unblock; no elapsed time is credited.
Emergency release requires Strict to be **disabled**, not merely temporarily
unlocked for editing. Both native release entry points recheck this condition;
the overlay hides the emergency control while Strict is enabled. Ordinary
countdown Return remains available and never unlocks Strict or releases rules.
The existing Unlock method summary uses compact minute units for full minutes,
seconds for short waits and both units for a remainder; zero is `Immediate`.
Its charger/Wi-Fi/NFC requirements remain visible on that same summary line.
No additional explanatory line is added; the existing Limits disclosure remains.
Strict buttons retain all commands with equal full width, at least 48px height,
16px rounded corners and 12px spacing. Configure is outlined beneath the primary
Lock now action. Pending NFC scan is separated from its timer and status;
Unlock choices remain stacked in a compact scrollable dialog. The Wait dropdown
constrains its selected value to available width, including large-text layouts.
Permission/tag launch failures clear their pending reply before retry; completion
and cancellation consume the reply once even if driver cleanup fails. Strict
configuration shares the same active-Focus edit boundary as plan configuration.

Strict does not prevent canonical Focus Finish, expiry, DND cleanup, calls,
alarms, Android Settings or uninstall. Customize saves title/message,
fixed decorative icon, Liquid Glass/Dark/Light/Space background and return delay
0/1/3/5/10/15/20 seconds or 1/3/5/10/15 minutes. Native app overlays and website
pages apply these choices. The app overlay and Android preview share native
icons, text, bounded palette and scrollable layout, with system-bar/cutout insets.
The six saved icon IDs (shield, work, games, social, sleep, study) resolve to
fixed outline vectors, not font-symbol substitutes. Native preview/overlay and
the offline website SVG use the same path definitions and theme foreground.
All four saved backgrounds remain independent Customize choices; reopening
restores the selected icon/background without changing protection authority.
They do not claim Flutter's blur compositor. The website's existing offline
document remains a separate renderer, not the exact Customize app preview.
On web/desktop, Customize shows a clearly labelled, read-only illustrative
preview using the same saved choices; it does not pretend to be a native
Android surface or run a real return timer. Long text remains scrollable.

An app-blocking attempt owns one finite monotonic `BlockReturnDelay`. Home or
opening MyLifeGraph retains that screen until its oval Return control is used;
switching between blocked targets/redraws does not restart or extend the wait.
The fill progresses left-to-right, snaps to ready at expiry and respects Android
animation settings. Progress ticks at 100ms; rule/expiry checks are bounded to
one second. Return rechecks the deadline in the service, consumes the attempt,
removes the overlay synchronously and opens MyLifeGraph (Home fallback on launch
failure). No target exception, Focus completion or Strict change occurs.
Master-off/source expiry clears the screen; phone, alarms, Settings and other
unblocked apps remain safe exits. System UI may hide the overlay without
resetting the deadline. Home is never globally blocked without a pending attempt.
Interrupt/destroy/dispose remove callbacks and animations. This is self-control,
not kiosk security: OS permission revocation, uninstall and OEM lifecycle cannot
be made tamper-proof. Installed-device evidence remains a separate requirement.

### Optional website observation

The XML declares window-content capability, but **no node query runs without
separate website consent**. Runtime content events and resource-ID reporting
activate only with consent, website targets and enabled app protection. Turning
either consent off from Plans stops that observation or usage reads; Strict
and active Focus guards still apply. Saved plan definitions are retained.
Package-only protection works
without consent. Exact package/resource-ID adapters target Chrome/Beta, Edge,
Brave, Firefox and Samsung Internet. These require installed-device verification
and may change with browser updates. Hidden bars, focused editable searches and
other browsers are not promised support. Page contents/messages/clicks and
arbitrary node text are never inspected or uploaded.

Whole-browser app rules take precedence over domain handling. Matching domains
open non-exported `LocalBlockPageActivity`: an offline WebView document with
JavaScript, network, file and content access off, escaped user text and rejected
navigation. Return and Back/predictive Back go Home, not immediately to the
same blocked tab. It does **not** rewrite a third-party tab, perform address-bar
actions, use a VPN or provide DNS filtering. This avoids an immediate return
loop without pretending universal browser control.
The offline Activity uses the existing AndroidX back dispatcher for both legacy
and predictive Back, preserving its monotonic return countdown.

Build/unit tests do not prove installed-device Accessibility, OEM survival,
browser adapters, NFC/Wi-Fi, calls or alarms. Evidence belongs in
`docs/verification.md`.

## Product Boundary

Focus Protection V1 is optional, Android-only and device-local. Its default
mode follows the real authenticated `focus_sessions` lifecycle; explicitly
chosen weekly/always app blocking runs independently. It is off by default and is not
shown on web, non-Android platforms, guest sessions, demo accounts, or mock-data
runs. The direct `/settings/focus-protection` route returns to Settings when
either the Android or synced-account capability is absent.

The canonical Focus session remains authoritative. Focus Protection adds no
Supabase table, FastAPI route, behavioral fact, recommendation input, or cloud
preference. Android receives only the confirmed `FocusSession.id`, `startedAt`,
and `plannedMinutes` required for a local lease. A native failure never rolls
back or reinterprets a durable Focus mutation.

## Explicit Configuration And Disclosure

The device configuration contains one off-by-default master switch, separate
selected-app and notification-silencing switches, selected Android package
names, and versions for the app-catalog, Accessibility, and notification-policy
disclosures. Before each sensitive system handoff, Flutter explains the narrow
use and offers `Agree ...` or `Not now`. Declining affects no Focus or other
product capability.

The native configuration and lease use the private SharedPreferences file
`mylifegraph_focus_protection_v1`; nothing is uploaded. They remain available
without a Flutter engine. Configuration is locked while an unexpired active
protection lease exists.

### Combinable app-blocking rules

The editor saves additive `appRules`, keyed by selected Android package.
Each rule combines `focus`, `weekly`, `always`, and optional `untilEpochMs`
with OR, not exclusive modes. Weekly days/times use the existing semantics
below. Temporary 15-minute, 1-hour and 2-hour shortcuts expire exclusively at
the saved instant; they create no Focus session. A selected app's tune button
edits only that app; `Rules for selected apps` explicitly applies one reviewed
rule to all selected apps. Cancelling writes nothing. Clear timer removes only
the temporary rule, not overlapping weekly/Focus/always rules.

Rules remain private device configuration. Essential packages, permission and
master switches still gate every decision. An overlay checks the foreground
app's own rule expiry even when another app remains blocked. The existing held
emergency release disables combined app blocking until explicitly re-enabled;
it does not alter the Focus lease or its independent DND behavior.

### Legacy configuration compatibility

Retained local configuration fields are `blockingMode` (`focus`, `weekly`,
`always`), `weekdays` (Monday=1 through Sunday=7), and `startMinute`/`endMinute`
(0..1439). Apps without an explicit `appRules` entry inherit these fields;
old configuration defaults to Focus. A weekly editor confirms the
days and times together; cancelling writes nothing. Empty days, equal times,
out-of-range values and unknown modes are rejected. Earlier end times mean the
following day, attributed to the selected start weekday. End is exclusive.

Weekly rules use current device wall time/timezone, including clock changes;
repeated DST wall-clock minutes follow the same selection. The Accessibility
service evaluates each package event and once per wall-clock minute while alive,
so it can block an already-open remembered app without Flutter running. There
is no page-content query, wake lock, new alarm permission or new service.
Android suspension/process death may delay checks until the service resumes or
a package event arrives; exact unattended start-time delivery is not promised.

Always/weekly rules persist on this device until disabled, not as account/cloud
records. Master-off and app-blocking-off stop them. The existing five-second
emergency confirmation disables app blocking in these two modes until explicit
re-enable; it does not mutate the Focus lease or DND. Essential-app exclusions
and the unchanged Focus emergency suppression remain authoritative. DND remains
Focus-only in every app-blocking mode. Finishing Focus never clears a weekly or
always preference and never creates a synthetic Focus session.

The consent-gated app list can collapse from its top or bottom without losing
selection. Deselect all clears the local selection. Block social media adds
installed selectable apps from an explicit package-ID preset (including X,
Instagram, Facebook, Threads, TikTok, Snapchat, Reddit, Pinterest, LinkedIn and
YouTube), preserving manual choices. No fuzzy labels, catalog upload, extra
visibility permission, or active-lease configuration bypass is introduced.

## Synced Focus Reconciliation

After the manual or scheduled backend `startSession` returns a confirmed row,
Flutter calls `activateLease`
before the slower projection refresh. An ambiguous committed start is first
reconciled against the exact active Focus id. Every Focus-page load and Android
app resume refetches the canonical active row and reconciles it idempotently.
An authoritative empty result clears a matching local lease; overlapping load
responses are generation-guarded so an older response cannot reactivate a
superseded lease.

The lease interval is exactly:

```text
[FocusSession.startedAt, FocusSession.startedAt + plannedMinutes)
```

For a makeup session, `startedAt` is the actual server-confirmed start rather
than the planned source time. Scheduled recovery remains outside this lease,
exactly like manual recovery.

Only a confirmed `finishSession` or `abandonSession` deactivates the matching
lease. A different session id cannot clear it. A native cleanup failure is
visible but does not undo terminal Supabase state. Reaching the lease end stops
device protection but never changes the stored Focus session.

A Handler while the process lives, persisted end time,
`AlarmManager.setAndAllowWhileIdle`, event-time expiry checks, and an explicit
boot receiver provide layered best-effort cleanup without Exact Alarm access or
a foreground service. Terminal, expiry, and emergency paths first persist an
inactive lease state, then persist a one-shot Zen-cleanup marker, publish
`FALSE`, and only then clear the ordinary lease. A process death at any point
therefore leaves either fail-open lease state or a retryable cleanup marker.

## Selected-App Blocking

App blocking is available from API 24. `FocusBlockAccessibilityService`
uses `TYPE_WINDOW_STATE_CHANGED` and `AccessibilityEvent.packageName` for
app protection. Optional V2 website observation is separately consented above.
Its XML fixes:

```text
canRetrieveWindowContent=true
canPerformGestures=false
isAccessibilityTool=false
```

Without website consent the service never queries foreground nodes. With
consent it reads only exact supported address-bar IDs, never page content,
notifications, messages or clicks. This follows Android's minimal
[accessibility-service configuration](https://developer.android.com/guide/topics/ui/accessibility/service).

The catalog is queried through `ACTION_MAIN` plus `CATEGORY_LAUNCHER`. Manifest
visibility declares only that intent signature; there is no
`QUERY_ALL_PACKAGES`. See Android's
[package visibility guide](https://developer.android.com/training/package-visibility/declaring).

MyLifeGraph, installed launchers, Android Settings, System UI, permission
controllers, package installers, the default dialer, and resolved alarm/clock
handlers are always allowed and not selectable where Android can resolve them.

A selected foreground package during its configured active blocking mode gets an API-owned
`TYPE_ACCESSIBILITY_OVERLAY` with Focus remaining time or a weekly/always status, Return to MyLifeGraph,
and a five-second press-and-hold emergency control followed by confirmation.
Lifting the original hold never confirms release. Accessibility `ACTION_CLICK`
starts the same five-second gate and requires a second action after it arms;
`ACTION_LONG_CLICK` has no shortcut. The screen scrolls, scales text, and
exposes accessibility descriptions.

While the overlay is visible, window events from MyLifeGraph itself and events
without a package do not replace the remembered foreground package. The service
still rechecks the lease on those events. MainActivity reports actual app resume
directly to dismiss the overlay, while other app/System UI events retain the
normal allow/block rules. This prevents overlay-generated events from repeatedly
removing and recreating the block screen without inspecting window content.

## Notification Silencing

Notification silencing requires API 29 and Notification Policy access. The app
owns one persistent `AutomaticZenRule` named `MyLifeGraph Focus`, backed by its
protected condition-provider component. Lease activation sends
`Condition.STATE_TRUE`; matching terminal transitions, expiry, and emergency
release send `Condition.STATE_FALSE`. The app never calls the global
`setInterruptionFilter`, changes another rule, or restores a captured global DND
state. Android's
[`NotificationManager`](https://developer.android.com/reference/android/app/NotificationManager)
remains authoritative, including user overrides.

Android 10 through 14 publish through the protected
`ConditionProviderService`; Android 15 and newer use the direct per-rule state
API. A persisted one-shot activation marker permits recovery only for an
unpublished fresh trigger. An ordinary replay or boot never republishes
`TRUE`, so it cannot undo a user snooze for the same session.

The rule allows alarms, starred callers, repeated callers, and media. It
disallows messages, conversations, events, and reminders, and hides full-screen
intent/peek, lights, badges, status icons, Ambient Display, and the notification
list. Before publishing `TRUE`, Android must return the stored rule enabled with
the exact owner, condition id, priority filter, and policy. Existing rules are
never silently updated or recreated. If the user deletes, disables, or edits
the rule, MyLifeGraph publishes `FALSE` where possible and reports
`zen_rule_missing_or_overridden`; an explicit notification-silencing off/on
cycle may reset only a deleted rule reference for a future fresh session. Below
Android 10, app blocking remains available and `dnd_unsupported` is shown.

## Public Interface And Status

Dart uses injectable `FocusProtectionGateway`; Android implements it over
`com.mylifegraph.app/focus_protection`, while other platforms use an unsupported
zero-effect implementation. Methods are `readStatus`, `listLaunchableApps`,
`saveConfiguration`, `openAccessibilitySettings`,
`openNotificationPolicySettings`, `activateLease`, `deactivateLease`, and
`emergencyRelease`.

Typed values are `InstalledLaunchableApp`,
`FocusProtectionConfiguration`, `FocusProtectionLease`, and
`FocusProtectionStatus`. Active mechanisms are `app_blocking` and
`silence_notifications`. Supported warnings are:

- `accessibility_disabled`
- `notification_policy_missing`
- `dnd_unsupported`
- `no_apps_selected`
- `zen_rule_missing_or_overridden`
- `native_failure`

The active Focus surface lists actual mechanisms and partial-protection
warnings; it never labels an unavailable mechanism active. Android exposes an
authoritative per-rule active-state read only from API 35. On API 29 through 34,
MyLifeGraph therefore does not attribute the global interruption filter to its
own rule: notification silencing remains unconfirmed in `activeMechanisms` and
uses `zen_rule_missing_or_overridden` with copy that also explains the
unconfirmed state. A failed initial channel read represents unknown
configuration and is never rendered as a known switched-off setting.

## Emergency Release

Emergency release changes only native state. The synced Focus session remains
active. Native state retains that released session id and
`emergency_released`; reconciliation cannot reactivate the same id. A new Focus
id may be protected normally. Matching Finish/Abandon clears the marker.

## Honest Limits And Store Gate

Legacy V1 is not URL, DNS, pornography, VPN, or desktop protection. A browser can only
be selected as a whole app. It does not suspend/uninstall packages or read,
delete, or intercept messages or notifications. Background audio, PiP,
split-screen, and deliberate multi-window workarounds are not reliably stopped.
Settings and uninstallation remain reachable.

Without Exact Alarm access, a hard-killed process can delay DND deactivation
until an allowed alarm/boot/app path runs. Package blocking always checks the
persisted end and fails open. The Zen cleanup marker survives that process death
and is retried without touching any other app's rule or captured global DND
state.

Accessibility use needs Play-listing disclosure, final privacy/Data Safety
text, and a review video showing agreement, refusal, app choice, and blocking.
The service is not declared an Accessibility Tool. Play approval is external
and cannot be guaranteed by code.

## Repository Build Gate

The repository tracks the Gradle 8.14 Unix and Windows launchers plus its
wrapper JAR so a fresh checkout can execute `testDebugUnitTest` and `lintDebug`.
The wrapper properties pin the official distribution SHA-256, and the Android
release source gate verifies that value together with Gradle's published
wrapper-JAR SHA-256. It requires one exact active value for every wrapper
property and rejects comments-as-pins, duplicate keys, and extra properties.
Git preserves the Unix launcher as LF, the Windows launcher as CRLF, and the
JAR as binary. Local SDK paths and signing material remain ignored. A successful
JVM, lint, or APK build is source/build evidence only and does not replace the
physical acceptance matrix below.

## Physical Acceptance

Use Android 11+ Wireless Debugging directly from WSL:

```bash
.tools/android-sdk/platform-tools/adb pair <IP>:<pair-port>
.tools/android-sdk/platform-tools/adb connect <IP>:<debug-port>
.tools/android-sdk/platform-tools/adb reverse tcp:54321 tcp:54321
.tools/android-sdk/platform-tools/adb reverse tcp:8000 tcp:8000
cd apps/mobile
FLUTTER_BIN="${FLUTTER_BIN:-flutter}"
"$FLUTTER_BIN" run -d <device-id>
```

Acceptance covers master-off zero effects, selected/unselected/essential apps,
Flutter-process death, notification visibility without message access,
alarm/starred/repeated calls, Finish/Abandon/expiry/emergency isolation, access
revocation, boot, rule override, rotation, gestures, and large text.
