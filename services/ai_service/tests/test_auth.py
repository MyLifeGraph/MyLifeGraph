import asyncio
import base64
import json
from datetime import UTC, datetime
from types import SimpleNamespace

import httpx
import pytest
from fastapi import HTTPException
from pydantic import ValidationError
from starlette.requests import Request

from app.api.deps import auth as auth_dependencies
from app.api.deps.auth import (
    Principal,
    SupabaseTokenVerifier,
    _has_current_pilot_participation,
    extract_bearer_token,
)


class AuthClient:
    def __init__(self, user: dict | None) -> None:
        self._user = user

    async def get_user_for_token(self, token: str):
        return self._user


def _token(payload: dict) -> str:
    def segment(value: dict) -> str:
        encoded = base64.urlsafe_b64encode(
            json.dumps(value, separators=(",", ":")).encode("utf-8"),
        )
        return encoded.rstrip(b"=").decode("ascii")

    return f"{segment({'alg': 'RS256'})}.{segment(payload)}.signature"


def _claims(**overrides):
    claims = {
        "sub": "owner-1",
        "session_id": "11111111-2222-4333-8444-555555555555",
        "amr": [{"method": "password", "timestamp": 1783944306}],
    }
    claims.update(overrides)
    return claims


def _verify(user: dict | None, *, token: str | None = None):
    return asyncio.run(
        SupabaseTokenVerifier(AuthClient(user)).verify(
            token or _token(_claims()),
        ),
    )


def test_supabase_verifier_uses_session_bound_auth_method_timestamp() -> None:
    principal = _verify(
        {
            "id": "owner-1",
            "last_sign_in_at": "2099-07-13T14:05:06Z",
        },
    )

    assert principal is not None
    assert principal.user_id == "owner-1"
    assert principal.authenticated_at == datetime.fromtimestamp(
        1783944306,
        tz=UTC,
    )

    refreshed = _verify(
        {"id": "owner-1"},
        token=_token(
            _claims(
                amr=[
                    {"method": "password", "timestamp": 1783944306},
                    {"method": "token_refresh", "timestamp": 2000000000},
                ],
            ),
        ),
    )
    assert refreshed is not None
    assert refreshed.authenticated_at == datetime.fromtimestamp(
        1783944306,
        tz=UTC,
    )


def test_supabase_verifier_fails_closed_for_invalid_session_auth_claims() -> None:
    invalid_claims = [
        _claims(sub="other-owner"),
        _claims(session_id="not-a-uuid"),
        _claims(amr=[]),
        _claims(amr=[{"method": "token_refresh", "timestamp": 1783944306}]),
        _claims(amr=[{"method": "anonymous", "timestamp": 1783944306}]),
        _claims(amr=[{"method": "password", "timestamp": True}]),
        _claims(amr=[{"method": "password", "timestamp": "1783944306"}]),
        _claims(amr=[{"method": "password"}] * 17),
    ]

    for claims in invalid_claims:
        principal = _verify(
            {"id": "owner-1", "last_sign_in_at": "2099-01-01T00:00:00Z"},
            token=_token(claims),
        )

        assert principal is not None
        assert principal.authenticated_at is None

    for malformed_token in ["", "not-a-jwt", "a.%%%.c"]:
        principal = _verify({"id": "owner-1"}, token=malformed_token or " ")
        assert principal is not None
        assert principal.authenticated_at is None


def test_supabase_verifier_still_rejects_missing_user_identity() -> None:
    assert _verify(None) is None
    assert _verify({"last_sign_in_at": "2026-07-13T12:05:06Z"}) is None
    assert _verify({"id": " ", "last_sign_in_at": "2026-07-13T12:05:06Z"}) is None


def test_principal_keeps_authentication_time_optional_but_timezone_aware() -> None:
    assert Principal(user_id="owner-1").authenticated_at is None

    with pytest.raises(ValidationError):
        Principal(
            user_id="owner-1",
            authenticated_at=datetime(2026, 7, 13, 12, 5, 6),
        )


def test_bearer_extraction_rejects_oversized_tokens_before_verification() -> None:
    with pytest.raises(HTTPException) as raised:
        extract_bearer_token("Bearer " + "x" * (16 * 1024 + 1))

    assert raised.value.status_code == 401


def test_pilot_participation_gate_requires_exact_persisted_profile_fields() -> None:
    valid = [
        {
            "id": "owner-1",
            "pilot_participation_notice_version": ("pilot-participation-notice-v1"),
            "pilot_participation_accepted_at": "2026-08-19T12:00:00Z",
        },
    ]
    assert _has_current_pilot_participation(valid, user_id="owner-1") is True

    invalid_rows = [
        [],
        [{**valid[0], "id": "other-owner"}],
        [
            {
                **valid[0],
                "pilot_participation_notice_version": "user-metadata-v1",
            },
        ],
        [{**valid[0], "pilot_participation_accepted_at": None}],
        [{**valid[0], "extra": True}],
    ]
    for rows in invalid_rows:
        assert _has_current_pilot_participation(rows, user_id="owner-1") is False


