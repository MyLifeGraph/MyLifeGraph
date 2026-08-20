import asyncio
from datetime import UTC, date, datetime
from uuid import UUID

import pytest

from app.core.config import Settings
from app.models.coach import (
    CoachAgentRequest,
    CoachErrorDetail,
    CoachRequest,
)
from app.providers.base import CoachProviderCapability
from app.repositories.coach_context_repository import CoachProfileContext
from app.repositories.coach_repository import (
    CoachClaimResult,
    CoachPersistenceConflict,
    CoachPersistenceRateLimited,
)
from app.services.coach_agent_service import CoachAgentService
from app.services.coach_service import CoachService, CoachServiceError


USER_ID = "coach-lifecycle-owner"
REQUEST_ID = UUID("77777777-7777-4777-8777-777777777777")
NOW = datetime(2026, 7, 28, 12, tzinfo=UTC)


class Repository:
    def __init__(self, *, claim: CoachClaimResult) -> None:
        self.claim = claim
        self.claim_error: Exception | None = None
        self.complete_error: Exception | None = None
        self.fail_error: Exception | None = None
        self.delete_error: Exception | None = None
        self.claim_calls = 0
        self.complete_calls: list[dict] = []
        self.fail_calls: list[dict] = []
        self.history_calls: list[tuple[str, int]] = []

    async def claim_request(self, **kwargs) -> CoachClaimResult:
        return await self._claim()

    async def claim_agent_request(self, **kwargs) -> CoachClaimResult:
        return await self._claim()

    async def probe_agent_terminal_replay(self, **kwargs) -> CoachClaimResult | None:
        del kwargs
        if self.claim.state in {"in_progress", "completed", "failed", "deleted"}:
            return self.claim
        return None

    async def _claim(self) -> CoachClaimResult:
        self.claim_calls += 1
        if self.claim_error is not None:
            raise self.claim_error
        return self.claim

    async def complete_request(self, **kwargs):
        return await self._complete(kwargs)

    async def complete_agent_request(self, **kwargs):
        return await self._complete(kwargs)

    async def _complete(self, kwargs):
        self.complete_calls.append(kwargs)
        if self.complete_error is not None:
            raise self.complete_error
        return kwargs["response"]

    async def fail_request(self, **kwargs) -> CoachErrorDetail:
        self.fail_calls.append(kwargs)
        if self.fail_error is not None:
            raise self.fail_error
        return kwargs["error"]

    async def list_history(self, *, user_id: str, limit: int) -> list[dict]:
        self.history_calls.append((user_id, limit))
        return []

    async def list_agent_history(self, *, user_id: str, limit: int) -> list[dict]:
        self.history_calls.append((user_id, limit))
        return []

    async def delete_history(self, **kwargs) -> int:
        if self.delete_error is not None:
            raise self.delete_error
        return 0

    async def count_usage(self, *, user_id: str, local_date: date) -> int:
        return 0


class ProfileReader:
    def __init__(self, *, eligible: bool = True) -> None:
        self.profile = CoachProfileContext(
            timezone="Europe/Berlin",
            role="user" if eligible else "guest",
            auth_provider="email" if eligible else "anonymous",
        )

    async def get_profile(self, *, user_id: str) -> CoachProfileContext:
        assert user_id == USER_ID
        return self.profile


class Provider:
    def __init__(self, *, ready: bool = True) -> None:
        self.ready = ready
        self.capability_calls = 0

    async def capability(self) -> CoachProviderCapability:
        self.capability_calls += 1
        return CoachProviderCapability(
            state="ready" if self.ready else "unavailable",
            provider="fake",
            provider_mode="deterministic_test_only",
            model_requested=None,
            model_source="not_applicable",
            reason_code="ready" if self.ready else "provider_unavailable",
        )

    async def respond(self, **kwargs):
        raise AssertionError(
            "The shared lifecycle scenario must not call the provider."
        )

    async def respond_agent(self, **kwargs):
        raise AssertionError(
            "The shared lifecycle scenario must not call the provider."
        )


