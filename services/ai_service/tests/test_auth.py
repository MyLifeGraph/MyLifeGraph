import asyncio
import base64
import json
from datetime import UTC, datetime

import pytest
from fastapi import HTTPException
from pydantic import ValidationError

from app.api.deps.auth import Principal, SupabaseTokenVerifier, extract_bearer_token


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
