# Android pilot release signing

The pilot APK uses one long-lived upload key. The keystore, passwords, and
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

Every distributable build comes from an immutable annotated RC tag on
protected `main`. The tag deterministically maps to Android `versionName` and
monotonically ordered `versionCode`; rerunning a tag does not invent a new app
version. Every third-party Action in the credential-bearing workflow is pinned
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
