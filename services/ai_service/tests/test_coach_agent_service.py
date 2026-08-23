import asyncio
import json
import shutil
import tempfile
from collections.abc import Callable
from datetime import UTC, date, datetime
from pathlib import Path
from uuid import UUID, uuid4

import pytest

from app.core.config import Settings
from app.models.coach import (
    CoachAgentCapabilitiesResponse,
    CoachAgentEvidence,
    CoachAgentLimits,
    CoachAgentModelOutput,
    CoachAgentRequest,
    CoachAgentResponse,
    CoachErrorDetail,
)
from app.providers.base import (
    CoachActivityCallback,
    CoachAgentProviderResult,
    CoachProviderCapability,
    CoachProviderError,
)
from app.repositories.coach_context_repository import CoachProfileContext
from app.repositories.coach_repository import CoachClaimResult
from app.coach_turn_lifecycle import (
    CoachPersistenceConflict,
    CoachPersistenceRateLimited,
)
from app.services import coach_agent_service as coach_agent_service_module
from app.services.coach_agent_service import CoachAgentService
from app.services.coach_service import CoachServiceError
from app.services.coach_snapshot import (
    CoachSnapshotCleanupError,
    CoachSnapshotCoverage,
    CoachSnapshotTooLargeError,
    PreparedCoachSnapshot,
)


NOW = datetime(2026, 7, 28, 12, tzinfo=UTC)


class ContextRepository:
    def __init__(self) -> None:
        self.profile = CoachProfileContext(
            timezone="Europe/Berlin",
            role="user",
            auth_provider="email",
        )

    async def get_profile(self, *, user_id: str) -> CoachProfileContext:
        assert user_id == "owner-1"
        return self.profile


class AgentRepository:
    def __init__(self) -> None:
        self.claim_result = CoachClaimResult(
            state="pending",
            remaining_requests=19,
            response=None,
            error=None,
        )
        self.probe_result: CoachClaimResult | None = None
        self.probe_error: Exception | None = None
        self.probe_calls: list[dict[str, object]] = []
        self.usage_count = 3
        self.claim_calls: list[dict[str, object]] = []
        self.completion_calls: list[dict[str, object]] = []
        self.failure_calls: list[dict[str, object]] = []
        self.history_rows: list[dict[str, object]] = []
        self.delete_calls = 0
        self.operator_usage_count = 0
        self.expected_operator_utc_date = date(2026, 7, 28)
        self.operator_dispatch_count = 0
        self.operator_dispatch_calls: list[dict[str, object]] = []
        self.operator_finish_calls: list[dict[str, object]] = []
        self.operator_dispatch_error: Exception | None = None
        self.operator_finish_error: Exception | None = None
        self.completion_error: Exception | None = None
        self.failure_error: Exception | None = None
        self.events: list[str] = []

    async def claim_agent_request(self, **kwargs) -> CoachClaimResult:
        self.claim_calls.append(kwargs)
        return self.claim_result

    async def probe_agent_terminal_replay(self, **kwargs) -> CoachClaimResult | None:
        self.probe_calls.append(kwargs)
        if self.probe_error is not None:
            raise self.probe_error
        return self.probe_result

    async def complete_agent_request(self, **kwargs) -> CoachAgentResponse:
        self.completion_calls.append(kwargs)
        self.events.append("complete_request")
        if self.completion_error is not None:
            raise self.completion_error
        return kwargs["response"]

    async def fail_request(self, **kwargs) -> CoachErrorDetail:
        self.failure_calls.append(kwargs)
        self.events.append("fail_request")
        if self.failure_error is not None:
            raise self.failure_error
        return kwargs["error"]

    async def count_usage(self, *, user_id: str, local_date: date) -> int:
        assert user_id == "owner-1"
        assert local_date == date(2026, 7, 28)
        return self.usage_count

    async def count_operator_usage(self, *, user_id: str, utc_date: date) -> int:
        assert user_id == "owner-1"
        assert utc_date == self.expected_operator_utc_date
        return self.operator_usage_count

    async def count_operator_dispatches(self, *, utc_date: date) -> int:
        assert utc_date == date(2026, 7, 28)
        return self.operator_dispatch_count

    async def record_operator_dispatch(self, **kwargs) -> None:
        self.operator_dispatch_calls.append(kwargs)
        self.events.append("record_dispatch")
        if self.operator_dispatch_error is not None:
            raise self.operator_dispatch_error

    async def finish_operator_dispatch(self, **kwargs) -> None:
        self.operator_finish_calls.append(kwargs)
        self.events.append("finish_dispatch")
        if self.operator_finish_error is not None:
            raise self.operator_finish_error

    async def reconcile_operator_dispatches(self, *, reconciled_at: datetime) -> int:
        assert reconciled_at == NOW
        return 0

    async def list_agent_history(
        self,
        *,
        user_id: str,
        limit: int,
    ) -> list[dict[str, object]]:
        assert user_id == "owner-1"
        assert limit == 50
        return self.history_rows

    async def delete_history(self, *, user_id: str, deleted_at: datetime) -> int:
        assert user_id == "owner-1"
        assert deleted_at == NOW
        self.delete_calls += 1
        return 2


class SnapshotService:
    def __init__(self) -> None:
        self.calls = 0
        self.snapshots: list[PreparedCoachSnapshot] = []
        self.error: Exception | None = None
        self.row_count = 9
        self.coverage = (
            CoachSnapshotCoverage(
                table="daily_logs",
                description="Daily Capture",
                record_count=5,
                period_start="2026-07-01",
                period_end="2026-07-28",
            ),
            CoachSnapshotCoverage(
                table="focus_sessions",
                description="Focus",
                record_count=4,
                period_start="2026-06-01",
                period_end="2026-07-27",
            ),
        )

    async def create(self, *, user_id: str) -> PreparedCoachSnapshot:
        assert user_id == "owner-1"
        self.calls += 1
        if self.error is not None:
            raise self.error
        working_directory = Path(
            tempfile.mkdtemp(prefix="mylifegraph-snapshot-test-"),
        )
        path = working_directory / "personal.sqlite"
        path.write_bytes(b"snapshot")
        snapshot = PreparedCoachSnapshot(
            path=path,
            working_directory=working_directory,
            row_count=self.row_count,
            source_bytes=1_234,
            coverage=self.coverage,
        )
        self.snapshots.append(snapshot)
        return snapshot


