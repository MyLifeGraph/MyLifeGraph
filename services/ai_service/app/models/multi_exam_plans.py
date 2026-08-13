from __future__ import annotations

from datetime import date, datetime, timedelta
from typing import Annotated, Literal, Self
from uuid import UUID
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from pydantic import BaseModel, ConfigDict, Field, model_validator

from app.models.deadline_plans import DeadlinePlanResponse


MULTI_EXAM_PLAN_CONTRACT_VERSION = "multi-exam-plan-v1"

MultiExamBalanceStatus = Literal["proposed", "confirmed", "cancelled"]


class MultiExamPlanProposalRequest(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, frozen=True)

    contract_version: Literal["multi-exam-plan-v1"]
    request_id: UUID = Field(strict=False)
    target_plan_id: UUID = Field(strict=False)
    expected_plan_revision: int = Field(ge=1, le=199)


class MultiExamPlanMutationRequest(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, frozen=True)

    contract_version: Literal["multi-exam-plan-v1"]
    request_id: UUID = Field(strict=False)
    expected_revision: int = Field(ge=1, le=200)


class MultiExamPlanBlock(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, frozen=True)

    id: UUID
    sequence: int = Field(ge=1, le=120)
    starts_at: datetime
    ends_at: datetime
    reserved_ends_at: datetime
    local_date: date
    planned_minutes: int = Field(ge=5, le=240)
    recovery_minutes: int = Field(ge=0, le=60)
    credited_minutes: int = Field(ge=0, le=240)

    @model_validator(mode="after")
    def validate_interval(self) -> Self:
        if any(
            value.tzinfo is None or value.utcoffset() is None
            for value in (self.starts_at, self.ends_at, self.reserved_ends_at)
        ):
            raise ValueError("exam balance block instants must be aware")
        if self.ends_at - self.starts_at != timedelta(
            minutes=self.planned_minutes,
        ):
            raise ValueError("exam balance Focus interval is inconsistent")
        if self.reserved_ends_at - self.ends_at != timedelta(
            minutes=self.recovery_minutes,
        ):
            raise ValueError("exam balance recovery interval is inconsistent")
        if self.credited_minutes > self.planned_minutes:
            raise ValueError("exam balance credit exceeds planned minutes")
        return self

    @property
    def effective_minutes(self) -> int:
        return self.planned_minutes - self.credited_minutes

    @property
    def schedule_signature(self) -> tuple[datetime, datetime, datetime, int, int]:
        return (
            self.starts_at,
            self.ends_at,
            self.reserved_ends_at,
            self.planned_minutes,
            self.recovery_minutes,
        )


