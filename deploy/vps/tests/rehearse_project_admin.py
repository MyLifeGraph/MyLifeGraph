"""Disposable Ubuntu only: real sudo authorization, uploads and SSH forwarding."""
import hashlib
import importlib.util
import os
from pathlib import Path
import shutil
import socket
import subprocess
import threading
import time


def run(*args, ok=True, input=None):
    result = subprocess.run(args, input=input, capture_output=True)
    if ok and result.returncode:
        raise AssertionError(result.stderr.decode(errors='replace'))
    return result


def main():
    assert Path('/.dockerenv').is_file() and os.getuid() == 0
    if run('id', 'ubuntu', ok=False).returncode == 0:
        run('userdel', 'ubuntu')  # Disposable image default user occupies the host's ops UID.
    spec = importlib.util.spec_from_file_location('access_rehearsal', '/input/tests/rehearse_access.py')
    access = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(access)
    access.main()
    run('gpasswd', '-d', 'mylifegraph-agent', 'sudo')
    assert run('id', '-u', 'mylifegraph-matthias').stdout.strip() == b'1003'
    helpers = Path('/usr/local/libexec/mylifegraph')
    helpers.mkdir(parents=True)
    for source, target in [('bin/project_admin.py', helpers/'project_admin.py'),
                           ('bin/mylifegraph-project', Path('/usr/local/sbin/mylifegraph-project'))]:
        shutil.copyfile('/input/' + source, target)
        target.chmod(0o555)
    root = Path('/srv/mylifegraph')
    root.mkdir(mode=0o750)
    (root/'incoming').mkdir(mode=0o700)
    Path('/usr/bin/systemctl').write_text('#!/bin/sh\n/usr/bin/printf "%s\\n" "$@" >> /root/systemctl-calls\n/usr/bin/printf "ActiveState=inactive\\n"\n')
    Path('/usr/bin/systemctl').chmod(0o755)
    shutil.copyfile('/input/sudoers.d/mylifegraph-matthias', '/etc/sudoers.d/mylifegraph-matthias')
    Path('/etc/sudoers.d/mylifegraph-matthias').chmod(0o440)
    run('/usr/sbin/visudo', '-c')
    as_user = ['/usr/sbin/runuser', '-u', 'mylifegraph-matthias', '--']
    command = [*as_user, '/usr/bin/sudo', '-n', '/usr/local/sbin/mylifegraph-project']
    run(*command, 'status')
    run(*command, 'restart', 'api')
    calls = Path('/root/systemctl-calls').read_bytes()
    for args in [('restart', 'ssh'), ('restart', 'docker'), ('logs', 'api', '--follow'), ('shell',)]:
        assert run(*command, *args, ok=False).returncode != 0
    assert Path('/root/systemctl-calls').read_bytes() == calls
    assert run(*as_user, 'sudo', '-n', '/bin/bash', '-c', 'id', ok=False).returncode != 0
    assert run(*as_user, 'sudo', '-n', '-E', '/usr/local/sbin/mylifegraph-project', 'status', ok=False).returncode != 0
    payload = b'bounded source input'
    digest = hashlib.sha256(payload).hexdigest()
    run(*command, 'upload', 'v1.0.0-pilot.1-rc.1', 'archive', digest, input=payload)
    destination = root/'incoming/mylifegraph-v1.0.0-pilot.1-rc.1.tar.gz'
    assert destination.read_bytes() == payload and destination.stat().st_uid == 0
    assert destination.stat().st_mode & 0o777 == 0o400 and destination.stat().st_nlink == 1
    run(*command, 'upload', 'v1.0.0-pilot.1-rc.1', 'archive', digest, input=payload)
    assert run(*command, 'upload', '../escape', 'archive', digest, input=payload, ok=False).returncode != 0
    assert run(*command, 'upload', 'v1.0.0-pilot.1-rc.1', 'archive', '0'*64, input=payload, ok=False).returncode != 0
    assert destination.read_bytes() == payload
    secret = Path('/etc/mylifegraph/api.env')
    secret.write_text('SYNTHETIC=yes\n')
    secret.chmod(0o600)
    editor = Path('/tmp/test-editor')
    editor.write_text('#!/bin/sh\nset -eu\n[ "$(id -u)" = 1003 ]\n[ ! -r /root/private-test ]\nprintf "SYNTHETIC=edited\\n" > "$1"\n')
    editor.chmod(0o755)
    Path('/root/private-test').write_text('not readable by the project editor')
    run(*as_user, '/usr/bin/env', 'SUDO_EDITOR=/tmp/test-editor', 'sudo', '-n', '-e', str(secret))
    assert secret.read_text() == 'SYNTHETIC=edited\n' and secret.stat().st_uid == 0
    assert run(*as_user, 'sudo', '-n', '-e', '/etc/sudoers', ok=False).returncode != 0
    # Prepare the actual private developer files as UID 1003, with a synthetic Git bundle.
    source = Path('/tmp/developer-source')
    source.mkdir()
    run('git', 'init', '-b', 'main', str(source))
    (source/'README.md').write_text('Synthetic development checkout')
    run('git', '-C', str(source), 'add', 'README.md')
    run('git', '-C', str(source), '-c', 'user.name=Test', '-c', 'user.email=test@example.invalid', 'commit', '-m', 'fixture')
    run('git', '-C', str(source), 'bundle', 'create', '/tmp/developer.bundle', 'main')
    payload = Path('/tmp/developer.bundle').read_bytes()
    import json
    config = {'branch': 'main', 'bundle_sha256': hashlib.sha256(payload).hexdigest(),
              'docker_unit': Path('/input/systemd/mylifegraph-development-docker.service').read_text()}
    developer = [*as_user, '/usr/bin/env', '-i', 'HOME=/home/mylifegraph-matthias', 'PATH=/usr/bin:/bin',
                 '/usr/bin/python3', '-I', '-c', Path('/input/bin/prepare_developer_home.py').read_text(), json.dumps(config)]
    run(*developer, input=payload)
    checkout = Path('/home/mylifegraph-matthias/MyLifeGraph')
    assert checkout.stat().st_uid == 1003 and not (checkout/'.env').exists()
    assert 'LOCAL_STACK_AI_PORT=8001' in Path('/home/mylifegraph-matthias/.config/mylifegraph/development.env').read_text()
    run(*as_user, 'touch', str(checkout/'preserved-work'))
    run(*developer, input=payload)
    assert (checkout/'preserved-work').exists()
    old = {user: run('/usr/sbin/sshd', '-T', '-C', f'user={user},host=localhost,addr=127.0.0.1').stdout
           for user in ('ops', 'agent', 'root', 'mylifegraph-agent')}
    shutil.copyfile('/input/manifests/matthias-forwarding.conf', '/etc/ssh/sshd_config.d/50-mylifegraph-matthias-forwarding.conf')
    run('/usr/sbin/sshd', '-t')
    for user, expected in old.items():
        assert run('/usr/sbin/sshd', '-T', '-C', f'user={user},host=localhost,addr=127.0.0.1').stdout == expected
    daemon = subprocess.Popen(['/usr/sbin/sshd', '-D', '-e'], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    forward = None
    listener = socket.socket()
    try:
        listener.bind(('127.0.0.1', 18321))
        listener.listen()
        listener.settimeout(8)
        def answer():
            conn, _ = listener.accept()
            with conn: conn.sendall(b'project-forward-ok')
        threading.Thread(target=answer, daemon=True).start()
        time.sleep(0.3)
        ssh = ['ssh', '-i', '/tmp/matthias', '-o', 'IdentitiesOnly=yes', '-o', 'BatchMode=yes',
               '-o', 'StrictHostKeyChecking=yes', '-o', 'UserKnownHostsFile=/tmp/known_hosts',
               '-o', 'ExitOnForwardFailure=yes']
        forward = subprocess.Popen([*ssh, '-N', '-L', '127.0.0.1:18322:127.0.0.1:18321',
                                    'mylifegraph-matthias@127.0.0.1'], stderr=subprocess.DEVNULL)
        for attempt in range(30):
            try:
                with socket.create_connection(('127.0.0.1', 18322), timeout=2) as client:
                    assert client.recv(64) == b'project-forward-ok'
                break
            except ConnectionRefusedError:
                time.sleep(0.1)
        else: raise AssertionError('SSH local tunnel failed')
        assert run(*ssh, '-N', '-R', '18323:127.0.0.1:18321', 'mylifegraph-matthias@127.0.0.1', ok=False).returncode != 0
    finally:
        listener.close()
        if forward is not None:
            forward.terminate()
            forward.wait(timeout=5)
        daemon.terminate()
        daemon.wait(timeout=5)
    print('Project role rehearsal passed: actual sudo whitelist/denials, unprivileged editor, sealed uploads, SSH local forwarding and remote forwarding denial. Systemd actions substituted; no live Docker or application activation.')


if __name__ == '__main__':
    main()
