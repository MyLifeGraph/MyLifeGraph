#!/usr/bin/python3 -I
"""One-time ops installation of the explicitly delegated MyLifeGraph role."""
import hashlib
import json
import os
from pathlib import Path
import pwd
import shutil
import subprocess
import sys
import tarfile
import tempfile

BUNDLE = Path('/root/mylifegraph-maintainer')
ENV = {'PATH': '/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin', 'LANG': 'C.UTF-8'}
HELPERS = Path('/usr/local/libexec/mylifegraph')
ROLE = Path('/etc/sudoers.d/mylifegraph-matthias')
FORWARDING = Path('/etc/ssh/sshd_config.d/50-mylifegraph-matthias-forwarding.conf')
SLICE = Path('/etc/systemd/system/user-1003.slice.d/60-mylifegraph-development.conf')
SETUP = Path('/root/mylifegraph-rc4')
PHASE = 'preflight'


def run(args, *, capture=False, **kwargs):
    kwargs.setdefault('timeout', 180)
    result = subprocess.run([str(arg) for arg in args], env=ENV, check=True,
        stdout=subprocess.PIPE if capture else None,
        stderr=subprocess.PIPE if capture else None, **kwargs)
    return result.stdout.decode().strip() if capture else ''


def protected(path, directory=False):
    for item in (path, *path.parents):
        info = item.lstat()
        assert not item.is_symlink() and info.st_uid == 0 and not info.st_mode & 0o022
        assert item.is_dir() if item != path or directory else item.is_file()


def write_new(path, content, mode):
    protected(path.parent, directory=True)
    fd, name = tempfile.mkstemp(prefix='.' + path.name + '.', dir=path.parent)
    temporary = Path(name)
    published = False
    identity = None
    try:
        with os.fdopen(fd, 'wb') as stream:
            stream.write(content)
            stream.flush()
            os.fchmod(stream.fileno(), mode)
            os.fsync(stream.fileno())
        info = temporary.stat()
        identity = (info.st_dev, info.st_ino)
        os.link(temporary, path, follow_symlinks=False)
        published = True
        temporary.unlink()
        parent = os.open(path.parent, os.O_RDONLY | os.O_DIRECTORY)
        try: os.fsync(parent)
        finally: os.close(parent)
    except BaseException:
        if published:
            info = path.lstat()
            if (info.st_dev, info.st_ino) == identity:
                path.unlink()
        raise
    finally:
        temporary.unlink(missing_ok=True)
    return identity


def remove_owned(path, identity):
    if identity is not None and (path.exists() or path.is_symlink()):
        info = path.lstat()
        if (info.st_dev, info.st_ino) == identity:
            path.unlink()


def ssh(user):
    return run(['/usr/sbin/sshd', '-T', '-C', f'user={user},host=localhost,addr=127.0.0.1'], capture=True)


