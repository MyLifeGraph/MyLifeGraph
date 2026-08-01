# Android Focus Protection V1 Contract

Status: implemented repository boundary, 2026-08-01.

## Product Boundary

Focus Protection V1 is an optional Android-only, device-local companion to a
real authenticated `focus_sessions` lifecycle. It is off by default and is not
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

## Synced Focus Reconciliation

After `startSession` returns a confirmed row, Flutter calls `activateLease`
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
subscribes only to `TYPE_WINDOW_STATE_CHANGED` and uses only
`AccessibilityEvent.packageName`. Its XML fixes:

```text
canRetrieveWindowContent=false
canPerformGestures=false
isAccessibilityTool=false
```

The service never inspects an event source, node, text, notification, message,
click, or window hierarchy. This follows Android's minimal
[accessibility-service configuration](https://developer.android.com/guide/topics/ui/accessibility/service).

The catalog is queried through `ACTION_MAIN` plus `CATEGORY_LAUNCHER`. Manifest
visibility declares only that intent signature; there is no
`QUERY_ALL_PACKAGES`. See Android's
[package visibility guide](https://developer.android.com/training/package-visibility/declaring).

MyLifeGraph, installed launchers, Android Settings, System UI, permission
controllers, package installers, the default dialer, and resolved alarm/clock
handlers are always allowed and not selectable where Android can resolve them.

A selected foreground package during an active lease gets an API-owned
`TYPE_ACCESSIBILITY_OVERLAY` with live remaining time, Return to MyLifeGraph,
and a five-second press-and-hold emergency control followed by confirmation.
Lifting the original hold never confirms release. Accessibility `ACTION_CLICK`
starts the same five-second gate and requires a second action after it arms;
`ACTION_LONG_CLICK` has no shortcut. The screen scrolls, scales text, and
exposes accessibility descriptions.

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

V1 is not URL, DNS, pornography, VPN, or desktop protection. A browser can only
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

## Physical Acceptance

Use Android 11+ Wireless Debugging directly from WSL:

```bash
.tools/android-sdk/platform-tools/adb pair <IP>:<pair-port>
.tools/android-sdk/platform-tools/adb connect <IP>:<debug-port>
.tools/android-sdk/platform-tools/adb reverse tcp:54321 tcp:54321
.tools/android-sdk/platform-tools/adb reverse tcp:8000 tcp:8000
cd apps/mobile
/home/gregor/tools/flutter/bin/flutter run -d <device-id>
```

Acceptance covers master-off zero effects, selected/unselected/essential apps,
Flutter-process death, notification visibility without message access,
alarm/starred/repeated calls, Finish/Abandon/expiry/emergency isolation, access
revocation, boot, rule override, rotation, gestures, and large text.
