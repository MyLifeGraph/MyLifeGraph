"""Unprivileged preparation only; no system services or existing app changes."""
import hashlib
import os
import subprocess
import sys
import tarfile
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent
MODEL = 'sherpa-onnx-nemo-parakeet-tdt-0.6b-v3-int8'
SHA256 = '5793d0fd397c5778d2cf2126994d58e9d56b1be7c04d13c7a15bb1b4eafb16bf'


def main():
    if os.geteuid() == 0:
        raise SystemExit('Run preparation as ops, never as root.')
    venv = ROOT / 'venv'
    if not venv.exists():
        subprocess.run([sys.executable, '-m', 'venv', str(venv)], check=True)
    python = str(venv / 'bin/python')
    subprocess.run([python, '-m', 'pip', 'install', '--disable-pip-version-check',
                    '-r', str(ROOT / 'requirements.txt')], check=True)
    archive = ROOT / (MODEL + '.tar.bz2')
    if not archive.exists():
        print('Downloading Parakeet TDT 0.6B v3 INT8 (about 487 MB)...', flush=True)
        urllib.request.urlretrieve(
            'https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/' + archive.name,
            archive)
    with archive.open('rb') as source:
        if hashlib.file_digest(source, 'sha256').hexdigest() != SHA256:
            raise SystemExit('Model archive checksum mismatch; no extraction performed.')
    model_dir = ROOT / MODEL
    if not model_dir.exists():
        with tarfile.open(archive) as source:
            # Only the named model tree, no links/devices/traversal.
            for member in source.getmembers():
                target = (ROOT / member.name).resolve()
                if not target.is_relative_to(model_dir) or not (member.isfile() or member.isdir()):
                    raise SystemExit('Unsafe model archive entry.')
            source.extractall(ROOT, filter='data')
    subprocess.run([python, '-m', 'unittest', '-v', 'test_app'], cwd=ROOT, check=True)
    print('Preparation ready. Existing services unchanged.', flush=True)


if __name__ == '__main__':
    main()