class AgentProvider:
    def __init__(self, *, with_trace: bool = False) -> None:
        self.calls = 0
        self.capability_calls = 0
        self.with_trace = with_trace
        self.trace_rows: list[dict[str, object]] | None = None
        self.last_prompt = ""
        self.capability_result = CoachProviderCapability(
            state="ready",
            provider="local_codex_oauth",
            provider_mode="local_development_only",
            model_requested="gpt-5.5",
            model_source="explicit",
            reason_code="ready",
        )
        self.capability_error: Exception | None = None
        self.response_error: Exception | None = None
        self.capability_started = asyncio.Event()
        self.capability_block: asyncio.Event | None = None
        self.started = asyncio.Event()
        self.block: asyncio.Event | None = None
        self.model_reported: str | None = "gpt-5.5"
        self.output = CoachAgentModelOutput(
            reply=(
                "The recorded days show lower stress later in the sample, "
                "but the app data cannot establish why."
            ),
            uncertainty={
                "level": "medium",
                "reason": "The sample is small and observational.",
            },
            safety={"classification": "normal"},
        )

    async def capability(self) -> CoachProviderCapability:
        self.capability_calls += 1
        self.capability_started.set()
        if self.capability_block is not None:
            await self.capability_block.wait()
        if self.capability_error is not None:
            raise self.capability_error
        return self.capability_result

    async def respond_agent(
        self,
        *,
        prompt: str,
        snapshot_path: Path,
        trace_path: Path,
        activity_callback: CoachActivityCallback | None = None,
    ) -> CoachAgentProviderResult:
        assert "free-form question" in prompt
        assert snapshot_path.name == "personal.sqlite"
        self.last_prompt = prompt
        self.calls += 1
        self.started.set()
        if self.block is not None:
            await self.block.wait()
        if self.response_error is not None:
            raise self.response_error
        if self.with_trace or self.trace_rows is not None:
            trace_rows = (
                self.trace_rows
                if self.trace_rows is not None
                else [
                    {
                        "sequence": 1,
                        "tool": "inspect_data",
                        "status": "completed",
                        "summary": "Inspected data.",
                        "row_count": None,
                        "duration_ms": 2,
                        "tables": [],
                    },
                    {
                        "sequence": 2,
                        "tool": "query_data",
                        "status": "completed",
                        "summary": "Queried logs.",
                        "row_count": 5,
                        "duration_ms": 4,
                        "tables": ["daily_logs"],
                        "sql": (
                            "SELECT entry_date, stress_level "
                            "FROM daily_logs ORDER BY entry_date"
                        ),
                    },
                    {
                        "sequence": 3,
                        "tool": "run_python",
                        "status": "completed",
                        "summary": "Tested association.",
                        "row_count": None,
                        "duration_ms": 7,
                        "tables": [],
                        "full_snapshot_access": True,
                        "python_codepoints": 321,
                    },
                ]
            )
            trace_path.write_text(
                (
                    "\n".join(json.dumps(item) for item in trace_rows) + "\n"
                    if trace_rows
                    else ""
                ),
                encoding="utf-8",
            )
        if activity_callback is not None:
            await activity_callback("Preparing a direct answer …")
        return CoachAgentProviderResult(
            output=self.output,
            model_reported=self.model_reported,
        )


class OperatorProvider(AgentProvider):
    def __init__(self) -> None:
        super().__init__(with_trace=True)
        self.capability_result = CoachProviderCapability(
            state="ready",
            provider="operator_codex_pilot",
            provider_mode="operator_subscription_pilot",
            model_requested="gpt-5.5",
            model_source="explicit",
            reason_code="ready",
        )
        self.reservation_id = UUID("aaaaaaaa-1111-4111-8111-aaaaaaaaaaaa")
        self.reserve_calls = 0
        self.release_calls: list[UUID] = []
        self.reserve_error: CoachProviderError | None = None
        self.reserve_block: asyncio.Event | None = None

    async def reserve(self) -> UUID:
        self.reserve_calls += 1
        if self.reserve_block is not None:
            await self.reserve_block.wait()
        if self.reserve_error is not None:
            raise self.reserve_error
        return self.reservation_id

    async def release_reservation(self, reservation_id: UUID) -> None:
        self.release_calls.append(reservation_id)

    async def respond_agent_reserved(
        self,
        *,
        reservation_id: UUID,
        prompt: str,
        snapshot_path: Path,
        trace_path: Path,
        activity_callback: CoachActivityCallback | None = None,
    ) -> CoachAgentProviderResult:
        assert reservation_id == self.reservation_id
        return await super().respond_agent(
            prompt=prompt,
            snapshot_path=snapshot_path,
            trace_path=trace_path,
            activity_callback=activity_callback,
        )


def _settings() -> Settings:
    return Settings(
        APP_ENV="development",
        USE_MOCK_DATA=False,
        COACH_PROVIDER="local_codex_oauth",
        LOCAL_CODEX_ENABLED=True,
        LOCAL_CODEX_MODEL="gpt-5.5",
        LOCAL_CODEX_MAX_REQUESTS_PER_USER_PER_DAY=99,
        SUPABASE_URL="http://127.0.0.1:54321",
        SUPABASE_SERVICE_ROLE_KEY="test-only",
    )


def _request(message: str = "How has my stress changed?") -> CoachAgentRequest:
    return CoachAgentRequest(
        contract_version="coach-request-v3",
        request_id=uuid4(),
        message=message,
    )


def _service(
    *,
    repository: AgentRepository,
    snapshot: SnapshotService,
    provider: AgentProvider,
    settings: Settings | None = None,
    global_semaphore: asyncio.Semaphore | None = None,
    operator_provider: OperatorProvider | None = None,
    now_provider: Callable[[], datetime] | None = None,
) -> CoachAgentService:
    return CoachAgentService(
        settings=settings or _settings(),
        repository=repository,
        context_repository=ContextRepository(),
        snapshot_service=snapshot,
        provider=provider,
        global_semaphore=global_semaphore or asyncio.Semaphore(1),
        now_provider=now_provider or (lambda: NOW),
        operator_provider=operator_provider,
    )


def _operator_settings() -> Settings:
    return Settings(
        _env_file=None,
        APP_ENV="staging",
        USE_MOCK_DATA=False,
        OPERATOR_CODEX_PILOT_ENABLED=True,
    )


def test_capabilities_publish_fixed_agent_limits_and_fast_configuration() -> None:
    repository = AgentRepository()
    service = _service(
        repository=repository,
        snapshot=SnapshotService(),
        provider=AgentProvider(),
    )

    result = asyncio.run(service.capabilities(user_id="owner-1"))

    assert result.contract_version == "coach-capabilities-v5"
    assert result.state == "ready"
    assert result.model_requested == "gpt-5.5"
    assert result.service_tier == "fast"
    assert result.fast_mode is True
    assert result.limits.requests_per_local_day == 20
    assert result.limits.remaining_requests == 17
    assert result.limits.max_tool_calls == 12
    assert result.limits.turn_timeout_seconds == 180
    assert result.limits.snapshot_max_rows == 50_000
    assert result.limits.snapshot_max_bytes == 8 * 1024 * 1024


def test_account_deletion_cancels_active_turn_and_blocks_new_turns() -> None:
    async def scenario() -> None:
        repository = AgentRepository()
        provider = AgentProvider()
        provider.block = asyncio.Event()
        service = _service(
            repository=repository,
            snapshot=SnapshotService(),
            provider=provider,
        )
        active = asyncio.create_task(
            service.respond(user_id="owner-1", request=_request()),
        )
        await provider.started.wait()

        await service.block_user_and_cancel(user_id="owner-1")

        with pytest.raises(asyncio.CancelledError):
            await active
        with pytest.raises(CoachServiceError) as blocked:
            await service.prepare_turn(user_id="owner-1", request=_request())
        assert blocked.value.detail.code == "account_deletion_pending"
        assert provider.calls == 1

    asyncio.run(scenario())


