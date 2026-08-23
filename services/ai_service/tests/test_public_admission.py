import asyncio
from collections.abc import AsyncIterator

import httpx
from fastapi import Depends, FastAPI

from app.api.deps.auth import (
    Principal,
    TokenVerifier,
    get_token_verifier,
    get_verified_principal,
)
from app.core.config import Settings
from app.public_admission import (
    PublicAdmissionController,
    PublicAdmissionMiddleware,
)


def _settings(**overrides: int) -> Settings:
    values: dict[str, object] = {
        "APP_ENV": "staging",
        "PUBLIC_ADMISSION_WAIT_MILLISECONDS": 10,
        "PUBLIC_COACH_IP_REQUESTS_PER_MINUTE": 2,
        "PUBLIC_COACH_OWNER_REQUESTS_PER_MINUTE": 1,
        "PUBLIC_COACH_CONCURRENCY": 1,
        "PUBLIC_READ_OWNER_REQUESTS_PER_MINUTE": 1,
    }
    values.update(overrides)
    return Settings(_env_file=None, **values)


def _asgi_app(
    *,
    entered: asyncio.Event | None = None,
    release: asyncio.Event | None = None,
):
    async def app(scope, receive, send) -> None:
        body = bytearray()
        while True:
            message = await receive()
            if message["type"] != "http.request":
                continue
            body.extend(message.get("body", b""))
            if not message.get("more_body", False):
                break
        if entered is not None and release is not None:
            entered.set()
            await release.wait()
        payload = bytes(body) or b"ok"
        await send(
            {
                "type": "http.response.start",
                "status": 200,
                "headers": [(b"content-length", str(len(payload)).encode("ascii"))],
            }
        )
        await send({"type": "http.response.body", "body": payload})

    return app


def test_public_coach_ip_rate_is_bounded_without_a_user_cap() -> None:
    async def scenario() -> None:
        controller = PublicAdmissionController(_settings(), clock=lambda: 0)
        app = PublicAdmissionMiddleware(_asgi_app(), controller=controller)
        async with httpx.AsyncClient(
            transport=httpx.ASGITransport(app=app),
            base_url="https://api.example.test",
        ) as client:
            first = await client.post("/v1/coach/respond", content=b"{}")
            second = await client.post("/v1/coach/respond", content=b"{}")
            limited = await client.post("/v1/coach/respond", content=b"{}")
        assert first.status_code == 200
        assert second.status_code == 200
        assert limited.status_code == 429
        assert limited.headers["retry-after"] == "60"
        assert limited.json()["detail"]["code"] == "route_rate_limited"

    asyncio.run(scenario())


def test_public_coach_concurrency_rejects_instead_of_queueing() -> None:
    async def scenario() -> None:
        entered = asyncio.Event()
        release = asyncio.Event()
        controller = PublicAdmissionController(
            _settings(PUBLIC_COACH_IP_REQUESTS_PER_MINUTE=20),
            clock=lambda: 0,
        )
        app = PublicAdmissionMiddleware(
            _asgi_app(entered=entered, release=release),
            controller=controller,
        )
        async with httpx.AsyncClient(
            transport=httpx.ASGITransport(app=app),
            base_url="https://api.example.test",
        ) as client:
            active = asyncio.create_task(
                client.post("/v1/coach/respond", content=b"{}")
            )
            await asyncio.wait_for(entered.wait(), timeout=1)
            busy = await client.post("/v1/coach/respond", content=b"{}")
            release.set()
            completed = await active
        assert busy.status_code == 429
        assert busy.headers["retry-after"] == "1"
        assert busy.json()["detail"]["code"] == "route_busy"
        assert completed.status_code == 200

    asyncio.run(scenario())


def test_slow_request_body_does_not_consume_the_execution_slot() -> None:
    async def scenario() -> None:
        body_read_started = asyncio.Event()
        release_body = asyncio.Event()
        controller = PublicAdmissionController(
            _settings(PUBLIC_COACH_IP_REQUESTS_PER_MINUTE=20),
            clock=lambda: 0,
        )
        app = PublicAdmissionMiddleware(_asgi_app(), controller=controller)

        slow_sent: list[dict[str, object]] = []
        fast_sent: list[dict[str, object]] = []
        slow_delivered = False

        async def slow_receive():
            nonlocal slow_delivered
            body_read_started.set()
            await release_body.wait()
            if slow_delivered:
                return {"type": "http.disconnect"}
            slow_delivered = True
            return {"type": "http.request", "body": b"{}", "more_body": False}

        async def fast_receive():
            return {"type": "http.request", "body": b"{}", "more_body": False}

        async def slow_send(message):
            slow_sent.append(message)

        async def fast_send(message):
            fast_sent.append(message)

        scope = {
            "type": "http",
            "method": "POST",
            "path": "/v1/coach/respond",
            "headers": [],
            "client": ("127.0.0.1", 12345),
        }
        slow = asyncio.create_task(app(scope, slow_receive, slow_send))
        await asyncio.wait_for(body_read_started.wait(), timeout=1)

        await asyncio.wait_for(app(scope, fast_receive, fast_send), timeout=1)
        assert fast_sent[0]["status"] == 200

        release_body.set()
        await asyncio.wait_for(slow, timeout=1)
        assert slow_sent[0]["status"] == 200

    asyncio.run(scenario())


