import asyncio
import json
from datetime import UTC, date, datetime
from pathlib import Path
from uuid import UUID, uuid4

import httpx
import pytest
from fastapi import FastAPI
from pydantic import ValidationError

from app.api.deps.auth import Principal, get_current_principal
from app.api.deps.coach import get_coach_agent_service
from app.api.routes.capture_draft import router
from app.coach_turn_lifecycle import CoachClaimResult, CoachServiceError
from app.core.config import Settings
from app.models.capture_draft import CaptureDraftRequest, EveningDraftFields, MorningDraftFields
from app.models.coach import CoachAgentModelOutput, CoachErrorDetail
from app.providers.base import CoachAgentProviderResult, CoachProviderCapability, CoachProviderError
from app.repositories.coach_context_repository import CoachProfileContext
from app.services.capture_draft_operation import CaptureDraftOperation, DRAFT_RECEIPT
from app.services.capture_draft_service import CaptureDraftService
from app.services.coach_agent_service import CoachAgentService
from app.services.coach_snapshot import PreparedCoachSnapshot

OWNER = "11111111-1111-4111-8111-111111111111"
NOW = datetime(2026, 9, 14, 12, tzinfo=UTC)


def request(transcript="My energy is 7 out of 10.", branch="morning", request_id=None):
    return CaptureDraftRequest(
        contract_version="daily-capture-draft-v1", request_id=request_id or uuid4(),
        branch=branch, transcript=transcript,
    )


def output(fields, evidence):
    return CoachAgentModelOutput(
        reply=json.dumps({"fields": fields, "evidence": evidence}, ensure_ascii=False),
        uncertainty={"level": "medium", "reason": "Confirm the extracted fields."},
        safety={"classification": "normal"},
    )


def operation(transcript="My energy is 7 out of 10.", branch="morning"):
    return CaptureDraftOperation(
        request=request(transcript, branch), owner_id=UUID(OWNER),
        entry_date=date(2026, 9, 14), timezone="Europe/Berlin",
    )


def test_transcript_and_proposal_are_excluded_from_repr():
    draft = operation()
    assert "My energy" not in repr(draft)
    assert "My energy" not in repr(draft.request)


@pytest.mark.parametrize("fields", [
    {"current_energy": True}, {"current_energy": "7"}, {"current_energy": 11},
    {"current_energy": 0}, {"day_shape": "normal"}, {"sleep_target_minutes": 301},
    {"sleep_start": "25:00"}, {"motivation": 3}, {"energy": 7},
])
def test_morning_fields_are_strict_and_do_not_add_retired_fields(fields):
    with pytest.raises(ValidationError):
        MorningDraftFields.model_validate(fields)


def test_evening_uses_only_existing_enum_and_value_ranges():
    with pytest.raises(ValidationError):
        EveningDraftFields.model_validate({"stress_source": "school"})
    with pytest.raises(ValidationError):
        EveningDraftFields.model_validate({"sport": False})


@pytest.mark.parametrize("transcript", ["", "   ", "x" * 4001, "private\x00text"])
def test_request_rejects_invalid_transcript(transcript):
    with pytest.raises(ValidationError):
        request(transcript)


def test_explicit_ratings_keep_missing_fields_null_and_only_return_redacted_receipt():
    draft = operation()
    receipt = draft.accept_output(output({"current_energy": 7}, {"current_energy": draft.request.transcript}))
    assert receipt.reply == DRAFT_RECEIPT
    assert draft.proposal.fields.current_energy == 7
    assert draft.proposal.fields.sleep_quality is None
    assert draft.proposal.owner_id == UUID(OWNER)
    assert draft.proposal.evidence == {"current_energy": draft.request.transcript}
    assert draft.request.transcript not in receipt.model_dump_json()


def test_german_verbatim_input_remains_data_and_is_not_subject_to_chat_language_rule():
    transcript = "Meine Energie ist sieben von zehn."
    draft = operation(transcript)
    draft.accept_output(output({"current_energy": 7}, {"current_energy": transcript}))
    assert draft.proposal.evidence["current_energy"] == transcript


