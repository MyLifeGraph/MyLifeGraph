import asyncio
from datetime import UTC, datetime
from uuid import UUID

import pytest

from app.core.config import Settings
from app.models.coach import CoachModelOutput, CoachRequest, CoachUsedContext
from app.providers.base import (
    CoachProviderCapability,
    CoachProviderError,
    CoachProviderResult,
)
from app.repositories.coach_context_repository import CoachProfileContext
from app.repositories.coach_repository import CoachClaimResult, CoachMemoryRows
from app.services.coach_context import CoachContextPackage
from app.services.coach_service import CoachService, CoachServiceError


USER_ID = "coach-owner"
REQUEST_ID = UUID("11111111-1111-4111-8111-111111111111")
NOW = datetime(2026, 7, 13, 10, tzinfo=UTC)


class Repository:
    def __init__(self, *, claim_state="pending", completed_response=None) -> None:
        self.claim_state = claim_state
        self.completed_response = completed_response
        self.claim_calls = []
        self.complete_calls = []
        self.fail_calls = []
        self.usage_count = 3
        self.complete_error = None
        self.fail_error = None
        self.memory_include_ids = []

    async def claim_request(self, **kwargs):
        self.claim_calls.append(kwargs)
        return CoachClaimResult(
            state=self.claim_state,
            remaining_requests=16,
            response=self.completed_response,
            error=None,
        )

    async def complete_request(self, **kwargs):
        self.complete_calls.append(kwargs)
        if self.complete_error is not None:
            raise self.complete_error
        return kwargs["response"]

    async def fail_request(self, **kwargs):
        self.fail_calls.append(kwargs)
        if self.fail_error is not None:
            raise self.fail_error
        return kwargs["error"]

    async def count_usage(self, **kwargs):
        return self.usage_count

    async def set_memory_selection(self, **kwargs):
        return {
            "state": "selected" if kwargs["selected"] else "unselected",
            "selected_count": 1 if kwargs["selected"] else 0,
        }

    async def list_memories(self, **kwargs):
        memory_id = kwargs.get("include_memory_id")
        self.memory_include_ids.append(memory_id)
        if memory_id is None:
            return CoachMemoryRows(available_count=0, rows=[])
        return CoachMemoryRows(
            available_count=101,
            rows=[
                {
                    "id": str(memory_id),
                    "type": "pattern",
                    "title": "Older selected pattern",
                    "content": "Keep one small next step reviewable.",
                    "metadata": {},
                    "updated_at": "2026-07-13T08:00:00Z",
                    "selected_at": None,
                },
            ],
        )


class ContextRepository:
    def __init__(self, *, role="user", auth_provider="email") -> None:
        self.calls = []
        self.role = role
        self.auth_provider = auth_provider

    async def get_profile(self, *, user_id: str):
        self.calls.append(user_id)
        return CoachProfileContext(
            timezone="Europe/Berlin",
            role=self.role,
            auth_provider=self.auth_provider,
        )


class ContextService:
    def __init__(self, *, freshness="current") -> None:
        self.calls = []
        self.package = CoachContextPackage(
            serialized=(
                '{"context_scope":"today","contract_version":"coach-context-v1",'
                '"local_date":"2026-07-13","sources":{}}'
            ),
            used_context=[
                CoachUsedContext(
                    source="profile",
                    available_count=1,
                    included_count=1,
                    omitted_count=0,
                    freshness="current",
                ),
            ],
            daily_state_freshness=freshness,
            daily_state_quality=freshness,
        )

    async def build_today(self, **kwargs):
        self.calls.append(kwargs)
        return self.package


class Provider:
    def __init__(self, *, error=None) -> None:
        self.capability_calls = 0
        self.respond_calls = []
        self.error = error

    async def capability(self):
        self.capability_calls += 1
        return CoachProviderCapability(
            state="ready",
            provider="fake",
            provider_mode="deterministic_test_only",
            model_requested=None,
            model_source="not_applicable",
            reason_code="ready",
        )

    async def respond(self, *, prompt: str):
        self.respond_calls.append(prompt)
        if self.error is not None:
            raise self.error
        return CoachProviderResult(
            output=CoachModelOutput(
                reply="Take one bounded step.",
                uncertainty={"level": "low", "reason": "Current bounded facts."},
                staged_suggestion=None,
                safety={"classification": "normal"},
            ),
        )