def main():
    global PHASE
    assert os.getuid() == 0 and sys.flags.isolated and Path.cwd() == BUNDLE
    protected(BUNDLE, directory=True)
    run(['/usr/bin/sha256sum', '--check', 'SHA256SUMS'], capture=True, cwd=BUNDLE)
    assert hashlib.sha256(Path('/etc/machine-id').read_text().encode()).hexdigest() == \
        'ace7dd6e5bc58feb3aab1ebd89a958ded75dd0b96e4ca357579b812ec99d08b7'
    account = pwd.getpwnam('mylifegraph-matthias')
    assert (account.pw_uid, account.pw_gid, account.pw_dir, account.pw_shell) == \
        (1003, 984, '/home/mylifegraph-matthias', '/bin/bash')
    assert run(['/usr/bin/id', '-Gn', 'mylifegraph-matthias'], capture=True).split() == \
        ['mylifegraph-matthias', 'mylifegraph-work']
    assert all('mylifegraph-matthias:296608:65536' in Path('/etc/' + name).read_text().splitlines()
               for name in ('subuid', 'subgid'))
    assert shutil.disk_usage('/srv').free >= 20 * 1024**3
    for executable in ('git', 'node', 'npm', 'python3', 'docker', 'rootlesskit', 'slirp4netns', 'newuidmap'):
        assert shutil.which(executable, path=ENV['PATH'])
    destinations = [ROLE, FORWARDING, SLICE, HELPERS/'project_admin.py', Path('/usr/local/sbin/mylifegraph-project')]
    for path in destinations:
        assert not path.exists() and not path.is_symlink(), 'Existing role file needs review'
    # Validate sudo policy before any sudo authority is installed.
    run(['/usr/sbin/visudo', '-cf', BUNDLE/'mylifegraph-matthias'], capture=True)
    run(['/usr/sbin/sshd', '-t'], capture=True)
    before = {user: ssh(user) for user in ('ops', 'agent', 'root', 'mylifegraph-agent')}
    watched = ['docker.service', 'hermes-gateway.service', 'user@994.service',
               'mylifegraph-api.service', 'mylifegraph-coach-executor.service',
               'mylifegraph-coach-executor.socket', 'caddy.service']
    service_state = {unit: run(['/usr/bin/systemctl', 'show', unit, '-p', 'ActiveState', '-p', 'MainPID'], capture=True)
                     for unit in watched}
    PHASE = 'seal_initial_setup'
    # Seal the already reviewed initial application package without executing it.
    if not SETUP.exists():
        assert not SETUP.is_symlink()
        archive = BUNDLE/'rc4-setup.tar'
        assert hashlib.sha256(archive.read_bytes()).hexdigest() == \
            '4dbb604dc2798ec545bc083517ce713304f464af46f79225e899415a6b8336ce'
        with tarfile.open(archive) as package:
            members = package.getmembers()
            expected = {'SHA256SUMS', 'activate.py', 'api-config.json', 'coach_check.py', 'db_check.py',
                        'install.sh', 'mylifegraph-v0.1.0-pilot.1-rc.4.source.json',
                        'mylifegraph-v0.1.0-pilot.1-rc.4.tar.gz'}
            assert len(members) == len(expected) and {entry.name for entry in members} == expected
            assert all(entry.isfile() and entry.size < 16 * 1024**2 for entry in members)
            SETUP.mkdir(mode=0o700)
            for entry in members:
                write_new(SETUP/entry.name, package.extractfile(entry).read(), 0o400)
    protected(SETUP, directory=True)
    assert (SETUP/'SHA256SUMS').read_bytes() == (BUNDLE/'rc4-SHA256SUMS').read_bytes()
    run(['/usr/bin/sha256sum', '--check', 'SHA256SUMS'], capture=True, cwd=SETUP)
    PHASE = 'project_helpers'
    write_new(HELPERS/'project_admin.py', (BUNDLE/'project_admin.py').read_bytes(), 0o555)
    write_new(Path('/usr/local/sbin/mylifegraph-project'), (BUNDLE/'mylifegraph-project').read_bytes(), 0o555)
    if not SLICE.parent.exists():
        protected(SLICE.parent.parent, directory=True)
        SLICE.parent.mkdir(mode=0o755)
    write_new(SLICE, (BUNDLE/'mylifegraph-development.slice.conf').read_bytes(), 0o644)
    PHASE = 'ssh_forwarding'
    forwarding_identity = None
    try:
        forwarding_identity = write_new(FORWARDING, (BUNDLE/'matthias-forwarding.conf').read_bytes(), 0o600)
        run(['/usr/sbin/sshd', '-t'], capture=True)
        assert all(ssh(user) == value for user, value in before.items()), 'Unrelated SSH policy changed'
        effective = dict(line.split(' ', 1) for line in ssh('mylifegraph-matthias').splitlines())
        expected_ssh = {
            'disableforwarding': 'no', 'allowtcpforwarding': 'local',
            'allowstreamlocalforwarding': 'no', 'allowagentforwarding': 'no',
            'x11forwarding': 'no', 'gatewayports': 'no',
            'permitopen': '127.0.0.1:* localhost:* [::1]:*',
            'authorizedkeysfile': '/etc/mylifegraph/authorized_keys/%u',
            'passwordauthentication': 'no', 'kbdinteractiveauthentication': 'no',
        }
        assert all(effective.get(key) == value for key, value in expected_ssh.items())
        run(['/usr/bin/systemctl', 'reload', 'ssh'])
    except BaseException:
        remove_owned(FORWARDING, forwarding_identity)
        raise
    run(['/usr/bin/systemctl', 'daemon-reload'])
    PHASE = 'developer_home'
    protected(BUNDLE/'developer.json')
    config = json.loads((BUNDLE/'developer.json').read_text())
    config['docker_unit'] = (BUNDLE/'mylifegraph-development-docker.service').read_text()
    developer = ['/usr/sbin/runuser', '-u', 'mylifegraph-matthias', '--', '/usr/bin/env', '-i',
                 'PATH=/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin', 'HOME=/home/mylifegraph-matthias',
                 'XDG_RUNTIME_DIR=/run/user/1003', 'DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1003/bus']
    run([*developer, '/usr/bin/python3', '-I', '-c', (BUNDLE/'prepare_developer_home.py').read_text(),
         json.dumps(config)], input=(BUNDLE/'repository.bundle').read_bytes())
    PHASE = 'rootless_development_docker'
    run(['/usr/bin/loginctl', 'enable-linger', 'mylifegraph-matthias'])
    run(['/usr/bin/systemctl', 'start', 'user@1003.service'])
    run([*developer, '/usr/bin/systemctl', '--user', 'daemon-reload'])
    run([*developer, '/usr/bin/systemctl', '--user', 'enable', '--now', 'docker.service'])
    info = json.loads(run([*developer, '/usr/bin/docker', '--host=unix:///run/user/1003/docker.sock',
                          'info', '--format', '{{json .SecurityOptions}}'], capture=True))
    assert any('rootless' in option for option in info)
    assert Path('/run/user/1003/docker.sock').stat().st_uid == 1003
    for prop, expected in [('MemoryMax', str(4 * 1024**3)), ('TasksMax', '2048'), ('CPUQuotaPerSecUSec', '2s')]:
        assert run(['/usr/bin/systemctl', 'show', 'user-1003.slice', '-p', prop, '--value'], capture=True) == expected
    # Authority is the final step, after helper, user daemon and SSH checks.
    PHASE = 'delegate_project_commands'
    role_identity = None
    try:
        role_identity = write_new(ROLE, (BUNDLE/'mylifegraph-matthias').read_bytes(), 0o440)
        run(['/usr/sbin/visudo', '-c'], capture=True)
        run([*developer, '/usr/bin/sudo', '-n', '/usr/local/sbin/mylifegraph-project', 'status'], capture=True)
        assert all(run(['/usr/bin/systemctl', 'show', unit, '-p', 'ActiveState', '-p', 'MainPID'], capture=True) == state
                   for unit, state in service_state.items()), 'Existing host service changed'
    except BaseException:
        remove_owned(ROLE, role_identity)
        raise
    print(json.dumps({'state': 'prepared', 'operator': 'mylifegraph-matthias',
        'development_home': '/home/mylifegraph-matthias/MyLifeGraph', 'rootless_docker': True,
        'project_commands': True, 'general_sudo': False, 'application_state_unchanged': True}))


if __name__ == '__main__':
    try:
        main()
    except BaseException as error:
        print(json.dumps({'state': 'failed', 'phase': PHASE, 'error_type': type(error).__name__,
                          'action': 'Inspect partial installation before retrying; never rerun blindly.'}))
        raise SystemExit(1)
