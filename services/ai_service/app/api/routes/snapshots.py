from fastapi import APIRouter, Depends

from app.api.deps.auth import Principal, get_current_principal
from app.api.deps.services import get_snapshot_aggregator
from app.models.snapshots import SnapshotGenerateRequest, SnapshotGenerateResponse
from app.services.snapshot_aggregator import SnapshotAggregator

router = APIRouter(prefix="/snapshots", tags=["snapshots"])


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