@pytest.mark.parametrize("orchestrator", ["legacy", "agent"])
@pytest.mark.parametrize(
    ("state", "expected_code", "expected_status"),
    [
        ("in_progress", "in_progress", 409),
        ("failed", "provider_failure", 503),
    ],
)
def test_both_orchestrators_apply_the_same_active_and_failed_claim_policy(
    orchestrator: str,
    state: str,
    expected_code: str,
    expected_status: int,
) -> None:
    error = (
        CoachErrorDetail(
            code="provider_failure",
            message="The local Coach provider failed.",
            retryable=True,
        )
        if state == "failed"
        else None
    )
    service, _, provider, request = _orchestrator(
        orchestrator,
        claim=CoachClaimResult(
            state=state,
            remaining_requests=19,
            response=None,
            error=error,
        ),
    )

    with pytest.raises(CoachServiceError) as caught:
        asyncio.run(service.respond(user_id=USER_ID, request=request))

    assert caught.value.detail.code == expected_code
    assert caught.value.detail.retryable is True
    assert caught.value.status_code == expected_status
    assert provider.capability_calls == 0


@pytest.mark.parametrize(
    ("orchestrator", "expected_code", "expected_message"),
    [
        (
            "legacy",
            "provider_failure",
            "The stored Coach request was deleted.",
        ),
        (
            "agent",
            "history_deleted",
            "This Coach request history was deleted.",
        ),
    ],
)
def test_both_orchestrators_preserve_their_terminal_tombstone_contract(
    orchestrator: str,
    expected_code: str,
    expected_message: str,
) -> None:
    service, _, provider, request = _orchestrator(
        orchestrator,
        claim=CoachClaimResult(
            state="deleted",
            remaining_requests=19,
            response=None,
            error=CoachErrorDetail(
                code="provider_failure",
                message="The stored Coach request was deleted.",
                retryable=True,
            ),
        ),
    )

    with pytest.raises(CoachServiceError) as caught:
        asyncio.run(service.respond(user_id=USER_ID, request=request))

    assert caught.value.detail.code == expected_code
    assert caught.value.detail.message == expected_message
    assert caught.value.detail.retryable is False
    assert caught.value.status_code == 410
    assert provider.capability_calls == 0


@pytest.mark.parametrize("orchestrator", ["legacy", "agent"])
@pytest.mark.parametrize(
    ("persistence_error", "expected_code", "expected_status", "retryable"),
    [
        (CoachPersistenceRateLimited, "account_limit", 429, True),
        (CoachPersistenceConflict, "request_conflict", 409, False),
    ],
)
def test_both_orchestrators_translate_claim_persistence_states_identically(
    orchestrator: str,
    persistence_error: type[Exception],
    expected_code: str,
    expected_status: int,
    retryable: bool,
) -> None:
    service, repository, provider, request = _orchestrator(orchestrator)
    repository.claim_error = persistence_error("stored boundary")

    with pytest.raises(CoachServiceError) as caught:
        asyncio.run(service.respond(user_id=USER_ID, request=request))

    assert caught.value.detail.code == expected_code
    assert caught.value.detail.retryable is retryable
    assert caught.value.status_code == expected_status
    assert provider.capability_calls == 0


@pytest.mark.parametrize("orchestrator", ["legacy", "agent"])
def test_both_orchestrators_replay_exact_completed_response_without_new_work(
    orchestrator: str,
) -> None:
    first, first_repository, _, request = _orchestrator(orchestrator)
    response = asyncio.run(first.respond(user_id=USER_ID, request=request))
    assert len(first_repository.complete_calls) == 1

    replay, repository, provider, replay_request = _orchestrator(
        orchestrator,
        claim=CoachClaimResult(
            state="completed",
            remaining_requests=19,
            response=response,
            error=None,
        ),
    )
    replay_request = replay_request.model_copy(
        update={"request_id": request.request_id},
    )

    result = asyncio.run(replay.respond(user_id=USER_ID, request=replay_request))

    assert result == response
    assert repository.complete_calls == []
    assert provider.capability_calls == 0


