# Health Connect V1

Optional Android 14+ foreground integration. Settings offers Health Connect,
connect, sync, stop sharing and delete imports. Garmin Connect must first write
its data to Android Health Connect; MyLifeGraph does not log into Garmin or need
a Garmin developer account. Other permitted Health Connect sources may contribute.
Older Android versions and Web can manage existing Cloud consent/data but cannot
read the device store. No dependency upgrade or background health permission.
On Android, account initialization/app resume checks existing Cloud consent and
device permission; an already connected matching device then syncs. Automatic
attempts are at least 15 minutes apart per running account session. Failures stay
visible in Health Connect Settings, never replace Dashboard or fabricate data.
Manual Sync now remains available; no automatic connect or permission prompt.

The compact Settings page shows Watch data, Sharing on/off, Sleep/Steps and
last-sync time when available. Connect/reconnect or Sync now is the primary
action. The header reload remains available after failures. A labelled overflow
keeps Stop sharing and Delete imported data; deletion retains its confirmation.
Android permissions and collapsed Details follow. Device requirements, Garmin
sharing instructions, seven-day foreground behavior and retention remain in
Details; unsupported platforms explicitly say import requires Android 14+.
Cloud consent is still a separate explicit dialog, not hidden in Details.
An enlarged watch icon and a short connection status supplement the existing
controls, with a Reduced-Motion-aware state fade. `Connected` means current
Cloud sharing, a matching bound device, supported Health Connect and granted
permission, not live Bluetooth/watch reachability or proof of fresh data.
`Not connected`, `Other device`, `Unavailable here`, `Checking…` and
`Could not confirm` remain distinct; an old sync timestamp cannot establish
connection. Opening this visual status adds no device read, upload or consent.

## Consent and authority

`health-connect-v1` GET/POST `/v1/health-connect` derives its owner from the verified
bearer. Guest/mock is zero-call. Connect requires the separate explicit
`health-connect-cloud-consent-v1` disclosure, including Cloud storage and the
selected Coach provider's potential access. Android permission alone is not
Cloud consent. Only one explicitly connected device may upload for an account.
Connect on another device supersedes that authority, not historical observations.

`profiles.health_connect_settings` is an additive, backend-owned account
preference. The service-only, owner-locked `apply_health_connect_v1` command
checks its revision and pending deletion. An exact latest request replays;
changed or stale commands fail closed. The private latest request is not exported
or included in Coach snapshots. Existing profile RLS and account gates remain.

## Observations

The Android framework aggregates steps and total sleep-session minutes for each
of the last seven calendar days in the account timezone. Health Connect's
aggregation resolves source priority rather than summing raw overlapping steps.
Null remains missing, never zero. Sleep totals are calendar-day session duration,
not a substituted previous-night Morning sleep estimate. The current day is partial.
No location, heart rate, raw sleep notes or other health types are read.

Sync replaces only the matching daily `health_connect_steps` and
`health_connect_sleep_minutes` observations with source `health_connect` in
`behavioral_events`. Values, timezone, exact observed interval, source package
identifiers and sync time are retained. A complete seven-day read is required;
permission/read failure does not clear earlier imports. Missing metrics in a
successful complete read clear only those imported metrics within that window.
Older history remains. Corrections older than seven days require deletion and
are not claimed to synchronize automatically.

Manual `daily_logs`, `quick_check_in` events, planning, recommendations and
Insights calculations are unchanged. The current read-only Coach snapshot already
includes owner behavioral events; its catalog explains provenance and prohibits
adding imported totals to overlapping manual observations. Existing owner export
includes events plus the public consent preference. Account deletion cascades both.

Stop sharing disables future uploads without deleting prior observations.
Delete imports also disables sharing and deletes only this source. Earlier saved
Coach answers are not rewritten; full account deletion remains separate.

## Verification and rollout

Watch start/end values remain absolute instants. Morning renders them once in
the current profile IANA zone, never through a second `toLocal()` conversion.
Manual clocks use the strict profile-zone resolver (DST gaps/folds require a
correction); an imported aware instant during a repeated hour stays valid.
Capture serialization emits canonical UTC, without appending a duplicate offset.
The selected wake date and actual elapsed duration, including DST changes,
remain authoritative. Existing saved data is not rewritten.

Opening an unsaved manual Morning check-in offers `Watch sleep` with `Use times`
and dismiss actions, only on the consented, permission-granted bound device.
It does not request permission, upload or save a Capture merely on opening.
The bridge reads up to 500 sleep sessions across the previous/current day,
rejects truncated responses, and proposes the longest 1–16 hour session ending
on the selected profile-local date (latest end breaks ties). Only start/end
timestamps reach Flutter, not raw notes or stages. Acceptance and the normal
final Save are required. Saved captures and reviewed voice drafts are never
replaced; manual clock edits, acceptance or dismissal suppress further offers
for that draft. Accepted times remain editable. Missing/invalid data leaves
manual entry available. Daily aggregate totals are never guessed into overnight
times. Web/older Android remain manual. No health Cloud schema change is needed.


Deploy the additive migration before the new API. An older API lacks this route:
the new Settings surface reports unavailable instead of fabricating success.
Repository tests cannot prove Garmin output, Android permission behavior, actual
watch accuracy or Cloud deployment. An installed Android device must verify
Garmin sharing, permission decline/grant, sync, revoke, account switch and deletion.
Play distribution additionally requires the Health Connect permission declaration
and a matching privacy policy. Existing signed APKs and Vercel releases are unchanged
until a separately approved release.
