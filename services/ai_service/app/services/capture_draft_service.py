import hashlib
import json
from uuid import UUID

from app.coach_turn_lifecycle import CoachServiceError
from app.models.capture_draft import CaptureDraftRequest, CaptureDraftResponse
from app.models.coach import CoachAgentRequest
from app.services.capture_draft_operation import CaptureDraftOperation
from app.services.coach_agent_service import CoachAgentService
from app.services.coach_safety import pre_provider_safety


class CaptureDraftService:
    def __init__(self, coach: CoachAgentService) -> None:
        self._coach = coach

    async def extract(self, *, user_id: str, request: CaptureDraftRequest) -> CaptureDraftResponse:
        timezone, entry_date = await self._coach.capture_draft_profile(user_id=user_id)
        if pre_provider_safety(request.transcript, force_english=True).bypass_provider:
            raise CoachServiceError(
                "invalid_request", "Please review this check-in manually.",
                retryable=False, status_code=422,
            )
        operation = CaptureDraftOperation(
            request=request, owner_id=UUID(user_id), entry_date=entry_date, timezone=timezone,
        )
        # Only purpose-bound hashes and date identity reach Coach request metadata.
        identity = json.dumps({
            "purpose": "daily_capture_draft",
            "version": request.contract_version,
            "branch": request.branch,
            "entry_date": entry_date.isoformat(),
            "timezone": timezone,
            "transcript_sha256": hashlib.sha256(request.transcript.encode("utf-8")).hexdigest(),
        }, sort_keys=True, separators=(",", ":"))
        coach = self._coach.for_capture_draft(operation)
        try:
            await coach.respond(
                user_id=user_id,
                request=CoachAgentRequest(
                    contract_version="coach-request-v4", request_id=request.request_id, message=identity,
                ),
            )
        except CoachServiceError as exc:
            if exc.detail.code != "history_deleted":
                raise
            raise CoachServiceError(
                "draft_expired", "This draft is no longer available. Review your text and try again.",
                retryable=False, status_code=409,
            ) from exc
        if operation.proposal is None:
            # Completed operations intentionally persist no personal draft.
            # Never redispatch this UUID or invent a proposal on replay.
            raise CoachServiceError(
                "draft_expired", "This draft is no longer available. Review your text and try again.",
                retryable=False, status_code=409,
            )
        current_timezone, current_date = await self._coach.capture_draft_profile(user_id=user_id)
        if (current_timezone, current_date) != (timezone, entry_date):
            raise CoachServiceError(
                "draft_expired", "Your local day changed. Please review this check-in again.",
                retryable=False, status_code=409,
            )
        return operation.proposal
