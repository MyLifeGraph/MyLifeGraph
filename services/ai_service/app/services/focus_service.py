from __future__ import annotations

import hashlib
import json
from datetime import UTC, datetime
from typing import Callable
from uuid import UUID

from app.models.focus import (
    FocusSessionResult,
    FocusSessionResponse,
    FocusOpenEndSessionResponse,
    FocusStartContextResponse,
    FocusStartRequest,
    FocusTimeCorrectionRequest,
    ManualFocusStartRequest,
    OpenEndFocusStartRequest,
    ScheduledFocusStartRequest,
    parse_focus_session,
)
from app.repositories.focus_repository import (
    FocusPersistenceConflict,
    FocusPersistenceNotFound,
    FocusRepository,
)


class FocusConflictError(RuntimeError):
    pass


class FocusNotFoundError(RuntimeError):
    pass


class FocusService:
    async def start_open_end(self, *, user_id: str,
                             request: OpenEndFocusStartRequest) -> FocusSessionResult:
        try:
            raw = await self._repository.start_open_end(
                user_id=user_id, request_id=request.request_id,
                request_fingerprint=_fingerprint(request),
                recovery_minutes=request.recovery_minutes,
                target_kind=request.target_kind, target_id=request.target_id,
                label=request.label, now=_utc(self._now()),
            )
        except FocusPersistenceNotFound as exc:
            raise FocusNotFoundError(str(exc)) from exc
        except FocusPersistenceConflict as exc:
            raise FocusConflictError(str(exc)) from exc
        result = parse_focus_session(raw)
        if not isinstance(result, FocusOpenEndSessionResponse) or result.id != request.request_id:
            raise ValueError("Open-end Focus response does not match request.")
        return result

    async def correct_time(self, *, user_id: str, session_id: UUID,
                           request: FocusTimeCorrectionRequest) -> FocusSessionResult:
        try:
            raw = await self._repository.correct_time(
                user_id=user_id, session_id=session_id, request_id=request.request_id,
                expected_updated_at=request.expected_updated_at, minutes=request.minutes,
            )
        except FocusPersistenceNotFound as exc:
            raise FocusNotFoundError(str(exc)) from exc
        except FocusPersistenceConflict as exc:
            raise FocusConflictError(str(exc)) from exc
        result = parse_focus_session(raw)
        if result.id != session_id or result.actual_minutes != request.minutes or result.status != "completed":
            raise ValueError("Correction response does not match request.")
        return result

    def __init__(
        self,
        *,
        repository: FocusRepository,
        now: Callable[[], datetime] | None = None,
    ) -> None:
        self._repository = repository
        self._now = now or (lambda: datetime.now(UTC))

    async def get_start_context(
        self,
        *,
        user_id: str,
        source_kind: str,
        block_id: UUID,
    ) -> FocusStartContextResponse:
        try:
            raw = await self._repository.get_start_context(
                user_id=user_id,
                source_kind=source_kind,
                block_id=block_id,
                now=_utc(self._now()),
            )
        except FocusPersistenceNotFound as exc:
            raise FocusNotFoundError(str(exc)) from exc
        except FocusPersistenceConflict as exc:
            raise FocusConflictError(str(exc)) from exc
        return FocusStartContextResponse.model_validate(raw)

    async def start(
        self,
        *,
        user_id: str,
        request: FocusStartRequest,
    ) -> FocusSessionResult:
        fingerprint = _fingerprint(request)
        if isinstance(request, ScheduledFocusStartRequest):
            source_block_id = request.source_block_id
            recovery_minutes = 0
            target_kind = None
            target_id = None
            label = None
        elif isinstance(request, ManualFocusStartRequest):
            source_block_id = None
            recovery_minutes = request.recovery_minutes
            target_kind = request.target_kind
            target_id = request.target_id
            label = request.label
        else:  # pragma: no cover - Pydantic's discriminator is exhaustive.
            raise TypeError("Unsupported Focus start request.")
        try:
            raw = await self._repository.start(
                user_id=user_id,
                request_id=request.request_id,
                request_fingerprint=fingerprint,
                source_kind=request.source_kind,
                source_block_id=source_block_id,
                planned_minutes=request.planned_minutes,
                recovery_minutes=recovery_minutes,
                target_kind=target_kind,
                target_id=target_id,
                label=label,
                now=_utc(self._now()),
            )
        except FocusPersistenceNotFound as exc:
            raise FocusNotFoundError(str(exc)) from exc
        except FocusPersistenceConflict as exc:
            raise FocusConflictError(str(exc)) from exc
        return FocusSessionResponse.model_validate(raw)

    async def finish(
        self,
        *,
        user_id: str,
        session_id: UUID,
        terminal_status: str,
    ) -> FocusSessionResult:
        try:
            raw = await self._repository.finish(
                user_id=user_id,
                session_id=session_id,
                terminal_status=terminal_status,
                now=_utc(self._now()),
            )
        except FocusPersistenceNotFound as exc:
            raise FocusNotFoundError(str(exc)) from exc
        except FocusPersistenceConflict as exc:
            raise FocusConflictError(str(exc)) from exc
        return parse_focus_session(raw)


def _fingerprint(request: FocusStartRequest | OpenEndFocusStartRequest) -> str:
    payload = request.model_dump(mode="json")
    encoded = json.dumps(
        payload,
        sort_keys=True,
        separators=(",", ":"),
        ensure_ascii=True,
    ).encode("utf-8")
    return hashlib.sha256(encoded).hexdigest()


def _utc(value: datetime) -> datetime:
    if value.tzinfo is None or value.utcoffset() is None:
        raise ValueError("Focus service clock must be timezone-aware.")
    return value.astimezone(UTC)