def test_one_ip_cannot_exhaust_the_global_body_reader_pool() -> None:
    async def scenario() -> None:
        releases = [asyncio.Event(), asyncio.Event()]
        entered = [asyncio.Event(), asyncio.Event()]
        controller = PublicAdmissionController(
            _settings(PUBLIC_COACH_IP_REQUESTS_PER_MINUTE=20),
            clock=lambda: 0,
        )
        app = PublicAdmissionMiddleware(_asgi_app(), controller=controller)

        async def run_slow(index: int) -> list[dict[str, object]]:
            delivered = False
            sent: list[dict[str, object]] = []

            async def receive():
                nonlocal delivered
                entered[index].set()
                await releases[index].wait()
                if delivered:
                    return {"type": "http.disconnect"}
                delivered = True
                return {
                    "type": "http.request",
                    "body": b"{}",
                    "more_body": False,
                }

            async def send(message):
                sent.append(message)

            await app(
                {
                    "type": "http",
                    "method": "POST",
                    "path": "/v1/coach/respond",
                    "headers": [],
                    "client": ("192.0.2.10", 12000 + index),
                },
                receive,
                send,
            )
            return sent

        slow_tasks = [
            asyncio.create_task(run_slow(0)),
            asyncio.create_task(run_slow(1)),
        ]
        await asyncio.wait_for(
            asyncio.gather(*(event.wait() for event in entered)),
            timeout=1,
        )

        async def request_from(ip: str) -> list[dict[str, object]]:
            sent: list[dict[str, object]] = []

            async def receive():
                return {
                    "type": "http.request",
                    "body": b"{}",
                    "more_body": False,
                }

            async def send(message):
                sent.append(message)

            await app(
                {
                    "type": "http",
                    "method": "POST",
                    "path": "/v1/coach/respond",
                    "headers": [],
                    "client": (ip, 13000),
                },
                receive,
                send,
            )
            return sent

        same_ip = await asyncio.wait_for(request_from("192.0.2.10"), timeout=1)
        other_ip = await asyncio.wait_for(request_from("192.0.2.11"), timeout=1)
        assert same_ip[0]["status"] == 429
        assert other_ip[0]["status"] == 200

        for release in releases:
            release.set()
        completed = await asyncio.gather(*slow_tasks)
        assert all(messages[0]["status"] == 200 for messages in completed)

    asyncio.run(scenario())


def test_coach_body_limit_rejects_content_length_and_chunked_overflow() -> None:
    async def chunks() -> AsyncIterator[bytes]:
        yield b"x" * (16 * 1024)
        yield b"x" * (16 * 1024 + 1)

    async def scenario() -> None:
        controller = PublicAdmissionController(
            _settings(PUBLIC_COACH_IP_REQUESTS_PER_MINUTE=20),
            clock=lambda: 0,
        )
        app = PublicAdmissionMiddleware(_asgi_app(), controller=controller)
        async with httpx.AsyncClient(
            transport=httpx.ASGITransport(app=app),
            base_url="https://api.example.test",
        ) as client:
            declared = await client.post(
                "/v1/coach/respond",
                content=b"x" * (32 * 1024 + 1),
            )
            chunked = await client.post("/v1/coach/respond", content=chunks())
        assert declared.status_code == 413
        assert chunked.status_code == 413
        assert declared.json()["detail"]["code"] == "request_too_large"

    asyncio.run(scenario())


def test_read_routes_reject_request_bodies() -> None:
    async def scenario() -> None:
        controller = PublicAdmissionController(_settings(), clock=lambda: 0)
        app = PublicAdmissionMiddleware(_asgi_app(), controller=controller)
        async with httpx.AsyncClient(
            transport=httpx.ASGITransport(app=app),
            base_url="https://api.example.test",
        ) as client:
            response = await client.request("GET", "/v1/items", content=b"unexpected")
        assert response.status_code == 413
        assert response.json()["detail"]["code"] == "request_too_large"

    asyncio.run(scenario())


class _Verifier(TokenVerifier):
    async def verify(self, token: str) -> Principal | None:
        return Principal(user_id=token)


def test_verified_owner_rate_uses_bearer_derived_principal() -> None:
    async def scenario() -> None:
        app = FastAPI()

        async def verifier_override() -> TokenVerifier:
            return _Verifier()

        app.dependency_overrides[get_token_verifier] = verifier_override
        app.state.public_admission = PublicAdmissionController(
            _settings(),
            clock=lambda: 0,
        )

        @app.get("/v1/items")
        async def items(
            principal: Principal = Depends(get_verified_principal),
        ) -> dict[str, str]:
            return {"owner": principal.user_id}

        async with httpx.AsyncClient(
            transport=httpx.ASGITransport(app=app),
            base_url="https://api.example.test",
        ) as client:
            first = await client.get(
                "/v1/items",
                headers={"Authorization": "Bearer owner-a"},
            )
            limited = await client.get(
                "/v1/items",
                headers={"Authorization": "Bearer owner-a"},
            )
            other_owner = await client.get(
                "/v1/items",
                headers={"Authorization": "Bearer owner-b"},
            )
        assert first.status_code == 200
        assert limited.status_code == 429
        assert limited.headers["retry-after"] == "60"
        assert other_owner.status_code == 200

    asyncio.run(scenario())
