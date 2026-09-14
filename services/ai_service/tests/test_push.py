import asyncio
import base64
import json
from datetime import UTC, datetime
from types import SimpleNamespace
from uuid import uuid4

import httpx
import pytest
from pydantic import ValidationError

from app.api.deps.auth import Principal, get_token_verifier
from app.api.routes import push
from app.main import create_app
from app.models.push import (
    PUSH_CONSENT_VERSION,
    PUSH_CONTRACT_VERSION,
    PushCommand,
    PushSettings,
)
from app.services.push_delivery import FcmSender, deliver_for_owner
from tests.api_test_dependencies import override_dependency


def test_sender_credentials_are_redacted_and_forbidden_in_executor(monkeypatch):
    from app.coach_executor import _assert_secret_free_environment
    from app.core.config import Settings

    settings = Settings(_env_file=None, FCM_CREDENTIALS_JSON="private-sender-credential")
    assert "private-sender-credential" not in repr(settings)
    monkeypatch.setenv("FCM_CREDENTIALS_JSON", "private-sender-credential")
    with pytest.raises(RuntimeError, match="forbidden application secrets"):
        _assert_secret_free_environment()

OWNER, SESSION = str(uuid4()), str(uuid4())


def preferences(**changes):
    return {
        "enabled": True,
        "revision": 1,
        "sleep": True,
        "deadlines": True,
        "patterns": True,
        "quiet_start": "22:00",
        "quiet_end": "07:00",
        "consent_version": PUSH_CONSENT_VERSION,
        "consented_at": "2026-09-14T00:00:00Z",
        **changes,
    }


def command(**changes):
    return {
        "contract_version": PUSH_CONTRACT_VERSION,
        "command": "settings",
        "request_id": str(uuid4()),
        "expected_revision": 0,
        **{
            k: v
            for k, v in preferences().items()
            if k not in ("revision", "consented_at")
        },
        **changes,
    }


@pytest.mark.parametrize(
    "changes",
    [
        {"user_id": OWNER},
        {"expected_revision": True},
        {"quiet_start": "25:00"},
        {"enabled": "true"},
        {"consent_version": None},
        {"device_id": str(uuid4())},
        {"contract_version": "bad"},
    ],
)
def test_settings_fail_closed(changes):
    with pytest.raises(ValidationError):
        PushCommand.model_validate(command(**changes))


def test_enabled_requires_timestamped_explicit_consent():
    assert PushSettings.model_validate(preferences()).enabled
    for changes in (
        {"consent_version": None},
        {"consented_at": None},
        {"consented_at": "2026-09-14T00:00:00"},
    ):
        with pytest.raises(ValidationError):
            PushSettings.model_validate(preferences(**changes))


def test_device_commands_are_separate_and_token_is_not_in_repr():
    body = {
        "contract_version": PUSH_CONTRACT_VERSION,
        "command": "register",
        "expected_revision": 1,
        "request_id": str(uuid4()),
        "device_id": str(uuid4()),
        "registration_id": str(uuid4()),
        "token": "private-device-token-example",
    }
    assert body["token"] not in repr(PushCommand.model_validate(body))
    for changes in (
        {"enabled": True},
        {"token": "bad token with spaces"},
        {"registration_id": None},
    ):
        with pytest.raises(ValidationError):
            PushCommand.model_validate({**body, **changes})


class Client:
    def __init__(self, *, allow=True):
        self.calls = []
        self.allow = allow

    async def rpc(self, name, params):
        self.calls.append((name, params))
        if name in ("get_push_state_v1", "apply_push_command_v1"):
            return {
                "contract_version": PUSH_CONTRACT_VERSION,
                "settings": preferences(),
                "timezone": "UTC",
            }
        if name == "reserve_push_v1":
            return {
                "attempt_id": str(uuid4()),
                "registration_id": str(uuid4()),
                "session_id": SESSION,
                "token": "private-device-token-example",
            }
        if name == "check_push_reservation_v1":
            return self.allow

    async def select(self, table, params):
        self.calls.append((table, params))
        assert table == "tasks"
        assert params["user_id"] == f"eq.{OWNER}"
        assert params["status"] == "in.(todo,in_progress)"
        assert params["limit"] == "1"
        return [{"id": str(uuid4())}]


