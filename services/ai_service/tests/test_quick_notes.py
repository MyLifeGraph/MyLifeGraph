import asyncio
from dataclasses import replace
from uuid import uuid4

import httpx
import pytest
from fastapi import FastAPI
from pydantic import ValidationError

from app.api.deps.auth import Principal, get_current_principal
from app.api.routes.quick_notes import get_quick_notes_service, router
from app.models.quick_notes import QuickNoteCreate
from app.models.snapshots import SnapshotGenerateRequest
from app.services.quick_notes_service import QuickNotesService
from app.services.snapshot_aggregator import SnapshotAggregator
from tests.test_snapshot_aggregator import (
    FakeSnapshotRepository,
    NOW,
    TODAY,
    sample_inputs,
)


NOTE_ID = str(uuid4())


def command(**changes):
    return (
        dict(
            contract_version="quick-notes-v1",
            note_id=NOTE_ID,
            timezone="Europe/Berlin",
            text="A private thought.",
        )
        | changes
    )


def note():
    return dict(
        id=NOTE_ID,
        text="A private thought.",
        entry_date="2026-09-14",
        timezone="Europe/Berlin",
        created_at="2026-09-14T12:00:00Z",
    )


@pytest.mark.parametrize(
    "change",
    [
        {"user_id": "another-owner"},
        {"text": ""},
        {"text": " \n\t"},
        {"text": "a" * 2001},
        {"text": True},
        {"text": "a\x00b"},
        {"timezone": "Invalid/Zone"},
        {"timezone": " UTC"},
        {"contract_version": "other"},
        {"note_id": "not-a-uuid"},
    ],
)
def test_invalid_note_cannot_be_saved(change):
    with pytest.raises(ValidationError):
        QuickNoteCreate.model_validate(command(**change))


class Client:
    def __init__(self):
        self.calls = []

    async def rpc(self, name, params):
        self.calls.append((name, params))
        if name == "read_quick_notes_v1":
            return dict(
                contract_version="quick-notes-v1",
                timezone="Europe/Berlin",
                notes=[note()],
                next_cursor=None,
            )
        if name == "save_quick_note_v1":
            return dict(contract_version="quick-notes-v1", note=note(), replayed=False)
        return dict(contract_version="quick-notes-v1", note_id=NOTE_ID, deleted=True)


def test_service_only_calls_owner_scoped_rpcs():
    client = Client()
    service = QuickNotesService(client)
    request = QuickNoteCreate.model_validate(command())
    assert asyncio.run(service.read("owner")).notes[0].text == command()["text"]
    assert not asyncio.run(service.save("owner", request)).replayed
    assert asyncio.run(service.delete("owner", request.note_id)).deleted
    assert all(params["p_user_id"] == "owner" for _, params in client.calls)
    assert client.calls[1][1]["p_request"] == command()


async def route_request(method="GET", body=None, suffix="", failure=None):
    client = Client()
    service = QuickNotesService(client)
    if failure:

        async def fail(*args, **kwargs):
            raise failure

        service.read = fail
    app = FastAPI()
    app.include_router(router, prefix="/v1")
    app.dependency_overrides[get_current_principal] = lambda: Principal(
        user_id="verified-owner"
    )
    app.dependency_overrides[get_quick_notes_service] = lambda: service
    async with httpx.AsyncClient(
        transport=httpx.ASGITransport(app=app), base_url="http://test"
    ) as http:
        response = await http.request(method, "/v1/quick-notes" + suffix, json=body)
    return response, client


def test_routes_use_verified_owner_and_private_response():
    for method, body, suffix in [
        ("GET", None, ""),
        ("POST", command(), ""),
        ("DELETE", None, f"/{NOTE_ID}"),
    ]:
        response, client = asyncio.run(route_request(method, body, suffix))
        assert response.status_code == 200
        assert response.headers["cache-control"] == "no-store"
        assert client.calls[0][1]["p_user_id"] == "verified-owner"


def test_errors_do_not_echo_private_note_or_storage_details():
    response, client = asyncio.run(
        route_request("POST", command(user_id="private owner"))
    )
    assert response.status_code == 422
    assert not client.calls
    assert "private" not in response.text
    response, _ = asyncio.run(
        route_request(failure=ValueError("private storage detail"))
    )
    assert response.status_code == 503
    assert "private" not in response.text


def test_note_is_not_counted_as_any_analysis_input():
    async def generate(inputs):
        repository = FakeSnapshotRepository(inputs)
        service = SnapshotAggregator(
            repository=repository,
            today_provider=lambda: TODAY,
            now_provider=lambda: NOW,
        )
        await service.generate_snapshot(
            user_id="owner", request=SnapshotGenerateRequest()
        )
        return repository.persist_calls

    original = sample_inputs()
    with_note = replace(
        original,
        behavioral_events=[
            *original.behavioral_events,
            {
                "id": NOTE_ID,
                "source": "quick_note",
                "event_type": "quick_note",
                "value": None,
                "occurred_at": "2026-07-02T10:00:00Z",
                "created_at": "2026-07-02T10:00:00Z",
                "metadata": {"text": "Energy 10!", "entry_date": "2026-07-02"},
            },
        ],
    )
    assert asyncio.run(generate(original)) == asyncio.run(generate(with_note))
