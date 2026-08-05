from collections.abc import Callable
from datetime import UTC, datetime, time
from typing import Any
from uuid import NAMESPACE_URL, UUID, uuid5

from app.models.intake import (
    IntakeCompleteRequest,
    IntakeCompleteResponse,
    IntakeResponses,
    IntakeSetupResponse,
    SnapshotSummary,
)
from app.repositories.intake_repository import (
    AtomicSetupApply,
    IntakeApplyConflict,
    IntakeClaimConflict,
    IntakeRepository,
    SetupMaterialization,
)
_ONBOARDING_PERIOD_KEY = "setup:intake-v1"


class IntakeRevisionConflict(RuntimeError):
    def __init__(
        self,
        message: str,
        *,
        current_revision: int,
        pending_request_id: str | None = None,
    ) -> None:
        super().__init__(message)
        self.current_revision = current_revision
        self.pending_request_id = pending_request_id

    def as_detail(self) -> dict[str, Any]:
        detail: dict[str, Any] = {
            "code": "intake_revision_conflict",
            "message": str(self),
            "current_revision": self.current_revision,
        }
        if self.pending_request_id is not None:
            detail["pending_request_id"] = self.pending_request_id
        return detail


class IntakeService:
    def __init__(
        self,
        repository: IntakeRepository,
        now_provider: Callable[[], datetime] | None = None,
    ) -> None:
        self._repository = repository
        self._now_provider = now_provider or _utc_now

    async def get_setup(self, *, user_id: str) -> IntakeSetupResponse:
        row = await self._repository.load_latest_intake(user_id=user_id)
        if row is None:
            return IntakeSetupResponse(
                exists=False,
                revision=0,
                base_revision=0,
            )
        return await self._setup_response_from_row(user_id=user_id, row=row)

    async def complete_intake(
        self,
        *,
        user_id: str,
        request: IntakeCompleteRequest,
    ) -> IntakeCompleteResponse:
        responses_json = request.responses.model_dump(mode="json", exclude_none=True)
        request_metadata = request.model_dump(mode="json")["metadata"]
        intake_row = await self._claim_or_resume_revision(
            user_id=user_id,
            request=request,
            responses_json=responses_json,
            request_metadata=request_metadata,
        )

        if str(intake_row.get("state")) == "applied":
            await self._complete_profile_marker(user_id=user_id, row=intake_row)
            return await self._complete_response_from_row(
                user_id=user_id,
                row=intake_row,
            )

        revision = int(intake_row["revision"])
        completed_at = self._now_provider()
        canonical_responses = _responses_from_row(user_id=user_id, row=intake_row)
        atomic_apply = _build_atomic_apply(
            user_id=user_id,
            row=intake_row,
            completed_at=completed_at,
            responses=canonical_responses,
        )
        try:
            apply_result = await self._repository.apply_setup_revision(
                user_id=user_id,
                intake_response_id=str(intake_row["id"]),
                request_id=UUID(str(intake_row["request_id"])),
                base_revision=int(intake_row["base_revision"]),
                revision=revision,
                apply=atomic_apply,
            )
        except IntakeApplyConflict:
            latest = await self._repository.load_latest_intake(user_id=user_id)
            current_revision = int(latest.get("revision") or 0) if latest else 0
            raise IntakeRevisionConflict(
                "Setup changed before this save could be applied.",
                current_revision=(
                    max(current_revision - 1, 0)
                    if latest and latest.get("state") == "pending"
                    else current_revision
                ),
                pending_request_id=(
                    str(latest.get("request_id"))
                    if latest and latest.get("state") == "pending"
                    else None
                ),
            ) from None
        if str(apply_result.get("state")) != "applied":
            raise RuntimeError("Atomic Intake V1 apply did not return applied state.")
        applied_row = await self._repository.load_intake_by_request(
            user_id=user_id,
            request_id=request.request_id,
        )
        if applied_row is None or str(applied_row.get("state")) != "applied":
            raise RuntimeError("Atomic Intake V1 apply was not readable after commit.")
        return await self._complete_response_from_row(
            user_id=user_id,
            row=applied_row,
        )

    async def _complete_profile_marker(
        self,
        *,
        user_id: str,
        row: dict[str, Any],
    ) -> None:
        latest_applied = await self._repository.load_latest_applied_intake(
            user_id=user_id,
        )
        if (
            latest_applied is None
            or str(latest_applied.get("id")) != str(row.get("id"))
        ):
            return
        responses = _responses_from_row(user_id=user_id, row=row)
        apply_result = await self._repository.apply_setup_revision(
            user_id=user_id,
            intake_response_id=str(row["id"]),
            request_id=UUID(str(row["request_id"])),
            base_revision=int(row["base_revision"]),
            revision=int(row["revision"]),
            apply=_build_atomic_apply(
                user_id=user_id,
                row=row,
                completed_at=_parse_datetime(row.get("completed_at")),
                responses=responses,
            ),
        )
        if str(apply_result.get("state")) != "applied":
            raise RuntimeError("Applied Intake V1 replay did not remain applied.")

    async def _claim_or_resume_revision(
        self,
        *,
        user_id: str,
        request: IntakeCompleteRequest,
        responses_json: dict[str, Any],
        request_metadata: dict[str, Any],
    ) -> dict[str, Any]:
        existing = await self._repository.load_intake_by_request(
            user_id=user_id,
            request_id=request.request_id,
        )
        if existing is not None:
            _validate_replayed_request(
                user_id=user_id,
                existing=existing,
                request=request,
                responses_json=responses_json,
                request_metadata=request_metadata,
            )
            return existing

        latest = await self._repository.load_latest_intake(user_id=user_id)
        _validate_base_revision(latest=latest, request=request)
        now = self._now_provider()
        row = {
            "id": str(_stable_id(user_id, "intake-request", request.request_id)),
            "request_id": str(request.request_id),
            "base_revision": request.base_revision,
            "revision": request.base_revision + 1,
            "state": "pending",
            "version": request.version,
            "responses": responses_json,
            "completed_at": now.isoformat(),
            "updated_at": now.isoformat(),
            "metadata": {
                "source": "onboarding",
                "request_metadata": request_metadata,
            },
        }
        try:
            return await self._repository.insert_pending_intake(
                user_id=user_id,
                row=row,
            )
        except IntakeClaimConflict:
            concurrent = await self._repository.load_intake_by_request(
                user_id=user_id,
                request_id=request.request_id,
            )
            if concurrent is not None:
                _validate_replayed_request(
                    user_id=user_id,
                    existing=concurrent,
                    request=request,
                    responses_json=responses_json,
                    request_metadata=request_metadata,
                )
                return concurrent
            latest = await self._repository.load_latest_intake(user_id=user_id)
            current_revision = int(latest.get("revision") or 0) if latest else 0
            raise IntakeRevisionConflict(
                "Another setup save claimed this revision.",
                current_revision=current_revision,
                pending_request_id=(
                    str(latest.get("request_id"))
                    if latest and latest.get("state") == "pending"
                    else None
                ),
            ) from None

    async def _setup_response_from_row(
        self,
        *,
        user_id: str,
        row: dict[str, Any],
    ) -> IntakeSetupResponse:
        responses = _responses_from_row(user_id=user_id, row=row)
        metadata = _metadata(row)
        snapshot_id = metadata.get("snapshot_id")
        if snapshot_id is None and str(row.get("state")) == "applied":
            snapshot = await self._repository.load_latest_onboarding_snapshot(
                user_id=user_id,
            )
            snapshot_id = snapshot.get("id") if snapshot else None
        return IntakeSetupResponse(
            exists=True,
            revision=int(row.get("revision") or 0),
            base_revision=int(row.get("base_revision") or 0),
            request_id=row.get("request_id"),
            status=row.get("state"),
            intake_response_id=str(row["id"]),
            snapshot_id=str(snapshot_id) if snapshot_id is not None else None,
            completed_at=_parse_datetime(row.get("completed_at")),
            responses=responses,
            summary=_build_summary(responses),
        )

    async def _complete_response_from_row(
        self,
        *,
        user_id: str,
        row: dict[str, Any],
    ) -> IntakeCompleteResponse:
        setup = await self._setup_response_from_row(user_id=user_id, row=row)
        if (
            setup.request_id is None
            or setup.snapshot_id is None
            or setup.completed_at is None
            or setup.responses is None
            or setup.summary is None
        ):
            raise RuntimeError("Applied intake is missing its canonical setup state.")
        return IntakeCompleteResponse(
            exists=True,
            revision=setup.revision,
            base_revision=setup.base_revision,
            request_id=setup.request_id,
            status="applied",
            intake_response_id=setup.intake_response_id or str(row["id"]),
            snapshot_id=setup.snapshot_id,
            completed_at=setup.completed_at,
            responses=setup.responses,
            summary=setup.summary,
            recommendations=[],
        )