def test_normal_turn_forces_high_uncertainty_for_missing_daily_state() -> None:
    service, repository, context, provider = _service(freshness="missing")
    response = asyncio.run(service.respond(user_id=USER_ID, request=_request()))

    assert response.uncertainty.level == "high"
    assert response.provenance.provider_called is True
    assert provider.capability_calls == 1
    assert len(provider.respond_calls) == 1
    assert len(context.calls) == 1
    completed = repository.complete_calls[0]
    assert completed["user_message"] == "Help me plan one step."
    assert completed["usage"]["provider_called"] is True
    assert completed["usage"]["context_bytes"] == context.package.byte_count
    assert completed["usage"]["reply_codepoints"] == len(response.reply)


def test_completed_replay_returns_exact_response_without_context_or_provider() -> None:
    first, first_repo, _, _ = _service()
    persisted = asyncio.run(first.respond(user_id=USER_ID, request=_request()))
    service, repository, context, provider = _service(
        claim_state="completed",
        completed_response=persisted,
    )

    replay = asyncio.run(service.respond(user_id=USER_ID, request=_request()))

    assert replay == persisted
    assert provider.capability_calls == 0
    assert provider.respond_calls == []
    assert context.calls == []
    assert repository.complete_calls == []
    assert first_repo.complete_calls


def test_urgent_safety_bypasses_capability_context_and_provider() -> None:
    service, repository, context, provider = _service()
    response = asyncio.run(
        service.respond(
            user_id=USER_ID,
            request=_request(message="I want to kill myself right now."),
        ),
    )

    assert response.safety.classification == "safety_redirect"
    assert response.used_context == []
    assert response.provenance.source == "deterministic_safety"
    assert response.provenance.provider == "fake"
    assert response.provenance.provider_called is False
    assert provider.capability_calls == 0
    assert provider.respond_calls == []
    assert context.calls == []
    assert repository.complete_calls[0]["usage"] == {
        "provider_called": False,
        "prompt_bytes": 0,
        "context_bytes": 0,
        "reply_codepoints": len(response.reply),
    }


def test_in_progress_uses_public_409_code() -> None:
    service, _, _, provider = _service(claim_state="in_progress")
    with pytest.raises(CoachServiceError) as caught:
        asyncio.run(service.respond(user_id=USER_ID, request=_request()))
    assert caught.value.status_code == 409
    assert caught.value.detail.code == "in_progress"
    assert provider.respond_calls == []


def test_unexpected_provider_error_is_sanitized_and_terminalized() -> None:
    service, repository, _, _ = _service(provider_error=RuntimeError("secret path"))
    with pytest.raises(CoachServiceError) as caught:
        asyncio.run(service.respond(user_id=USER_ID, request=_request()))
    assert caught.value.detail.model_dump() == {
        "code": "provider_failure",
        "message": "The local Coach provider failed.",
        "retryable": True,
    }
    assert repository.fail_calls[0]["error"].code == "provider_failure"
    assert repository.fail_calls[0]["usage"]["provider_called"] is True


def test_provider_account_limit_is_terminalized_and_returned_as_http_429() -> None:
    service, repository, _, _ = _service(
        provider_error=CoachProviderError(
            "account_limit",
            "private account diagnostic",
            retryable=True,
        ),
    )
    with pytest.raises(CoachServiceError) as caught:
        asyncio.run(service.respond(user_id=USER_ID, request=_request()))

    assert caught.value.status_code == 429
    assert caught.value.detail.model_dump() == {
        "code": "account_limit",
        "message": "The local Codex account limit has been reached.",
        "retryable": True,
    }
    assert repository.fail_calls[0]["error"] == caught.value.detail


def test_ambiguous_failure_persistence_forces_exact_same_id_replay() -> None:
    service, repository, _, _ = _service(
        provider_error=CoachProviderError(
            "timeout",
            "private timeout diagnostic",
            retryable=True,
        ),
        fail_error=OSError("connection lost after failure commit"),
    )

    with pytest.raises(CoachServiceError) as caught:
        asyncio.run(service.respond(user_id=USER_ID, request=_request()))

    assert caught.value.status_code == 409
    assert caught.value.detail.model_dump() == {
        "code": "in_progress",
        "message": (
            "The Coach failure could not be confirmed. "
            "Retry the same request id."
        ),
        "retryable": True,
    }
    assert len(repository.fail_calls) == 1


