import asyncio
from datetime import UTC, datetime
from uuid import UUID

import pytest

from app.models.focus import ManualFocusStartRequest, ScheduledFocusStartRequest
from app.services.focus_service import FocusConflictError, FocusService
from app.repositories.focus_repository import FocusPersistenceConflict


USER_ID = "focus-owner"
SESSION_ID = UUID("f4000000-0000-4000-8000-000000000001")
BLOCK_ID = UUID("f4000000-0000-4000-8000-000000000002")
TASK_ID = UUID("f4000000-0000-4000-8000-000000000003")
NOW = datetime(2026, 8, 2, 10, tzinfo=UTC)


class Repository:
    def __init__(self, *, conflict: bool = False) -> None:
        self.conflict = conflict
        self.calls = []

    async def get_start_context(self, **kwargs):
        self.calls.append(("context", kwargs))
        return _context()

    async def start(self, **kwargs):
        self.calls.append(("start", kwargs))
        if self.conflict:
            raise FocusPersistenceConflict("focus_request_conflict")
        return _session(active=True)

    async def finish(self, **kwargs):
        self.calls.append(("finish", kwargs))
        return _session(active=False, status=kwargs["terminal_status"])


def _context():
    return {
        "contract_version": "focus-start-context-v2",
        "origin": "authenticated_backend",
        "source_kind": "planner_task_block",
        "block_id": str(BLOCK_ID),
        "target": {"kind": "task", "id": str(TASK_ID), "title": "Read"},
        "original_starts_at": "2026-08-01T08:00:00+00:00",
        "original_ends_at": "2026-08-01T08:30:00+00:00",
        "recovery_minutes": 10,
        "remaining_minutes": 20,
        "source_state": "partial",
        "can_start": True,
        "blocking_reason": None,
    }


def _session(*, active: bool, status: str = "active"):
    return {
        "contract_version": "focus-session-v2",
        "origin": "authenticated_backend",
        "replayed": False,
        "id": str(SESSION_ID),
        "status": status,
        "started_at": NOW.isoformat(),
        "ended_at": None if active else "2026-08-02T10:17:59+00:00",
        "planned_minutes": 20,
        "actual_minutes": None if active else 17,
        "label": "Read",
        "task_id": str(TASK_ID),
        "habit_id": None,
        "entry_date": "2026-08-02",
        "recovery_minutes": 10,
        "updated_at": (
            NOW.isoformat() if active else "2026-08-02T10:17:59+00:00"
        ),
        "schedule_source": {
            "source_kind": "planner_task_block",
            "block_id": str(BLOCK_ID),
            "original_starts_at": "2026-08-01T08:00:00+00:00",
            "original_ends_at": "2026-08-01T08:30:00+00:00",
            "original_recovery_minutes": 10,
        },
    }


def test_scheduled_start_binds_request_content_and_server_clock() -> None:
    repository = Repository()
    service = FocusService(repository=repository, now=lambda: NOW)
    request = ScheduledFocusStartRequest.model_validate(
        {
            "contract_version": "focus-start-v2",
            "request_id": str(SESSION_ID),
            "source_kind": "planner_task_block",
            "source_block_id": str(BLOCK_ID),
            "planned_minutes": 20,
        },
    )

    response = asyncio.run(service.start(user_id=USER_ID, request=request))

    assert response.started_at == NOW
    call = repository.calls[0][1]
    assert call["request_id"] == SESSION_ID
    assert call["source_block_id"] == BLOCK_ID
    assert call["recovery_minutes"] == 0
    assert call["target_kind"] is None
    assert call["now"] == NOW
    assert len(call["request_fingerprint"]) == 64
    assert set(call["request_fingerprint"]) <= set("0123456789abcdef")


def test_manual_and_scheduled_requests_have_distinct_exact_fingerprints() -> None:
    repository = Repository()
    service = FocusService(repository=repository, now=lambda: NOW)
    manual = ManualFocusStartRequest.model_validate(
        {
            "contract_version": "focus-start-v2",
            "request_id": str(SESSION_ID),
            "source_kind": "manual",
            "planned_minutes": 20,
            "recovery_minutes": 10,
            "target_kind": "task",
            "target_id": str(TASK_ID),
            "label": "Read",
        },
    )
    asyncio.run(service.start(user_id=USER_ID, request=manual))
    first = repository.calls[-1][1]["request_fingerprint"]
    asyncio.run(service.start(user_id=USER_ID, request=manual))
    second = repository.calls[-1][1]["request_fingerprint"]
    assert first == second

    scheduled = ScheduledFocusStartRequest.model_validate(
        {
            "contract_version": "focus-start-v2",
            "request_id": str(SESSION_ID),
            "source_kind": "planner_task_block",
            "source_block_id": str(BLOCK_ID),
            "planned_minutes": 20,
        },
    )
    asyncio.run(service.start(user_id=USER_ID, request=scheduled))
    assert repository.calls[-1][1]["request_fingerprint"] != first


def test_persistence_conflicts_are_exposed_without_reinterpretation() -> None:
    service = FocusService(repository=Repository(conflict=True), now=lambda: NOW)
    request = ScheduledFocusStartRequest.model_validate(
        {
            "contract_version": "focus-start-v2",
            "request_id": str(SESSION_ID),
            "source_kind": "planner_task_block",
            "source_block_id": str(BLOCK_ID),
            "planned_minutes": 20,
        },
    )
    with pytest.raises(FocusConflictError, match="focus_request_conflict"):
        asyncio.run(service.start(user_id=USER_ID, request=request))


def test_terminal_service_uses_one_captured_server_instant() -> None:
    repository = Repository()
    service = FocusService(repository=repository, now=lambda: NOW)
    response = asyncio.run(
        service.finish(
            user_id=USER_ID,
            session_id=SESSION_ID,
            terminal_status="completed",
        ),
    )
    assert response.actual_minutes == 17
    assert repository.calls == [
        (
            "finish",
            {
                "user_id": USER_ID,
                "session_id": SESSION_ID,
                "terminal_status": "completed",
                "now": NOW,
            },
        ),
    ]