def _build_atomic_apply(
    *,
    user_id: str,
    row: dict[str, Any],
    completed_at: datetime,
    responses: IntakeResponses,
) -> AtomicSetupApply:
    revision = int(row["revision"])
    request_id = UUID(str(row["request_id"]))
    summary = _build_summary(responses)
    snapshot = {
        "user_id": user_id,
        "scope": "onboarding",
        "period_key": _ONBOARDING_PERIOD_KEY,
        "summary": summary.model_dump(mode="json"),
        "signals": {},
        "source": "backend",
        "generated_at": completed_at.isoformat(),
        "metadata": {
            "source": "intake-v1",
            "managed_by": "setup",
            "intake_response_id": str(row["id"]),
            "request_id": str(request_id),
            "revision": revision,
        },
    }
    row_metadata = _metadata(row)
    request_metadata = row_metadata.get("request_metadata")
    if not isinstance(request_metadata, dict):
        request_metadata = {}
    return AtomicSetupApply(
        completed_at=completed_at.isoformat(),
        notification_preferences={},
        materialization=_build_materialization(
            user_id=user_id,
            revision=revision,
            intake_response_id=str(row["id"]),
            completed_at=completed_at,
            responses=responses,
        ),
        snapshot=snapshot,
        intake_metadata={
            **row_metadata,
            "source": "onboarding",
            "request_metadata": request_metadata,
        },
    )


