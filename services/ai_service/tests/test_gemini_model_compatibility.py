import pytest
from pydantic import ValidationError

from app.models.coach import COACH_GEMINI_MODEL, CoachAgentProvenance
from tests.migration_source import load_migration


def provenance(model: str, reported: str | None) -> dict:
    return dict(
        source="model", provider="gemini", provider_mode="user_supplied_key",
        model_requested=model, model_reported=reported, model_source="explicit",
        prompt_version="free-coach-agent-prompt-v5", context_version="personal-snapshot-v3",
        generated_at="2026-09-15T10:00:00Z", provider_called=True,
        service_tier="not_applicable", service_tier_status="not_applicable",
        fast_mode=False, snapshot_row_count=0, snapshot_bytes=0,
    )


@pytest.mark.parametrize("model", ["gemini-3.6-flash", "gemini-3.8-flash"])
@pytest.mark.parametrize("reported", [True, False])
def test_current_and_historical_gemini_provenance(model, reported):
    parsed = CoachAgentProvenance.model_validate(provenance(model, model if reported else None))
    assert parsed.model_requested == model
    assert COACH_GEMINI_MODEL == "gemini-3.8-flash"


@pytest.mark.parametrize("model,reported", [
    ("gemini-3.8-flash", "gemini-3.6-flash"),
    ("gemini-3.6-flash", "gemini-3.8-flash"),
    ("gemini-unapproved", None),
])
def test_gemini_rejects_unknown_or_mismatched_provenance(model, reported):
    with pytest.raises(ValidationError):
        CoachAgentProvenance.model_validate(provenance(model, reported))


def test_gemini_migration_is_additive_and_preserves_function_privileges():
    sql = load_migration("20260915105930_coach_gemini_38_flash.sql")
    assert "claim_coach_request_v8_local_date_legacy" in sql
    assert "claim_coach_request_v7" in sql
    assert "private.coach_response_is_valid_v3" in sql
    assert "p_model_requested is null" in sql
    assert "array_length(string_to_array(definition, old_guard), 1) <> 2" in sql
    assert "execute replace(definition, old_guard, new_guard)" in sql
    assert "grant " not in sql.lower()
    assert "update public." not in sql.lower()