def test_ambiguous_completion_is_not_rewritten_as_failed() -> None:
    service, repository, _, _ = _service()
    repository.complete_error = OSError("connection lost after commit")
    with pytest.raises(CoachServiceError) as caught:
        asyncio.run(service.respond(user_id=USER_ID, request=_request()))
    assert caught.value.detail.code == "in_progress"
    assert caught.value.detail.retryable is True
    assert caught.value.status_code == 409
    assert repository.fail_calls == []


def test_capability_remaining_uses_retained_request_count() -> None:
    service, _, _, provider = _service()
    capability = asyncio.run(service.capabilities(user_id=USER_ID))
    assert capability.limits.remaining_requests == 17
    assert capability.state == "ready"
    assert provider.respond_calls == []


def test_capability_preflight_waits_for_global_provider_slot() -> None:
    async def scenario() -> None:
        semaphore = asyncio.Semaphore(1)
        service, _, _, provider = _service(global_semaphore=semaphore)
        await semaphore.acquire()
        task = asyncio.create_task(service.capabilities(user_id=USER_ID))
        await asyncio.sleep(0)
        assert provider.capability_calls == 0
        semaphore.release()
        capability = await task
        assert capability.state == "ready"
        assert provider.capability_calls == 1

    asyncio.run(scenario())


@pytest.mark.parametrize(
    ("role", "auth_provider"),
    [
        ("guest", "anonymous"),
        ("user", "anonymous"),
        ("guest", "email"),
    ],
)
def test_guest_or_anonymous_profile_cannot_reach_provider_or_claim(
    role: str,
    auth_provider: str,
) -> None:
    service, repository, context, provider = _service(
        role=role,
        auth_provider=auth_provider,
    )

    with pytest.raises(CoachServiceError) as capability_error:
        asyncio.run(service.capabilities(user_id=USER_ID))
    assert capability_error.value.status_code == 403
    assert capability_error.value.detail.code == "authenticated_account_required"

    with pytest.raises(CoachServiceError) as respond_error:
        asyncio.run(service.respond(user_id=USER_ID, request=_request()))
    assert respond_error.value.status_code == 403
    assert repository.claim_calls == []
    assert provider.capability_calls == 0
    assert provider.respond_calls == []
    assert context.calls == []


def test_guest_profile_cannot_read_history() -> None:
    service, _, _, _ = _service(role="guest", auth_provider="anonymous")
    with pytest.raises(CoachServiceError) as caught:
        asyncio.run(service.history(user_id=USER_ID))
    assert caught.value.status_code == 403
    assert caught.value.detail.code == "authenticated_account_required"


def test_deselect_response_keeps_mutated_memory_outside_top_100() -> None:
    service, repository, _, _ = _service()
    memory_id = UUID("22222222-2222-4222-8222-222222222222")

    response = asyncio.run(
        service.set_memory_selection(
            user_id=USER_ID,
            memory_id=memory_id,
            selected=False,
        ),
    )

    assert repository.memory_include_ids == [memory_id]
    assert len(response.memories) == 1
    assert response.memories[0].id == memory_id
    assert response.memories[0].selected is False


def _service(
    *,
    freshness="current",
    claim_state="pending",
    completed_response=None,
    provider_error=None,
    fail_error=None,
    role="user",
    auth_provider="email",
    global_semaphore=None,
):
    settings = Settings(
        APP_ENV="test",
        USE_MOCK_DATA=False,
        COACH_PROVIDER="fake",
        COACH_FAKE_PROVIDER_ENABLED=True,
        LOCAL_CODEX_MAX_REQUESTS_PER_USER_PER_DAY=20,
    )
    repository = Repository(
        claim_state=claim_state,
        completed_response=completed_response,
    )
    repository.fail_error = fail_error
    context_repository = ContextRepository(
        role=role,
        auth_provider=auth_provider,
    )
    context_service = ContextService(freshness=freshness)
    provider = Provider(error=provider_error)
    return (
        CoachService(
            settings=settings,
            repository=repository,
            context_repository=context_repository,
            context_service=context_service,
            provider=provider,
            global_semaphore=global_semaphore or asyncio.Semaphore(2),
            now_provider=lambda: NOW,
        ),
        repository,
        context_service,
        provider,
    )


def _request(*, message="Help me plan one step.") -> CoachRequest:
    return CoachRequest(
        contract_version="coach-request-v1",
        request_id=REQUEST_ID,
        message=message,
        context_scope="today",
    )
