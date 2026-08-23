import re
from datetime import date
from typing import Annotated, Any, Literal, Mapping

from pydantic import (
    BaseModel,
    ConfigDict,
    Field,
    StringConstraints,
    model_validator,
)


EXECUTABLE_ACTION_CONTRACT_VERSION = "executable-action-v1"

ExecutableActionKind = Literal[
    "task",
    "habit",
    "focus",
    "planning",
    "recovery",
    "capture",
]
ExecutableActionCommand = Literal[
    "open_task",
    "complete_task",
    "log_habit",
    "start_focus",
    "review_plan",
    "open_capture",
]
ExecutableActionTargetKind = Literal["task", "habit"]
HabitOutcome = Literal["completed", "skipped"]
CaptureRoute = Literal["/quick-mood-check-in", "/morning-calibration"]

ActionIdentifier = Annotated[
    str,
    StringConstraints(
        min_length=1,
        max_length=200,
        pattern=r"^[A-Za-z0-9][A-Za-z0-9._:-]*$",
    ),
]
ActionSource = Annotated[
    str,
    StringConstraints(
        min_length=1,
        max_length=64,
        pattern=r"^[a-z0-9][a-z0-9._:-]*$",
    ),
]


class ExecutableActionMetadata(BaseModel):
    """Bounded scalar context for an executable action.

    Keeping this as a strict model makes unknown and nested metadata fail at the
    contract boundary instead of leaking arbitrary payloads into handlers.
    """

    model_config = ConfigDict(extra="forbid", strict=True, frozen=True)

    entry_date: str | None = None
    focus_minutes: int | None = Field(default=None, strict=True, ge=5, le=240)
    habit_outcome: HabitOutcome | None = None
    route: CaptureRoute | None = None
    source: ActionSource | None = None
    target_kind: ExecutableActionTargetKind | None = None

    @model_validator(mode="before")
    @classmethod
    def reject_explicit_null_values(cls, value: Any) -> Any:
        if isinstance(value, Mapping):
            null_fields = sorted(
                str(name)
                for name, field_value in value.items()
                if field_value is None
            )
            if null_fields:
                names = ", ".join(null_fields)
                raise ValueError(
                    f"metadata fields cannot be null: {names}",
                )
        return value

    @model_validator(mode="after")
    def validate_entry_date(self) -> "ExecutableActionMetadata":
        if self.entry_date is None:
            return self
        if re.fullmatch(r"\d{4}-\d{2}-\d{2}", self.entry_date) is None:
            raise ValueError("entry_date must be an ISO calendar date")
        try:
            date.fromisoformat(self.entry_date)
        except ValueError as exc:
            raise ValueError("entry_date must be an ISO calendar date") from exc
        return self


class ExecutableActionTarget(BaseModel):
    """Strict, ranking-independent executable action envelope."""

    model_config = ConfigDict(extra="forbid", strict=True, frozen=True)

    contract_version: Literal["executable-action-v1"]
    id: ActionIdentifier
    kind: ExecutableActionKind
    command: ExecutableActionCommand
    target_id: ActionIdentifier | None = None
    estimated_minutes: int | None = Field(
        default=None,
        strict=True,
        ge=1,
        le=480,
    )
    metadata: ExecutableActionMetadata = Field(
        default_factory=ExecutableActionMetadata,
    )

    @model_validator(mode="after")
    def validate_command_contract(self) -> "ExecutableActionTarget":
        expected_kind = {
            "open_task": "task",
            "complete_task": "task",
            "log_habit": "habit",
            "start_focus": "focus",
            "review_plan": "planning",
            "open_capture": "capture",
        }[self.command]
        if self.kind != expected_kind:
            raise ValueError(
                f"{self.command} requires kind {expected_kind}",
            )

        requires_target = self.command in {
            "open_task",
            "complete_task",
            "log_habit",
        }
        if requires_target and self.target_id is None:
            raise ValueError(f"{self.command} requires target_id")
        if self.command == "open_capture" and self.target_id is not None:
            raise ValueError("open_capture does not accept target_id")

        present_metadata = {
            name
            for name in ExecutableActionMetadata.model_fields
            if getattr(self.metadata, name) is not None
        }
        allowed_metadata = {
            "open_task": {"source"},
            "complete_task": {"source"},
            "log_habit": {"entry_date", "habit_outcome", "source"},
            "start_focus": {"focus_minutes", "source", "target_kind"},
            "review_plan": {"source"},
            "open_capture": {"entry_date", "route", "source"},
        }[self.command]
        unsupported_metadata = present_metadata - allowed_metadata
        if unsupported_metadata:
            names = ", ".join(sorted(unsupported_metadata))
            raise ValueError(
                f"{self.command} does not accept metadata fields: {names}",
            )

        if self.command == "start_focus":
            has_target = self.target_id is not None
            has_target_kind = self.metadata.target_kind is not None
            if has_target != has_target_kind:
                raise ValueError(
                    "start_focus target_id and metadata.target_kind must be "
                    "provided together",
                )
            if (
                self.estimated_minutes is not None
                and not 5 <= self.estimated_minutes <= 240
            ):
                raise ValueError("start_focus duration must be within 5..240")
            if (
                self.estimated_minutes is not None
                and self.metadata.focus_minutes is not None
                and self.estimated_minutes != self.metadata.focus_minutes
            ):
                raise ValueError(
                    "start_focus duration fields must agree when both are set",
                )

        if self.command == "open_capture" and self.metadata.route is None:
            raise ValueError("open_capture requires metadata.route")

        return self


def parse_executable_action_target(
    payload: Mapping[str, Any],
) -> ExecutableActionTarget:
    """Parse an untrusted action payload without permissive type coercion."""

    return ExecutableActionTarget.model_validate(payload, strict=True)