class MultiExamPlanItem(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, frozen=True)

    position: int = Field(ge=1, le=8)
    plan_id: UUID
    title: str = Field(min_length=1, max_length=160)
    deadline_at: datetime
    remaining_minutes: int = Field(ge=0, le=30_000)
    active_revision: int = Field(ge=1, le=200)
    base_revision: int = Field(ge=1, le=199)
    proposed_revision: int = Field(ge=2, le=200)
    current_blocks: list[MultiExamPlanBlock] = Field(max_length=120)
    proposed_blocks: list[MultiExamPlanBlock] = Field(max_length=120)
    retained_minutes: int = Field(ge=0, le=30_000)
    added_minutes: int = Field(ge=0, le=30_000)
    shifted_minutes: int = Field(ge=0, le=30_000)
    removed_minutes: int = Field(ge=0, le=30_000)
    retained_block_count: int = Field(ge=0, le=120)
    added_block_count: int = Field(ge=0, le=120)
    shifted_block_count: int = Field(ge=0, le=120)
    removed_block_count: int = Field(ge=0, le=120)

    @model_validator(mode="after")
    def validate_change_summary(self) -> Self:
        if self.title != self.title.strip():
            raise ValueError("exam balance title must be trimmed")
        if self.deadline_at.tzinfo is None or self.deadline_at.utcoffset() is None:
            raise ValueError("exam balance deadline must be aware")
        if (
            self.active_revision > self.base_revision
            or self.proposed_revision != self.base_revision + 1
        ):
            raise ValueError("exam balance revision must advance exactly once")
        for blocks, label in (
            (self.current_blocks, "current"),
            (self.proposed_blocks, "proposed"),
        ):
            if [block.sequence for block in blocks] != list(
                range(1, len(blocks) + 1),
            ):
                raise ValueError(f"exam balance {label} blocks are not contiguous")
            if len({block.id for block in blocks}) != len(blocks):
                raise ValueError(f"exam balance {label} block ids are not unique")
            if blocks != sorted(
                blocks,
                key=lambda block: (block.starts_at, str(block.id)),
            ):
                raise ValueError(f"exam balance {label} blocks are not ordered")
        if any(block.credited_minutes != 0 for block in self.proposed_blocks):
            raise ValueError("proposed exam balance blocks cannot be pre-credited")

        proposed_remaining = list(self.proposed_blocks)
        retained_minutes = 0
        retained_count = 0
        current_unmatched_minutes = 0
        current_unmatched_count = 0
        for block in self.current_blocks:
            index = next(
                (
                    position
                    for position, proposed_block in enumerate(proposed_remaining)
                    if block.credited_minutes == 0
                    and proposed_block.schedule_signature == block.schedule_signature
                ),
                None,
            )
            if index is None:
                current_unmatched_minutes += block.effective_minutes
                current_unmatched_count += 1
            else:
                proposed_remaining.pop(index)
                retained_minutes += block.effective_minutes
                retained_count += 1
        proposed_unmatched_minutes = sum(
            block.effective_minutes for block in proposed_remaining
        )
        proposed_unmatched_count = len(proposed_remaining)
        shifted_minutes = min(
            current_unmatched_minutes,
            proposed_unmatched_minutes,
        )
        shifted_count = min(current_unmatched_count, proposed_unmatched_count)
        expected = (
            retained_minutes,
            proposed_unmatched_minutes - shifted_minutes,
            shifted_minutes,
            current_unmatched_minutes - shifted_minutes,
            retained_count,
            proposed_unmatched_count - shifted_count,
            shifted_count,
            current_unmatched_count - shifted_count,
        )
        actual = (
            self.retained_minutes,
            self.added_minutes,
            self.shifted_minutes,
            self.removed_minutes,
            self.retained_block_count,
            self.added_block_count,
            self.shifted_block_count,
            self.removed_block_count,
        )
        if actual != expected:
            raise ValueError("exam balance change summary is inconsistent")
        if (
            self.current_blocks == self.proposed_blocks
            or self.added_minutes
            + self.shifted_minutes
            + self.removed_minutes
            + self.added_block_count
            + self.shifted_block_count
            + self.removed_block_count
            == 0
        ):
            raise ValueError("exam balance item must contain a real change")
        return self


class MultiExamPlanChildLink(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, frozen=True)

    plan_id: UUID
    proposed_revision: int = Field(ge=2, le=200)
    balance_id: UUID
    balance_revision: int = Field(ge=1, le=200)
    status: MultiExamBalanceStatus


class MultiExamPlanBatch(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, frozen=True)

    id: UUID
    status: MultiExamBalanceStatus
    revision: int = Field(ge=1, le=200)
    target_plan_id: UUID
    context_fingerprint: str = Field(pattern=r"^[0-9a-f]{64}$")
    confirmation_fingerprint: str = Field(pattern=r"^[0-9a-f]{64}$")
    timezone: str = Field(min_length=1, max_length=100)
    created_at: datetime
    updated_at: datetime
    confirmed_at: datetime | None = None
    cancelled_at: datetime | None = None
    retained_minutes: int = Field(ge=0, le=240_000)
    added_minutes: int = Field(ge=0, le=240_000)
    shifted_minutes: int = Field(ge=0, le=240_000)
    removed_minutes: int = Field(ge=0, le=240_000)
    items: list[MultiExamPlanItem] = Field(min_length=2, max_length=8)
    child_links: list[MultiExamPlanChildLink] = Field(min_length=2, max_length=8)

    @model_validator(mode="after")
    def validate_batch(self) -> Self:
        timestamps = [self.created_at, self.updated_at]
        timestamps.extend(
            value for value in (self.confirmed_at, self.cancelled_at) if value
        )
        if any(
            value.tzinfo is None or value.utcoffset() is None for value in timestamps
        ):
            raise ValueError("exam balance timestamps must be aware")
        try:
            ZoneInfo(self.timezone)
        except (ZoneInfoNotFoundError, ValueError) as exc:
            raise ValueError("exam balance timezone is invalid") from exc
        terminal_at = self.confirmed_at or self.cancelled_at
        if self.updated_at < self.created_at or (
            terminal_at is not None
            and not self.created_at <= terminal_at <= self.updated_at
        ):
            raise ValueError("exam balance timestamp order is invalid")
        if self.status == "proposed":
            if self.confirmed_at is not None or self.cancelled_at is not None:
                raise ValueError("proposed exam balance lifecycle is invalid")
        elif self.status == "confirmed":
            if self.confirmed_at is None or self.cancelled_at is not None:
                raise ValueError("confirmed exam balance lifecycle is invalid")
        elif self.cancelled_at is None or self.confirmed_at is not None:
            raise ValueError("cancelled exam balance lifecycle is invalid")
        expected_priority = sorted(
            self.items,
            key=lambda item: (
                item.deadline_at,
                -item.remaining_minutes,
                str(item.plan_id),
            ),
        )
        if self.items != expected_priority or [
            item.position for item in self.items
        ] != list(
            range(1, len(self.items) + 1),
        ):
            raise ValueError("exam balance items must use stable priority order")
        if len({item.plan_id for item in self.items}) != len(self.items):
            raise ValueError("exam balance plans must be unique")
        if self.target_plan_id not in {item.plan_id for item in self.items}:
            raise ValueError("exam balance target must be a changed plan")
        links = {link.plan_id: link for link in self.child_links}
        if len(links) != len(self.items):
            raise ValueError("exam balance child links must be unique")
        for item in self.items:
            link = links.get(item.plan_id)
            if (
                link is None
                or link.proposed_revision != item.proposed_revision
                or link.balance_id != self.id
                or link.balance_revision != self.revision
                or link.status != self.status
            ):
                raise ValueError("exam balance child link is inconsistent")
        actual_totals = (
            self.retained_minutes,
            self.added_minutes,
            self.shifted_minutes,
            self.removed_minutes,
        )
        expected_totals = tuple(
            sum(getattr(item, field) for item in self.items)
            for field in (
                "retained_minutes",
                "added_minutes",
                "shifted_minutes",
                "removed_minutes",
            )
        )
        if actual_totals != expected_totals:
            raise ValueError("exam balance aggregate totals are inconsistent")
        return self