def _validate_replayed_request(
    *,
    user_id: str,
    existing: dict[str, Any],
    request: IntakeCompleteRequest,
    responses_json: dict[str, Any],
    request_metadata: dict[str, Any],
) -> None:
    try:
        existing_responses = _responses_from_row(
            user_id=user_id,
            row=existing,
        ).model_dump(mode="json", exclude_none=True)
    except (RuntimeError, ValueError):
        existing_responses = existing.get("responses")
    same_payload = (
        str(existing.get("version")) == request.version
        and int(existing.get("base_revision") or 0) == request.base_revision
        and existing_responses == responses_json
        and _metadata(existing).get("request_metadata", {}) == request_metadata
    )
    if same_payload:
        return
    raise IntakeRevisionConflict(
        "request_id was already used with a different setup payload.",
        current_revision=int(existing.get("revision") or 0),
        pending_request_id=(
            str(existing.get("request_id"))
            if existing.get("state") == "pending"
            else None
        ),
    )


def _validate_base_revision(
    *,
    latest: dict[str, Any] | None,
    request: IntakeCompleteRequest,
) -> None:
    if latest is None:
        if request.base_revision == 0:
            return
        raise IntakeRevisionConflict(
            "Setup does not yet have the requested base revision.",
            current_revision=0,
        )
    revision = int(latest.get("revision") or 0)
    if latest.get("state") == "pending":
        raise IntakeRevisionConflict(
            "A setup save is pending and must be retried with its request_id.",
            current_revision=max(revision - 1, 0),
            pending_request_id=str(latest.get("request_id")),
        )
    if request.base_revision != revision:
        raise IntakeRevisionConflict(
            "Setup changed after this draft was loaded.",
            current_revision=revision,
        )


