import asyncio
from datetime import datetime, timedelta
from uuid import uuid4
from zoneinfo import ZoneInfo

import httpx
import pytest
from pydantic import ValidationError

from app.models.coach_phone_data import PhoneCommand, PhoneSample
from app.services.coach_phone_data import CoachPhoneDataService
from app.api.deps.auth import Principal, get_token_verifier
from app.api.routes import coach as coach_routes
from app.main import create_app
from tests.api_test_dependencies import override_dependency


def sample(zone="Europe/Berlin"):
    captured = datetime.fromisoformat("2026-10-04T00:30:00+00:00")
    today = captured.astimezone(ZoneInfo(zone)).date()
    return dict(
        timezone=zone,
        captured_at=captured.isoformat(),
        days=[dict(date=str(today - timedelta(days=n)), minutes=30) for n in range(7)],
        apps=[dict(name="Browser", minutes=210)],
        attempts_today=None,
    )


@pytest.mark.parametrize(
    "zone", ["UTC", "Europe/Berlin", "America/New_York", "Pacific/Kiritimati"]
)
def test_profile_window_and_unavailable_counter(zone):
    parsed = PhoneSample.model_validate(sample(zone))
    assert parsed.attempts_today is None
    assert len(parsed.days) == 7


@pytest.mark.parametrize("zone", ["Invalid/Timezone", "", "../UTC", "/etc/passwd"])
def test_bad_timezone_is_validation_error(zone):
    payload = sample()
    payload["timezone"] = zone
    with pytest.raises(ValidationError):
        PhoneSample.model_validate(payload)


@pytest.mark.parametrize(
    "field,value",
    [
        ("attempts_today", -1),
        ("attempts_today", True),
        ("attempts_today", "0"),
        ("apps", [dict(name="x", minutes=1)] * 11),
    ],
)
def test_bounds_and_strict_values(field, value):
    with pytest.raises(ValidationError):
        PhoneSample.model_validate({**sample(), field: value})


def test_repeated_day_or_gap_rejected():
    payload = sample()
    payload["days"][-1] = payload["days"][0]
    with pytest.raises(ValidationError):
        PhoneSample.model_validate(payload)


def command(operation="disable", **kwargs):
    return dict(
        contract_version="coach-phone-data-v1",
        request_id=str(uuid4()),
        expected_revision=4,
        command=operation,
        **kwargs,
    )


@pytest.mark.parametrize(
    "payload",
    [
        command("enable", device_id=str(uuid4())),
        command("sync", device_id=str(uuid4())),
        command("delete", data=sample()),
        command("disable", device_id=str(uuid4())),
        command("disable", user_id="forged"),
    ],
)
def test_consent_binding_and_minimal_commands(payload):
    with pytest.raises(ValidationError):
        PhoneCommand.model_validate(payload)


def test_service_owner_filter_and_revision_rpc():
    class Client:
        calls = []

        async def select(self, table, *, params):
            self.calls.append((table, params))
            return [
                dict(timezone="UTC", coach_phone_data=dict(enabled=False, revision=4))
            ]

        async def rpc(self, name, *, params):
            self.calls.append((name, params))
            return dict(
                timezone="UTC", coach_phone_data=dict(enabled=False, revision=5)
            )

    client = Client()
    service = CoachPhoneDataService(client)
    assert asyncio.run(service.read("verified-owner")).revision == 4
    cmd = PhoneCommand.model_validate(command())
    assert asyncio.run(service.apply("verified-owner", cmd)).revision == 5
    assert client.calls[0][1]["id"] == "eq.verified-owner"
    assert client.calls[1][1]["p_user_id"] == "verified-owner"
    assert client.calls[1][1]["p_request"]["expected_revision"] == 4


def test_http_auth_owner_validation_and_conflict_redaction(monkeypatch):
    class Verifier:
        async def verify(self, token):
            return Principal(user_id="verified-owner") if token == "synthetic" else None

    class Client:
        owner = None
        conflict = False

        async def select(self, table, *, params):
            self.owner = params["id"]
            return [
                dict(timezone="UTC", coach_phone_data=dict(enabled=False, revision=4))
            ]

        async def rpc(self, name, *, params):
            self.owner = params["p_user_id"]
            if self.conflict:
                response = httpx.Response(
                    409, request=httpx.Request("POST", "http://synthetic/rpc")
                )
                raise httpx.HTTPStatusError(
                    "private internal details",
                    request=response.request,
                    response=response,
                )
            return dict(
                timezone="UTC", coach_phone_data=dict(enabled=False, revision=5)
            )

    db = Client()
    monkeypatch.setattr(coach_routes, "get_supabase_client", lambda _: db)
    app = create_app()
    override_dependency(app, get_token_verifier, Verifier())

    async def run():
        async with httpx.AsyncClient(
            transport=httpx.ASGITransport(app=app), base_url="http://test"
        ) as client:
            assert (await client.get("/v1/coach/phone-data")).status_code == 401
            headers = {"Authorization": "Bearer synthetic"}
            result = await client.get("/v1/coach/phone-data", headers=headers)
            assert result.status_code == 200
            assert result.headers["cache-control"] == "no-store"
            assert db.owner == "eq.verified-owner"
            invalid = sample()
            invalid["timezone"] = "Invalid/Zone"
            result = await client.post(
                "/v1/coach/phone-data",
                headers=headers,
                json=command("sync", device_id=str(uuid4()), data=invalid),
            )
            assert result.status_code == 422
            result = await client.post(
                "/v1/coach/phone-data", headers=headers, json=command()
            )
            assert result.status_code == 200
            assert result.headers["cache-control"] == "no-store"
            assert db.owner == "verified-owner"
            db.conflict = True
            result = await client.post(
                "/v1/coach/phone-data", headers=headers, json=command()
            )
            assert result.status_code == 409
            assert "private internal" not in result.text

    asyncio.run(run())