@pytest.mark.parametrize('transcript', ['Schlaf 7/10', 'Schlafqualität sieben von zehn'])
def test_german_sleep_rating_maps_to_canonical_field(transcript):
    draft = operation(transcript)
    draft.accept_output(output({'sleep_quality': 7}, {'sleep_quality': transcript}))
    assert draft.proposal.fields.sleep_quality == 7
    assert draft.proposal.fields.sleep_start is None
    assert draft.proposal.fields.wake_time is None


def test_ambiguous_german_sleep_is_not_a_rating():
    draft = operation('Schlaf sieben')
    with pytest.raises(CoachProviderError):
        draft.accept_output(output({'sleep_quality': 7}, {'sleep_quality': 'Schlaf sieben'}))


@pytest.mark.parametrize("fields,evidence,transcript", [
    ({"current_energy": 8}, {"current_energy": "Feeling good"}, "Feeling good"),
    ({"current_energy": 8}, {"current_energy": "Energy 7/10"}, "Energy 7/10"),
    ({"current_energy": 7}, {"current_energy": "Mood 7/10"}, "Mood 7/10"),
    ({"current_energy": 7}, {}, "Energy 7/10"),
    ({"current_energy": 7}, {"current_energy": "Energy 7/10"}, "My mood was good"),
    ({}, {"current_energy": "Energy 7/10"}, "Energy 7/10"),
    ({"sleep_start": "23:00"}, {"sleep_start": "I slept 8 hours"}, "I slept 8 hours"),
    ({"wake_time": "09:00"}, {"wake_time": "Woke at 08:00"}, "Woke at 08:00"),
    ({"sleep_target_minutes": 480}, {"sleep_target_minutes": "target 6 hours"}, "target 6 hours"),
    ({"sleep_target_minutes": 480}, {"sleep_target_minutes": "I slept 8 hours"}, "I slept 8 hours"),
    ({"motivation": 2}, {"motivation": "I finished all tasks"}, "I finished all tasks"),
])
def test_unsupported_or_invented_evidence_never_becomes_proposal(fields, evidence, transcript):
    draft = operation(transcript)
    with pytest.raises(CoachProviderError):
        draft.accept_output(output(fields, evidence))
    assert draft.proposal is None


@pytest.mark.parametrize("key,value,text", [
    ("sleep_start", "23:00", "Schlafbeginn 23 Uhr"),
    ("wake_time", "07:30", "Woke at 7:30 am"),
    ("sleep_target_minutes", 480, "My target is eight hours"),
    ("motivation", 2, "My study motivation is high"),
])
def test_explicit_clocks_target_and_optional_signal(key, value, text):
    draft = operation(text)
    draft.accept_output(output({key: value}, {key: text}))
    assert getattr(draft.proposal.fields, key) == value


@pytest.mark.parametrize("key,value,english,german", [
    ("motivation", 0, "Study motivation low", "Lernmotivation niedrig"),
    ("motivation", 1, "Study motivation medium", "Motivation mittel"),
    ("motivation", 2, "Study motivation high", "Motivation hoch"),
    ("sport", 0, "Sport none", "Kein Sport"),
    ("sport", 1, "Light exercise", "Leichtes Training"),
    ("sport", 2, "Intense training", "Intensiver Sport"),
    ("social", 0, "Little social contact", "Wenig soziale Kontakte"),
    ("social", 1, "Some social contact", "Etwas sozialer Kontakt"),
    ("social", 2, "Lots of social contact", "Viele soziale Kontakte"),
])
@pytest.mark.parametrize("language", ["english", "german"])
def test_optional_choices_match_the_existing_ui_scales(key, value, english, german, language):
    text = english if language == "english" else german
    draft = operation(text, "morning" if key == "motivation" else "evening")
    draft.accept_output(output({key: value}, {key: text}))
    assert getattr(draft.proposal.fields, key) == value


