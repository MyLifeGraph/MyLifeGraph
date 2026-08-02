from typing import assert_never

from fastapi import HTTPException, status

from app.services.personal_patterns_service import (
    PersonalPatternsDataError,
    PersonalPatternsNotFoundError,
    PersonalPatternsUnavailableError,
)

type PersonalPatternsError = (
    PersonalPatternsNotFoundError
    | PersonalPatternsUnavailableError
    | PersonalPatternsDataError
)

PERSONAL_PATTERNS_ERRORS = (
    PersonalPatternsNotFoundError,
    PersonalPatternsUnavailableError,
    PersonalPatternsDataError,
)


def personal_patterns_problem(error: PersonalPatternsError) -> HTTPException:
    if isinstance(error, PersonalPatternsNotFoundError):
        return HTTPException(
            status.HTTP_404_NOT_FOUND,
            "Personal pattern profile is unavailable.",
        )
    if isinstance(error, (PersonalPatternsUnavailableError, PersonalPatternsDataError)):
        return HTTPException(
            status.HTTP_503_SERVICE_UNAVAILABLE,
            "Personal patterns could not be loaded.",
        )
    assert_never(error)
