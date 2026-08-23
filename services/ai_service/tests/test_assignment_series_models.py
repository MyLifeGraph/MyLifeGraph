import json
from copy import deepcopy

import pytest
from pydantic import ValidationError

from app.models.assignment_series import (
    AssignmentSeriesMutationRequest,
    AssignmentSeriesProposalRequest,
)


def _proposal() -> dict[str, object]:
    return {
        "contract_version": "assignment-series-v1",
        "request_id": "11111111-1111-4111-8111-111111111111",
        "series_id": "22222222-2222-4222-8222-222222222222",
        "base_revision": 0,
        "title": "Weekly algorithms sheet",
        "next_deadline_at": "2026-08-17T17:00:00+02:00",
        "remaining_occurrences": 12,
        "estimated_total_minutes": 90,
        "preferred_session_minutes": 30,
        "max_daily_minutes": 60,
        "buffer_days": 1,
        "use_calendar_availability": False,
    }


def test_assignment_series_proposal_accepts_exact_finite_transport() -> None:
    parsed = AssignmentSeriesProposalRequest.model_validate_json(
        json.dumps(_proposal()),
    )

    assert parsed.remaining_occurrences == 12
    assert parsed.base_revision == 0


def test_assignment_series_proposal_rejects_coercion_unknowns_and_nulls() -> None:
    invalid_payloads: list[dict[str, object]] = []
    for key, value in (
        ("remaining_occurrences", "12"),
        ("use_calendar_availability", 0),
        ("next_deadline_at", "2026-08-17T17:00:00"),
        ("request_id", 123),
    ):
        invalid = deepcopy(_proposal())
        invalid[key] = value
        invalid_payloads.append(invalid)
    unknown = deepcopy(_proposal())
    unknown["user_id"] = "client-supplied-owner"
    invalid_payloads.append(unknown)
    explicit_null = deepcopy(_proposal())
    explicit_null["title"] = None
    invalid_payloads.append(explicit_null)

    for invalid in invalid_payloads:
        with pytest.raises(ValidationError):
            AssignmentSeriesProposalRequest.model_validate_json(
                json.dumps(invalid),
            )


def test_new_series_needs_multiple_occurrences_but_edits_may_leave_one() -> None:
    new_single = {**_proposal(), "remaining_occurrences": 1}
    with pytest.raises(ValidationError, match="2 to 20"):
        AssignmentSeriesProposalRequest.model_validate_json(json.dumps(new_single))

    edited_single = {
        **new_single,
        "base_revision": 1,
    }
    parsed = AssignmentSeriesProposalRequest.model_validate_json(
        json.dumps(edited_single),
    )
    assert parsed.remaining_occurrences == 1


def test_series_mutation_is_strict_and_versioned() -> None:
    parsed = AssignmentSeriesMutationRequest.model_validate_json(
        json.dumps(
            {
                "contract_version": "assignment-series-v1",
                "request_id": "33333333-3333-4333-8333-333333333333",
                "expected_revision": 2,
            },
        ),
    )
    assert parsed.expected_revision == 2

    with pytest.raises(ValidationError):
        AssignmentSeriesMutationRequest.model_validate_json(
            json.dumps(
                {
                    "contract_version": "assignment-series-v1",
                    "request_id": "33333333-3333-4333-8333-333333333333",
                    "expected_revision": "2",
                },
            ),
        )
