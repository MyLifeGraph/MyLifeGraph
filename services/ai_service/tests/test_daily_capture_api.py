import asyncio
from datetime import UTC, date, datetime

import httpx

from app.api.deps.auth import Principal
from app.main import create_app
from app.repositories.daily_capture_repository import DailyCaptureConflictError
from app.services.daily_capture_service import DailyCaptureService


USER_ID = "capture-owner"
NOW = datetime(2026, 7, 29, 18, tzinfo=UTC)
REQUEST_ID = "11111111-1111-4111-8111-111111111111"


class Verifier:
    async def verify(self, token: str):
        if token != "valid-capture-token":
            return None
        return Principal(user_id=USER_ID, authenticated_at=NOW)


class Repository:
    def __init__(self) -> None:
        self.calls: list[dict[str, object]] = []
        self.error: Exception | None = None

    async def apply_branch(self, **kwargs):
        self.calls.append(kwargs)
        if self.error is not None:
            raise self.error
        capture = kwargs["capture"]
        return {
            "contract_version": "daily-capture-write-v1",
            "entry_date": kwargs["entry_date"].isoformat(),
            "branch": kwargs["branch"],
            "capture_id": capture["capture_id"],
            "captured_at": capture["captured_at"],
            "updated_at": kwargs["now"].isoformat(),
            "replayed": False,
        }


def _evening_capture() -> dict[str, object]:
    return {
        "branch_version": "daily-capture-v4",
        "capture_kind": "evening",
        "entry_date": "2026-07-29",
        "capture_id": "evening:2026-07-29",
        "captured_at": "2026-07-29T17:55:00Z",
        "mood": 7,
        "energy": 6,
        "stress_intensity": 3,
        "stress_intensity_label": "Low",
        "planned_sleep_time": "23:00",
        "sleep_target_minutes": 480,
    }


async def _request(
    repository: Repository,
    *,
    body: dict[str, object],
) -> httpx.Response:
    app = create_app()
    app.state.token_verifier = Verifier()
    app.state.daily_capture_service = DailyCaptureService(
        repository=repository,
        now=lambda: NOW,
    )
    async with httpx.AsyncClient(
        transport=httpx.ASGITransport(app=app),
        base_url="http://test",
    ) as client:
        return await client.put(
            "/v1/daily-capture/2026-07-29/evening",
            headers={"Authorization": "Bearer valid-capture-token"},
            json=body,
        )


def test_daily_capture_put_passes_complete_branch_and_expected_identity() -> None:
    repository = Repository()
    body = {
        "contract_version": "daily-capture-write-v1",
        "request_id": REQUEST_ID,
        "expected_capture": {
            "capture_id": "evening:2026-07-29",
            "captured_at": "2026-07-29T17:30:00Z",
        },
        "capture": _evening_capture(),
    }

    response = asyncio.run(_request(repository, body=body))

    assert response.status_code == 200
    assert response.json() == {
        "contract_version": "daily-capture-write-v1",
        "entry_date": "2026-07-29",
        "branch": "evening",
        "capture_id": "evening:2026-07-29",
        "captured_at": "2026-07-29T17:55:00Z",
        "updated_at": "2026-07-29T18:00:00Z",
        "replayed": False,
    }
    assert len(repository.calls) == 1
    call = repository.calls[0]
    assert call["user_id"] == USER_ID
    assert call["entry_date"] == date(2026, 7, 29)
    assert call["expected_capture"] == {
        "capture_id": "evening:2026-07-29",
        "captured_at": "2026-07-29T17:30:00+00:00",
    }
    assert len(str(call["request_fingerprint"])) == 64


def test_daily_capture_put_rejects_incomplete_branch_before_persistence() -> None:
    repository = Repository()
    capture = _evening_capture()
    del capture["planned_sleep_time"]

    response = asyncio.run(
        _request(
            repository,
            body={
                "contract_version": "daily-capture-write-v1",
                "request_id": REQUEST_ID,
                "expected_capture": None,
                "capture": capture,
            },
        ),
    )

    assert response.status_code == 422
    assert repository.calls == []


def test_daily_capture_put_maps_same_branch_cas_conflict_to_409() -> None:
    repository = Repository()
    repository.error = DailyCaptureConflictError("Capture changed.")

    response = asyncio.run(
        _request(
            repository,
            body={
                "contract_version": "daily-capture-write-v1",
                "request_id": REQUEST_ID,
                "expected_capture": None,
                "capture": _evening_capture(),
            },
        ),
    )

    assert response.status_code == 409
    assert response.json()["detail"] == "Capture changed."
