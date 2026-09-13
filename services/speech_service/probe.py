"""One public model sample, no personal data; run with the service's limits."""
import json
import os
import resource
import subprocess
import sys
import time
from pathlib import Path

root = Path(__file__).resolve().parent
model = root / 'sherpa-onnx-nemo-parakeet-tdt-0.6b-v3-int8'
sample = model / 'test_wavs/de.wav'
if not sample.exists():
    sample = model / 'test_wavs/en.wav'
audio = subprocess.run(['ffmpeg', '-v', 'error', '-i', str(sample), '-t', '30',
                        '-f', 's16le', '-ar', '16000', '-ac', '1', 'pipe:1'],
                       check=True, capture_output=True).stdout
started = time.monotonic()
result = subprocess.run([sys.executable, str(root / 'transcribe.py')], input=audio,
    capture_output=True, timeout=75,
    env={'SPEECH_MODEL_DIR': str(model), 'PATH': '/usr/bin:/bin', 'OMP_NUM_THREADS': '2'})
if result.returncode:
    # Public sample only; package errors are safe here, not on the HTTP endpoint.
    print(result.stderr.decode(errors='replace')[-2500:])
    raise SystemExit(result.returncode)
text = json.loads(result.stdout)['text']
assert text.strip(), 'Empty transcription'
print(json.dumps({'sample': sample.name, 'audio_seconds': len(audio) / 32000,
    'elapsed_seconds': round(time.monotonic() - started, 2),
    'peak_child_memory_mib': round(resource.getrusage(resource.RUSAGE_CHILDREN).ru_maxrss / 1024),
    'text': text}, ensure_ascii=True))
