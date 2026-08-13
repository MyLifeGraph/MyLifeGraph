import json
from copy import deepcopy
from datetime import UTC, datetime, timedelta
from uuid import UUID

import pytest
from pydantic import TypeAdapter, ValidationError

from app.models.multi_exam_plans import (
    MultiExamPlanItem,
    MultiExamPlanProposalRequest,
    MultiExamPlanProposalResponse,
)


PLAN_ID = "11111111-1111-4111-8111-111111111111"
BALANCE_ID = "22222222-2222-4222-8222-222222222222"
START = datetime(2026, 8, 20, 9, tzinfo=UTC)


def _block(
    identifier: str,
    *,
    starts_at: datetime,
    minutes: int,
    credited: int = 0,
    sequence: int = 1,
) -> dict[str, object]:
    ends_at = starts_at + timedelta(minutes=minutes)
    return {
        "id": identifier,
        "sequence": sequence,
        "starts_at": starts_at.isoformat(),
        "ends_at": ends_at.isoformat(),
        "reserved_ends_at": ends_at.isoformat(),
        "local_date": starts_at.date().isoformat(),
        "planned_minutes": minutes,
        "recovery_minutes": 0,
        "credited_minutes": credited,
    }


def _item(
    current: list[dict[str, object]],
    proposed: list[dict[str, object]],
    *,
    summary: tuple[int, int, int, int, int, int, int, int],
    active_revision: int = 1,
    base_revision: int = 1,
) -> dict[str, object]:
    return {
        "position": 1,
        "plan_id": PLAN_ID,
        "title": "Algorithms",
        "deadline_at": "2026-09-20T12:00:00+00:00",
        "remaining_minutes": 120,
        "active_revision": active_revision,
        "base_revision": base_revision,
        "proposed_revision": base_revision + 1,
        "current_blocks": current,
        "proposed_blocks": proposed,
        "retained_minutes": summary[0],
        "added_minutes": summary[1],
        "shifted_minutes": summary[2],
        "removed_minutes": summary[3],
        "retained_block_count": summary[4],
        "added_block_count": summary[5],
        "shifted_block_count": summary[6],
        "removed_block_count": summary[7],
    }


def test_proposal_request_is_strict_and_binds_selected_latest_revision() -> None:
    payload = {
        "contract_version": "multi-exam-plan-v1",
        "request_id": "33333333-3333-4333-8333-333333333333",
        "target_plan_id": PLAN_ID,
        "expected_plan_revision": 4,
    }
    parsed = MultiExamPlanProposalRequest.model_validate_json(json.dumps(payload))
    assert parsed.expected_plan_revision == 4

    for key, value in (
        ("expected_plan_revision", "4"),
        ("expected_plan_revision", 0),
        ("target_plan_id", 1),
        ("owner_id", PLAN_ID),
    ):
        invalid = deepcopy(payload)
        invalid[key] = value
        with pytest.raises(ValidationError):
            MultiExamPlanProposalRequest.model_validate_json(json.dumps(invalid))


def test_change_axes_are_disjoint_when_old_unmatched_exceeds_new() -> None:
    retained = _block(
        "44444444-4444-4444-8444-444444444441",
        starts_at=START,
        minutes=30,
    )
    old = _block(
        "44444444-4444-4444-8444-444444444442",
        starts_at=START + timedelta(hours=2),
        minutes=60,
        sequence=2,
    )
    new = _block(
        "44444444-4444-4444-8444-444444444443",
        starts_at=START + timedelta(hours=3),
        minutes=25,
        sequence=2,
    )
    parsed = MultiExamPlanItem.model_validate_json(
        json.dumps(
            _item(
                [retained, old],
                [{**retained, "id": "55555555-5555-4555-8555-555555555551"}, new],
                summary=(30, 0, 25, 35, 1, 0, 1, 0),
            )
        ),
    )
    assert (
        parsed.retained_minutes + parsed.shifted_minutes + parsed.removed_minutes == 90
    )
    assert parsed.retained_minutes + parsed.shifted_minutes + parsed.added_minutes == 55


