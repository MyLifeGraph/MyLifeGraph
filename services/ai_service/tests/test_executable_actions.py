import pytest
from pydantic import ValidationError

from app.models.executable_actions import (
    EXECUTABLE_ACTION_CONTRACT_VERSION,
    ExecutableActionTarget,
    parse_executable_action_target,
)


def action_payload(**overrides):
    payload = {
        "contract_version": EXECUTABLE_ACTION_CONTRACT_VERSION,
        "id": "complete_task:task-123",
        "kind": "task",
        "command": "complete_task",
        "target_id": "task-123",
        "estimated_minutes": 25,
        "metadata": {"source": "daily-briefing"},
    }
    payload.update(overrides)
    return payload


@pytest.mark.parametrize(
    ("payload", "command"),
    [
        (action_payload(), "complete_task"),
        (
            action_payload(
                id="open_task:task-123",
                command="open_task",
            ),
            "open_task",
        ),
        (
            action_payload(
                id="log_habit:habit-123:2026-07-11",
                kind="habit",
                command="log_habit",
                target_id="habit-123",
                estimated_minutes=None,
                metadata={
                    "entry_date": "2026-07-11",
                    "habit_outcome": "completed",
                    "source": "daily-briefing",
                },
            ),
            "log_habit",
        ),
        (
            action_payload(
                id="start_focus:task-123",
                kind="focus",
                command="start_focus",
                target_id="task-123",
                estimated_minutes=50,
                metadata={
                    "focus_minutes": 50,
                    "target_kind": "task",
                    "source": "daily-briefing",
                },
            ),
            "start_focus",
        ),
        (
            action_payload(
                id="start_focus:unlinked",
                kind="focus",
                command="start_focus",
                target_id=None,
                estimated_minutes=25,
                metadata={"source": "quick-action"},
            ),
            "start_focus",
        ),
        (
            action_payload(
                id="review_plan:today",
                kind="planning",
                command="review_plan",
                target_id=None,
                estimated_minutes=10,
                metadata={"source": "daily-briefing"},
            ),
            "review_plan",
        ),
        (
            action_payload(
                id="open_capture:morning",
                kind="capture",
                command="open_capture",
                target_id=None,
                estimated_minutes=None,
                metadata={
                    "entry_date": "2026-07-11",
                    "route": "/morning-calibration",
                    "source": "daily-briefing",
                },
            ),
            "open_capture",
        ),
    ],
)
def test_parser_accepts_supported_command_contracts(payload, command) -> None:
    parsed = parse_executable_action_target(payload)

    assert isinstance(parsed, ExecutableActionTarget)
    assert parsed.command == command


@pytest.mark.parametrize(
    "changes",
    [
        {"contract_version": "future-action-v2"},
        {"kind": "future-kind"},
        {"command": "delete_everything"},
        {"id": " contains whitespace"},
        {"target_id": None},
        {"estimated_minutes": 0},
        {"estimated_minutes": 481},
        {"estimated_minutes": "25"},
        {"metadata": {"source": None}},
        {"metadata": {"source": "daily-briefing", "nested": {"x": 1}}},
        {"metadata": {"source": ["daily-briefing"]}},
    ],
)
def test_parser_rejects_unknown_invalid_or_coerced_values(changes) -> None:
    with pytest.raises(ValidationError):
        parse_executable_action_target(action_payload(**changes))


def test_parser_rejects_command_kind_mismatch() -> None:
    with pytest.raises(ValidationError, match="requires kind habit"):
        parse_executable_action_target(
            action_payload(command="log_habit"),
        )


@pytest.mark.parametrize(
    "payload",
    [
        action_payload(
            id="start_focus:ambiguous",
            kind="focus",
            command="start_focus",
            target_id="task-123",
            metadata={"focus_minutes": 25},
        ),
        action_payload(
            id="start_focus:no-target",
            kind="focus",
            command="start_focus",
            target_id=None,
            metadata={"focus_minutes": 25, "target_kind": "habit"},
        ),
        action_payload(
            id="start_focus:mismatch",
            kind="focus",
            command="start_focus",
            target_id="task-123",
            estimated_minutes=50,
            metadata={"focus_minutes": 25, "target_kind": "task"},
        ),
        action_payload(
            id="start_focus:too-long",
            kind="focus",
            command="start_focus",
            target_id=None,
            estimated_minutes=300,
            metadata={},
        ),
        action_payload(
            id="start_focus:too-short",
            kind="focus",
            command="start_focus",
            target_id=None,
            estimated_minutes=4,
            metadata={},
        ),
    ],
)
def test_start_focus_rejects_ambiguous_or_inconsistent_linkage(payload) -> None:
    with pytest.raises(ValidationError):
        parse_executable_action_target(payload)


@pytest.mark.parametrize(
    "metadata",
    [
        {},
        {"route": "/dashboard"},
        {"route": "/morning-calibration", "habit_outcome": "completed"},
    ],
)
def test_open_capture_requires_allowlisted_route_and_command_metadata(
    metadata,
) -> None:
    with pytest.raises(ValidationError):
        parse_executable_action_target(
            action_payload(
                id="open_capture:invalid",
                kind="capture",
                command="open_capture",
                target_id=None,
                metadata=metadata,
            ),
        )


def test_log_habit_rejects_malformed_date_and_unknown_outcome() -> None:
    for metadata in (
        {"entry_date": "2026-02-31"},
        {"entry_date": "20260711"},
        {"entry_date": "2026-W28-6"},
        {"habit_outcome": "open"},
    ):
        with pytest.raises(ValidationError):
            parse_executable_action_target(
                action_payload(
                    id="log_habit:invalid",
                    kind="habit",
                    command="log_habit",
                    target_id="habit-123",
                    metadata=metadata,
                ),
            )
