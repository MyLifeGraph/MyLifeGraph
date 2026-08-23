import json
from copy import deepcopy
from datetime import UTC, date, datetime
from uuid import UUID

import pytest
from pydantic import ValidationError

from app.models.deadline_plans import (
    DeadlinePlanProposalRequest,
    PreparationWorkloadDetailResponse,
    PreparationWorkloadResponse,
)


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


def test_workload_contract_requires_seven_consecutive_consistent_days() -> None:
    payload = {
        "contract_version": "preparation-workload-v1",
        "origin": "authenticated_backend",
        "generated_at": "2026-07-20T08:00:00Z",
        "timezone": "Europe/Berlin",
        "daily_preparation_budget_minutes": 120,
        "days": [
            {
                "local_date": f"2026-07-{20 + offset:02d}",
                "reserved_preparation_minutes": 50 if offset == 0 else 0,
                "remaining_budget_minutes": 70 if offset == 0 else 120,
                "over_budget_minutes": 0,
                "active_plan_count": 1 if offset == 0 else 0,
                "fixed_commitment_minutes": 90 if offset == 0 else 0,
            }
            for offset in range(7)
        ],
    }

    parsed = PreparationWorkloadResponse.model_validate_json(json.dumps(payload))
    assert parsed.days[0].remaining_budget_minutes == 70

    for mutate in (
        lambda value: value.update(daily_preparation_budget_minutes=121),
        lambda value: value["days"][0].update(remaining_budget_minutes=71),
        lambda value: value["days"][1].update(local_date="2026-07-23"),
        lambda value: value.update(extra="not-v1"),
    ):
        invalid = deepcopy(payload)
        mutate(invalid)
        with pytest.raises(ValidationError):
            PreparationWorkloadResponse.model_validate_json(json.dumps(invalid))


def test_workload_detail_contract_requires_exact_unique_contributions() -> None:
    payload = {
        "contract_version": "preparation-workload-detail-v1",
        "origin": "authenticated_backend",
        "generated_at": "2026-07-20T08:00:00Z",
        "timezone": "Europe/Berlin",
        "local_date": "2026-07-20",
        "daily_preparation_budget_minutes": 120,
        "reserved_preparation_minutes": 140,
        "remaining_budget_minutes": 0,
        "over_budget_minutes": 20,
        "contributions": [
            {
                "plan_id": "22222222-2222-4222-8222-222222222222",
                "title": "Algorithms exam",
                "reserved_preparation_minutes": 80,
                "block_count": 2,
            },
            {
                "plan_id": "33333333-3333-4333-8333-333333333333",
                "title": "History paper",
                "reserved_preparation_minutes": 60,
                "block_count": 1,
            },
        ],
    }

    parsed = PreparationWorkloadDetailResponse.model_validate_json(
        json.dumps(payload),
    )
    assert parsed.over_budget_minutes == 20

    for mutate in (
        lambda value: value.update(extra="not-v1"),
        lambda value: value.update(reserved_preparation_minutes=139),
        lambda value: value["contributions"][1].update(
            plan_id=value["contributions"][0]["plan_id"],
        ),
        lambda value: value["contributions"][0].update(title=" Algorithms exam"),
    ):
        invalid = deepcopy(payload)
        mutate(invalid)
        with pytest.raises(ValidationError):
            PreparationWorkloadDetailResponse.model_validate_json(
                json.dumps(invalid),
            )
