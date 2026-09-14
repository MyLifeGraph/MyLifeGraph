from uuid import UUID

from app.clients.supabase import SupabaseRestClient
from app.models.quick_notes import (
    QuickNoteCreate,
    QuickNoteDeleted,
    QuickNoteSaved,
    QuickNotesPage,
)


class QuickNotesService:
    """Explicit owner commands; never writes a Daily Capture or numeric signal."""

    def __init__(self, client: SupabaseRestClient):
        self._client = client

    async def read(self, user_id: str, before: UUID | None = None) -> QuickNotesPage:
        result = await self._client.rpc(
            "read_quick_notes_v1",
            params={"p_user_id": user_id, "p_before": str(before) if before else None},
        )
        return QuickNotesPage.model_validate(result)

    async def save(self, user_id: str, command: QuickNoteCreate) -> QuickNoteSaved:
        result = await self._client.rpc(
            "save_quick_note_v1",
            params={"p_user_id": user_id, "p_request": command.model_dump(mode="json")},
        )
        return QuickNoteSaved.model_validate(result)

    async def delete(self, user_id: str, note_id: UUID) -> QuickNoteDeleted:
        result = await self._client.rpc(
            "delete_quick_note_v1",
            params={"p_user_id": user_id, "p_note_id": str(note_id)},
        )
        return QuickNoteDeleted.model_validate(result)
