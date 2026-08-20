"""Bounded single-worker admission for the public VPS HTTP surface."""

from __future__ import annotations

import asyncio
import json
import math
import time
from collections import OrderedDict
from dataclasses import dataclass
from typing import Callable

from starlette.types import ASGIApp, Message, Receive, Scope, Send

from app.core.config import Settings


_MAX_TRACKED_RATE_KEYS = 8_192
_MAX_ACTIVE_BODY_READERS_PER_IP = 2
_COACH_PATHS = frozenset({"/coach/respond", "/coach/respond/stream"})
_MUTATION_METHODS = frozenset({"POST", "PUT", "PATCH", "DELETE"})


class PublicAdmissionRejected(RuntimeError):
    def __init__(self, *, code: str, retry_after: int) -> None:
        super().__init__(code)
        self.code = code
        self.retry_after = retry_after


@dataclass(frozen=True, slots=True)
class RoutePolicy:
    name: str
    max_body_bytes: int
    ip_requests_per_minute: int
    owner_requests_per_minute: int | None
    concurrency: int


@dataclass(slots=True)
class _WindowEntry:
    window: int
    count: int


class _FixedWindowLimiter:
    def __init__(
        self,
        *,
        clock: Callable[[], float] = time.monotonic,
        max_keys: int = _MAX_TRACKED_RATE_KEYS,
    ) -> None:
        self._clock = clock
        self._max_keys = max_keys
        self._entries: OrderedDict[tuple[str, str], _WindowEntry] = OrderedDict()
        self._lock = asyncio.Lock()

    async def admit(self, *, namespace: str, key: str, limit: int) -> None:
        now = self._clock()
        window = int(now // 60)
        retry_after = max(1, math.ceil(60 - (now % 60)))
        composite = (namespace, key)
        async with self._lock:
            entry = self._entries.get(composite)
            if entry is None or entry.window != window:
                self._entries[composite] = _WindowEntry(window=window, count=1)
            elif entry.count >= limit:
                self._entries.move_to_end(composite)
                raise PublicAdmissionRejected(
                    code="route_rate_limited",
                    retry_after=retry_after,
                )
            else:
                entry.count += 1
                self._entries.move_to_end(composite)
            while len(self._entries) > self._max_keys:
                self._entries.popitem(last=False)


class PublicAdmissionController:
    """Owns route policies, concurrency slots, and bounded rate state."""

    def __init__(
        self,
        settings: Settings,
        *,
        clock: Callable[[], float] = time.monotonic,
    ) -> None:
        self._api_prefix = settings.api_prefix.rstrip("/")
        self._wait_seconds = settings.public_admission_wait_milliseconds / 1000
        self._limiter = _FixedWindowLimiter(clock=clock)
        self._policies = {
            "ready": RoutePolicy(
                name="ready",
                max_body_bytes=0,
                ip_requests_per_minute=settings.public_ready_ip_requests_per_minute,
                owner_requests_per_minute=None,
                concurrency=settings.public_ready_concurrency,
            ),
            "read": RoutePolicy(
                name="read",
                max_body_bytes=0,
                ip_requests_per_minute=settings.public_read_ip_requests_per_minute,
                owner_requests_per_minute=(
                    settings.public_read_owner_requests_per_minute
                ),
                concurrency=settings.public_read_concurrency,
            ),
            "mutation": RoutePolicy(
                name="mutation",
                max_body_bytes=1_048_576,
                ip_requests_per_minute=(
                    settings.public_mutation_ip_requests_per_minute
                ),
                owner_requests_per_minute=(
                    settings.public_mutation_owner_requests_per_minute
                ),
                concurrency=settings.public_mutation_concurrency,
            ),
            "coach": RoutePolicy(
                name="coach",
                max_body_bytes=32 * 1024,
                ip_requests_per_minute=settings.public_coach_ip_requests_per_minute,
                owner_requests_per_minute=(
                    settings.public_coach_owner_requests_per_minute
                ),
                concurrency=settings.public_coach_concurrency,
            ),
        }
        self._semaphores = {
            name: asyncio.Semaphore(policy.concurrency)
            for name, policy in self._policies.items()
        }
        self._body_semaphores = {
            name: asyncio.Semaphore(max(policy.concurrency * 4, 8))
            for name, policy in self._policies.items()
        }
        self._body_reader_counts: dict[tuple[str, str], int] = {}
        self._body_reader_lock = asyncio.Lock()

    def policy_for(self, *, method: str, path: str) -> RoutePolicy | None:
        if path in {
            f"{self._api_prefix}/health",
            f"{self._api_prefix}/internal/database-contract",
        }:
            return None
        if path == f"{self._api_prefix}/ready":
            return self._policies["ready"]
        relative = path.removeprefix(self._api_prefix)
        if method in _MUTATION_METHODS and relative in _COACH_PATHS:
            return self._policies["coach"]
        if method in _MUTATION_METHODS:
            return self._policies["mutation"]
        return self._policies["read"]

    async def admit_ip(self, *, policy: RoutePolicy, client_ip: str) -> None:
        await self._limiter.admit(
            namespace=f"ip:{policy.name}",
            key=client_ip,
            limit=policy.ip_requests_per_minute,
        )

    async def admit_verified_owner(
        self,
        *,
        method: str,
        path: str,
        user_id: str,
    ) -> None:
        policy = self.policy_for(method=method, path=path)
        if policy is None or policy.owner_requests_per_minute is None:
            return
        await self._limiter.admit(
            namespace=f"owner:{policy.name}",
            key=user_id,
            limit=policy.owner_requests_per_minute,
        )

    async def acquire(self, policy: RoutePolicy) -> asyncio.Semaphore:
        semaphore = self._semaphores[policy.name]
        try:
            async with asyncio.timeout(self._wait_seconds):
                await semaphore.acquire()
        except TimeoutError:
            raise PublicAdmissionRejected(
                code="route_busy",
                retry_after=1,
            ) from None
        return semaphore

    async def acquire_body_reader(
        self,
        policy: RoutePolicy,
        *,
        client_ip: str,
    ) -> asyncio.Semaphore:
        key = (policy.name, client_ip)
        async with self._body_reader_lock:
            count = self._body_reader_counts.get(key, 0)
            if count >= _MAX_ACTIVE_BODY_READERS_PER_IP:
                raise PublicAdmissionRejected(
                    code="route_busy",
                    retry_after=1,
                )
            self._body_reader_counts[key] = count + 1
        semaphore = self._body_semaphores[policy.name]
        try:
            async with asyncio.timeout(self._wait_seconds):
                await semaphore.acquire()
        except BaseException as exc:
            await self._release_body_reader_count(key)
            if isinstance(exc, TimeoutError):
                raise PublicAdmissionRejected(
                    code="route_busy",
                    retry_after=1,
                ) from None
            raise
        return semaphore

    async def release_body_reader(
        self,
        policy: RoutePolicy,
        *,
        client_ip: str,
        semaphore: asyncio.Semaphore,
    ) -> None:
        semaphore.release()
        await self._release_body_reader_count((policy.name, client_ip))

    async def _release_body_reader_count(self, key: tuple[str, str]) -> None:
        async with self._body_reader_lock:
            count = self._body_reader_counts.get(key)
            if count is None or count < 1:
                raise RuntimeError("body reader admission state is inconsistent")
            if count == 1:
                del self._body_reader_counts[key]
            else:
                self._body_reader_counts[key] = count - 1


class PublicAdmissionMiddleware:
    def __init__(self, app: ASGIApp, *, controller: PublicAdmissionController) -> None:
        self._app = app
        self._controller = controller

    async def __call__(self, scope: Scope, receive: Receive, send: Send) -> None:
        if scope["type"] != "http" or scope.get("method") == "OPTIONS":
            await self._app(scope, receive, send)
            return
        method = str(scope.get("method", "GET")).upper()
        path = str(scope.get("path", ""))
        policy = self._controller.policy_for(method=method, path=path)
        if policy is None:
            await self._app(scope, receive, send)
            return

        client = scope.get("client")
        client_ip = str(client[0]) if client else "unknown"
        semaphore: asyncio.Semaphore | None = None
        body_semaphore: asyncio.Semaphore | None = None
        try:
            await self._controller.admit_ip(policy=policy, client_ip=client_ip)
            body_semaphore = await self._controller.acquire_body_reader(
                policy,
                client_ip=client_ip,
            )
            try:
                bounded_receive = await _bounded_request_body(
                    scope=scope,
                    receive=receive,
                    max_bytes=policy.max_body_bytes,
                )
            finally:
                await self._controller.release_body_reader(
                    policy,
                    client_ip=client_ip,
                    semaphore=body_semaphore,
                )
                body_semaphore = None
            semaphore = await self._controller.acquire(policy)
            await self._app(scope, bounded_receive, send)
        except PublicAdmissionRejected as exc:
            await _send_problem(
                send,
                status=429,
                code=exc.code,
                message="The public service is temporarily rate limited.",
                headers=[(b"retry-after", str(exc.retry_after).encode("ascii"))],
            )
        except _RequestBodyTooLarge:
            await _send_problem(
                send,
                status=413,
                code="request_too_large",
                message="The request body exceeds this route's limit.",
            )
        except _InvalidContentLength:
            await _send_problem(
                send,
                status=400,
                code="invalid_content_length",
                message="Content-Length is invalid.",
            )
        finally:
            if body_semaphore is not None:
                await self._controller.release_body_reader(
                    policy,
                    client_ip=client_ip,
                    semaphore=body_semaphore,
                )
            if semaphore is not None:
                semaphore.release()


class _RequestBodyTooLarge(RuntimeError):
    pass


class _InvalidContentLength(RuntimeError):
    pass


async def _bounded_request_body(
    *,
    scope: Scope,
    receive: Receive,
    max_bytes: int,
) -> Receive:
    content_lengths = [
        value
        for name, value in scope.get("headers", [])
        if name.lower() == b"content-length"
    ]
    if len(content_lengths) > 1:
        raise _InvalidContentLength()
    if content_lengths:
        try:
            raw_length = content_lengths[0].decode("ascii")
        except UnicodeDecodeError as exc:
            raise _InvalidContentLength() from exc
        if not raw_length.isdigit():
            raise _InvalidContentLength()
        if int(raw_length) > max_bytes:
            raise _RequestBodyTooLarge()

    body = bytearray()
    while True:
        message = await receive()
        if message["type"] == "http.disconnect":
            raise _InvalidContentLength()
        if message["type"] != "http.request":
            continue
        chunk = message.get("body", b"")
        if not isinstance(chunk, bytes):
            raise _InvalidContentLength()
        body.extend(chunk)
        if len(body) > max_bytes:
            raise _RequestBodyTooLarge()
        if not message.get("more_body", False):
            break

    replayed = False

    async def replay() -> Message:
        nonlocal replayed
        if not replayed:
            replayed = True
            return {"type": "http.request", "body": bytes(body), "more_body": False}
        return await receive()

    return replay


async def _send_problem(
    send: Send,
    *,
    status: int,
    code: str,
    message: str,
    headers: list[tuple[bytes, bytes]] | None = None,
) -> None:
    body = json.dumps(
        {
            "detail": {
                "code": code,
                "message": message,
                "retryable": status == 429,
            }
        },
        separators=(",", ":"),
    ).encode("utf-8")
    response_headers = [
        (b"content-type", b"application/json"),
        (b"content-length", str(len(body)).encode("ascii")),
        *(headers or []),
    ]
    await send({"type": "http.response.start", "status": status, "headers": response_headers})
    await send({"type": "http.response.body", "body": body})
