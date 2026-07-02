from fastapi import APIRouter, Depends, HTTPException, Request, status

from app.api.deps.auth import Principal, get_current_principal
from app.clients.supabase import SupabaseConfigurationError, SupabaseRestClient
from app.core.config import settings
from app.models.snapshots import SnapshotGenerateRequest, SnapshotGenerateResponse
from app.repositories.snapshot_repository import SupabaseSnapshotRepository
from app.services.snapshot_aggregator import SnapshotAggregator

router = APIRouter(prefix="/snapshots", tags=["snapshots"])


async def get_snapshot_aggregator(request: Request) -> SnapshotAggregator:
    injected_aggregator = getattr(request.app.state, "snapshot_aggregator", None)
    if injected_aggregator is not None:
        return injected_aggregator
    try:
        client = SupabaseRestClient.from_settings(settings)
    except SupabaseConfigurationError as exc:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Snapshot persistence is not configured.",
        ) from exc
    return SnapshotAggregator(repository=SupabaseSnapshotRepository(client))


@router.post("/generate", response_model=SnapshotGenerateResponse)
async def generate_snapshot(
    request: SnapshotGenerateRequest,
    principal: Principal = Depends(get_current_principal),
    aggregator: SnapshotAggregator = Depends(get_snapshot_aggregator),
) -> SnapshotGenerateResponse:
    return await aggregator.generate_snapshot(
        user_id=principal.user_id,
        request=request,
    )
