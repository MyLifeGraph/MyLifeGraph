import asyncio
from datetime import UTC, datetime, timedelta
from uuid import uuid4

import httpx
import pytest
from pydantic import ValidationError

from app.api.deps.auth import Principal, get_token_verifier
from app.api.routes.health_connect import get_health_connect_repository
from app.main import create_app
from app.models.health_connect import (
    HealthConnectCommand,
    HealthConnectDay,
    HealthConnectState,
)
from app.repositories.health_connect_repository import HealthConnectRepository
from tests.api_test_dependencies import override_dependency


def command(**changes):
    result = dict(
        contract_version="health-connect-v1",
        request_id=str(uuid4()),
        expected_revision=0,
        command="connect",
        device_id=str(uuid4()),
        consent_version="health-connect-cloud-consent-v1",
    )
    result.update(changes)
    return result


def sync(**changes):
    now = datetime.now(UTC)
    result = command(
        command="sync",
        consent_version=None,
        timezone="Europe/Berlin",
        captured_at=now.isoformat(),
        days=[
            {
                "date": (now.date() - timedelta(days=offset)).isoformat(),
                "steps": 1500,
                "sleep_minutes": None,
            }
            for offset in range(7)
        ],
    )
    result.update(changes)
    return result


@pytest.mark.parametrize(
    "change",
    [
        {"user_id": str(uuid4())},
        {"consent_version": None},
        {"device_id": None},
        {"expected_revision": -1},
        {"expected_revision": True},
        {"days": [{"date": "2026-09-14", "steps": 5}]},
        {"contract_version": "unknown"},
    ],
)
def test_connect_rejects_unsafe_or_mixed_payload(change):
    with pytest.raises(ValidationError):
        HealthConnectCommand.model_validate(command(**change))


@pytest.mark.parametrize("value", [-1, 200001, True, 1.5, "10"])
def test_steps_are_bounded_integers(value):
    with pytest.raises(ValidationError):
        HealthConnectDay(date="2026-09-14", steps=value)


def test_missing_is_not_zero_and_provenance_is_bounded():
    assert HealthConnectDay(date="2026-09-14").steps is None
    assert HealthConnectDay(date="2026-09-14", steps=0).steps == 0
    for source in ("token=private", "x" * 201, "a/b"):
        with pytest.raises(ValidationError):
            HealthConnectDay(date="2026-09-14", steps_sources=[source])


@pytest.mark.parametrize("value", [True, "10", -1, float("nan"), 1501])
def test_sleep_is_a_bounded_number_not_a_coerced_value(value):
    with pytest.raises(ValidationError):
        HealthConnectDay(date="2026-09-14", sleep_minutes=value)


def test_sync_requires_complete_unique_window_and_valid_timezone():
    assert len(HealthConnectCommand.model_validate(sync()).days) == 7
    for changes in (
        {"days": []},
        {"timezone": "not/a/timezone"},
        {"days": [{"date": "2026-09-14"}] * 7},
    ):
        with pytest.raises(ValidationError):
            HealthConnectCommand.model_validate(sync(**changes))


def test_disconnect_does_not_accept_health_or_consent():
    assert (
        HealthConnectCommand.model_validate(
            command(command="disconnect", device_id=None, consent_version=None)
        ).command
        == "disconnect"
    )
    with pytest.raises(ValidationError):
        HealthConnectCommand.model_validate(command(command="disconnect"))


class Verifier:
    async def verify(self, token):
        return Principal(user_id="verified-owner") if token == "valid" else None


class Repository:
    def __init__(self, failure=None):
        self.calls = []
        self.failure = failure

    async def read(self, user_id):
        self.calls.append(("read", user_id))
        if self.failure:
            raise self.failure
        return HealthConnectState(
            timezone="Europe/Berlin", window_start="2026-09-08", window_end="2026-09-14"
        )

    async def apply(self, user_id, request):
        self.calls.append(("apply", user_id, request))
        return await self.read(user_id)


async def request(method="GET", body=None, token="valid", failure=None):
    app = create_app()
    repository = Repository(failure)
    override_dependency(app, get_token_verifier, Verifier())
    override_dependency(app, get_health_connect_repository, repository)
    async with httpx.AsyncClient(
        transport=httpx.ASGITransport(app=app), base_url="http://test"
    ) as client:
        response = await client.request(
            method,
            "/v1/health-connect",
            json=body,
            headers={"Authorization": f"Bearer {token}"},
        )
    return response, repository


def test_route_uses_verified_owner_and_read_is_side_effect_free():
    response, repository = asyncio.run(request())
    assert response.status_code == 200
    assert repository.calls == [("read", "verified-owner")]
    response, repository = asyncio.run(request("POST", command()))
    assert response.status_code == 200
    assert repository.calls[0][0:2] == ("apply", "verified-owner")


def test_invalid_auth_and_owner_injection_never_write():
    response, repository = asyncio.run(request("POST", command(), token="invalid"))
    assert response.status_code == 401
    assert not repository.calls
    response, repository = asyncio.run(request("POST", command(user_id="someone-else")))
    assert response.status_code == 422
    assert not repository.calls


def test_persistence_errors_do_not_leak_health_or_credentials():
    response, _ = asyncio.run(
        request(failure=ValueError("private health and credentials"))
    )
    assert response.status_code == 503
    assert "private" not in response.text


def test_repository_scopes_read_and_writes_to_owner():
    class Client:
        async def select(self, table, params):
            assert table == "profiles"
            assert params["id"] == "eq.owner"
            assert "health_connect_last_request" not in params["select"]
            return [{"timezone": "Europe/Berlin", "health_connect_settings": {}}]

        async def rpc(self, name, params):
            assert name == "apply_health_connect_v1"
            assert params["p_user_id"] == "owner"
            assert "user_id" not in params["p_request"]
            return {"timezone": "Europe/Berlin", "health_connect_settings": {}}

    repository = HealthConnectRepository(Client())
    assert not asyncio.run(repository.read("owner")).enabled
    assert not asyncio.run(
        repository.apply("owner", HealthConnectCommand.model_validate(command()))
    ).enabled
