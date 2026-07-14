from datetime import UTC, datetime, timedelta

from fastapi import APIRouter, Depends, HTTPException, Request, Response, status

from app.api.deps.auth import Principal, get_current_principal
from app.clients.supabase import SupabaseConfigurationError, SupabaseRestClient
from app.core.config import settings
from app.models.account import (
    AccountDeleteRequest,
    AccountExportResponse,
    AccountProfileResponse,
    AccountProfileUpdateRequest,
)
from app.repositories.account_repository import (
    AccountDeletionOutcomeUnknownError,
    AccountNotFoundError,
    AccountPersistenceError,
    AccountProfileUpdateOutcomeUnknownError,
    SupabaseAccountRepository,
)
from app.services.account_service import (
    AccountExportTooLargeError,
    AccountService,
    InvalidAccountTimezoneError,
)


router = APIRouter(prefix="/account", tags=["account"])

_RECENT_AUTHENTICATION_MAX_AGE = timedelta(minutes=15)
_RECENT_AUTHENTICATION_FUTURE_TOLERANCE = timedelta(minutes=1)
_RECENT_AUTHENTICATION_REQUIRED_DETAIL = (
    "Recent authentication is required before account deletion."
)


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


async def get_account_service(request: Request) -> AccountService:
    injected = getattr(request.app.state, "account_service", None)
    if injected is not None:
        return injected
    try:
        client = SupabaseRestClient.from_settings(settings)
    except SupabaseConfigurationError as exc:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Account persistence is not configured.",
        ) from exc
    return AccountService(repository=SupabaseAccountRepository(client))


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
            timezone=body.timezone,
        )
    except InvalidAccountTimezoneError as exc:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_CONTENT,
            detail=str(exc),
        ) from exc
    except AccountNotFoundError as exc:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Account profile is unavailable.",
        ) from exc
    except AccountProfileUpdateOutcomeUnknownError as exc:
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail="Account profile update outcome could not be determined.",
        ) from exc
    except AccountPersistenceError as exc:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Account profile could not be updated.",
        ) from exc


@router.get(
    "/export",
    response_model=AccountExportResponse,
)
async def export_account(
    principal: Principal = Depends(get_current_principal),
    service: AccountService = Depends(get_account_service),
) -> Response:
    try:
        export = await service.export_account(user_id=principal.user_id)
    except AccountExportTooLargeError as exc:
        raise HTTPException(
            status_code=status.HTTP_413_CONTENT_TOO_LARGE,
            detail=str(exc),
        ) from exc
    except AccountPersistenceError as exc:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Account export could not be generated.",
        ) from exc
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
    principal: Principal = Depends(get_current_principal),
    service: AccountService = Depends(get_account_service),
) -> Response:
    _require_recent_authentication(principal, now=datetime.now(UTC))
    try:
        await service.delete_account(
            user_id=principal.user_id,
            confirmation=body.confirmation,
        )
    except AccountNotFoundError as exc:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Account is unavailable.",
        ) from exc
    except AccountDeletionOutcomeUnknownError as exc:
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail="Account deletion outcome could not be determined.",
        ) from exc
    except AccountPersistenceError as exc:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Account deletion could not be completed.",
        ) from exc
    return Response(status_code=status.HTTP_204_NO_CONTENT)
