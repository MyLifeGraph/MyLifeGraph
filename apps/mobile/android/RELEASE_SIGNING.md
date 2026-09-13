# Android pilot release signing

Directly distributed pilot APKs use one long-lived app-signing key (not a
Play-managed upload-key exchange). The keystore, passwords, and
`key.properties` are never committed, uploaded as ordinary artifacts, copied
to the VPS, or handed to participants.

For local release builds, copy `key.properties.example` to the ignored
`key.properties`, use an absolute private keystore path, and restrict both
files to the developer account. CI instead supplies the four
`ANDROID_KEY*`/`ANDROID_KEYSTORE*` environment values from the protected
`pilot-release` environment; it never creates a password-bearing properties
file.

The signing certificate SHA-256 fingerprint is public identity, not a private
key. Store its normalized lowercase hexadecimal value as the protected GitHub
environment variable `ANDROID_SIGNING_CERT_SHA256`. The release workflow
rejects an APK whose verified signer differs.

The existing automatic workflow (`staging-debug-apk.yml`, filename retained)
now produces a signed release-mode testing APK on each protected `main` push,
or a manual dispatch on `main` only. It uses `main-<SHA>` build identity, the
same Pilot backend and protected signing environment, checks the certificate,
and uploads only the APK, checksum, fingerprint and source SHA. Missing signing
values fail closed; there is no debug-key fallback or signing on pull requests.
The annotated-RC workflow remains the separate fully attested candidate path
with SBOM. Neither workflow publishes a release or installs an APK.

Both CI paths derive `versionCode` as 10,000,000 plus the full first-parent
commit count, keeping main builds and later tags on one update sequence. Main
must not be force-rewritten. A tag on the same commit retains that version code;
its tag supplies `versionName`. Tagged candidates must lie on main's first-parent
chain; merged side-branch commits are rejected because their own first-parent
count is not the main update sequence. The helper's old tag-only calculation remains
available for historical tooling, but CI passes the commit count explicitly.
Every third-party Action in the credential-bearing workflow is pinned
to an immutable full commit SHA; updating a pin requires a separate review.
The workflow uploads the APK, checksum, signing fingerprint, source
SHA/tag, build metadata, and a checksum-pinned Syft CycloneDX source SBOM but
does not publish a GitHub release or distribute the APK automatically. The
separate VPS acceptance still scans the built analysis image and records its
digest; a source SBOM does not prove that runtime image safe.

Before handoff, install the APK on a physical supported device from a clean
state and test signup/confirmation, recovery, Google callback, persisted
session, ordinary product data, BYOK, Project Coach, export, deletion, reboot,
and update installation from the preceding signed pilot build. Record device,
Android version, APK checksum, certificate fingerprint, release SHA/tag, and
time in the final attestation.

If the private key may be exposed, stop distribution immediately. Revoke all
available CI copies, record the incident, create a new signing identity and
higher version code, rebuild from a new RC tag, and tell evaluators to remove
the compromised build. Direct APK distribution has no store-managed key
recovery; loss of the key means existing installs cannot receive a normal
same-identity update.

Android debug APKs are already signed, but their debug certificate is not the
private release identity. Switching certificates generally requires uninstalling
the old debug build first; this removes device-local data and stored keys, not
the user's synced Cloud data. Keep a separate private backup of the release
keystore and passwords. Do not replace the CI key to solve an install error.

Signing does not bypass Android's restricted settings for sideloaded apps.
On supported Android versions the user may need App info > the overflow menu >
Allow restricted settings before enabling the disclosed Accessibility service.
Only the user should grant that access. See the official
[Android restricted-settings help](https://support.google.com/android/answer/12623953).