class _ParticipationProfileClient:
    def __init__(
        self,
        rows: object = None,
        *,
        error: Exception | None = None,
        deletion_pending: bool = False,
    ) -> None:
        self.rows = rows
        self.error = error
        self.deletion_pending = deletion_pending
        self.calls: list[tuple[str, dict]] = []

    async def account_deletion_pending(self, *, user_id: str) -> bool:
        assert user_id == "owner-1"
        return self.deletion_pending

    async def select(self, table: str, *, params: dict):
        self.calls.append((table, params))
        if self.error is not None:
            raise self.error
        return self.rows


def _request() -> Request:
    return Request({"type": "http", "method": "GET", "path": "/v1/today"})


def test_development_principal_bypasses_hosted_participation_lookup(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    principal = Principal(user_id="owner-1")
    monkeypatch.setattr(
        auth_dependencies,
        "get_settings",
        lambda: SimpleNamespace(requires_pilot_participation=False),
    )
    monkeypatch.setattr(
        auth_dependencies,
        "get_supabase_client",
        lambda _: (_ for _ in ()).throw(AssertionError("unexpected lookup")),
    )

    result = asyncio.run(
        auth_dependencies.get_current_principal(_request(), principal),
    )

    assert result is principal


def test_hosted_principal_requires_and_accepts_exact_profile_pair(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    principal = Principal(user_id="owner-1")
    client = _ParticipationProfileClient(
        [
            {
                "id": "owner-1",
                "pilot_participation_notice_version": ("pilot-participation-notice-v1"),
                "pilot_participation_accepted_at": "2026-08-19T12:00:00Z",
            },
        ],
    )
    monkeypatch.setattr(
        auth_dependencies,
        "get_settings",
        lambda: SimpleNamespace(requires_pilot_participation=True),
    )
    monkeypatch.setattr(
        auth_dependencies,
        "get_supabase_client",
        lambda _: client,
    )

    result = asyncio.run(
        auth_dependencies.get_current_principal(_request(), principal),
    )

    assert result is principal
    assert client.calls == [
        (
            "profiles",
            {
                "select": (
                    "id,pilot_participation_notice_version,"
                    "pilot_participation_accepted_at"
                ),
                "id": "eq.owner-1",
                "limit": "1",
            },
        ),
    ]


def test_hosted_principal_missing_acceptance_is_a_structured_403(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setattr(
        auth_dependencies,
        "get_settings",
        lambda: SimpleNamespace(requires_pilot_participation=True),
    )
    monkeypatch.setattr(
        auth_dependencies,
        "get_supabase_client",
        lambda _: _ParticipationProfileClient([]),
    )

    with pytest.raises(HTTPException) as raised:
        asyncio.run(
            auth_dependencies.get_current_principal(
                _request(),
                Principal(user_id="owner-1"),
            ),
        )

    assert raised.value.status_code == 403
    assert raised.value.detail == {
        "code": "pilot_participation_required",
        "message": (
            "Confirm the current adult pilot notice before using product services."
        ),
        "notice_version": "pilot-participation-notice-v1",
    }


def test_hosted_principal_blocks_product_use_while_deletion_is_pending(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    client = _ParticipationProfileClient([], deletion_pending=True)
    monkeypatch.setattr(
        auth_dependencies,
        "get_settings",
        lambda: SimpleNamespace(requires_pilot_participation=True),
    )
    monkeypatch.setattr(auth_dependencies, "get_supabase_client", lambda _: client)

    with pytest.raises(HTTPException) as raised:
        asyncio.run(
            auth_dependencies.get_current_principal(
                _request(),
                Principal(user_id="owner-1"),
            ),
        )

    assert raised.value.status_code == 423
    assert raised.value.detail["code"] == "account_deletion_pending"
    assert client.calls == []


def test_hosted_principal_lookup_failure_is_a_sanitized_503(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    request = httpx.Request("GET", "https://example.test/profiles")
    monkeypatch.setattr(
        auth_dependencies,
        "get_settings",
        lambda: SimpleNamespace(requires_pilot_participation=True),
    )
    monkeypatch.setattr(
        auth_dependencies,
        "get_supabase_client",
        lambda _: _ParticipationProfileClient(
            error=httpx.ConnectError("private detail", request=request),
        ),
    )

    with pytest.raises(HTTPException) as raised:
        asyncio.run(
            auth_dependencies.get_current_principal(
                _request(),
                Principal(user_id="owner-1"),
            ),
        )

    assert raised.value.status_code == 503
    assert raised.value.detail == "Pilot participation verification is unavailable."