@pytest.mark.parametrize("orchestrator", ["legacy", "agent"])
def test_both_orchestrators_require_same_id_replay_after_ambiguous_completion(
    orchestrator: str,
) -> None:
    service, repository, _, request = _orchestrator(orchestrator)
    repository.complete_error = OSError("completion response lost")

    with pytest.raises(CoachServiceError) as caught:
        asyncio.run(service.respond(user_id=USER_ID, request=request))

    assert caught.value.detail.model_dump() == {
        "code": "in_progress",
        "message": (
            "The Coach response could not be confirmed. Retry the same request id."
        ),
        "retryable": True,
    }
    assert caught.value.status_code == 409
    assert repository.fail_calls == []


@pytest.mark.parametrize("orchestrator", ["legacy", "agent"])
def test_both_orchestrators_require_same_id_replay_after_ambiguous_failure(
    orchestrator: str,
) -> None:
    service, repository, _, request = _orchestrator(
        orchestrator,
        provider_ready=False,
    )
    request = request.model_copy(update={"message": "Help me plan one step."})
    repository.fail_error = OSError("failure response lost")

    with pytest.raises(CoachServiceError) as caught:
        asyncio.run(service.respond(user_id=USER_ID, request=request))

    assert caught.value.detail.model_dump() == {
        "code": "in_progress",
        "message": "The Coach failure could not be confirmed. Retry the same request id.",
        "retryable": True,
    }
    assert caught.value.status_code == 409
    assert len(repository.fail_calls) == 1
    assert repository.fail_calls[0]["usage"]["provider_called"] is False


@pytest.mark.parametrize("orchestrator", ["legacy", "agent"])
def test_both_orchestrators_share_history_eligibility_limit_and_delete_conflict(
    orchestrator: str,
) -> None:
    service, repository, _, _ = _orchestrator(orchestrator)

    history = asyncio.run(service.history(user_id=USER_ID))
    assert history.turns == []
    assert repository.history_calls == [(USER_ID, 50)]

    repository.delete_error = CoachPersistenceConflict("pending turn")
    with pytest.raises(CoachServiceError) as caught:
        asyncio.run(service.delete_history(user_id=USER_ID))
    assert caught.value.detail.code == "in_progress"
    assert caught.value.status_code == 409


@pytest.mark.parametrize("orchestrator", ["legacy", "agent"])
def test_both_orchestrators_reject_ineligible_profiles_before_claim(
    orchestrator: str,
) -> None:
    service, repository, provider, request = _orchestrator(
        orchestrator,
        eligible=False,
    )

    with pytest.raises(CoachServiceError) as caught:
        asyncio.run(service.respond(user_id=USER_ID, request=request))

    assert caught.value.detail.code == "authenticated_account_required"
    assert caught.value.status_code == 403
    assert repository.claim_calls == 0
    assert provider.capability_calls == 0


def _orchestrator(
    orchestrator: str,
    *,
    claim: CoachClaimResult | None = None,
    provider_ready: bool = True,
    eligible: bool = True,
):
    repository = Repository(
        claim=claim
        or CoachClaimResult(
            state="pending",
            remaining_requests=19,
            response=None,
            error=None,
        ),
    )
    profile_reader = ProfileReader(eligible=eligible)
    provider = Provider(ready=provider_ready)
    settings = Settings(
        APP_ENV="test",
        USE_MOCK_DATA=False,
        COACH_PROVIDER="fake",
        COACH_FAKE_PROVIDER_ENABLED=True,
        LOCAL_CODEX_MAX_REQUESTS_PER_USER_PER_DAY=20,
    )
    if orchestrator == "legacy":
        service = CoachService(
            settings=settings,
            repository=repository,
            context_repository=profile_reader,
            context_service=object(),
            provider=provider,
            global_semaphore=asyncio.Semaphore(1),
            now_provider=lambda: NOW,
        )
        request = CoachRequest(
            contract_version="coach-request-v1",
            request_id=REQUEST_ID,
            message="I want to kill myself right now.",
            context_scope="today",
        )
    else:
        service = CoachAgentService(
            settings=settings,
            repository=repository,
            context_repository=profile_reader,
            snapshot_service=object(),
            provider=provider,
            global_semaphore=asyncio.Semaphore(1),
            now_provider=lambda: NOW,
        )
        request = CoachAgentRequest(
            contract_version="coach-request-v3",
            request_id=REQUEST_ID,
            message="I want to kill myself right now.",
        )
    return service, repository, provider, request
