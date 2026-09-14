from uuid import UUID

import httpx
from fastapi import APIRouter, Depends, HTTPException, Request, Response
from fastapi.exceptions import RequestValidationError
from fastapi.routing import APIRoute

from app.api.deps.auth import Principal, get_current_principal
from app.api.deps.supabase import get_supabase_client
from app.clients.supabase import SupabaseConfigurationError
from app.models.quick_notes import (
    QuickNoteCreate,
    QuickNoteDeleted,
    QuickNoteSaved,
    QuickNotesPage,
)
from app.services.quick_notes_service import QuickNotesService


class PrivateNoteRoute(APIRoute):
    def get_route_handler(self):
        original = super().get_route_handler()

        async def handler(request):
            try:
                return await original(request)
            except RequestValidationError:
                raise HTTPException(422, "Invalid note request.") from None

        return handler


router = APIRouter(
    prefix="/quick-notes", tags=["quick-notes"], route_class=PrivateNoteRoute
)


def get_quick_notes_service(request: Request) -> QuickNotesService:
    try:
        return QuickNotesService(get_supabase_client(request))
    except SupabaseConfigurationError as error:
        raise _problem(error) from error


def _problem(error: Exception) -> HTTPException:
    status, message = 503, "Notes are unavailable. Keep your text and retry."
    if isinstance(error, httpx.HTTPStatusError):
        code = error.response.status_code
        if code == 409:
            status, message = (
                409,
                "This note changed or was deleted. Reload your notes.",
            )
        elif code == 404:
            status, message = 404, "Note not found."
        elif code in (400, 403):
            status, message = 422, "The note or account timezone is no longer valid."
    return HTTPException(status_code=status, detail=message)


@router.get("", response_model=QuickNotesPage)
async def read_quick_notes(
    response: Response,
    before: UUID | None = None,
    principal: Principal = Depends(get_current_principal),
    service: QuickNotesService = Depends(get_quick_notes_service),
):
    response.headers["Cache-Control"] = "no-store"
    try:
        return await service.read(principal.user_id, before)
    except (httpx.HTTPError, ValueError, SupabaseConfigurationError) as error:
        raise _problem(error) from error


@router.post("", response_model=QuickNoteSaved)
async def save_quick_note(
    command: QuickNoteCreate,
    response: Response,
    principal: Principal = Depends(get_current_principal),
    service: QuickNotesService = Depends(get_quick_notes_service),
):
    response.headers["Cache-Control"] = "no-store"
    try:
        return await service.save(principal.user_id, command)
    except (httpx.HTTPError, ValueError, SupabaseConfigurationError) as error:
        raise _problem(error) from error


@router.delete("/{note_id}", response_model=QuickNoteDeleted)
async def delete_quick_note(
    note_id: UUID,
    response: Response,
    principal: Principal = Depends(get_current_principal),
    service: QuickNotesService = Depends(get_quick_notes_service),
):
    response.headers["Cache-Control"] = "no-store"
    try:
        return await service.delete(principal.user_id, note_id)
    except (httpx.HTTPError, ValueError, SupabaseConfigurationError) as error:
        raise _problem(error) from error