def _build_summary(responses: IntakeResponses) -> SnapshotSummary:
    confirmed_routines = [
        routine
        for routine in responses.routines
        if routine.cadence_confirmed and routine.status in {"active", "paused"}
    ]
    return SnapshotSummary(
        best_energy_window=responses.best_energy_window,
        fixed_commitment_count=sum(
            commitment.status == "active"
            for commitment in responses.fixed_commitments
        ),
        existing_habit_count=len(confirmed_routines),
        routine_candidate_count=sum(
            routine.status == "candidate" for routine in responses.routines
        ),
        active_habit_count=sum(
            routine.status == "active" for routine in confirmed_routines
        ),
    )


def _build_materialization(
    *,
    user_id: str,
    revision: int,
    intake_response_id: str,
    completed_at: datetime,
    responses: IntakeResponses,
) -> SetupMaterialization:
    timestamp = completed_at.isoformat()
    habit_rows = [
        {
            "id": str(_stable_id(user_id, "habit", routine.key)),
            "user_id": user_id,
            "title": routine.title,
            "frequency": routine.frequency,
            "target": routine.target,
            "active": routine.status == "active",
            "metadata": _setup_metadata(
                setup_item_id=routine.key,
                revision=revision,
                setup_state=routine.status,
                extra={"cadence_confirmed": True},
            ),
            "updated_at": timestamp,
        }
        for routine in responses.routines
        if routine.cadence_confirmed and routine.status != "candidate"
    ]

    schedule_rows = [
        {
            "id": str(_stable_id(user_id, "schedule-item", commitment.key)),
            "user_id": user_id,
            "title": commitment.title,
            "location": commitment.location,
            "weekday": commitment.weekday,
            "starts_at": _format_time(commitment.starts_at),
            "ends_at": _format_time(commitment.ends_at),
            "source": "onboarding",
            "metadata": _setup_metadata(
                setup_item_id=commitment.key,
                revision=revision,
                setup_state="active",
                extra={
                    **(
                        {"valid_from": commitment.valid_from.isoformat()}
                        if commitment.valid_from is not None
                        else {}
                    ),
                    **(
                        {"valid_until": commitment.valid_until.isoformat()}
                        if commitment.valid_until is not None
                        else {}
                    ),
                },
            ),
            "updated_at": timestamp,
        }
        for commitment in responses.fixed_commitments
        if commitment.status == "active"
    ]

    memory_rows = _memory_rows(
        user_id=user_id,
        revision=revision,
        intake_response_id=intake_response_id,
        completed_at=completed_at,
        responses=responses,
    )
    return SetupMaterialization(
        habits=habit_rows,
        schedule_items=schedule_rows,
        memory_entries=memory_rows,
    )


def _memory_rows(
    *,
    user_id: str,
    revision: int,
    intake_response_id: str,
    completed_at: datetime,
    responses: IntakeResponses,
) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    energy_key = _stable_id(user_id, "memory-key", "energy-window")
    rows.append(
        _memory_row(
            user_id=user_id,
            setup_item_id=energy_key,
            record_kind="pattern-memory",
            revision=revision,
            intake_response_id=intake_response_id,
            completed_at=completed_at,
            memory_type="pattern",
            title="Best energy window",
            content=responses.best_energy_window,
        ),
    )
    return rows


