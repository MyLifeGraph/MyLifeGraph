from typing import assert_never

from fastapi import HTTPException, status

from app.services.calendar_ical_parser import CalendarParseError
from app.services.calendar_integration_service import (
    CalendarConflictError,
    CalendarConnectionNotFoundError,
    CalendarCursorError,
    CalendarCursorStaleError,
)

type CalendarProblemError = (
    CalendarConflictError
    | CalendarConnectionNotFoundError
    | CalendarCursorError
    | CalendarCursorStaleError
    | CalendarParseError
)

CALENDAR_CREATE_ERRORS = (CalendarConflictError,)
CALENDAR_IMPORT_ERRORS = (
    CalendarConnectionNotFoundError,
    CalendarConflictError,
    CalendarParseError,
)
CALENDAR_EVENTS_ERRORS = (
    CalendarConnectionNotFoundError,
    CalendarCursorStaleError,
    CalendarCursorError,
)
CALENDAR_MUTATION_ERRORS = (
    CalendarConnectionNotFoundError,
    CalendarConflictError,
)


def calendar_problem(error: CalendarProblemError) -> HTTPException:
    if isinstance(error, CalendarConnectionNotFoundError):
        return HTTPException(status.HTTP_404_NOT_FOUND, str(error))
    if isinstance(error, (CalendarConflictError, CalendarCursorStaleError)):
        return HTTPException(status.HTTP_409_CONFLICT, str(error))
    if isinstance(error, (CalendarParseError, CalendarCursorError)):
        return HTTPException(status.HTTP_422_UNPROCESSABLE_CONTENT, str(error))
    assert_never(error)
