from fastapi import HTTPException, status

from app.services.intake_service import IntakeRevisionConflict

INTAKE_COMPLETE_ERRORS = (IntakeRevisionConflict,)


def intake_problem(error: IntakeRevisionConflict) -> HTTPException:
    return HTTPException(
        status.HTTP_409_CONFLICT,
        error.as_detail(),
    )
