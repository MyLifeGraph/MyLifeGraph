#!/usr/bin/python3 -I
"""Fixed project operations for a trusted MyLifeGraph release operator."""
from __future__ import annotations

import argparse
import fcntl
import hashlib
import json
import os
from pathlib import Path
import pwd
import re
import shutil
import signal
import stat
import subprocess
import sys
import tempfile

ROOT = Path('/srv/mylifegraph')
HELPERS = Path('/usr/local/libexec/mylifegraph')
SETUP = Path('/root/mylifegraph-rc4')
ENV = {'PATH': '/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin', 'LANG': 'C.UTF-8'}
UNITS = {'api': 'mylifegraph-api.service', 'coach': 'mylifegraph-coach-executor.service',
         'socket': 'mylifegraph-coach-executor.socket', 'web': 'caddy.service'}
LIMITS = {'archive': 128 * 1024 * 1024, 'manifest': 256 * 1024}
SUFFIXES = {'archive': 'tar.gz', 'manifest': 'source.json'}
RESERVE = 15 * 1024**3


class ProjectError(RuntimeError):
    pass


def require(condition, message):
    if not condition:
        raise ProjectError(message)


def protected(path, *, directory=False):
    for entry in (path, *path.parents):
        info = entry.lstat()
        is_directory = directory if entry == path else True
        require((stat.S_ISDIR(info.st_mode) if is_directory else stat.S_ISREG(info.st_mode))
                and info.st_uid == 0 and not info.st_mode & 0o022,
                'Untrusted project path: ' + str(entry))
        if not is_directory:
            require(info.st_nlink == 1, 'Hard-linked project file')


def run(args, *, capture=False, timeout=300, cwd='/', input=None):
    child = subprocess.Popen([str(arg) for arg in args], env=ENV, cwd=cwd,
        stdin=subprocess.PIPE if input is not None else None,
        stdout=subprocess.PIPE if capture else None, stderr=subprocess.PIPE if capture else None,
        text=True, start_new_session=True)
    try:
        stdout, _ = child.communicate(input, timeout=timeout)
    except BaseException:
        saved = {sig: signal.signal(sig, signal.SIG_IGN) for sig in (signal.SIGINT, signal.SIGTERM)}
        try:
            try: os.killpg(child.pid, signal.SIGTERM)
            except ProcessLookupError: pass
            try: child.communicate(timeout=10)
            except subprocess.TimeoutExpired: pass
            finally:
                try: os.killpg(child.pid, signal.SIGKILL)
                except ProcessLookupError: pass
            child.communicate(timeout=5)
        finally:
            for sig, handler in saved.items(): signal.signal(sig, handler)
        raise
    require(child.returncode == 0, 'Project command failed: ' + Path(str(args[0])).name)
    return (stdout or '').strip()


def helper(name, *args, **kwargs):
    path = HELPERS / name
    protected(path)
    return run([path, *args], **kwargs)


def tag(value):
    require(re.fullmatch(r'v[0-9]+\.[0-9]+\.[0-9]+-pilot\.[0-9]+-rc\.[0-9]+', value)
            is not None, 'Expected an exact pilot RC tag')
    return value


def artifact(release_tag, kind):
    return ROOT / 'incoming' / f'mylifegraph-{tag(release_tag)}.{SUFFIXES[kind]}'


def upload(release_tag, kind, expected, stream):
    require(re.fullmatch('[0-9a-f]{64}', expected) is not None, 'Invalid SHA256')
    target = artifact(release_tag, kind)
    protected(target.parent, directory=True)
    require(shutil.disk_usage(ROOT).free >= RESERVE + LIMITS[kind], 'Preserve 15 GiB free space')
    fd, name = tempfile.mkstemp(prefix='.project-upload-', dir=target.parent)
    temporary = Path(name)
    try:
        digest = hashlib.sha256()
        size = 0
        with os.fdopen(fd, 'wb') as handle:
            while chunk := stream.read(min(1024 * 1024, LIMITS[kind] + 1 - size)):
                size += len(chunk)
                require(size <= LIMITS[kind], 'Artifact exceeds upload limit')
                digest.update(chunk)
                handle.write(chunk)
            require(size > 0 and digest.hexdigest() == expected, 'Artifact checksum mismatch')
            handle.flush()
            os.fchmod(handle.fileno(), 0o400)
            os.fsync(handle.fileno())
        if target.exists() or target.is_symlink():
            protected(target)
            require(target.stat().st_mode & 0o777 == 0o400, 'Existing input permissions differ')
            require(hashlib.sha256(target.read_bytes()).hexdigest() == expected,
                    'Refusing to replace an existing release input')
        else:
            os.link(temporary, target, follow_symlinks=False)
        temporary.unlink()
        parent = os.open(target.parent, os.O_RDONLY | os.O_DIRECTORY)
        try: os.fsync(parent)
        finally: os.close(parent)
    finally:
        temporary.unlink(missing_ok=True)
    print(json.dumps({'state': 'uploaded', 'tag': release_tag, 'kind': kind, 'sha256': expected}))