def test_capabilities_report_configured_usage_when_provider_probe_fails() -> None:
    repository = AgentRepository()
    repository.usage_count = 7
    provider = AgentProvider()
    provider.capability_error = RuntimeError("private provider diagnostic")
    service = _service(
        repository=repository,
        snapshot=SnapshotService(),
        provider=provider,
    )

    result = asyncio.run(service.capabilities(user_id="owner-1"))

    assert result.state == "unavailable"
    assert result.reason_code == "provider_failure"
    assert result.limits.remaining_requests == 13


def test_capabilities_return_promptly_when_all_turn_slots_are_busy(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    semaphore = asyncio.Semaphore(0)
    service = _service(
        repository=AgentRepository(),
        snapshot=SnapshotService(),
        provider=AgentProvider(),
        global_semaphore=semaphore,
    )
    monkeypatch.setattr(
        coach_agent_service_module,
        "_CAPABILITY_SLOT_TIMEOUT_SECONDS",
        0.01,
    )

    result = asyncio.run(service.capabilities(user_id="owner-1"))

    assert result.state == "unavailable"
    assert result.reason_code == "provider_busy"
    assert result.limits.remaining_requests == 17


def test_unavailable_capabilities_report_an_invalid_configured_model() -> None:
    settings = _settings().model_copy(
        update={"local_codex_model": "unavailable-model"},
    )
    provider = AgentProvider()
    provider.capability_result = CoachProviderCapability(
        state="ready",
        provider="local_codex_oauth",
        provider_mode="local_development_only",
        model_requested="unavailable-model",
        model_source="explicit",
        reason_code="ready",
    )
    service = _service(
        repository=AgentRepository(),
        snapshot=SnapshotService(),
        provider=provider,
        settings=settings,
    )

    result = asyncio.run(service.capabilities(user_id="owner-1"))

    assert result.state == "unavailable"
    assert result.reason_code == "unavailable_model"
    assert result.model_requested == "unavailable-model"


def test_ready_capabilities_and_evidence_reject_inconsistent_truth() -> None:
    limits = CoachAgentLimits(
        message_codepoints=2_000,
        reply_codepoints=4_000,
        requests_per_local_day=20,
        request_period="profile_local_day",
        remaining_requests=19,
        max_tool_calls=12,
        turn_timeout_seconds=180,
        sql_timeout_seconds=5,
        python_timeout_seconds=30,
        snapshot_max_rows=50_000,
        snapshot_max_bytes=8 * 1024 * 1024,
    )
    with pytest.raises(ValueError, match="ready local Coach"):
        CoachAgentCapabilitiesResponse(
            contract_version="coach-capabilities-v3",
            state="ready",
            provider="local_codex_oauth",
            provider_mode="local_development_only",
            model_requested="another-model",
            model_source="explicit",
            service_tier="fast",
            fast_mode=True,
            reason_code="ready",
            limits=limits,
            tools=["inspect_data", "query_data", "run_python"],
        )
    with pytest.raises(ValueError, match="periods"):
        CoachAgentEvidence(
            source="daily_logs",
            record_count=1,
            period_start="2026-07-28",
            period_end=None,
        )


def test_free_turn_builds_snapshot_and_derives_trace_evidence_from_actual_tools() -> (
    None
):
    repository = AgentRepository()
    snapshot = SnapshotService()
    provider = AgentProvider(with_trace=True)
    service = _service(
        repository=repository,
        snapshot=snapshot,
        provider=provider,
    )
    request = _request()
    activity: list[str] = []

    async def run() -> CoachAgentResponse:
        async def record(message: str) -> None:
            activity.append(message)

        return await service.respond(
            user_id="owner-1",
            request=request,
            activity_callback=record,
        )

    result = asyncio.run(run())

    assert result.contract_version == "coach-response-v3"
    assert result.request_id == request.request_id
    assert result.agent_trace.tool_call_count == 3
    assert [step.tool for step in result.agent_trace.steps] == [
        "inspect_data",
        "query_data",
        "run_python",
    ]
    assert result.agent_trace.steps[1].summary.startswith("Read-only SQL:")
    assert result.agent_trace.steps[2].summary == (
        "Isolated Python analysis (321 code points)."
    )
    assert [(item.source, item.record_count) for item in result.evidence] == [
        ("daily_logs", 5),
        ("personal_snapshot", 9),
    ]
    assert result.agent_trace.limitations[-1] == (
        "Python had read-only access to the full personal snapshot; "
        "table-level attribution from arbitrary code is not trusted."
    )
    assert result.provenance.model_reported == "gpt-5.5"
    assert result.provenance.service_tier_status == "configured"
    assert result.provenance.snapshot_row_count == 9
    assert result.provenance.snapshot_bytes == 1_234
    assert repository.claim_calls[0]["daily_limit"] == 20
    assert repository.completion_calls[0]["usage"] == {
        "provider_called": True,
        "prompt_bytes": repository.completion_calls[0]["usage"]["prompt_bytes"],
        "context_bytes": 1_234,
        "reply_codepoints": len(result.reply),
    }
    assert repository.completion_calls[0]["usage"]["prompt_bytes"] > 0
    assert activity == [
        "Preparing a private data snapshot …",
        "Preparing a direct answer …",
    ]
    assert not snapshot.snapshots[0].working_directory.exists()


def test_turn_fails_instead_of_completing_when_private_snapshot_remains(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    repository = AgentRepository()
    snapshot = SnapshotService()
    provider = AgentProvider()
    service = _service(
        repository=repository,
        snapshot=snapshot,
        provider=provider,
    )

    def fail_cleanup(_prepared: PreparedCoachSnapshot) -> None:
        raise CoachSnapshotCleanupError(
            "The private Coach snapshot could not be securely removed.",
        )

    monkeypatch.setattr(PreparedCoachSnapshot, "cleanup", fail_cleanup)
    try:
        with pytest.raises(CoachServiceError) as caught:
            asyncio.run(
                service.respond(user_id="owner-1", request=_request()),
            )

        assert caught.value.detail.code == "context_failure"
        assert caught.value.detail.message == (
            "Coach could not securely remove the private turn data."
        )
        assert repository.completion_calls == []
        assert repository.failure_calls[0]["error"].code == "context_failure"
        assert repository.failure_calls[0]["usage"]["context_bytes"] == 1_234
        assert snapshot.snapshots[0].working_directory.exists()
    finally:
        if snapshot.snapshots:
            shutil.rmtree(
                snapshot.snapshots[0].working_directory,
                ignore_errors=True,
            )


@pytest.mark.parametrize(
    (
        "message",
        "reply",
        "trace_rows",
        "expected_tools",
        "expected_sources",
        "empty_snapshot",
    ),
    [
        (
            "What does a median mean?",
            "A median is the middle recorded value after sorting the sample.",
            [],
            [],
            [],
            False,
        ),
        (
            "Compare my check-ins with my Focus history.",
            "The two recorded sources cover different but overlapping periods.",
            [
                {
                    "sequence": 1,
                    "tool": "query_data",
                    "status": "completed",
                    "summary": "Read check-ins.",
                    "row_count": 5,
                    "duration_ms": 2,
                    "tables": ["daily_logs"],
                    "sql": "SELECT entry_date FROM daily_logs",
                },
                {
                    "sequence": 2,
                    "tool": "query_data",
                    "status": "completed",
                    "summary": "Read Focus history.",
                    "row_count": 4,
                    "duration_ms": 2,
                    "tables": ["focus_sessions"],
                    "sql": "SELECT started_at FROM focus_sessions",
                },
            ],
            ["query_data", "query_data"],
            ["daily_logs", "focus_sessions"],
            False,
        ),
        (
            "What changed across the full year?",
            "The available records span more than one part of the year.",
            [
                {
                    "sequence": 1,
                    "tool": "query_data",
                    "status": "completed",
                    "summary": "Read the full available period.",
                    "row_count": 5,
                    "duration_ms": 3,
                    "tables": ["daily_logs"],
                    "sql": (
                        "SELECT entry_date FROM daily_logs "
                        "WHERE entry_date >= '2026-01-01'"
                    ),
                },
            ],
            ["query_data"],
            ["daily_logs"],
            False,
        ),
        (
            "Test whether these recorded samples differ.",
            "The isolated test is descriptive and does not establish a cause.",
            [
                {
                    "sequence": 1,
                    "tool": "run_python",
                    "status": "completed",
                    "summary": "Tested the recorded samples.",
                    "row_count": None,
                    "duration_ms": 8,
                    "tables": [],
                    "full_snapshot_access": True,
                    "python_codepoints": 480,
                },
            ],
            ["run_python"],
            ["personal_snapshot"],
            False,
        ),
        (
            "My Focus duration always improved, right?",
            "No. The recorded history includes a counterexample to that premise.",
            [
                {
                    "sequence": 1,
                    "tool": "query_data",
                    "status": "completed",
                    "summary": "Searched for counterexamples.",
                    "row_count": 4,
                    "duration_ms": 2,
                    "tables": ["focus_sessions"],
                    "sql": (
                        "SELECT started_at, actual_minutes "
                        "FROM focus_sessions ORDER BY started_at"
                    ),
                },
            ],
            ["query_data"],
            ["focus_sessions"],
            False,
        ),
        (
            "What do my check-ins show?",
            "There are no recorded check-ins available for this question.",
            [
                {
                    "sequence": 1,
                    "tool": "query_data",
                    "status": "completed",
                    "summary": "Checked available check-ins.",
                    "row_count": 0,
                    "duration_ms": 1,
                    "tables": ["daily_logs"],
                    "sql": "SELECT entry_date FROM daily_logs",
                },
            ],
            ["query_data"],
            ["daily_logs"],
            True,
        ),
        (
            "Is it better?",
            "Which recorded outcome and comparison period do you mean?",
            [],
            [],
            [],
            False,
        ),
    ],
)
def test_scripted_free_question_scenarios_preserve_actual_tool_truth(
    message: str,
    reply: str,
    trace_rows: list[dict[str, object]],
    expected_tools: list[str],
    expected_sources: list[str],
    empty_snapshot: bool,
) -> None:
    repository = AgentRepository()
    snapshot = SnapshotService()
    if empty_snapshot:
        snapshot.row_count = 0
        snapshot.coverage = (
            CoachSnapshotCoverage(
                table="daily_logs",
                description="Daily Capture",
                record_count=0,
                period_start=None,
                period_end=None,
            ),
        )
    provider = AgentProvider()
    provider.trace_rows = trace_rows
    provider.output = provider.output.model_copy(update={"reply": reply})

    result = asyncio.run(
        _service(
            repository=repository,
            snapshot=snapshot,
            provider=provider,
        ).respond(user_id="owner-1", request=_request(message)),
    )

    assert [step.tool for step in result.agent_trace.steps] == expected_tools
    assert [item.source for item in result.evidence] == expected_sources
    assert result.reply == reply
    assert message in provider.last_prompt


def test_direct_safety_response_bypasses_snapshot_and_provider() -> None:
    repository = AgentRepository()
    snapshot = SnapshotService()
    provider = AgentProvider()
    service = _service(
        repository=repository,
        snapshot=snapshot,
        provider=provider,
    )
    request = _request("I plan to kill myself.")

    result = asyncio.run(
        service.respond(user_id="owner-1", request=request),
    )

    assert result.safety.classification == "safety_redirect"
    assert result.provenance.source == "deterministic_safety"
    assert result.provenance.provider_called is False
    assert result.agent_trace.tool_call_count == 0
    assert result.evidence == []
    assert snapshot.calls == 0
    assert provider.calls == 0
    assert repository.completion_calls[0]["usage"]["prompt_bytes"] == 0


def test_direct_safety_response_bypasses_busy_provider_admission() -> None:
    repository = AgentRepository()
    service = _service(
        repository=repository,
        snapshot=SnapshotService(),
        provider=AgentProvider(),
        global_semaphore=asyncio.Semaphore(0),
    )

    result = asyncio.run(
        service.respond(
            user_id="owner-1",
            request=_request("I plan to kill myself."),
        ),
    )

    assert result.provenance.source == "deterministic_safety"
    assert len(repository.claim_calls) == 1


def test_v3_direct_safety_response_is_english_for_german_input() -> None:
    repository = AgentRepository()
    snapshot = SnapshotService()
    provider = AgentProvider()
    service = _service(
        repository=repository,
        snapshot=snapshot,
        provider=provider,
    )

    result = asyncio.run(
        service.respond(
            user_id="owner-1",
            request=_request("Ich möchte mich umbringen."),
        ),
    )

    assert result.safety.classification == "safety_redirect"
    assert "local emergency service" in result.reply
    assert result.uncertainty.reason == (
        "This situation cannot be safely assessed here."
    )
    assert "Notfalldienst" not in result.reply
    assert provider.capability_calls == 0


def test_v3_post_provider_safety_response_is_english_for_german_input() -> None:
    repository = AgentRepository()
    snapshot = SnapshotService()
    provider = AgentProvider()
    provider.output = CoachAgentModelOutput(
        reply="Provider-authored redirect.",
        uncertainty={"level": "medium", "reason": "Provider-authored reason."},
        safety={"classification": "safety_redirect"},
    )
    service = _service(
        repository=repository,
        snapshot=snapshot,
        provider=provider,
    )

    result = asyncio.run(
        service.respond(
            user_id="owner-1",
            request=_request("Ich brauche sofort Unterstützung."),
        ),
    )

    assert result.safety.classification == "safety_redirect"
    assert result.provenance.source == "deterministic_safety"
    assert result.provenance.provider_called is True
    assert "immediate human support" in result.reply
    assert result.uncertainty.reason == (
        "This situation cannot be safely assessed here."
    )
    assert "Provider-authored" not in result.reply


def test_v3_normal_german_question_still_returns_english_provider_output() -> None:
    repository = AgentRepository()
    snapshot = SnapshotService()
    provider = AgentProvider()
    service = _service(
        repository=repository,
        snapshot=snapshot,
        provider=provider,
    )

    result = asyncio.run(
        service.respond(
            user_id="owner-1",
            request=_request(
                "Kannst du meine Fokusdaten prüfen und die Unsicherheit erklären?",
            ),
        ),
    )

    assert result.reply == provider.output.reply
    assert result.uncertainty.reason == provider.output.uncertainty.reason
    assert result.provenance.prompt_version == "free-coach-agent-prompt-v5"
    assert result.provenance.context_version == "personal-snapshot-v3"
    assert repository.completion_calls
    assert repository.failure_calls == []


@pytest.mark.parametrize(
    ("field", "german_text"),
    [
        (
            "reply",
            "Die Daten zeigen eine Veränderung, aber sie erklären die Ursache nicht.",
        ),
        (
            "uncertainty",
            "Die Datenlage ist klein und die Erklärung bleibt unsicher.",
        ),
    ],
)
def test_v3_rejects_clearly_german_provider_text_as_invalid_output(
    field: str,
    german_text: str,
) -> None:
    repository = AgentRepository()
    snapshot = SnapshotService()
    provider = AgentProvider()
    if field == "reply":
        provider.output = provider.output.model_copy(
            update={"reply": german_text},
        )
    else:
        provider.output = provider.output.model_copy(
            update={
                "uncertainty": provider.output.uncertainty.model_copy(
                    update={"reason": german_text},
                ),
            },
        )
    service = _service(
        repository=repository,
        snapshot=snapshot,
        provider=provider,
    )

    with pytest.raises(CoachServiceError) as caught:
        asyncio.run(
            service.respond(
                user_id="owner-1",
                request=_request("Bitte antworte auf Deutsch."),
            ),
        )

    assert caught.value.detail.code == "invalid_output"
    assert caught.value.detail.retryable is True
    assert repository.completion_calls == []
    assert repository.failure_calls[0]["error"].code == "invalid_output"
    assert repository.failure_calls[0]["error"].retryable is True


@pytest.mark.parametrize(
    "unsafe_reply",
    [
        "Your shorter sleep caused your lower focus.",
        "Your symptoms confirm a diagnosis of depression.",
    ],
)
def test_v3_rejects_unsupported_personal_claims_and_records_failure(
    unsafe_reply: str,
) -> None:
    repository = AgentRepository()
    snapshot = SnapshotService()
    provider = AgentProvider()
    provider.output = provider.output.model_copy(update={"reply": unsafe_reply})
    service = _service(
        repository=repository,
        snapshot=snapshot,
        provider=provider,
    )

    with pytest.raises(CoachServiceError) as caught:
        asyncio.run(
            service.respond(user_id="owner-1", request=_request()),
        )

    assert caught.value.detail.code == "invalid_output"
    assert repository.completion_calls == []
    assert repository.failure_calls[0]["error"].code == "invalid_output"
    assert repository.failure_calls[0]["usage"]["provider_called"] is True
    assert not snapshot.snapshots[0].working_directory.exists()


def test_capability_failure_after_claim_is_recorded_as_provider_failure() -> None:
    repository = AgentRepository()
    snapshot = SnapshotService()
    provider = AgentProvider()
    provider.capability_error = RuntimeError("private preflight diagnostic")
    service = _service(
        repository=repository,
        snapshot=snapshot,
        provider=provider,
    )

    with pytest.raises(CoachServiceError) as caught:
        asyncio.run(
            service.respond(user_id="owner-1", request=_request()),
        )

    assert caught.value.detail.code == "provider_failure"
    assert caught.value.detail.message == "The local Coach agent failed."
    assert snapshot.calls == 0
    assert provider.calls == 0
    assert repository.failure_calls[0]["error"].code == "provider_failure"
    assert repository.failure_calls[0]["usage"]["provider_called"] is False


def test_fast_mode_rejection_after_claim_is_reported_without_fallback() -> None:
    repository = AgentRepository()
    provider = AgentProvider()
    provider.capability_result = CoachProviderCapability(
        state="unavailable",
        provider="local_codex_oauth",
        provider_mode="local_development_only",
        model_requested="gpt-5.5",
        model_source="explicit",
        reason_code="fast_mode_unavailable",
    )
    service = _service(
        repository=repository,
        snapshot=SnapshotService(),
        provider=provider,
    )

    with pytest.raises(CoachServiceError) as caught:
        asyncio.run(service.respond(user_id="owner-1", request=_request()))

    assert caught.value.detail.code == "fast_mode_unavailable"
    assert caught.value.detail.message == (
        "The required Codex Fast mode is unavailable."
    )
    assert repository.failure_calls[0]["error"].code == "fast_mode_unavailable"
    assert repository.failure_calls[0]["usage"]["provider_called"] is False


def test_cancellation_during_capability_preflight_records_interruption() -> None:
    repository = AgentRepository()
    snapshot = SnapshotService()
    provider = AgentProvider()
    provider.capability_block = asyncio.Event()
    service = _service(
        repository=repository,
        snapshot=snapshot,
        provider=provider,
    )

    async def run() -> None:
        task = asyncio.create_task(
            service.respond(user_id="owner-1", request=_request()),
        )
        await provider.capability_started.wait()
        task.cancel()
        with pytest.raises(asyncio.CancelledError):
            await task

    asyncio.run(run())

    assert snapshot.calls == 0
    assert provider.calls == 0
    assert repository.failure_calls[0]["error"].code == "interrupted"
    assert repository.failure_calls[0]["usage"]["provider_called"] is False


def test_capability_preflight_is_inside_the_turn_timeout(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    repository = AgentRepository()
    snapshot = SnapshotService()
    provider = AgentProvider()
    provider.capability_block = asyncio.Event()
    service = _service(
        repository=repository,
        snapshot=snapshot,
        provider=provider,
    )
    monkeypatch.setattr(
        coach_agent_service_module,
        "COACH_AGENT_TIMEOUT_SECONDS",
        0.01,
    )

    with pytest.raises(CoachServiceError) as caught:
        asyncio.run(
            service.respond(user_id="owner-1", request=_request()),
        )

    assert caught.value.detail.code == "provider_timeout"
    assert snapshot.calls == 0
    assert provider.calls == 0
    assert repository.failure_calls[0]["error"].code == "provider_timeout"
    assert repository.failure_calls[0]["usage"]["provider_called"] is False


def test_global_turn_slot_also_serializes_snapshot_creation() -> None:
    semaphore = asyncio.Semaphore(1)
    snapshot = SnapshotService()
    provider = AgentProvider()
    provider.block = asyncio.Event()
    first = _service(
        repository=AgentRepository(),
        snapshot=snapshot,
        provider=provider,
        global_semaphore=semaphore,
    )
    second = _service(
        repository=AgentRepository(),
        snapshot=snapshot,
        provider=provider,
        global_semaphore=semaphore,
    )

    async def run() -> None:
        first_task = asyncio.create_task(
            first.respond(user_id="owner-1", request=_request()),
        )
        await provider.started.wait()
        second_task = asyncio.create_task(
            second.respond(user_id="owner-1", request=_request()),
        )
        for _ in range(3):
            await asyncio.sleep(0)
        assert snapshot.calls == 1
        provider.block.set()
        await asyncio.gather(first_task, second_task)

    asyncio.run(run())

    assert snapshot.calls == 2


def test_busy_turn_is_rejected_before_claim_or_snapshot(monkeypatch) -> None:
    monkeypatch.setattr(
        coach_agent_service_module,
        "_TURN_ADMISSION_TIMEOUT_SECONDS",
        0.01,
    )
    repository = AgentRepository()
    snapshot = SnapshotService()
    provider = AgentProvider()
    service = _service(
        repository=repository,
        snapshot=snapshot,
        provider=provider,
        global_semaphore=asyncio.Semaphore(0),
    )

    with pytest.raises(CoachServiceError) as caught:
        asyncio.run(service.respond(user_id="owner-1", request=_request()))

    assert caught.value.status_code == 429
    assert caught.value.detail.code == "provider_busy"
    assert caught.value.response_headers == {"Retry-After": "15"}
    assert repository.claim_calls == []
    assert snapshot.calls == 0
    assert provider.capability_calls == 0
    assert provider.calls == 0


def test_operator_turn_reserves_records_dispatch_and_releases() -> None:
    repository = AgentRepository()
    provider = OperatorProvider()
    service = _service(
        repository=repository,
        snapshot=SnapshotService(),
        provider=AgentProvider(),
        settings=_operator_settings(),
        operator_provider=provider,
    ).for_operator_request()
    request = CoachAgentRequest(
        contract_version="coach-request-v4",
        request_id=uuid4(),
        message="Compare my recorded patterns.",
    )

    result = asyncio.run(service.respond(user_id="owner-1", request=request))

    assert result.contract_version == "coach-response-v4"
    assert result.provenance.provider == "operator_codex_pilot"
    assert result.provenance.provider_mode == "operator_subscription_pilot"
    assert result.provenance.fast_mode is True
    assert provider.reserve_calls == 1
    assert provider.calls == 1
    assert provider.release_calls == [provider.reservation_id]
    assert repository.claim_calls[0]["contract_version"] == "coach-request-v4"
    assert repository.claim_calls[0]["daily_limit"] == 5
    assert repository.claim_calls[0]["provider_dispatch_required"] is True
    assert len(repository.operator_dispatch_calls) == 1
    assert repository.operator_dispatch_calls[0]["reservation_id"] == (
        provider.reservation_id
    )
    assert repository.operator_finish_calls[0]["state"] == "completed"
    assert repository.events == [
        "record_dispatch",
        "complete_request",
        "finish_dispatch",
    ]


def test_operator_turn_preserves_missing_cli_model_provenance() -> None:
    repository = AgentRepository()
    provider = OperatorProvider()
    provider.model_reported = None
    service = _service(
        repository=repository,
        snapshot=SnapshotService(),
        provider=AgentProvider(),
        settings=_operator_settings(),
        operator_provider=provider,
    ).for_operator_request()

    result = asyncio.run(
        service.respond(
            user_id="owner-1",
            request=CoachAgentRequest(
                contract_version="coach-request-v4",
                request_id=uuid4(),
                message="Compare my recorded patterns.",
            ),
        ),
    )

    assert result.provenance.model_requested == "gpt-5.5"
    assert result.provenance.model_reported is None
    assert repository.completion_calls[0]["response"].provenance.model_reported is None


def test_operator_terminal_request_survives_deferred_private_ledger_finish() -> None:
    repository = AgentRepository()
    repository.operator_finish_error = RuntimeError("simulated ledger outage")
    provider = OperatorProvider()
    service = _service(
        repository=repository,
        snapshot=SnapshotService(),
        provider=AgentProvider(),
        settings=_operator_settings(),
        operator_provider=provider,
    ).for_operator_request()

    result = asyncio.run(
        service.respond(
            user_id="owner-1",
            request=CoachAgentRequest(
                contract_version="coach-request-v4",
                request_id=uuid4(),
                message="Compare my recorded patterns.",
            ),
        ),
    )

    assert result.contract_version == "coach-response-v4"
    assert len(repository.completion_calls) == 1
    assert repository.failure_calls == []
    assert repository.operator_finish_calls[0]["state"] == "completed"
    assert provider.calls == 1


def test_operator_ambiguous_completion_stays_dispatched_for_reconciliation() -> None:
    repository = AgentRepository()
    repository.completion_error = RuntimeError("simulated lost completion response")
    provider = OperatorProvider()
    service = _service(
        repository=repository,
        snapshot=SnapshotService(),
        provider=AgentProvider(),
        settings=_operator_settings(),
        operator_provider=provider,
    ).for_operator_request()

    with pytest.raises(CoachServiceError) as caught:
        asyncio.run(
            service.respond(
                user_id="owner-1",
                request=CoachAgentRequest(
                    contract_version="coach-request-v4",
                    request_id=uuid4(),
                    message="Compare my recorded patterns.",
                ),
            ),
        )

    assert caught.value.detail.code == "in_progress"
    assert repository.events == ["record_dispatch", "complete_request"]
    assert repository.operator_finish_calls == []
    assert repository.failure_calls == []


def test_operator_failure_terminalizes_dispatch_after_request_failure() -> None:
    repository = AgentRepository()
    provider = OperatorProvider()
    provider.response_error = CoachProviderError(
        "provider_failure",
        "simulated executor failure",
        retryable=True,
    )
    service = _service(
        repository=repository,
        snapshot=SnapshotService(),
        provider=AgentProvider(),
        settings=_operator_settings(),
        operator_provider=provider,
    ).for_operator_request()

    with pytest.raises(CoachServiceError) as caught:
        asyncio.run(
            service.respond(
                user_id="owner-1",
                request=CoachAgentRequest(
                    contract_version="coach-request-v4",
                    request_id=uuid4(),
                    message="Compare my recorded patterns.",
                ),
            ),
        )

    assert caught.value.detail.code == "provider_failure"
    assert repository.operator_finish_calls[0]["state"] == "failed"
    assert repository.events == [
        "record_dispatch",
        "fail_request",
        "finish_dispatch",
    ]


def test_operator_capabilities_publish_separate_user_and_global_limits() -> None:
    repository = AgentRepository()
    repository.operator_usage_count = 2
    repository.operator_dispatch_count = 7
    provider = OperatorProvider()
    service = _service(
        repository=repository,
        snapshot=SnapshotService(),
        provider=AgentProvider(),
        settings=_operator_settings(),
        operator_provider=provider,
    ).for_operator_request()

    result = asyncio.run(service.capabilities(user_id="owner-1"))

    assert result.contract_version == "coach-capabilities-v5"
    assert result.provider == "operator_codex_pilot"
    assert result.state == "ready"
    assert result.limits.requests_per_local_day == 5
    assert result.limits.request_period == "utc_day"
    assert result.limits.remaining_requests == 3
    assert result.limits.global_requests_per_utc_day == 15
    assert result.limits.global_remaining_requests == 8


def test_operator_capabilities_use_utc_when_profile_local_day_is_ahead() -> None:
    repository = AgentRepository()
    near_midnight = datetime(2026, 7, 28, 23, 30, tzinfo=UTC)
    provider = OperatorProvider()
    service = _service(
        repository=repository,
        snapshot=SnapshotService(),
        provider=AgentProvider(),
        settings=_operator_settings(),
        operator_provider=provider,
        now_provider=lambda: near_midnight,
    ).for_operator_request()

    result = asyncio.run(service.capabilities(user_id="owner-1"))

    assert result.limits.request_period == "utc_day"
    assert result.limits.remaining_requests == 5


def test_operator_safety_bypass_consumes_no_reservation_or_dispatch() -> None:
    repository = AgentRepository()
    provider = OperatorProvider()
    service = _service(
        repository=repository,
        snapshot=SnapshotService(),
        provider=AgentProvider(),
        settings=_operator_settings(),
        operator_provider=provider,
    ).for_operator_request()
    request = CoachAgentRequest(
        contract_version="coach-request-v4",
        request_id=uuid4(),
        message="I plan to kill myself.",
    )

    result = asyncio.run(service.respond(user_id="owner-1", request=request))

    assert result.provenance.source == "deterministic_safety"
    assert result.provenance.provider == "operator_codex_pilot"
    assert result.provenance.provider_called is False
    assert provider.reserve_calls == 0
    assert repository.claim_calls[0]["provider_dispatch_required"] is False
    assert repository.operator_dispatch_calls == []
    assert repository.operator_finish_calls == []


def test_operator_global_limit_rejects_before_executor_reservation_or_claim() -> None:
    repository = AgentRepository()
    repository.operator_dispatch_count = 15
    provider = OperatorProvider()
    service = _service(
        repository=repository,
        snapshot=SnapshotService(),
        provider=AgentProvider(),
        settings=_operator_settings(),
        operator_provider=provider,
    ).for_operator_request()

    with pytest.raises(CoachServiceError) as caught:
        asyncio.run(
            service.respond(
                user_id="owner-1",
                request=CoachAgentRequest(
                    contract_version="coach-request-v4",
                    request_id=uuid4(),
                    message="Compare my recorded patterns.",
                ),
            ),
        )

    assert caught.value.status_code == 429
    assert caught.value.detail.code == "provider_limit"
    assert provider.reserve_calls == 0
    assert repository.claim_calls == []


def test_operator_global_limit_race_fails_without_provider_dispatch() -> None:
    repository = AgentRepository()
    repository.operator_dispatch_error = CoachPersistenceRateLimited(
        "durable global limit won a race",
    )
    provider = OperatorProvider()
    snapshot = SnapshotService()
    service = _service(
        repository=repository,
        snapshot=snapshot,
        provider=AgentProvider(),
        settings=_operator_settings(),
        operator_provider=provider,
    ).for_operator_request()

    with pytest.raises(CoachServiceError) as caught:
        asyncio.run(
            service.respond(
                user_id="owner-1",
                request=CoachAgentRequest(
                    contract_version="coach-request-v4",
                    request_id=uuid4(),
                    message="Compare my recorded patterns.",
                ),
            ),
        )

    assert caught.value.status_code == 429
    assert caught.value.detail.code == "provider_limit"
    assert provider.calls == 0
    assert provider.release_calls == [provider.reservation_id]
    assert repository.operator_finish_calls == []
    assert repository.failure_calls[0]["usage"]["provider_called"] is False
    assert not snapshot.snapshots[0].working_directory.exists()


def test_operator_busy_rejects_before_claim_with_retry_after() -> None:
    repository = AgentRepository()
    provider = OperatorProvider()
    provider.reserve_error = CoachProviderError(
        "provider_busy",
        "private executor detail",
        retryable=True,
    )
    service = _service(
        repository=repository,
        snapshot=SnapshotService(),
        provider=AgentProvider(),
        settings=_operator_settings(),
        operator_provider=provider,
    ).for_operator_request()

    with pytest.raises(CoachServiceError) as caught:
        asyncio.run(
            service.respond(
                user_id="owner-1",
                request=CoachAgentRequest(
                    contract_version="coach-request-v4",
                    request_id=uuid4(),
                    message="Compare my recorded patterns.",
                ),
            ),
        )

    assert caught.value.detail.code == "provider_busy"
    assert caught.value.response_headers == {"Retry-After": "15"}
    assert repository.claim_calls == []


def test_operator_admission_timeout_rejects_before_claim(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setattr(
        coach_agent_service_module,
        "_TURN_ADMISSION_TIMEOUT_SECONDS",
        0.01,
    )
    repository = AgentRepository()
    provider = OperatorProvider()
    provider.reserve_block = asyncio.Event()
    service = _service(
        repository=repository,
        snapshot=SnapshotService(),
        provider=AgentProvider(),
        settings=_operator_settings(),
        operator_provider=provider,
    ).for_operator_request()

    with pytest.raises(CoachServiceError) as caught:
        asyncio.run(
            service.respond(
                user_id="owner-1",
                request=CoachAgentRequest(
                    contract_version="coach-request-v4",
                    request_id=uuid4(),
                    message="Compare my recorded patterns.",
                ),
            ),
        )

    assert caught.value.detail.code == "provider_busy"
    assert caught.value.response_headers == {"Retry-After": "15"}
    assert provider.reserve_calls == 1
    assert repository.claim_calls == []
    assert repository.operator_dispatch_calls == []


def test_completed_request_replays_without_new_snapshot_or_provider_call() -> None:
    first_repository = AgentRepository()
    first_snapshot = SnapshotService()
    first_provider = AgentProvider()
    first_service = _service(
        repository=first_repository,
        snapshot=first_snapshot,
        provider=first_provider,
    )
    request = _request()
    persisted = asyncio.run(
        first_service.respond(user_id="owner-1", request=request),
    )

    repository = AgentRepository()
    repository.probe_result = CoachClaimResult(
        state="completed",
        remaining_requests=19,
        response=persisted,
        error=None,
    )
    snapshot = SnapshotService()
    provider = AgentProvider()
    replayed = asyncio.run(
        _service(
            repository=repository,
            snapshot=snapshot,
            provider=provider,
            global_semaphore=asyncio.Semaphore(0),
        ).respond(user_id="owner-1", request=request),
    )

    assert replayed == persisted
    assert snapshot.calls == 0
    assert provider.calls == 0
    assert repository.claim_calls == []
    assert repository.completion_calls == []


def test_operator_terminal_replay_bypasses_kill_switch_budget_and_busy() -> None:
    request = CoachAgentRequest(
        contract_version="coach-request-v4",
        request_id=uuid4(),
        message="Compare my recorded patterns.",
    )
    first_repository = AgentRepository()
    first_provider = OperatorProvider()
    persisted = asyncio.run(
        _service(
            repository=first_repository,
            snapshot=SnapshotService(),
            provider=AgentProvider(),
            settings=_operator_settings(),
            operator_provider=first_provider,
        )
        .for_operator_request()
        .respond(user_id="owner-1", request=request),
    )

    for disabled in [True, False]:
        repository = AgentRepository()
        repository.probe_result = CoachClaimResult(
            state="completed",
            remaining_requests=0,
            response=persisted,
            error=None,
        )
        repository.operator_dispatch_count = 15
        operator = OperatorProvider()
        operator.reserve_error = CoachProviderError(
            "provider_busy",
            "private busy detail",
            retryable=True,
        )
        settings = (
            Settings(_env_file=None, APP_ENV="staging", USE_MOCK_DATA=False)
            if disabled
            else _operator_settings()
        )
        replayed = asyncio.run(
            _service(
                repository=repository,
                snapshot=SnapshotService(),
                provider=AgentProvider(),
                settings=settings,
                operator_provider=None if disabled else operator,
            )
            .for_operator_request()
            .respond(user_id="owner-1", request=request),
        )
        assert replayed == persisted
        assert repository.claim_calls == []
        assert operator.reserve_calls == 0
        assert repository.operator_dispatch_calls == []


def test_terminal_failure_and_conflict_resolve_before_operator_admission() -> None:
    request = CoachAgentRequest(
        contract_version="coach-request-v4",
        request_id=uuid4(),
        message="Compare my recorded patterns.",
    )
    terminal = AgentRepository()
    terminal.probe_result = CoachClaimResult(
        state="failed",
        remaining_requests=0,
        response=None,
        error=CoachErrorDetail(
            code="provider_timeout",
            message="The original provider turn timed out.",
            retryable=True,
        ),
    )
    with pytest.raises(CoachServiceError) as failed:
        asyncio.run(
            _service(
                repository=terminal,
                snapshot=SnapshotService(),
                provider=AgentProvider(),
                settings=Settings(
                    _env_file=None,
                    APP_ENV="staging",
                    USE_MOCK_DATA=False,
                ),
            )
            .for_operator_request()
            .respond(user_id="owner-1", request=request),
        )
    assert failed.value.detail.code == "provider_timeout"
    assert terminal.claim_calls == []

    conflict = AgentRepository()
    conflict.probe_error = CoachPersistenceConflict("changed input")
    operator = OperatorProvider()
    with pytest.raises(CoachServiceError) as rejected:
        asyncio.run(
            _service(
                repository=conflict,
                snapshot=SnapshotService(),
                provider=AgentProvider(),
                settings=_operator_settings(),
                operator_provider=operator,
            )
            .for_operator_request()
            .respond(user_id="owner-1", request=request),
        )
    assert rejected.value.detail.code == "request_conflict"
    assert operator.reserve_calls == 0
    assert conflict.claim_calls == []


def test_missing_operator_request_still_obeys_kill_switch_after_probe() -> None:
    repository = AgentRepository()
    service = _service(
        repository=repository,
        snapshot=SnapshotService(),
        provider=AgentProvider(),
        settings=Settings(
            _env_file=None,
            APP_ENV="staging",
            USE_MOCK_DATA=False,
        ),
    ).for_operator_request()

    with pytest.raises(CoachServiceError) as caught:
        asyncio.run(
            service.respond(
                user_id="owner-1",
                request=CoachAgentRequest(
                    contract_version="coach-request-v4",
                    request_id=uuid4(),
                    message="Compare my recorded patterns.",
                ),
            )
        )

    assert caught.value.detail.code == "provider_disabled"
    assert len(repository.probe_calls) == 1
    assert repository.claim_calls == []


def test_snapshot_overflow_is_recorded_without_provider_call() -> None:
    repository = AgentRepository()
    snapshot = SnapshotService()
    snapshot.error = CoachSnapshotTooLargeError(
        "Personal data exceeds the 8 MiB Coach snapshot limit.",
    )
    provider = AgentProvider()
    service = _service(
        repository=repository,
        snapshot=snapshot,
        provider=provider,
    )

    with pytest.raises(CoachServiceError) as caught:
        asyncio.run(
            service.respond(user_id="owner-1", request=_request()),
        )

    assert caught.value.detail.code == "snapshot_too_large"
    assert caught.value.detail.retryable is False
    assert provider.calls == 0
    assert repository.failure_calls[0]["usage"]["provider_called"] is False


def test_cancellation_records_interruption_and_deletes_turn_files() -> None:
    repository = AgentRepository()
    snapshot = SnapshotService()
    provider = AgentProvider()
    provider.block = asyncio.Event()
    service = _service(
        repository=repository,
        snapshot=snapshot,
        provider=provider,
    )

    async def run() -> None:
        task = asyncio.create_task(
            service.respond(user_id="owner-1", request=_request()),
        )
        await provider.started.wait()
        task.cancel()
        with pytest.raises(asyncio.CancelledError):
            await task

    asyncio.run(run())

    assert repository.failure_calls[0]["error"].code == "interrupted"
    assert repository.failure_calls[0]["usage"]["provider_called"] is True
    assert not snapshot.snapshots[0].working_directory.exists()


def test_one_running_turn_is_reported_without_starting_work() -> None:
    repository = AgentRepository()
    repository.claim_result = CoachClaimResult(
        state="in_progress",
        remaining_requests=19,
        response=None,
        error=None,
    )
    snapshot = SnapshotService()
    provider = AgentProvider()

    with pytest.raises(CoachServiceError) as caught:
        asyncio.run(
            _service(
                repository=repository,
                snapshot=snapshot,
                provider=provider,
            ).respond(user_id="owner-1", request=_request()),
        )

    assert caught.value.detail.code == "in_progress"
    assert caught.value.status_code == 409
    assert snapshot.calls == 0
    assert provider.calls == 0


def test_history_accepts_stored_v2_turns_and_delete_keeps_usage_boundary() -> None:
    repository = AgentRepository()
    snapshot = SnapshotService()
    provider = AgentProvider()
    service = _service(
        repository=repository,
        snapshot=snapshot,
        provider=provider,
    )
    request = _request()
    response = asyncio.run(
        service.respond(user_id="owner-1", request=request),
    )
    repository.history_rows = [
        {
            "request_id": str(request.request_id),
            "message": request.message,
            "response": response.model_dump(mode="json"),
            "created_at": NOW.isoformat(),
        },
    ]

    history = asyncio.run(service.history(user_id="owner-1"))
    deleted = asyncio.run(service.delete_history(user_id="owner-1"))

    assert history.contract_version == "coach-history-v4"
    assert history.turns[0].response == response
    assert deleted.deleted is True
    assert repository.delete_calls == 1


def test_request_contract_has_no_mode_scope_or_time_parameters() -> None:
    request_id = UUID("aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa")

    with pytest.raises(ValueError):
        CoachAgentRequest.model_validate(
            {
                "contract_version": "coach-request-v3",
                "request_id": str(request_id),
                "message": "What stands out?",
                "context_scope": "patterns",
                "context_parameters": {"horizon": "all_available"},
            },
        )
