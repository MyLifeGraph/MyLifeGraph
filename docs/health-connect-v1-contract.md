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

Deploy the additive migration before the new API. An older API lacks this route:
the new Settings surface reports unavailable instead of fabricating success.
Repository tests cannot prove Garmin output, Android permission behavior, actual
watch accuracy or Cloud deployment. An installed Android device must verify
Garmin sharing, permission decline/grant, sync, revoke, account switch and deletion.
Play distribution additionally requires the Health Connect permission declaration
and a matching privacy policy. Existing signed APKs and Vercel releases are unchanged
until a separately approved release.