async def route_request(monkeypatch, body=None, *, valid=True, enabled=True):
    payload = (
        base64.urlsafe_b64encode(
            json.dumps({"sub": OWNER, "session_id": SESSION}).encode()
        )
        .decode()
        .rstrip("=")
    )
    bearer = f"header.{payload}.signature"

    class Verifier:
        async def verify(self, token):
            return Principal(user_id=OWNER) if valid and token == bearer else None

    app = create_app()
    app.state.settings = SimpleNamespace(push_delivery_enabled=enabled)
    client = Client()
    monkeypatch.setattr(push, "get_supabase_client", lambda request: client)
    override_dependency(app, get_token_verifier, Verifier())
    async with httpx.AsyncClient(
        transport=httpx.ASGITransport(app=app), base_url="http://test"
    ) as http:
        response = await http.request(
            "GET" if body is None else "POST",
            "/v1/push",
            json=body,
            headers={"Authorization": f"Bearer {bearer}"},
        )
    return response, client


def test_read_is_side_effect_free_and_write_uses_verified_owner_session(monkeypatch):
    response, client = asyncio.run(route_request(monkeypatch))
    assert response.status_code == 200
    assert response.headers["cache-control"] == "no-store"
    assert client.calls == [("get_push_state_v1", {"p_user_id": OWNER})]
    response, client = asyncio.run(route_request(monkeypatch, command()))
    assert response.status_code == 200
    assert client.calls[0][1]["p_user_id"] == OWNER
    assert client.calls[0][1]["p_session_id"] == SESSION


def test_unauthorized_and_invalid_requests_never_write_or_echo_tokens(monkeypatch):
    response, client = asyncio.run(route_request(monkeypatch, command(), valid=False))
    assert response.status_code == 401 and not client.calls
    response, client = asyncio.run(
        route_request(monkeypatch, command(token="do-not-echo-this-device-secret"))
    )
    assert response.status_code == 422 and not client.calls
    assert "do-not-echo" not in response.text


def test_unactivated_server_allows_opt_out_but_not_opt_in(monkeypatch):
    response, client = asyncio.run(route_request(monkeypatch, command(), enabled=False))
    assert response.status_code == 503 and not client.calls
    response, client = asyncio.run(
        route_request(monkeypatch, command(enabled=False), enabled=False)
    )
    assert response.status_code == 200 and client.calls


@pytest.mark.parametrize(
    "claims", [{"sub": "other", "session_id": SESSION}, {"sub": OWNER}, [], None]
)
def test_session_identity_cannot_be_substituted(claims):
    part = base64.urlsafe_b64encode(json.dumps(claims).encode()).decode()
    with pytest.raises(Exception) as error:
        push.verified_session_id(f"Bearer h.{part}.s", OWNER)
    assert error.value.status_code == 401


class UnavailableAnalysis:
    async def get_recommendation(self, **kwargs):
        raise ValueError("private analysis must not be logged")


class Sender:
    def __init__(self, *, failure=False):
        self.calls = []
        self.failure = failure

    async def send(self, **kwargs):
        self.calls.append(kwargs)
        if self.failure:
            raise httpx.ReadTimeout("private provider details")
        return True, False


