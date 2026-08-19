from datetime import UTC, datetime, timedelta

from fastapi import APIRouter, Depends, HTTPException, Response, status

from app.api.deps.auth import (
    Principal,
    get_current_principal,
    get_verified_principal,
)
from app.api.deps.services import get_account_service
from app.api.problems.account import (
    ACCOUNT_DELETE_ERRORS,
    ACCOUNT_EXPORT_ERRORS,
    ACCOUNT_PREPARATION_BUDGET_ERRORS,
    ACCOUNT_PROFILE_ERRORS,
    ACCOUNT_PARTICIPATION_ERRORS,
    account_delete_problem,
    account_export_problem,
    account_preparation_budget_problem,
    account_profile_problem,
    account_participation_problem,
)
from app.models.account import (
    AccountDeleteRequest,
    AccountExportResponse,
    AccountPreparationBudgetResponse,
    AccountPreparationBudgetUpdateRequest,
    AccountProfileResponse,
    AccountProfileUpdateRequest,
    PilotParticipationRequest,
    PilotParticipationResponse,
)
from app.services.account_service import (
    AccountService,
)


router = APIRouter(prefix="/account", tags=["account"])

_RECENT_AUTHENTICATION_MAX_AGE = timedelta(minutes=15)
_RECENT_AUTHENTICATION_FUTURE_TOLERANCE = timedelta(minutes=1)
_RECENT_AUTHENTICATION_REQUIRED_DETAIL = (
    "Recent authentication is required before account deletion."
)


@router.post(
    "/pilot-participation",
    response_model=PilotParticipationResponse,
)
async def accept_pilot_participation(
    body: PilotParticipationRequest,
    principal: Principal = Depends(get_verified_principal),
    service: AccountService = Depends(get_account_service),
) -> PilotParticipationResponse:
    try:
        return await service.accept_pilot_participation(
            user_id=principal.user_id,
            notice_version=body.notice_version,
        )
    except ACCOUNT_PARTICIPATION_ERRORS as exc:
        raise account_participation_problem(exc) from exc


def _require_recent_authentication(
    principal: Principal,
    *,
    now: datetime,
) -> None:
    authenticated_at = principal.authenticated_at
    if authenticated_at is None or authenticated_at.utcoffset() is None:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail=_RECENT_AUTHENTICATION_REQUIRED_DETAIL,
        )

    age = now - authenticated_at.astimezone(UTC)
    if (
        age > _RECENT_AUTHENTICATION_MAX_AGE
        or age < -_RECENT_AUTHENTICATION_FUTURE_TOLERANCE
    ):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail=_RECENT_AUTHENTICATION_REQUIRED_DETAIL,
        )


@router.patch(
    "/profile",
    response_model=AccountProfileResponse,
)
async def update_account_profile(
    body: AccountProfileUpdateRequest,
    principal: Principal = Depends(get_current_principal),
    service: AccountService = Depends(get_account_service),
) -> AccountProfileResponse:
    try:
        return await service.update_timezone(
            user_id=principal.user_id,
            request_id=body.request_id,
            expected_revision=body.expected_revision,
            timezone=body.timezone,
        )
    except ACCOUNT_PROFILE_ERRORS as exc:
        raise account_profile_problem(exc) from exc


@router.patch(
    "/preparation-budget",
    response_model=AccountPreparationBudgetResponse,
)
async def update_account_preparation_budget(
    body: AccountPreparationBudgetUpdateRequest,
    principal: Principal = Depends(get_current_principal),
    service: AccountService = Depends(get_account_service),
) -> AccountPreparationBudgetResponse:
    try:
        return await service.update_preparation_budget(
            user_id=principal.user_id,
            request_id=body.request_id,
            expected_revision=body.expected_revision,
            minutes=body.daily_preparation_budget_minutes,
        )
    except ACCOUNT_PREPARATION_BUDGET_ERRORS as exc:
        raise account_preparation_budget_problem(exc) from exc


@router.get(
    "/export",
    response_model=AccountExportResponse,
)
async def export_account(
    principal: Principal = Depends(get_verified_principal),
    service: AccountService = Depends(get_account_service),
) -> Response:
    try:
        export = await service.export_account(user_id=principal.user_id)
    except ACCOUNT_EXPORT_ERRORS as exc:
        raise account_export_problem(exc) from exc
    return Response(
        content=export.content,
        media_type="application/json",
        headers={
            "Cache-Control": "no-store",
            "Content-Disposition": (
                'attachment; filename="mylifegraph-account-export.json"'
            ),
        },
    )


@router.delete("", status_code=status.HTTP_204_NO_CONTENT)
async def delete_account(
    body: AccountDeleteRequest,
    principal: Principal = Depends(get_verified_principal),
    service: AccountService = Depends(get_account_service),
) -> Response:
    _require_recent_authentication(principal, now=datetime.now(UTC))
    try:
        await service.delete_account(
            user_id=principal.user_id,
            confirmation=body.confirmation,
        )
    except ACCOUNT_DELETE_ERRORS as exc:
        raise account_delete_problem(exc) from exc
    return Response(status_code=status.HTTP_204_NO_CONTENT)