@pytest.mark.parametrize("key,value,text", [
    ("sport", 2, "Energy high"),
    ("sport", 2, "Sport light"),
    ("social", 1, "Little social contact"),
    ("social", 2, "Lots of work"),
    ("motivation", 2, "Energy high"),
    ("motivation", 1, "Motivation low or medium"),
    ("stress_source", "workload", "Today was busy"),
    ("stress_source", "private_emotional", "This is private text"),
    ("stress_source", "workload", "Stress from workload or physical recovery"),
    ("stress_controllability", "mostly_controllable", "I finished most tasks"),
    ("stress_controllability", "mostly_controllable", "Little control"),
])
def test_categories_need_explicit_unambiguous_field_evidence(key, value, text):
    draft = operation(text, "morning" if key == "motivation" else "evening")
    with pytest.raises(CoachProviderError):
        draft.accept_output(output({key: value}, {key: text}))
    assert draft.proposal is None


@pytest.mark.parametrize("key,value,text", [
    ("stress_source", "workload", "My stress source is workload"),
    ("stress_source", "avoidable_pressure", "Stress durch vermeidbaren Druck"),
    ("stress_source", "private_emotional", "My stress is private or emotional"),
    ("stress_source", "physical_recovery", "Stress durch körperliche Erholung"),
    ("stress_source", "external_environment", "Stress from the external environment"),
    ("stress_controllability", "hardly_controllable", "Little control over stress"),
    ("stress_controllability", "partly_controllable", "Stress teilweise kontrollierbar"),
    ("stress_controllability", "mostly_controllable", "Stress mostly controllable"),
    ("stress_source", "physical_recovery", "physical_recovery"),
    ("stress_controllability", "mostly_controllable", "mostly_controllable"),
])
def test_explicit_existing_stress_choices_are_supported(key, value, text):
    draft = operation(text, "evening")
    draft.accept_output(output({key: value}, {key: text}))
    assert getattr(draft.proposal.fields, key) == value


def test_safety_redirect_cannot_be_redacted_into_success():
    draft = operation()
    unsafe = CoachAgentModelOutput.model_validate(
        output({}, {}).model_dump() | {"safety": {"classification": "safety_redirect"}},
    )
    with pytest.raises(CoachProviderError):
        draft.accept_output(unsafe)


class Context:
    async def get_profile(self, *, user_id):
        assert user_id == OWNER
        return CoachProfileContext(timezone="Europe/Berlin")


class Ledger:
    def __init__(self):
        self.claims, self.completions, self.failures = [], [], []
        self.replay = None
        self.dispatches, self.finishes = [], []
        self.purpose = "chat"
        self.claim_error = None
        self.global_count = 0

    def for_capture_draft(self):
        self.purpose = "daily_capture_draft"
        return self

    async def probe_agent_terminal_replay(self, **kwargs):
        return self.replay

    async def claim_agent_request(self, **kwargs):
        self.claims.append(kwargs)
        if self.claim_error is not None:
            raise self.claim_error
        return CoachClaimResult("pending", 4, None, None)

    async def complete_agent_request(self, **kwargs):
        self.completions.append(kwargs)
        self.replay = CoachClaimResult("deleted", 3, None, CoachErrorDetail(
            code="history_deleted", message="Request content was discarded.", retryable=False,
        ))
        return kwargs["response"]

    async def fail_request(self, **kwargs):
        self.failures.append(kwargs)
        return kwargs["error"]

    async def count_operator_dispatches(self, **kwargs):
        return self.global_count

    async def record_operator_dispatch(self, **kwargs):
        self.dispatches.append(kwargs)

    async def finish_operator_dispatch(self, **kwargs):
        self.finishes.append(kwargs)