def release(release_tag):
    result = ROOT / 'releases' / tag(release_tag)
    protected(result, directory=True)
    helper('release_tree.py', 'verify', '--release', result, capture=True)
    return result


def coach_command(*args):
    uid = pwd.getpwnam('mylifegraph-coach').pw_uid
    return ['/usr/sbin/runuser', '-u', 'mylifegraph-coach', '--', '/usr/bin/env', '-i',
            'PATH=/usr/sbin:/usr/bin:/sbin:/bin', 'HOME=/var/lib/mylifegraph-coach',
            f'XDG_RUNTIME_DIR=/run/user/{uid}', f'DOCKER_HOST=unix:///run/user/{uid}/docker.sock',
            *args]


def image(release_tag):
    candidate = release(release_tag)
    # Candidate code runs only as the already entrusted runtime identity.
    run(coach_command('/bin/bash', candidate / 'scripts/prepare_coach_analysis_image.sh'), timeout=900)
    image_file = candidate / '.mylifegraph-executor-release.env'
    protected(image_file)
    match = re.fullmatch(r'COACH_ANALYSIS_IMAGE=(mylifegraph-coach-analysis:sha256-([0-9a-f]{64}))\n',
                         image_file.read_text())
    require(match is not None, 'Invalid sealed image identity')
    actual = run(coach_command('/usr/bin/docker', 'image', 'inspect', '--format',
        '{{ index .Config.Labels "org.mylifegraph.coach-analysis.revision" }}', match[1]), capture=True)
    require(actual == match[2], 'Analysis image is not ready')


def public_host():
    path = Path('/etc/mylifegraph/caddy.env')
    protected(path)
    hosts = [line.removeprefix('MYLIFEGRAPH_API_HOST=') for line in path.read_text().splitlines()
             if line.startswith('MYLIFEGRAPH_API_HOST=')]
    require(len(hosts) == 1, 'Expected one API hostname')
    helper('validate_public_origin.py', '--host', hosts[0], capture=True)
    return hosts[0]


def coach_ready(candidate):
    code = '''import asyncio
from app.core.config import Settings
from app.providers.operator_executor import OperatorExecutorCoachProvider
async def check():
    provider = OperatorExecutorCoachProvider(Settings(_env_file=None, APP_ENV="pilot",
        USE_MOCK_DATA=False, OPERATOR_CODEX_PILOT_ENABLED=True,
        COACH_EXECUTOR_SOCKET_PATH="/run/mylifegraph-coach/executor.sock"))
    assert (await provider.capability()).state == "ready"
asyncio.run(check())
'''
    run(['/usr/sbin/runuser', '-u', 'mylifegraph-api', '--', '/usr/bin/env', '-i',
         'PATH=/usr/bin:/bin', 'PYTHONDONTWRITEBYTECODE=1',
         candidate / 'services/ai_service/.venv/bin/python', '-c', code],
        cwd=candidate / 'services/ai_service', capture=True, timeout=30)


def core_ready(candidate, host):
    manifest_path = candidate / '.mylifegraph-source-manifest.json'
    protected(manifest_path)
    manifest = json.loads(manifest_path.read_text())
    for origin in ('http://127.0.0.1:8000', 'https://' + host):
        helper('health_check.py', '--base-url', origin,
               '--expected-sha', manifest['release_sha'], '--expected-tag', manifest['release_tag'],
               '--expected-migration-head', manifest['migration_head'],
               '--expected-migration-count', str(manifest['migration_inventory']['count']),
               '--expected-migration-identity-sha256', manifest['migration_inventory']['identity_sha256'],
               capture=True, timeout=30)


def setup():
    protected(SETUP, directory=True)
    for name in ('install.sh', 'SHA256SUMS'):
        protected(SETUP / name)
    # Installed/sealed by ops from the separately approved RC4 archive.
    require(hashlib.sha256((SETUP / 'install.sh').read_bytes()).hexdigest() ==
            'a22190362a64fadf67b96ea6bb24e5a364fbc05e36c6b0c02b09a527c9d13a5a',
            'Initial setup installer changed')
    run(['/usr/bin/sha256sum', '--check', 'SHA256SUMS'], cwd=SETUP, capture=True)
    require(sys.stdin.isatty(), 'Initial setup needs an interactive SSH terminal')
    os.chdir(SETUP)
    os.execve('/bin/bash', ['/bin/bash', str(SETUP / 'install.sh')], ENV)


