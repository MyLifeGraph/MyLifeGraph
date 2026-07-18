import json
from copy import deepcopy
from datetime import UTC, date, datetime
from uuid import UUID

import pytest
from pydantic import ValidationError

from app.models.deadline_plans import DeadlinePlanProposalRequest


def _proposal() -> dict[str, object]:
    return {
        "request_id": "11111111-1111-4111-8111-111111111111",
        "plan_id": "22222222-2222-4222-8222-222222222222",
        "base_revision": 0,
        "kind": "exam",
        "title": "Mathematics",
        "deadline_at": "2026-08-01T12:00:00+02:00",
        "estimated_total_minutes": 600,
        "credited_prior_minutes": 30,
        "preferred_session_minutes": 50,
        "max_daily_minutes": 100,
        "planning_start_on": "2026-07-20",
        "buffer_days": 2,
        "source_kind": "manual",
        "use_calendar_availability": False,
    }


def test_proposal_accepts_exact_json_transport_and_rejects_coercion() -> None:
    parsed = DeadlinePlanProposalRequest.model_validate_json(json.dumps(_proposal()))
    assert parsed.estimated_total_minutes == 600
    assert parsed.source_calendar_event_id is None

    for key, value in [
        ("estimated_total_minutes", "600"),
        ("use_calendar_availability", 0),
        ("deadline_at", "2026-08-01T12:00:00"),
        ("deadline_at", 1_785_583_200),
        ("planning_start_on", 1_785_542_400),
        ("request_id", 123),
    ]:
        invalid = deepcopy(_proposal())
        invalid[key] = value
        with pytest.raises(ValidationError):
            DeadlinePlanProposalRequest.model_validate_json(json.dumps(invalid))

    native = _proposal()
    native["request_id"] = UUID(str(native["request_id"]))
    native["deadline_at"] = datetime(2026, 8, 1, 12, tzinfo=UTC)
    native["planning_start_on"] = date(2026, 7, 20)
    with pytest.raises(ValidationError):
        DeadlinePlanProposalRequest.model_validate(native)


def test_proposal_rejects_unknown_null_and_incoherent_source_fields() -> None:
    invalid_shapes = []
    unknown = deepcopy(_proposal())
    unknown["user_id"] = "not-authority"
    invalid_shapes.append(unknown)
    explicit_null = deepcopy(_proposal())
    explicit_null["source_calendar_event_id"] = None
    invalid_shapes.append(explicit_null)
    manual_with_event = deepcopy(_proposal())
    manual_with_event["source_calendar_event_id"] = (
        "33333333-3333-4333-8333-333333333333"
    )
    manual_with_event["source_calendar_event_fingerprint"] = "a" * 64
    invalid_shapes.append(manual_with_event)
    missing_calendar_pin = deepcopy(_proposal())
    missing_calendar_pin["source_kind"] = "calendar_event"
    invalid_shapes.append(missing_calendar_pin)

    for invalid in invalid_shapes:
        with pytest.raises(ValidationError):
            DeadlinePlanProposalRequest.model_validate_json(json.dumps(invalid))


def test_proposal_enforces_estimate_and_daily_capacity_relationships() -> None:
    prior_too_large = deepcopy(_proposal())
    prior_too_large["credited_prior_minutes"] = 600
    daily_too_small = deepcopy(_proposal())
    daily_too_small["preferred_session_minutes"] = 90
    daily_too_small["max_daily_minutes"] = 50
    for invalid in (prior_too_large, daily_too_small):
        with pytest.raises(ValidationError):
            DeadlinePlanProposalRequest.model_validate_json(json.dumps(invalid))
