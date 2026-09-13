"""Explicit one-time OPS installation. Default is read-only preview."""
import argparse
import hashlib
import json
import os
import shutil
import subprocess
import time
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent
DEST = Path('/opt/mylifegraph-speech')
CADDY = Path('/etc/caddy/Caddyfile')
UNIT = Path('/etc/systemd/system/mylifegraph-speech.service')
MODEL = 'sherpa-onnx-nemo-parakeet-tdt-0.6b-v3-int8'
MARKER = '\t# MyLifeGraph speech: independent dictation sidecar\n'
ADDITION = (MARKER + '\t@speech path /v1/speech/transcribe\n'
            '\treverse_proxy @speech 127.0.0.1:8002\n\n')


def patched_caddy(original: str) -> str:
    anchor = '\treverse_proxy 127.0.0.1:8000 {'
    if original.count(anchor) != 1 or MARKER in original:
        raise ValueError('Unexpected Caddy layout; refusing to modify it.')
    return original.replace(anchor, ADDITION + anchor, 1)


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def run(*args):
    subprocess.run(args, check=True)


def publish(path: Path, data: bytes):
    temporary = path.with_name(path.name + '.speech-new')
    with temporary.open('xb') as output:
        output.write(data)
    os.chmod(temporary, 0o644)
    temporary.replace(path)


def rollback():
    receipt = json.loads((DEST / 'install-receipt.json').read_text())
    current = CADDY.read_bytes()
    if digest(current) != receipt['installed_caddy_sha256']:
        raise SystemExit('Caddy changed since installation. Stop: manual removal of speech block required.')
    backup = Path(receipt['caddy_backup'])
    publish(CADDY, backup.read_bytes())
    run('systemctl', 'reload', 'caddy')
    run('systemctl', 'disable', '--now', 'mylifegraph-speech.service')
    print('Speech disabled; original Caddy restored. Files retained for recovery.')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--apply', action='store_true')
    parser.add_argument('--rollback', action='store_true')
    parser.add_argument('--expected-caddy-sha256')
    args = parser.parse_args()
    if args.rollback:
        if os.geteuid() != 0:
            raise SystemExit('Rollback requires sudo.')
        rollback()
        return
    original = CADDY.read_bytes()
    candidate = patched_caddy(original.decode()).encode()
    print('Adds only: /opt/mylifegraph-speech, mylifegraph-speech.service, one Caddy route.')
    print('Loopback 8002; dynamic service user; 2 GB RAM; 1.5 CPUs; no audio files.')
    print('Existing API/Coach units, releases, databases and firewall remain unchanged.')
    print('Current Caddy SHA256:', digest(original))
    if not args.apply:
        return
    if os.geteuid() != 0 or args.expected_caddy_sha256 != digest(original):
        raise SystemExit('Use sudo and the reviewed Caddy SHA256 from preview.')
    if DEST.exists() or UNIT.exists():
        raise SystemExit('Speech installation already exists. Refusing to overwrite it.')
    if not (ROOT / 'venv/bin/python').exists() or not (ROOT / MODEL / 'encoder.int8.onnx').exists():
        raise SystemExit('Run prepare.py as ops first.')
    # Only this newly created directory is populated. No existing app is edited.
    DEST.mkdir(mode=0o755)
    for name in ('app.py', 'transcribe.py', 'requirements.txt', 'install.py'):
        shutil.copyfile(ROOT / name, DEST / name)
        os.chmod(DEST / name, 0o644)
    shutil.copytree(ROOT / 'venv', DEST / 'venv', symlinks=True)
    shutil.copytree(ROOT / MODEL, DEST / MODEL)
    origins = ','.join([
        'http://127.0.0.1:7357', 'http://localhost:7357',
        'https://my-life-graph-mu.vercel.app', 'https://my-life-graph.vercel.app',
        'https://my-life-graph-my-life-graph-s-projects.vercel.app',
        'https://my-life-graph-git-preview-morni-de38cf-my-life-graph-s-projects.vercel.app',
    ])
    unit = f'''[Unit]
Description=MyLifeGraph Parakeet dictation (independent sidecar)
After=network.target

[Service]
Type=simple
DynamicUser=yes
User=mylifegraph-speech
WorkingDirectory={DEST}
ExecStart={DEST}/venv/bin/python -m uvicorn app:app --host 127.0.0.1 --port 8002 --workers 1 --no-access-log --limit-concurrency 4 --backlog 8
Environment=SPEECH_MODEL_DIR={DEST}/{MODEL}
Environment=SPEECH_ALLOWED_ORIGINS={origins}
Environment=PYTHONDONTWRITEBYTECODE=1
MemoryMax=2G
MemorySwapMax=0
LimitCORE=0
CPUQuota=150%
TasksMax=64
Nice=10
Restart=on-failure
RestartSec=5
TimeoutStopSec=15
NoNewPrivileges=yes
ProtectSystem=strict
ProtectHome=yes
PrivateTmp=yes
PrivateDevices=yes
ProtectKernelTunables=yes
ProtectKernelModules=yes
ProtectControlGroups=yes
RestrictAddressFamilies=AF_UNIX AF_INET AF_INET6
CapabilityBoundingSet=
UMask=0077

[Install]
WantedBy=multi-user.target
'''
    publish(UNIT, unit.encode())
    backup = CADDY.with_name('Caddyfile.before-mylifegraph-speech-' + str(int(time.time())))
    backup.write_bytes(original)
    os.chmod(backup, 0o600)
    receipt = {'caddy_backup': str(backup), 'installed_caddy_sha256': digest(candidate)}
    (DEST / 'install-receipt.json').write_text(json.dumps(receipt))
    try:
        run('systemctl', 'daemon-reload')
        run('systemctl', 'enable', '--now', 'mylifegraph-speech.service')
        for attempt in range(20):
            try:
                with urllib.request.urlopen('http://127.0.0.1:8002/health', timeout=2) as response:
                    if response.status == 200:
                        break
            except OSError:
                time.sleep(1)
        else:
            raise RuntimeError('Speech health check failed.')
        if CADDY.read_bytes() != original:
            raise RuntimeError('Caddy changed during installation. Not modifying it.')
        publish(CADDY, candidate)
        # Caddy validates before applying reload; failure restores the original.
        run('systemctl', 'reload', 'caddy')
    except Exception:
        if CADDY.read_bytes() == candidate:
            publish(CADDY, original)
            subprocess.run(['systemctl', 'reload', 'caddy'])
        subprocess.run(['systemctl', 'disable', '--now', 'mylifegraph-speech.service'])
        raise
    print('Speech installed. API and Coach were not restarted.')
    print('Rollback: sudo python3 /opt/mylifegraph-speech/install.py --rollback')


if __name__ == '__main__':
    main()
