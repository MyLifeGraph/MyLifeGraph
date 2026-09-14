from datetime import date
from typing import Literal
from uuid import UUID
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from pydantic import AwareDatetime, BaseModel, ConfigDict, Field, field_validator


QUICK_NOTES_CONTRACT_VERSION = "quick-notes-v1"


class QuickNoteCreate(BaseModel):
    model_config = ConfigDict(extra="forbid")

    contract_version: Literal["quick-notes-v1"]
    note_id: UUID
    timezone: str = Field(strict=True, min_length=1, max_length=100)
    text: str = Field(strict=True, min_length=1, max_length=2000)

    @field_validator("text")
    @classmethod
    def valid_text(cls, value: str) -> str:
        if not value.strip() or "\x00" in value:
            raise ValueError("A note requires nonblank text.")
        return value

    @field_validator("timezone")
    @classmethod
    def valid_timezone(cls, value: str) -> str:
        try:
            ZoneInfo(value)
        except (ValueError, ZoneInfoNotFoundError) as error:
            raise ValueError("Invalid timezone.") from error
        return value


class QuickNote(BaseModel):
    model_config = ConfigDict(extra="forbid")

    id: UUID
    text: str = Field(strict=True, min_length=1, max_length=2000)
    entry_date: date
    timezone: str
    created_at: AwareDatetime


class QuickNoteSaved(BaseModel):
    model_config = ConfigDict(extra="forbid")

    contract_version: Literal["quick-notes-v1"] = QUICK_NOTES_CONTRACT_VERSION
    note: QuickNote
    replayed: bool = Field(strict=True)


class QuickNotesPage(BaseModel):
    model_config = ConfigDict(extra="forbid")

    contract_version: Literal["quick-notes-v1"] = QUICK_NOTES_CONTRACT_VERSION
    timezone: str
    notes: list[QuickNote] = Field(max_length=50)
    next_cursor: UUID | None


class QuickNoteDeleted(BaseModel):
    model_config = ConfigDict(extra="forbid")

    contract_version: Literal["quick-notes-v1"] = QUICK_NOTES_CONTRACT_VERSION
    note_id: UUID
    deleted: Literal[True]
