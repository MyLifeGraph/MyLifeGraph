"""Independent dictation sidecar. No database/model-provider credentials."""
import asyncio
import json
import os
import sys
import time
from collections import deque
from pathlib import Path

import httpx
from fastapi import FastAPI, HTTPException, Request
from fastapi.middleware.cors import CORSMiddleware

MAX_BYTES = 16000 * 2 * 30
ORIGINS = os.environ.get('SPEECH_ALLOWED_ORIGINS', 'http://127.0.0.1:7357').split(',')
app = FastAPI(docs_url=None, redoc_url=None, openapi_url=None)
app.add_middleware(CORSMiddleware, allow_origins=ORIGINS,
                   allow_methods=['POST'], allow_headers=['Authorization', 'Content-Type'])
_lock = asyncio.Lock()
_starts: deque[float] = deque()


async def authorize(request: Request, *, development: bool) -> None:
    """Reuse the existing verified-principal/deletion/participation gates.

    History is an existing generation-free, provider-key-free read. We inspect
    only its status, never retain or parse the personal response body. Failure
    stays closed; the sidecar does not invent a second Auth policy.
    """
    authorization = request.headers.get('authorization', '')
    if not authorization.startswith('Bearer ') or len(authorization) > 16384:
        raise HTTPException(401, 'Sign in to use dictation.')
    origin = request.headers.get('origin')
    if origin and origin not in ORIGINS:
        raise HTTPException(403, 'Origin not allowed.')
    port = 8001 if development else 8000
    try:
        async with httpx.AsyncClient(timeout=10, trust_env=False) as client:
            async with client.stream('GET', f'http://127.0.0.1:{port}/v1/coach/history',
                                     headers={'Authorization': authorization}) as response:
                code = response.status_code
    except httpx.HTTPError:
        raise HTTPException(503, 'Account access could not be verified.') from None
    if code != 200:
        raise HTTPException(code if code in (401, 403, 423, 429) else 503,
                            'Account access could not be verified.')


async def read_audio(request: Request) -> bytes:
    if request.headers.get('content-type', '').split(';')[0] != 'application/octet-stream':
        raise HTTPException(415, 'Expected mono PCM16LE audio at 16000 Hz.')
    data = bytearray()
    try:
        async with asyncio.timeout(30):
            async for chunk in request.stream():
                if len(data) + len(chunk) > MAX_BYTES:
                    raise HTTPException(413, 'Recording exceeds 30 seconds.')
                data.extend(chunk)
    except TimeoutError:
        raise HTTPException(408, 'Audio upload timed out.') from None
    if len(data) < 3200 or len(data) % 2:
        raise HTTPException(422, 'Recording is empty, too short, or malformed.')
    return bytes(data)


async def recognize(audio: bytes) -> str:
    # A bounded, disposable worker releases model RAM after every recording.
    process = await asyncio.create_subprocess_exec(
        sys.executable, str(Path(__file__).with_name('transcribe.py')),
        stdin=asyncio.subprocess.PIPE, stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.DEVNULL,
        env={'PATH': '/usr/bin:/bin', 'OMP_NUM_THREADS': '2',
             'SPEECH_MODEL_DIR': os.environ['SPEECH_MODEL_DIR']},
    )
    try:
        stdout, _ = await asyncio.wait_for(process.communicate(audio), timeout=75)
        if process.returncode != 0 or len(stdout) > 20000:
            raise HTTPException(503, 'Transcription unavailable.')
        text = json.loads(stdout)['text']
        if not isinstance(text, str) or len(text) > 2000:
            raise HTTPException(422, 'Dictation is too long for a question.')
        return text
    except (TimeoutError, ValueError, KeyError):
        raise HTTPException(503, 'Transcription unavailable.') from None
    finally:
        if process.returncode is None:
            process.kill()
        await process.wait()


async def transcribe(request: Request, *, development: bool) -> dict:
    if _lock.locked():
        raise HTTPException(429, 'Dictation is busy. Try again shortly.',
                            headers={'Retry-After': '10'})
    async with _lock:
        await authorize(request, development=development)
        now = time.monotonic()
        while _starts and _starts[0] < now - 60:
            _starts.popleft()
        if len(_starts) >= 6:
            raise HTTPException(429, 'Dictation is busy. Try again shortly.',
                                headers={'Retry-After': '60'})
        _starts.append(now)
        audio = await read_audio(request)
        text = await recognize(audio)
        return {'text': text}


@app.post('/v1/speech/transcribe')
async def production_transcribe(request: Request) -> dict:
    return await transcribe(request, development=False)


# Not forwarded by Caddy: available only through the development SSH tunnel.
@app.post('/dev/v1/speech/transcribe')
async def development_transcribe(request: Request) -> dict:
    return await transcribe(request, development=True)


@app.get('/health')
async def health() -> dict:
    return {'status': 'ok'}
