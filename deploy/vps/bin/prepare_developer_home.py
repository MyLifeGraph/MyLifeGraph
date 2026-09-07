#!/usr/bin/python3 -I
"""Run as Matthias, never root; install only his private development files."""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys


def main():
    config = json.loads(sys.argv[1])
    assert os.getuid() == 1003
    home = Path('/home/mylifegraph-matthias')
    assert Path.home() == home
    os.umask(0o077)
    files = {
        home / '.config/systemd/user/docker.service': config['docker_unit'],
        home / '.config/mylifegraph/development.env': (
            'export DOCKER_HOST=unix:///run/user/1003/docker.sock\n'
            'export XDG_RUNTIME_DIR=/run/user/1003\n'
            'export DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1003/bus\n'
            'export LOCAL_STACK_AI_PORT=8001\n'
            'export AI_SERVICE_PORT=8001\n'
        ),
    }
    for path, content in files.items():
        path.parent.mkdir(parents=True, exist_ok=True)
        if path.exists() or path.is_symlink():
            assert path.is_file() and not path.is_symlink() and path.read_text() == content
        else:
            with path.open('x') as stream:
                stream.write(content)
    repository = home / 'MyLifeGraph'
    payload = sys.stdin.buffer.read(64 * 1024 * 1024 + 1)
    assert len(payload) <= 64 * 1024 * 1024
    assert hashlib.sha256(payload).hexdigest() == config['bundle_sha256']
    if repository.exists():
        assert repository.is_dir() and not repository.is_symlink()
        result = subprocess.run(['/usr/bin/git', '-C', str(repository), 'remote', 'get-url', 'origin'],
                                capture_output=True, text=True, check=True)
        assert result.stdout.strip() in (
            'https://github.com/MyLifeGraph/MyLifeGraph.git',
            'git@github.com:MyLifeGraph/MyLifeGraph.git',
        )
        print('Existing working repository preserved.')
    else:
        bundle = home / '.mylifegraph-bootstrap.bundle'
        with bundle.open('xb') as stream:
            stream.write(payload)
        try:
            subprocess.run(['/usr/bin/git', 'clone', '--branch', config['branch'],
                            str(bundle), str(repository)], check=True)
            subprocess.run(['/usr/bin/git', '-C', str(repository), 'remote', 'set-url', 'origin',
                            'https://github.com/MyLifeGraph/MyLifeGraph.git'], check=True)
        finally:
            bundle.unlink()
    print('Developer files prepared; no credentials copied.')


if __name__ == '__main__':
    main()