class MultiExamPlanBatchSummary(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, frozen=True)

    id: UUID
    status: MultiExamBalanceStatus
    revision: int = Field(ge=1, le=200)
    target_plan_id: UUID
    affected_plan_count: int = Field(ge=2, le=8)
    shifted_minutes: int = Field(ge=0, le=240_000)
    created_at: datetime
    updated_at: datetime

    @model_validator(mode="after")
    def validate_summary(self) -> Self:
        if (
            any(
                value.tzinfo is None or value.utcoffset() is None
                for value in (self.created_at, self.updated_at)
            )
            or self.updated_at < self.created_at
        ):
            raise ValueError("exam balance summary timestamps are invalid")
        return self


class MultiExamPlanListResponse(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, frozen=True)

    contract_version: Literal["multi-exam-plan-v1"]
    origin: Literal["authenticated_backend"]
    balances: list[MultiExamPlanBatchSummary] = Field(max_length=200)

    @model_validator(mode="after")
    def validate_feed(self) -> Self:
        if len({balance.id for balance in self.balances}) != len(self.balances):
            raise ValueError("exam balance summaries must be unique")
        expected = sorted(
            self.balances,
            key=lambda balance: (balance.updated_at, str(balance.id)),
            reverse=True,
        )
        if self.balances != expected:
            raise ValueError("exam balance summaries are not ordered")
        return self


class MultiExamPlanBatchResponse(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, frozen=True)

    contract_version: Literal["multi-exam-plan-v1"]
    origin: Literal["authenticated_backend"]
    balance: MultiExamPlanBatch


class MultiExamPlanNoChangeResponse(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, frozen=True)

    contract_version: Literal["multi-exam-plan-v1"]
    origin: Literal["authenticated_backend"]
    outcome: Literal["no_change"]
    target_plan_id: UUID
    reason: Literal["already_balanced"]


class MultiExamPlanSingleResponse(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, frozen=True)

    contract_version: Literal["multi-exam-plan-v1"]
    origin: Literal["authenticated_backend"]
    outcome: Literal["single_plan"]
    plan: DeadlinePlanResponse

    @model_validator(mode="after")
    def validate_single(self) -> Self:
        if self.plan.plan.kind != "exam" or self.plan.pending_revision is None:
            raise ValueError("single Exam balance must return one staged Exam")
        return self


class MultiExamPlanBatchProposalResponse(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, frozen=True)

    contract_version: Literal["multi-exam-plan-v1"]
    origin: Literal["authenticated_backend"]
    outcome: Literal["multi_exam_batch"]
    balance: MultiExamPlanBatch

    @model_validator(mode="after")
    def validate_proposal(self) -> Self:
        if self.balance.status != "proposed":
            raise ValueError("Exam balance proposal must be staged")
        return self


MultiExamPlanProposalResponse = Annotated[
    MultiExamPlanNoChangeResponse
    | MultiExamPlanSingleResponse
    | MultiExamPlanBatchProposalResponse,
    Field(discriminator="outcome"),
]
