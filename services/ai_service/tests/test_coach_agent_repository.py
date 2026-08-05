import asyncio
from datetime import UTC, date, datetime, timedelta
from uuid import UUID

from app.models.coach import CoachAgentResponse
from app.repositories.coach_repository import SupabaseCoachRepository


USER_ID = "11111111-1111-4111-8111-111111111111"
REQUEST_ID = UUID("aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa")
NOW = datetime(2026, 7, 28, 12, tzinfo=UTC)


class Client:
    def __init__(self) -> None:
        self.rpc_calls: list[tuple[str, dict[str, object]]] = []
        self.select_calls: list[tuple[str, dict[str, str]]] = []
        self.response = _response()

    async def rpc(self, function, *, params):
        self.rpc_calls.append((function, params))
        if function == "claim_coach_request_v5":
            return {
                "state": "pending",
                "remaining_requests": 19,
                "response": None,
                "error": None,
            }
        if function == "complete_coach_request_v2":
            return {
                "state": "completed",
                "response": self.response.model_dump(mode="json"),
            }
        raise AssertionError(function)

    async def select(self, table, *, params):
        self.select_calls.append((table, params))
        if table == "coach_requests":
            return [
                {
                    "request_id": str(REQUEST_ID),
                    "response": self.response.model_dump(mode="json"),
                    "created_at": NOW.isoformat(),
                },
            ]
        if table == "coach_messages":
            return [
                {
                    "request_id": str(REQUEST_ID),
                    "content": "What changed across the full history?",
                },
            ]
        raise AssertionError(table)


def _response() -> CoachAgentResponse:
    return CoachAgentResponse(
        contract_version="coach-response-v2",
        request_id=REQUEST_ID,
        reply="The stored records span two distinct periods.",
        uncertainty={
            "level": "medium",
            "reason": "Some weeks contain no observations.",
        },
        safety={"classification": "normal"},
        evidence=[
            {
                "source": "daily_logs",
                "record_count": 8,
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
                    "row_count": 8,
                    "duration_ms": 10,
                },
            ],
            "limitations": ["Observational app data cannot establish causality."],
        },
        provenance={
            "source": "model",
            "provider": "local_codex_oauth",
            "provider_mode": "local_development_only",
            "model_requested": "gpt-5.5",
            "model_reported": "gpt-5.5",
            "model_source": "explicit",
            "prompt_version": "free-coach-agent-prompt-v3",
            "context_version": "personal-snapshot-v2",
            "generated_at": NOW,
            "provider_called": True,
            "service_tier": "fast",
            "service_tier_status": "configured",
            "fast_mode": True,
            "snapshot_row_count": 8,
            "snapshot_bytes": 1_024,
        },
    )


def test_v5_claim_binds_only_request_identity_message_and_backend_provenance() -> None:
    client = Client()
    repository = SupabaseCoachRepository(client)

    result = asyncio.run(
        repository.claim_agent_request(
            user_id=USER_ID,
            request_id=REQUEST_ID,
            message_fingerprint="a" * 64,
            local_date=date(2026, 7, 28),
            provider="local_codex_oauth",
            provider_mode="local_development_only",
            model_requested="gpt-5.5",
            model_source="explicit",
            claimed_at=NOW,
            lease_expires_at=NOW + timedelta(seconds=240),
            daily_limit=20,
        ),
    )

    assert result.state == "pending"
    function, params = client.rpc_calls[0]
    assert function == "claim_coach_request_v5"
    assert set(params) == {
        "p_user_id",
        "p_request_id",
        "p_message_fingerprint",
        "p_local_date",
        "p_provider",
        "p_provider_mode",
        "p_model_requested",
        "p_model_source",
        "p_claimed_at",
        "p_lease_expires_at",
        "p_daily_limit",
    }
    assert params["p_daily_limit"] == 20
    assert not {
        "p_context_scope",
        "p_context_parameters",
        "p_prompt_version",
        "p_context_version",
        "p_message",
    } & set(params)


def test_v2_completion_sends_backend_derived_evidence_trace_and_fast_tier() -> None:
    client = Client()
    response = client.response
    repository = SupabaseCoachRepository(client)

    persisted = asyncio.run(
        repository.complete_agent_request(
            user_id=USER_ID,
            request_id=REQUEST_ID,
            user_message="What changed?",
            response=response,
            usage={
                "provider_called": True,
                "prompt_bytes": 500,
                "context_bytes": 1_024,
                "reply_codepoints": len(response.reply),
            },
            completed_at=NOW,
        ),
    )

    assert persisted == response
    function, params = client.rpc_calls[0]
    assert function == "complete_coach_request_v2"
    assert params["p_evidence"] == [
        response.evidence[0].model_dump(mode="json"),
    ]
    assert params["p_agent_trace"] == response.agent_trace.model_dump(mode="json")
    assert params["p_tool_call_count"] == 1
    assert params["p_service_tier"] == "fast"
    assert params["p_response"]["provenance"]["service_tier_status"] == "configured"


def test_agent_history_reads_only_completed_owner_rows_and_user_messages() -> None:
    client = Client()

    rows = asyncio.run(
        SupabaseCoachRepository(client).list_agent_history(
            user_id=USER_ID,
            limit=50,
        ),
    )

    assert rows == [
        {
            "request_id": str(REQUEST_ID),
            "message": "What changed across the full history?",
            "response": client.response.model_dump(mode="json"),
            "created_at": NOW.isoformat(),
        },
    ]
    request_query = client.select_calls[0]
    assert request_query[0] == "coach_requests"
    assert request_query[1] == {
        "select": "request_id,response,created_at",
        "user_id": f"eq.{USER_ID}",
        "state": "eq.completed",
        "order": "created_at.desc,request_id.asc",
        "limit": "50",
    }
    message_query = client.select_calls[1]
    assert message_query[0] == "coach_messages"
    assert message_query[1]["role"] == "eq.user"
    assert message_query[1]["user_id"] == f"eq.{USER_ID}"
