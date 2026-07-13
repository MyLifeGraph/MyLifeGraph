from datetime import UTC, datetime
from uuid import UUID

import pytest
from pydantic import ValidationError

from app.models.coach import (
    CoachModelOutput,
    CoachRequest,
    CoachResponse,
    CoachUsedContext,
)


REQUEST_ID = UUID("11111111-1111-4111-8111-111111111111")


def test_request_trims_message_and_counts_unicode_codepoints() -> None:
    request = CoachRequest.model_validate(
        {
            "contract_version": "coach-request-v1",
            "request_id": str(REQUEST_ID),
            "message": "  Plan one step 🌱  ",
            "context_scope": "today",
        },
    )
    assert request.message == "Plan one step 🌱"

    accepted = request.model_copy(update={"message": "🌱" * 2_000})
    assert len(accepted.message) == 2_000
    with pytest.raises(ValidationError):
        CoachRequest.model_validate(
            {
                "contract_version": "coach-request-v1",
                "request_id": str(REQUEST_ID),
                "message": "🌱" * 2_001,
                "context_scope": "today",
            },
        )


@pytest.mark.parametrize(
    "mutation",
    [
        {"user_id": "attacker"},
        {"unknown": True},
        {"message": None},
        {"context_scope": None},
        {"message": 7},
    ],
)
def test_request_rejects_unknown_null_and_coerced_fields(mutation) -> None:
    payload = {
        "contract_version": "coach-request-v1",
        "request_id": str(REQUEST_ID),
        "message": "Help me plan.",
        "context_scope": "today",
        **mutation,
    }
    with pytest.raises(ValidationError):
        CoachRequest.model_validate(payload)


def test_used_context_counts_reconcile() -> None:
    item = CoachUsedContext(
        source="tasks",
        available_count=3,
        included_count=2,
        omitted_count=1,
        freshness="current",
    )
    assert item.available_count == 3
    with pytest.raises(ValidationError):
        CoachUsedContext(
            source="tasks",
            available_count=3,
            included_count=1,
            omitted_count=1,
            freshness="current",
        )


def test_persisted_response_parses_identity_without_content_coercion() -> None:
    response = CoachResponse.model_validate(_response_json())
    assert response.request_id == REQUEST_ID
    assert response.provenance.generated_at == datetime(2026, 7, 13, tzinfo=UTC)

    invalid = _response_json()
    invalid["provenance"]["provider_called"] = 1
    with pytest.raises(ValidationError):
        CoachResponse.model_validate(invalid)


@pytest.mark.parametrize("provider_called", [False, True])
def test_deterministic_safety_provenance_accepts_bypass_and_post_provider_redirect(
    provider_called: bool,
) -> None:
    payload = _response_json()
    payload["safety"]["classification"] = "safety_redirect"
    payload["provenance"].update(
        {
            "source": "deterministic_safety",
            "provider_called": provider_called,
        },
    )

    response = CoachResponse.model_validate(payload)

    assert response.provenance.provider_called is provider_called
    assert response.provenance.source == "deterministic_safety"


@pytest.mark.parametrize(
    ("source", "provider_called", "safety"),
    [
        ("model", False, "normal"),
        ("model", True, "safety_redirect"),
        ("deterministic_safety", False, "normal"),
        ("deterministic_safety", True, "sensitive"),
    ],
)
def test_response_rejects_inconsistent_safety_provenance(
    source: str,
    provider_called: bool,
    safety: str,
) -> None:
    payload = _response_json()
    payload["safety"]["classification"] = safety
    payload["provenance"].update(
        {
            "source": source,
            "provider_called": provider_called,
        },
    )

    with pytest.raises(ValidationError):
        CoachResponse.model_validate(payload)


@pytest.mark.parametrize(
    "payload",
    [
        {
            "reply": "   ",
            "uncertainty": {"level": "medium", "reason": "bounded"},
            "staged_suggestion": None,
            "safety": {"classification": "normal"},
        },
        {
            "reply": "bounded",
            "uncertainty": {"level": "medium", "reason": "   "},
            "staged_suggestion": None,
            "safety": {"classification": "normal"},
        },
        {
            "reply": "bounded",
            "uncertainty": {"level": "medium", "reason": "bounded"},
            "staged_suggestion": {"title": "   ", "rationale": "bounded"},
            "safety": {"classification": "normal"},
        },
    ],
)
def test_untrusted_model_output_rejects_whitespace_only_text(payload) -> None:
    with pytest.raises(ValidationError):
        CoachModelOutput.model_validate(payload)


def _response_json() -> dict:
    return {
        "contract_version": "coach-response-v1",
        "request_id": str(REQUEST_ID),
        "reply": "Protect one small next step.",
        "uncertainty": {"level": "medium", "reason": "Bounded current context."},
        "staged_suggestion": None,
        "safety": {"classification": "normal"},
        "used_context": [],
        "provenance": {
            "source": "model",
            "provider": "fake",
            "provider_mode": "deterministic_test_only",
            "model_requested": None,
            "model_reported": None,
            "model_source": "not_applicable",
            "prompt_version": "controlled-coach-prompt-v1",
            "context_version": "coach-context-v1",
            "generated_at": "2026-07-13T00:00:00Z",
            "provider_called": True,
        },
    }
