import asyncio
import json
from datetime import UTC, datetime
from uuid import UUID

import httpx
import pytest
from pydantic import ValidationError

from app.api.deps.auth import Principal
from app.api.routes.coach import _stream_turn
from app.main import create_app
from app.models.coach import (
    CoachAgentCapabilitiesResponse,
    CoachAgentHistoryResponse,
    CoachAgentLimits,
    CoachAgentModelOutput,
    CoachAgentRequest,
    CoachAgentResponse,
    CoachHistoryDeleteResponse,
)
from app.services.coach_service import CoachServiceError


USER_ID = "agent-owner"
REQUEST_ID = UUID("aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa")
NOW = datetime(2026, 7, 28, 12, tzinfo=UTC)


class Verifier:
    async def verify(self, token: str):
        return Principal(user_id=USER_ID) if token == "valid-agent-token" else None


class AgentService:
    def __init__(self) -> None:
        self.calls: list[tuple[str, object]] = []
        self.failure: CoachServiceError | None = None

    async def capabilities(self, *, user_id: str):
        self.calls.append(("capabilities", user_id))
        return CoachAgentCapabilitiesResponse(
            contract_version="coach-capabilities-v2",
            state="ready",
            provider="fake",
            provider_mode="deterministic_test_only",
            model_requested=None,
            model_source="not_applicable",
            service_tier="not_applicable",
            fast_mode=False,
            reason_code="ready",
            limits=CoachAgentLimits(
                message_codepoints=2_000,
                reply_codepoints=4_000,
                requests_per_local_day=20,
                remaining_requests=18,
                max_tool_calls=12,
                turn_timeout_seconds=180,
                sql_timeout_seconds=5,
                python_timeout_seconds=30,
                snapshot_max_rows=50_000,
                snapshot_max_bytes=8 * 1024 * 1024,
            ),
        )

    async def respond(self, *, user_id: str, request, activity_callback=None):
        self.calls.append(("respond", user_id, request))
        if activity_callback is not None:
            await activity_callback("Checking relevant history …")
            await activity_callback(
                "SQL text and hidden chain-of-thought that must not be streamed",
            )
        if self.failure is not None:
            raise self.failure
        return _response(request.request_id)

    async def history(self, *, user_id: str):
        self.calls.append(("history", user_id))
        return CoachAgentHistoryResponse(
            contract_version="coach-history-v2",
            turns=[],
        )

    async def delete_history(self, *, user_id: str):
        self.calls.append(("delete_history", user_id))
        return CoachHistoryDeleteResponse(
            contract_version="coach-history-v1",
            deleted=True,
        )


class BlockingStreamAgentService(AgentService):
    def __init__(self) -> None:
        super().__init__()
        self.started = asyncio.Event()
        self.cancelled = asyncio.Event()

    async def respond(self, *, user_id: str, request, activity_callback=None):
        self.started.set()
        try:
            await asyncio.Event().wait()
        except asyncio.CancelledError:
            self.cancelled.set()
            raise


async def _request(
    method: str,
    path: str,
    *,
    service: AgentService | None = None,
    json_body=None,
):
    app = create_app()
    actual_service = service or AgentService()
    app.state.token_verifier = Verifier()
    app.state.coach_agent_service = actual_service
    async with httpx.AsyncClient(
        transport=httpx.ASGITransport(app=app),
        base_url="http://test",
    ) as client:
        response = await client.request(
            method,
            path,
            headers={"Authorization": "Bearer valid-agent-token"},
            json=json_body,
        )
    return response, actual_service


def _response(request_id: UUID) -> CoachAgentResponse:
    return CoachAgentResponse(
        contract_version="coach-response-v2",
        request_id=request_id,
        reply="The available records show two different periods.",
        uncertainty={
            "level": "medium",
            "reason": "The app contains no observations for several weeks.",
        },
        safety={"classification": "normal"},
        evidence=[
            {
                "source": "daily_logs",
                "record_count": 12,
                "period_start": "2026-01-01",
                "period_end": "2026-07-28",
            },
        ],
        agent_trace={
            "tool_call_count": 1,
            "steps": [
                {
                    "sequence": 1,
                    "tool": "query_data",
                    "status": "completed",
                    "summary": "Read-only SQL: SELECT * FROM daily_logs",
                    "row_count": 12,
                    "duration_ms": 4,
                },
            ],
            "limitations": [
                "The snapshot contains app data only and cannot establish causality.",
            ],
        },
        provenance={
            "source": "model",
            "provider": "fake",
            "provider_mode": "deterministic_test_only",
            "model_requested": None,
            "model_reported": None,
            "model_source": "not_applicable",
            "prompt_version": "free-coach-agent-prompt-v2",
            "context_version": "personal-snapshot-v1",
            "generated_at": NOW,
            "provider_called": True,
            "service_tier": "not_applicable",
            "service_tier_status": "not_applicable",
            "fast_mode": False,
            "snapshot_row_count": 12,
            "snapshot_bytes": 2_048,
        },
    )