def parser():
    result = argparse.ArgumentParser(description=__doc__)
    commands = result.add_subparsers(dest='action', required=True)
    commands.add_parser('setup')
    commands.add_parser('status')
    commands.add_parser('check')
    for action in ('start', 'restart', 'stop', 'enable', 'disable', 'logs'):
        commands.add_parser(action).add_argument('unit', choices=UNITS)
    for action in ('prepare', 'image', 'promote'):
        commands.add_parser(action).add_argument('tag')
    stage = commands.add_parser('upload')
    stage.add_argument('tag')
    stage.add_argument('kind', choices=LIMITS)
    stage.add_argument('sha256')
    return result


def main():
    args = parser().parse_args()
    require(os.getuid() == 0 and sys.flags.isolated, 'Use the installed project command through sudo')
    require(Path(__file__).absolute() == HELPERS / 'project_admin.py', 'Use the installed project command')
    protected(Path(__file__))
    os.environ.clear()
    os.environ.update(ENV)
    protected(ROOT, directory=True)
    signal.signal(signal.SIGTERM, lambda *_: (_ for _ in ()).throw(ProjectError('Interrupted')))
    lock_path = ROOT / '.project-admin.lock'
    if lock_path.exists() or lock_path.is_symlink(): protected(lock_path)
    lock = os.open(lock_path, os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600)
    try:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        if args.action == 'setup':
            # Preserve the terminal and keep the operation lock through exec.
            os.set_inheritable(lock, True)
            setup()
        elif args.action == 'upload':
            upload(args.tag, args.kind, args.sha256, sys.stdin.buffer)
        elif args.action == 'prepare':
            helper('prepare_release.sh', artifact(args.tag, 'archive'), artifact(args.tag, 'manifest'), timeout=1800)
            image(args.tag)
        elif args.action == 'image':
            image(args.tag)
        elif args.action == 'promote':
            candidate = release(args.tag)
            image(args.tag)
            public_host()
            helper('promote_release.sh', args.tag, timeout=600)
            # Core promotion has its own rollback. A subsequent Coach error is
            # reported explicitly; it does not pretend to undo core promotion.
            try: coach_ready(candidate)
            except ProjectError as exc:
                raise ProjectError('Release promoted, but Coach is not ready; inspect project logs') from exc
            print(json.dumps({'state': 'promoted', 'tag': args.tag, 'coach_ready': True}))
        elif args.action == 'status':
            for unit in UNITS.values():
                print(run(['/usr/bin/systemctl', 'show', unit, '-p', 'Id', '-p', 'ActiveState',
                           '-p', 'SubState', '-p', 'UnitFileState', '-p', 'MainPID'], capture=True))
        elif args.action in ('start', 'restart', 'stop', 'enable', 'disable'):
            if args.action in ('start', 'restart') and args.unit == 'web': public_host()
            run(['/usr/bin/systemctl', args.action, UNITS[args.unit]], timeout=120)
            if args.action in ('start', 'restart'):
                print('Service start requested; after startup run: sudo mylifegraph-project check')
        elif args.action == 'logs':
            run(['/usr/bin/journalctl', '--no-pager', '--output=short-iso', '--lines=100',
                 '--unit=' + UNITS[args.unit]], timeout=30)
        elif args.action == 'check':
            host = public_host()
            protected(HELPERS / 'preflight_host.sh')
            run(['/usr/bin/env', f'MYLIFEGRAPH_API_HOST={host}', HELPERS / 'preflight_host.sh'], capture=True)
            helper('verify_permissions.sh', capture=True)
            current = (ROOT / 'current').resolve(strict=True)
            require(current.parent == ROOT / 'releases', 'Invalid current release')
            candidate = release(current.name)
            core_ready(candidate, host)
            coach_ready(candidate)
            print(json.dumps({'state': 'passed', 'public_api_and_coach_ready': True}))
    finally:
        os.close(lock)
    return 0


if __name__ == '__main__':
    try:
        raise SystemExit(main())
    except (ProjectError, OSError, ValueError, subprocess.TimeoutExpired, KeyboardInterrupt) as error:
        print('Project operation stopped: ' + (str(error) if isinstance(error, ProjectError)
              else type(error).__name__), file=sys.stderr)
        raise SystemExit(1)
