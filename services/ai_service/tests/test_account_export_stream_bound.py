import asyncio
from decimal import Decimal

import pytest

import app.clients.supabase as supabase_module
from app.clients.supabase import SupabaseResponseTooLargeError, SupabaseRestClient


class _StreamingResponse:
    def __init__(
        self,
        *,
        chunks: list[bytes],
        content_length: int | None = None,
    ) -> None:
        self._chunks = chunks
        self.headers = (
            {"Content-Length": str(content_length)}
            if content_length is not None
            else {}
        )
        self.iterated = False

    async def __aenter__(self):
        return self

    async def __aexit__(self, exc_type, exc, traceback):
        return False

    def raise_for_status(self) -> None:
        return None

    async def aiter_bytes(self, *, chunk_size: int):
        assert chunk_size > 0
        self.iterated = True
        for chunk in self._chunks:
            yield chunk


class _AsyncClient:
    def __init__(self, response: _StreamingResponse, *, timeout: float) -> None:
        self._response = response
        self.timeout = timeout
        self.stream_call = None

    async def __aenter__(self):
        return self

    async def __aexit__(self, exc_type, exc, traceback):
        return False

    def stream(self, method: str, url: str, *, params, headers):
        self.stream_call = (method, url, params, headers)
        return self._response


def _install_stream(monkeypatch, response: _StreamingResponse) -> _AsyncClient:
    client = _AsyncClient(response, timeout=10)
    monkeypatch.setattr(
        supabase_module.httpx,
        "AsyncClient",
        lambda *, timeout: client,
    )
    return client


def _rest_client() -> SupabaseRestClient:
    return SupabaseRestClient(
        url="http://supabase.test",
        service_role_key="service-role-test-key",
    )


def test_bounded_select_decodes_only_a_complete_in_bound_response(monkeypatch) -> None:
    body = b'[{"id":"row-1"}]'
    response = _StreamingResponse(chunks=[body[:5], body[5:]])
    transport = _install_stream(monkeypatch, response)

    rows = asyncio.run(
        _rest_client().select(
            "daily_logs",
            params={"select": "id"},
            max_response_bytes=len(body),
        ),
    )

    assert rows == [{"id": "row-1"}]
    assert response.iterated is True
    assert transport.stream_call is not None
    assert transport.stream_call[:3] == (
        "GET",
        "http://supabase.test/rest/v1/daily_logs",
        {"select": "id"},
    )


def test_bounded_select_preserves_arbitrary_precision_json_numbers(monkeypatch) -> None:
    body = (
        b'[{"id":"row-1","exact":0.12345678901234567890,'
        b'"large":9007199254740993}]'
    )
    _install_stream(monkeypatch, _StreamingResponse(chunks=[body]))

    rows = asyncio.run(
        _rest_client().select(
            "daily_logs",
            params={"select": "*"},
            max_response_bytes=len(body),
        ),
    )

    assert rows == [
        {
            "id": "row-1",
            "exact": Decimal("0.12345678901234567890"),
            "large": 9007199254740993,
        },
    ]


def test_bounded_select_rejects_declared_oversize_before_reading(monkeypatch) -> None:
    response = _StreamingResponse(chunks=[b"[]"], content_length=4097)
    _install_stream(monkeypatch, response)

    with pytest.raises(SupabaseResponseTooLargeError, match="byte bound"):
        asyncio.run(
            _rest_client().select(
                "daily_logs",
                params={"select": "id"},
                max_response_bytes=4096,
            ),
        )

    assert response.iterated is False


def test_bounded_select_rejects_chunked_oversize_before_json_materialization(
    monkeypatch,
) -> None:
    response = _StreamingResponse(chunks=[b"[" + b"x" * 2048, b"x" * 2048 + b"]"])
    _install_stream(monkeypatch, response)

    with pytest.raises(SupabaseResponseTooLargeError, match="byte bound"):
        asyncio.run(
            _rest_client().select(
                "daily_logs",
                params={"select": "id"},
                max_response_bytes=4096,
            ),
        )

    assert response.iterated is True
