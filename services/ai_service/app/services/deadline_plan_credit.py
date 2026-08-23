from __future__ import annotations

from datetime import datetime
from typing import Any


def deadline_block_credits(
    blocks: list[dict[str, Any]],
    focus_facts: list[dict[str, Any]],
    *,
    tracked_focus_minutes_at_proposal: int,
) -> dict[str, int]:
    """Allocate completed Focus minutes to one active revision's blocks.

    Proposal-time Focus is removed first. New source-linked Focus fills its
    originating block before generic overflow is distributed chronologically.
    The helper is shared by Deadline detail and Exam Plan Health so the two
    read projections cannot disagree about block credit.
    """

    ordered_blocks = sorted(
        blocks,
        key=lambda block: (_exact_int(block["sequence"]), str(block["id"])),
    )
    capacities = {
        str(block["id"]): _exact_int(block["planned_minutes"])
        for block in ordered_blocks
    }
    credits = {block_id: 0 for block_id in capacities}
    proposal_credit_left = max(0, tracked_focus_minutes_at_proposal)
    generic_credit = 0
    ordered_facts = sorted(
        focus_facts,
        key=lambda fact: (_aware_datetime(fact["started_at"]), str(fact["id"])),
    )
    for fact in ordered_facts:
        minutes = max(0, _exact_int(fact.get("actual_minutes")))
        already_considered = min(minutes, proposal_credit_left)
        proposal_credit_left -= already_considered
        minutes -= already_considered
        if minutes <= 0:
            continue
        source_block_id = fact.get("deadline_plan_block_id")
        source_key = str(source_block_id) if source_block_id is not None else None
        if source_key in capacities:
            source_available = capacities[source_key] - credits[source_key]
            source_credit = min(minutes, max(0, source_available))
            credits[source_key] += source_credit
            minutes -= source_credit
        generic_credit += minutes

    for block in ordered_blocks:
        if generic_credit <= 0:
            break
        block_key = str(block["id"])
        available = capacities[block_key] - credits[block_key]
        applied = min(generic_credit, max(0, available))
        credits[block_key] += applied
        generic_credit -= applied
    return credits


def _exact_int(value: object) -> int:
    if type(value) is not int:
        raise ValueError("Deadline credit minutes are invalid.")
    return value


def _aware_datetime(value: object) -> datetime:
    if isinstance(value, datetime):
        result = value
    elif isinstance(value, str):
        result = datetime.fromisoformat(value.replace("Z", "+00:00"))
    else:
        raise ValueError("Deadline credit timestamp is invalid.")
    if result.tzinfo is None or result.utcoffset() is None:
        raise ValueError("Deadline credit timestamp must be timezone-aware.")
    return result
