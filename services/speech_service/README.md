# Independent Coach dictation

This optional sidecar adds Parakeet TDT 0.6B v3 INT8 transcription without
changing the existing API, Coach executor, database, or release directories.
The feature owner is [Coach](../../docs/phase-10-controlled-coach-plan.md).

## Request and privacy boundary

- POST `/v1/speech/transcribe`: raw mono 16-bit little-endian PCM, 16000 Hz,
  `Content-Type: application/octet-stream`, existing bearer Authorization.
  Returns `{ "text": "recognized words" }`. No automatic Coach submission.
- Maximum 30 seconds / 960000 bytes; uploads time out after 30 seconds.
- Exactly one upload/auth/inference at a time; up to six authenticated attempts
  per minute globally, restart-local. Busy returns 429; no queue or automatic retry.
- Access is delegated to the existing generation-free Coach history read on
  loopback API port 8000. Only HTTP 200 admits audio processing. Its body is not
  parsed or retained. This preserves verified account, pending-deletion and
  participation checks without new keys or a separate JWT authority. An outage
  of that read also disables dictation; provider selection/key is not required.
- The development endpoint adds `/dev` before the public path and delegates to
  port 8001 instead. Caddy forwards only the exact public path; the development
  endpoint remains accessible only on loopback or an explicit SSH tunnel.
- Audio is held in memory and passed to a disposable model process over stdin.
  It is not written to disk, logged, sent to a third-party model API, or saved
  to Coach history. Worker RAM is released on completion, with a 75-second hard
  timeout. Cancelling the client may not stop already accepted server work;
  it still expires and does not save the audio. Recognized text only becomes
  ordinary Coach content after the user explicitly presses Send (during
  recording or after reviewing the draft).
- Model conversion/source: [sherpa-onnx Parakeet documentation](https://k2-fsa.github.io/sherpa/onnx/pretrained_models/offline-transducer/nemo-transducer-models.html).
  The archive is SHA256-checked before extracting regular files/directories only.

## Installation and rollback

Prepare these files in a dedicated, private directory owned by the installing
operator. Run `python3 prepare.py` **without sudo**. This creates only its own
virtualenv and downloads the pinned, checksummed model, then runs the small
service tests. No existing service is touched.

Run `python3 install.py` for a read-only preview. Review the existing Caddy hash,
then run `sudo python3 install.py --apply --expected-caddy-sha256 HASH`.
The first-install-only script copies the prepared service to
`/opt/mylifegraph-speech` and adds `mylifegraph-speech.service` with a dynamic
unprivileged user, 2 GiB RAM maximum, no swap, 150% CPU quota and loopback port
8002. Only one exact speech route is added to Caddy. API and Coach are not
restarted. No root pip install, system package upgrade, firewall change,
Supabase change, new secret, or permanent sudo grant is involved.

Caddy's existing 1 MB body limit remains. Reload validates the new configuration;
a failed activation restores the original Caddy file when still unchanged by
others and stops the new service. Installation files remain for diagnosis.

Rollback: `sudo python3 /opt/mylifegraph-speech/install.py --rollback`.
It restores the original Caddy config only if the installed config has not
subsequently changed; otherwise it stops for manual review. It disables only
the speech service and retains files. Do not blindly restore an old Caddy
backup after someone else has edited that file.

## Clients and verification

Hosted Flutter defaults to the existing `AI_SERVICE_BASE_URL`; a future Web/APK
build therefore uses the added HTTPS route without a different model endpoint.
The updated web build allows microphone permission for `self` only. Android
adds runtime microphone permission through the pinned recorder package; neither
change grants permission without the user. Old deployed clients stay unchanged
until a separately authorized release.

Local development: forward laptop loopback 8002 to VPS loopback 8002 and set
`SPEECH_SERVICE_BASE_URL=http://127.0.0.1:8002/dev` before starting Flutter.
Only approved exact browser origins are allowed (see installer); adding another
site requires reviewing that list. Hosted staging needs its own corresponding
verified API; staging tokens must not be routed to the pilot API.

Check `python -m unittest -v test_app` in this directory's virtualenv; test a
public sample through `transcribe.py` within the intended service limits before
activation. HTTP health alone does not prove microphone access, model loading,
language accuracy, device behavior or acceptable latency. Physical Web/Android
recording and authenticated upload remain explicit acceptance checks.