def _memory_row(
    *,
    user_id: str,
    setup_item_id: UUID,
    record_kind: str,
    revision: int,
    intake_response_id: str,
    completed_at: datetime,
    memory_type: str,
    title: str,
    content: str,
) -> dict[str, Any]:
    timestamp = completed_at.isoformat()
    return {
        "id": str(_stable_id(user_id, record_kind, setup_item_id)),
        "user_id": user_id,
        "type": memory_type,
        "title": title,
        "content": content,
        "strength": 0.7,
        "evidence": [
            {
                "source": "intake-v1",
                "intake_response_id": intake_response_id,
                "revision": revision,
            },
        ],
        "metadata": _setup_metadata(
            setup_item_id=setup_item_id,
            revision=revision,
            setup_state="active",
        ),
        "last_seen_at": timestamp,
        "updated_at": timestamp,
    }


def _setup_metadata(
    *,
    setup_item_id: UUID,
    revision: int,
    setup_state: str,
    extra: dict[str, Any] | None = None,
) -> dict[str, Any]:
    return {
        "source": "intake-v1",
        "managed_by": "setup",
        "setup_item_id": str(setup_item_id),
        "revision": revision,
        "setup_state": setup_state,
        **(extra or {}),
    }


def _responses_from_row(*, user_id: str, row: dict[str, Any]) -> IntakeResponses:
    raw = row.get("responses")
    if not isinstance(raw, dict):
        raise RuntimeError("Stored intake responses are not an object.")
    normalized = dict(raw)
    if "routines" not in normalized:
        legacy_habits = normalized.pop("existing_habits", [])
        normalized["routines"] = [
            {
                "key": str(
                    _stable_id(user_id, "legacy-routine", f"{index}:{title}"),
                ),
                "title": title,
                "status": "candidate",
                "cadence_confirmed": False,
            }
            for index, title in enumerate(legacy_habits)
            if isinstance(title, str) and title.strip()
        ]
    commitments = normalized.get("fixed_commitments", [])
    if isinstance(commitments, list):
        normalized["fixed_commitments"] = [
            (
                item
                if not isinstance(item, dict) or item.get("key") is not None
                else {
                    **item,
                    "key": str(
                        _stable_id(
                            user_id,
                            "legacy-commitment",
                            f"{index}:{item}",
                        ),
                    ),
                    "status": "active",
                }
            )
            for index, item in enumerate(commitments)
            if not _is_known_legacy_default_commitment(item)
        ]
    return IntakeResponses.model_validate(normalized)


def _stable_id(user_id: str, kind: str, item_key: UUID | str) -> UUID:
    return uuid5(NAMESPACE_URL, f"mylifegraph:{user_id}:{kind}:{item_key}")


def _is_known_legacy_default_commitment(value: Any) -> bool:
    if not isinstance(value, dict) or value.get("key") is not None:
        return False
    starts_at = next(
        (
            value.get(key)
            for key in ("starts_at", "startsAt", "start_time", "startTime")
            if value.get(key) is not None
        ),
        None,
    )
    ends_at = next(
        (
            value.get(key)
            for key in ("ends_at", "endsAt", "end_time", "endTime")
            if value.get(key) is not None
        ),
        None,
    )
    return (
        value.get("title") == "Math"
        and value.get("location") == "Room 204"
        and value.get("weekday") == 1
        and str(starts_at or "")[:5] == "08:15"
        and str(ends_at or "")[:5] == "09:45"
    )


def _metadata(row: dict[str, Any]) -> dict[str, Any]:
    metadata = row.get("metadata")
    return metadata if isinstance(metadata, dict) else {}


def _format_time(value: time) -> str:
    return value.strftime("%H:%M")


def _parse_datetime(value: Any) -> datetime:
    if isinstance(value, datetime):
        return value
    if value is None:
        raise RuntimeError("Stored intake is missing completed_at.")
    return datetime.fromisoformat(str(value).replace("Z", "+00:00"))


def _utc_now() -> datetime:
    return datetime.now(tz=UTC)