class EmptySnapshot:
    def __init__(self, tmp_path):
        self.path = tmp_path
        self.empty_calls = 0

    async def create(self, **kwargs):
        raise AssertionError("Draft must not read a personal snapshot")

    async def create_empty(self):
        self.empty_calls += 1
        folder = self.path / f"mylifegraph-snapshot-{uuid4()}"
        folder.mkdir()
        path = folder / "personal-data.sqlite"
        path.touch()
        return PreparedCoachSnapshot(path, folder, 0, 100, ())


class Provider:
    def __init__(self):
        self.calls = 0
        self.reservations, self.releases = [], []
        self.invalid = False
        self.block = None
        self.started = asyncio.Event()

    async def capability(self):
        return CoachProviderCapability("ready", "operator_codex_pilot", "operator_subscription_pilot", "gpt-5.5", "explicit", "ready")

    async def reserve(self):
        reservation = uuid4()
        self.reservations.append(reservation)
        return reservation

    async def release_reservation(self, reservation_id):
        self.releases.append(reservation_id)

    async def respond_agent_reserved(self, *, reservation_id, prompt, snapshot_path, trace_path, activity_callback=None):
        assert reservation_id in self.reservations
        assert "explicit check-in draft extraction" in prompt
        assert "NOT a Coach chat answer" in prompt
        assert "My energy is 7 out of 10." in prompt
        assert Path(snapshot_path).exists()
        self.calls += 1
        self.started.set()
        if self.block is not None:
            await self.block.wait()
        result = output({"current_energy": 8 if self.invalid else 7}, {"current_energy": "My energy is 7 out of 10."})
        return CoachAgentProviderResult(result, "gpt-5.5")


def service(tmp_path):
    ledger, provider, snapshot = Ledger(), Provider(), EmptySnapshot(tmp_path)
    coach = CoachAgentService(
        settings=Settings(_env_file=None, APP_ENV="pilot", OPERATOR_CODEX_PILOT_ENABLED=True),
        repository=ledger, context_repository=Context(), snapshot_service=snapshot,
        provider=provider, operator_provider=provider, global_semaphore=asyncio.Semaphore(1),
        now_provider=lambda: NOW,
    ).for_operator_request()
    return CaptureDraftService(coach), ledger, provider, snapshot


def test_extraction_uses_reserved_dispatch_and_quota_but_persists_no_text(tmp_path):
    async def run():
        draft_service, ledger, provider, snapshot = service(tmp_path)
        req = request()
        proposal = await draft_service.extract(user_id=OWNER, request=req)
        assert proposal.fields.current_energy == 7
        assert snapshot.empty_calls == 1
        assert provider.calls == len(provider.reservations) == len(provider.releases) == 1
        assert len(ledger.claims) == len(ledger.dispatches) == len(ledger.completions) == len(ledger.finishes) == 1
        assert ledger.purpose == "daily_capture_draft"
        stored = str(ledger.claims) + str(ledger.completions) + str(ledger.dispatches)
        assert req.transcript not in stored
        assert "current_energy" not in stored
        response = ledger.completions[0]["response"]
        assert response.reply == DRAFT_RECEIPT
        assert response.agent_trace.model_dump() == {"tool_call_count": 0, "steps": [], "limitations": []}
        assert response.evidence == []
        assert not list(tmp_path.iterdir())
        with pytest.raises(CoachServiceError) as failure:
            await draft_service.extract(user_id=OWNER, request=req)
        assert failure.value.detail.code == "draft_expired"
        assert provider.calls == 1
    asyncio.run(run())


def test_invalid_extraction_consumes_dispatch_and_finishes_failure_without_content(tmp_path):
    async def run():
        draft_service, ledger, provider, _ = service(tmp_path)
        provider.invalid = True
        with pytest.raises(CoachServiceError) as error:
            await draft_service.extract(user_id=OWNER, request=request())
        assert error.value.detail.code == "invalid_output"
        assert len(ledger.dispatches) == len(ledger.failures) == len(ledger.finishes) == 1
        assert ledger.completions == []
        assert "My energy" not in str(ledger.failures)
        assert not list(tmp_path.iterdir())
    asyncio.run(run())