def test_deadlines_survive_unavailable_analysis_and_are_reserved_before_send():
    client, sender = Client(), Sender()
    composition = SimpleNamespace(sleep_recommendation_service=UnavailableAnalysis())
    result = asyncio.run(
        deliver_for_owner(
            client,
            composition,
            sender,
            {"id": OWNER, "timezone": "UTC", "push_settings": preferences()},
            now=datetime(2026, 9, 14, 9, 5, tzinfo=UTC),
        )
    )
    assert result == 1 and len(sender.calls) == 1
    assert [name for name, _ in client.calls] == [
        "tasks",
        "reserve_push_v1",
        "check_push_reservation_v1",
        "finish_push_v1",
    ]
    assert client.calls[-1][1]["p_accepted"] is True


def test_revocation_after_reservation_prevents_send():
    client, sender = Client(allow=False), Sender()
    result = asyncio.run(
        deliver_for_owner(
            client,
            None,
            sender,
            {"id": OWNER, "timezone": "UTC", "push_settings": preferences(sleep=False)},
            now=datetime(2026, 9, 14, 9, 5, tzinfo=UTC),
        )
    )
    assert result == 0 and not sender.calls
    assert client.calls[-1][1]["p_accepted"] is False


def test_ambiguous_send_is_finished_as_failed_not_retried():
    client, sender = Client(), Sender(failure=True)
    with pytest.raises(httpx.ReadTimeout):
        asyncio.run(
            deliver_for_owner(
                client,
                None,
                sender,
                {
                    "id": OWNER,
                    "timezone": "UTC",
                    "push_settings": preferences(sleep=False),
                },
                now=datetime(2026, 9, 14, 9, 5, tzinfo=UTC),
            )
        )
    assert len(sender.calls) == 1
    assert client.calls[-1][1]["p_accepted"] is False


@pytest.mark.parametrize("enabled,hour", [(False, 9), (True, 23), (True, 6)])
def test_consent_off_and_quiet_hours_make_no_product_reads(enabled, hour):
    client, sender = Client(), Sender()
    assert (
        asyncio.run(
            deliver_for_owner(
                client,
                None,
                sender,
                {
                    "id": OWNER,
                    "timezone": "UTC",
                    "push_settings": preferences(enabled=enabled),
                },
                now=datetime(2026, 9, 14, hour, tzinfo=UTC),
            )
        )
        == 0
    )
    assert not client.calls and not sender.calls


@pytest.mark.parametrize(
    "status,expected",
    [(200, (True, False)), (404, (False, True)), (503, (False, False))],
)
def test_fcm_sends_only_generic_data_and_never_queues_or_retries(
    monkeypatch, status, expected
):
    import app.services.push_delivery as module

    requests = []

    def transport(request):
        requests.append(request)
        return httpx.Response(
            status, json={"error": {"details": [{"errorCode": "UNREGISTERED"}]}}
        )

    original = httpx.AsyncClient
    monkeypatch.setattr(
        module.httpx,
        "AsyncClient",
        lambda **kwargs: original(**kwargs, transport=httpx.MockTransport(transport)),
    )
    sender = object.__new__(FcmSender)
    sender._credentials = SimpleNamespace(valid=True, token="test-server-credential")
    sender._url = (
        "https://fcm.googleapis.com/v1/projects/mylifegraph-5d234/messages:send"
    )
    result = asyncio.run(
        sender.send(
            owner=OWNER,
            registration={
                "token": "test-device-token",
                "session_id": SESSION,
                "registration_id": "registration",
                "attempt_id": "attempt",
            },
            reminder=SimpleNamespace(
                kind="sleep",
                destination="/insights",
                expires_at=datetime(2026, 9, 14, 21, tzinfo=UTC),
            ),
        )
    )
    assert result == expected and len(requests) == 1
    message = json.loads(requests[0].content)["message"]
    assert message["android"] == {"priority": "HIGH", "ttl": "0s"}
    assert "notification" not in message
    assert set(message["data"]) == {
        "contract_version",
        "owner",
        "registration_id",
        "session_id",
        "attempt_id",
        "kind",
        "expires_epoch",
        "destination",
    }
    assert all(isinstance(value, str) for value in message["data"].values())
    assert "test-server-credential" not in requests[0].content.decode()
