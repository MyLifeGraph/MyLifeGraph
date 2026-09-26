# Android app updates

## Authority and release selection

Android Settings exposes `Updates` with installed version, manual `Check`, and
`Download` when a newer compatible release is found. Web and other platforms do
not expose an APK updater. This feature adds no database, authenticated API,
permissions, install service or dependency. Account logout does not reset the
device's update notice history.

An isolated unauthenticated client reads only the public
`MyLifeGraph/MyLifeGraph` GitHub release feed and its official release metadata.
It never reuses product HTTP interceptors or sends account/provider credentials.
Published pilot RCs are included explicitly; `/releases/latest` would omit them.
Drafts, duplicate/missing/non-uploaded assets and invalid metadata are excluded.
The bounded feed paginates (up to three pages of 100); hitting that bound fails
closed instead of falsely claiming `Up to date`. Requests have short connection/
receive timeouts and an overall 30-second cancellation deadline.

The existing `mylifegraph-android-artifact-v1` metadata must match its tag,
build name, full source SHA and installed signing certificate. A unique APK,
metadata and checksum asset must exist at the fixed repository's exact URLs.
Numeric `build_number` is compared with Android's actual installed versionCode,
not sorted release titles, filenames, publication dates or `rc.9`/`rc.10` text.
The highest compatible newer build wins; equal/older versions are not offered.
No valid compatible release or an unreadable feed is a failed check, not proof
that the installation is current. Future release metadata/naming changes need
a corresponding compatibility update here; they must not silently guess assets.

## Startup and dismissal

After entering the product shell, Android checks asynchronously. Resuming the app
can check again; repeated attempts in the same process are throttled for six hours.
Manual checks bypass that throttle and concurrent checks share one request.
Startup failures stay silent; Settings exposes `Could not check. Try again.`

Only an idle root tab in the foreground can show `Update available`, a version,
`Close` and `Download now`. Forms, keyboard editing and other modal routes are
not interrupted. A deferred result can be shown when returning to a root tab or
resuming. Before showing, the controller stores the highest notified build in
device-local SharedPreferences (`app_update_highest_notified_build`). Closing,
outside tap, system Back, download or process restart therefore cannot show that
build again. A newer build may show once. Storage failure suppresses automatic
notices; it does not remove manual Settings access. Clearing app storage or
reinstalling can reset this local preference.

## Download and verification boundary

An explicit download action opens the official APK URL externally. The browser
downloads and Android asks the user to install/allow the source where necessary.
There is no silent installation and no app-managed APK cache. The client checks
release metadata compatibility, not downloaded APK bytes: existing release CI
verifies the signed artifact and Android validates package/signature on install.
No claim of an on-device SHA256 verification is made for the browser download.
Launcher failure retains a retry action. App data and other product flows are
not written by this feature.

Regression tests cover version ordering, release filtering/pagination, metadata
and URL validation, failures/retry, concurrent checks, dismissal persistence,
foreground popup behavior and narrow/large-text dialogs. Installed-device
download/installation remains a separate acceptance check; exact executed
evidence belongs in [Verification](verification.md#current-verified-baseline).