def _v3_body() -> dict[str, object]:
    return {
        "contract_version": "coach-request-v3",
        "request_id": str(REQUEST_ID),
        "message": "  Compare everything available and challenge my premise.  ",
    }


def _sse_events(body: str) -> list[tuple[str, dict[str, object]]]:
    events = []
    for block in body.strip().split("\n\n"):
        lines = block.splitlines()
        assert lines[0].startswith("event: ")
        assert lines[1].startswith("data: ")
        events.append(
            (
                lines[0].removeprefix("event: "),
                json.loads(lines[1].removeprefix("data: ")),
            ),
        )
    return events


def test_non_streaming_wrapper_accepts_free_v3_request_and_derives_owner() -> None:
    response, service = asyncio.run(
        _request("POST", "/v1/coach/respond", json_body=_v3_body()),
    )

    assert response.status_code == 200
    assert response.json()["contract_version"] == "coach-response-v2"
    assert response.json()["request_id"] == str(REQUEST_ID)
    assert service.calls[0][0:2] == ("respond", USER_ID)
    assert service.calls[0][2].message == (
        "Compare everything available and challenge my premise."
    )


def test_v3_rejects_every_client_selected_scope_or_period() -> None:
    invalid = {
        **_v3_body(),
        "context_scope": "patterns",
        "context_parameters": {"horizon": "all_available"},
    }

    response, service = asyncio.run(
        _request("POST", "/v1/coach/respond", json_body=invalid),
    )

    assert response.status_code == 422
    assert response.json()["detail"]["code"] == "invalid_request"
    assert service.calls == []


def test_v3_rejects_json_escaped_lone_surrogate_before_service_call() -> None:
    invalid = {
        **_v3_body(),
        "message": "\ud800",
    }

    async def request_escaped_json():
        app = create_app()
        service = AgentService()
        app.state.token_verifier = Verifier()
        app.state.coach_agent_service = service
        async with httpx.AsyncClient(
            transport=httpx.ASGITransport(app=app),
            base_url="http://test",
        ) as client:
            response = await client.post(
                "/v1/coach/respond",
                headers={
                    "Authorization": "Bearer valid-agent-token",
                    "Content-Type": "application/json",
                },
                content=json.dumps(invalid).encode("ascii"),
            )
        return response, service

    response, service = asyncio.run(request_escaped_json())

    assert response.status_code == 422
    assert response.json()["detail"]["code"] == "invalid_request"
    assert service.calls == []


@pytest.mark.parametrize(
    ("reply", "reason"),
    [
        ("\ud800", "Valid uncertainty."),
        ("Valid reply.", "\udfff"),
    ],
)
def test_agent_model_output_rejects_lone_surrogates(
    reply: str,
    reason: str,
) -> None:
    with pytest.raises(ValidationError):
        CoachAgentModelOutput.model_validate(
            {
                "reply": reply,
                "uncertainty": {"level": "high", "reason": reason},
                "safety": {"classification": "normal"},
            },
        )


def test_sse_streams_only_started_safe_activity_and_completed() -> None:
    response, service = asyncio.run(
        _request("POST", "/v1/coach/respond/stream", json_body=_v3_body()),
    )

    assert response.status_code == 200
    assert response.headers["content-type"].startswith("text/event-stream")
    assert response.headers["cache-control"] == "no-cache, no-store"
    events = _sse_events(response.text)
    assert [event for event, _ in events] == [
        "started",
        "activity",
        "activity",
        "completed",
    ]
    assert events[0][1] == {
        "request_id": str(REQUEST_ID),
        "contract_version": "coach-request-v3",
    }
    assert events[1][1] == {"message": "Checking relevant history …"}
    assert events[2][1] == {"message": "Working with personal data …"}
    assert "chain-of-thought" not in response.text
    assert events[3][1]["response"]["contract_version"] == "coach-response-v2"
    assert service.calls[0][0:2] == ("respond", USER_ID)


def test_sse_reports_strict_failed_event_without_partial_answer() -> None:
    service = AgentService()
    service.failure = CoachServiceError(
        "provider_timeout",
        "Coach analysis exceeded its 180-second turn limit.",
        retryable=True,
        status_code=503,
    )

    response, _ = asyncio.run(
        _request(
            "POST",
            "/v1/coach/respond/stream",
            service=service,
            json_body=_v3_body(),
        ),
    )

    events = _sse_events(response.text)
    assert events[-1] == (
        "failed",
        {
            "error": {
                "code": "provider_timeout",
                "message": "Coach analysis exceeded its 180-second turn limit.",
                "retryable": True,
            },
        },
    )
    assert "completed" not in [event for event, _ in events]


def test_closing_sse_stream_cancels_the_running_agent_turn() -> None:
    service = BlockingStreamAgentService()
    request = CoachAgentRequest.model_validate(_v3_body())

    async def run() -> None:
        stream = _stream_turn(
            service=service,
            user_id=USER_ID,
            request=request,
        )
        started = await anext(stream)
        assert started.startswith(b"event: started\n")
        await service.started.wait()
        await stream.aclose()
        await asyncio.wait_for(service.cancelled.wait(), timeout=1)

    asyncio.run(run())