def test_change_axes_are_disjoint_when_new_unmatched_exceeds_old() -> None:
    old = _block(
        "66666666-6666-4666-8666-666666666661",
        starts_at=START,
        minutes=25,
    )
    new = _block(
        "66666666-6666-4666-8666-666666666662",
        starts_at=START + timedelta(hours=2),
        minutes=60,
    )
    parsed = MultiExamPlanItem.model_validate_json(
        json.dumps(_item([old], [new], summary=(0, 35, 25, 0, 0, 0, 1, 0))),
    )
    assert parsed.shifted_minutes == 25
    assert parsed.added_minutes == 35


def test_duplicate_signatures_match_as_a_multiset_and_partial_credit_shifts_rest() -> (
    None
):
    duplicate_a = _block(
        "77777777-7777-4777-8777-777777777771",
        starts_at=START,
        minutes=30,
    )
    duplicate_b = {
        **duplicate_a,
        "id": "77777777-7777-4777-8777-777777777772",
        "sequence": 2,
        "credited_minutes": 10,
    }
    proposed = {
        **duplicate_a,
        "id": "77777777-7777-4777-8777-777777777773",
    }
    parsed = MultiExamPlanItem.model_validate_json(
        json.dumps(
            _item(
                [duplicate_a, duplicate_b],
                [proposed],
                summary=(30, 0, 0, 20, 1, 0, 0, 1),
            )
        ),
    )
    assert parsed.current_blocks[1].effective_minutes == 20
    assert parsed.removed_minutes == 20

    invalid = _item(
        [duplicate_a, duplicate_b],
        [proposed],
        summary=(50, 0, 0, 0, 2, 0, 0, 0),
    )
    with pytest.raises(ValidationError):
        MultiExamPlanItem.model_validate_json(json.dumps(invalid))


def test_cancel_then_new_balance_keeps_active_base_and_proposed_distinct() -> None:
    old = _block(
        "88888888-8888-4888-8888-888888888881",
        starts_at=START,
        minutes=30,
    )
    new = _block(
        "88888888-8888-4888-8888-888888888882",
        starts_at=START + timedelta(hours=2),
        minutes=30,
    )
    parsed = MultiExamPlanItem.model_validate_json(
        json.dumps(
            _item(
                [old],
                [new],
                summary=(0, 0, 30, 0, 0, 0, 1, 0),
                active_revision=2,
                base_revision=4,
            )
        ),
    )
    assert (parsed.active_revision, parsed.base_revision, parsed.proposed_revision) == (
        2,
        4,
        5,
    )


def test_proposal_union_rejects_unknown_or_mixed_outcomes() -> None:
    adapter = TypeAdapter(MultiExamPlanProposalResponse)
    no_change = {
        "contract_version": "multi-exam-plan-v1",
        "origin": "authenticated_backend",
        "outcome": "no_change",
        "target_plan_id": PLAN_ID,
        "reason": "already_balanced",
    }
    assert adapter.validate_json(json.dumps(no_change)).outcome == "no_change"
    with pytest.raises(ValidationError):
        adapter.validate_json(json.dumps({**no_change, "outcome": "heuristic"}))
    with pytest.raises(ValidationError):
        adapter.validate_json(json.dumps({**no_change, "balance_id": BALANCE_ID}))


def test_transport_uuid_fields_remain_uuid_values_after_strict_json_parse() -> None:
    payload = {
        "contract_version": "multi-exam-plan-v1",
        "request_id": "99999999-9999-4999-8999-999999999991",
        "target_plan_id": PLAN_ID,
        "expected_plan_revision": 1,
    }
    parsed = MultiExamPlanProposalRequest.model_validate_json(json.dumps(payload))
    assert parsed.target_plan_id == UUID(PLAN_ID)