def test_cancellation_releases_reservation_and_records_no_transcript(tmp_path):
    async def run():
        draft_service, ledger, provider, _ = service(tmp_path)
        provider.block = asyncio.Event()
        task = asyncio.create_task(draft_service.extract(user_id=OWNER, request=request()))
        await provider.started.wait()
        task.cancel()
        with pytest.raises(asyncio.CancelledError):
            await task
        assert len(provider.releases) == 1
        assert len(ledger.failures) == 1
        assert "My energy" not in str(ledger.failures)
        assert not list(tmp_path.iterdir())
    asyncio.run(run())


def test_api_validation_never_echoes_transcript_or_accepts_owner():
    async def run():
        app = FastAPI()
        app.include_router(router, prefix="/v1")
        app.dependency_overrides[get_current_principal] = lambda: Principal(user_id=OWNER)
        app.dependency_overrides[get_coach_agent_service] = lambda: object()
        async with httpx.AsyncClient(transport=httpx.ASGITransport(app=app), base_url="http://test") as client:
            body = request().model_dump(mode="json") | {"owner_id": OWNER}
            response = await client.post("/v1/daily-capture/draft", json=body)
            assert response.status_code == 422
            assert "My energy" not in response.text
            assert OWNER not in response.text
    asyncio.run(run())


def test_api_returns_requested_identity_profile_day_and_no_store(tmp_path):
    async def run():
        draft_service, _, _, _ = service(tmp_path)
        app = FastAPI()
        app.include_router(router, prefix="/v1")
        app.dependency_overrides[get_current_principal] = lambda: Principal(user_id=OWNER)
        app.dependency_overrides[get_coach_agent_service] = lambda: draft_service._coach
        req = request()
        async with httpx.AsyncClient(transport=httpx.ASGITransport(app=app), base_url="http://test") as client:
            result = await client.post("/v1/daily-capture/draft", json=req.model_dump(mode="json"), headers={"X-MyLifeGraph-Coach-Provider": "operator_codex_pilot"})
        assert result.status_code == 200, result.text
        assert result.headers["cache-control"] == "no-store"
        assert result.json()["request_id"] == str(req.request_id)
        assert result.json()["owner_id"] == OWNER
        assert result.json()["timezone"] == "Europe/Berlin"
        assert result.json()["entry_date"] == "2026-09-14"
    asyncio.run(run())


def test_account_and_global_limits_cannot_be_bypassed_by_draft(tmp_path):
    from app.coach_turn_lifecycle import CoachPersistenceRateLimited

    async def run():
        draft_service, ledger, provider, snapshot = service(tmp_path)
        ledger.global_count = 15
        with pytest.raises(CoachServiceError) as error:
            await draft_service.extract(user_id=OWNER, request=request())
        assert error.value.detail.code == "provider_limit"
        assert provider.calls == len(provider.reservations) == snapshot.empty_calls == 0
        ledger.global_count = 0
        ledger.claim_error = CoachPersistenceRateLimited()
        with pytest.raises(CoachServiceError) as error:
            await draft_service.extract(user_id=OWNER, request=request())
        assert error.value.detail.code == "account_limit"
        assert provider.calls == snapshot.empty_calls == 0
        assert provider.releases == provider.reservations
    asyncio.run(run())


def test_midnight_or_timezone_change_invalidates_proposal(tmp_path):
    async def run():
        draft_service, _, provider, _ = service(tmp_path)
        original = draft_service._coach.capture_draft_profile

        async def changed_profile(*, user_id):
            timezone, local_date = await original(user_id=user_id)
            return ("America/New_York", local_date) if provider.calls else (timezone, local_date)

        draft_service._coach.capture_draft_profile = changed_profile
        with pytest.raises(CoachServiceError) as error:
            await draft_service.extract(user_id=OWNER, request=request())
        assert error.value.detail.code == "draft_expired"
        assert provider.calls == 1
    asyncio.run(run())
