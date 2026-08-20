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
        self.probe_response: dict[str, object] = {
            "state": "missing",
            "response": None,
            "error": None,
        }

    async def rpc(self, function, *, params):
        self.rpc_calls.append((function, params))
        if function == "probe_coach_terminal_replay_v1":
            return self.probe_response
        if function == "claim_coach_request_v8":
            return {
                "state": "pending",
                "remaining_requests": 19,
                "response": None,
                "error": None,
            }
        if function in {"complete_coach_request_v2", "complete_coach_request_v3"}:
            return {
                "state": "completed",
                "response": self.response.model_dump(mode="json"),
            }
        if function == "record_coach_operator_dispatch_v1":
            return {"state": "dispatched"}
        if function == "finish_coach_operator_dispatch_v1":
            return {"state": params["p_state"]}
        if function == "reconcile_expired_coach_operator_dispatches_v1":
            return {"state": "reconciled", "reconciled_count": 1}
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
        if table == "coach_operator_daily_budgets":
            return [{"dispatch_count": 7}]
        if table in {"coach_requests", "coach_operator_dispatches"}:
            return []
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
            "prompt_version": "free-coach-agent-prompt-v4",
            "context_version": "personal-snapshot-v3",
            "generated_at": NOW,
            "provider_called": True,
            "service_tier": "fast",
            "service_tier_status": "configured",
            "fast_mode": True,
            "snapshot_row_count": 8,
            "snapshot_bytes": 1_024,
        },
    )


def _operator_response() -> CoachAgentResponse:
    payload = _response().model_dump(mode="json")
    payload["contract_version"] = "coach-response-v4"
    payload["provenance"].update(
        {
            "provider": "operator_codex_pilot",
            "provider_mode": "operator_subscription_pilot",
        },
    )
    return CoachAgentResponse.model_validate(payload)


def test_v8_claim_binds_only_request_identity_message_and_backend_provenance() -> None:
    client = Client()
    repository = SupabaseCoachRepository(client)

    result = asyncio.run(
        repository.claim_agent_request(
            contract_version="coach-request-v3",
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
            provider_dispatch_required=True,
        ),
    )

    assert result.state == "pending"
    function, params = client.rpc_calls[0]
    assert function == "claim_coach_request_v8"
    assert set(params) == {
        "p_user_id",
        "p_contract_version",
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
        "p_provider_dispatch_required",
    }
    assert params["p_daily_limit"] == 20
    assert not {
        "p_context_scope",
        "p_context_parameters",
        "p_prompt_version",
        "p_context_version",
        "p_message",
    } & set(params)


def test_operator_usage_reads_the_separate_utc_budget_period() -> None:
    client = Client()
    repository = SupabaseCoachRepository(client)

    used = asyncio.run(
        repository.count_operator_usage(
            user_id=USER_ID,
            utc_date=date(2026, 7, 28),
        )
    )

    assert used == 1
    assert client.select_calls == [
        (
            "coach_requests",
            {
                "select": "request_id",
                "user_id": f"eq.{USER_ID}",
                "operator_budget_utc_date": "eq.2026-07-28",
                "provider": "eq.operator_codex_pilot",
                "provider_dispatch_required": "eq.true",
                "limit": "6",
            },
        )
    ]


def test_terminal_replay_probe_is_owner_and_full_identity_bound() -> None:
    client = Client()
    client.probe_response = {
        "state": "completed",
        "response": client.response.model_dump(mode="json"),
        "error": None,
    }
    repository = SupabaseCoachRepository(client)

    replay = asyncio.run(
        repository.probe_agent_terminal_replay(
            contract_version="coach-request-v3",
            user_id=USER_ID,
            request_id=REQUEST_ID,
            message_fingerprint="a" * 64,
            provider="local_codex_oauth",
            provider_mode="local_development_only",
            model_requested="gpt-5.5",
            model_source="explicit",
            provider_dispatch_required=True,
        )
    )

    assert replay is not None
    assert replay.state == "completed"
    assert replay.response == client.response
    function, params = client.rpc_calls[0]
    assert function == "probe_coach_terminal_replay_v1"
    assert params == {
        "p_user_id": USER_ID,
        "p_contract_version": "coach-request-v3",
        "p_request_id": str(REQUEST_ID),
        "p_message_fingerprint": "a" * 64,
        "p_provider": "local_codex_oauth",
        "p_provider_mode": "local_development_only",
        "p_model_requested": "gpt-5.5",
        "p_model_source": "explicit",
        "p_provider_dispatch_required": True,
    }

    client.probe_response = {"state": "active", "response": None, "error": None}
    assert (
        asyncio.run(
            repository.probe_agent_terminal_replay(
                contract_version="coach-request-v3",
                user_id=USER_ID,
                request_id=REQUEST_ID,
                message_fingerprint="a" * 64,
                provider="local_codex_oauth",
                provider_mode="local_development_only",
                model_requested="gpt-5.5",
                model_source="explicit",
                provider_dispatch_required=True,
            )
        )
        is None
    )


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


def test_v4_completion_and_operator_dispatch_use_dedicated_rpcs() -> None:
    client = Client()
    client.response = _operator_response()
    repository = SupabaseCoachRepository(client)
    dispatch_id = UUID("bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb")
    reservation_id = UUID("cccccccc-cccc-4ccc-8ccc-cccccccccccc")

    persisted = asyncio.run(
        repository.complete_agent_request(
            user_id=USER_ID,
            request_id=REQUEST_ID,
            user_message="What changed?",
            response=client.response,
            usage={
                "provider_called": True,
                "prompt_bytes": 500,
                "context_bytes": 1_024,
                "reply_codepoints": len(client.response.reply),
            },
            completed_at=NOW,
        ),
    )
    asyncio.run(
        repository.record_operator_dispatch(
            dispatch_id=dispatch_id,
            request_id=REQUEST_ID,
            user_id=USER_ID,
            reservation_id=reservation_id,
            dispatched_at=NOW,
            global_limit=15,
        ),
    )
    asyncio.run(
        repository.finish_operator_dispatch(
            dispatch_id=dispatch_id,
            request_id=REQUEST_ID,
            state="completed",
            error_code=None,
            terminal_at=NOW,
        ),
    )
    reconciled = asyncio.run(
        repository.reconcile_operator_dispatches(reconciled_at=NOW),
    )

    assert persisted == client.response
    assert reconciled == 1
    assert [function for function, _ in client.rpc_calls] == [
        "complete_coach_request_v3",
        "record_coach_operator_dispatch_v1",
        "finish_coach_operator_dispatch_v1",
        "reconcile_expired_coach_operator_dispatches_v1",
    ]
    assert client.rpc_calls[1][1]["p_global_limit"] == 15
    assert client.rpc_calls[2][1]["p_error_code"] is None


def test_operator_global_usage_reads_deletion_safe_daily_budget() -> None:
    client = Client()
    count = asyncio.run(
        SupabaseCoachRepository(client).count_operator_dispatches(
            utc_date=date(2026, 7, 28),
        ),
    )

    assert count == 7
    assert client.select_calls[-1] == (
        "coach_operator_daily_budgets",
        {
            "select": "dispatch_count",
            "utc_date": "eq.2026-07-28",
            "limit": "1",
        },
    )


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
