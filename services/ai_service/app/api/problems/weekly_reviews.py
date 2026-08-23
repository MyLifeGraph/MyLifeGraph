from fastapi import HTTPException, status

from app.services.weekly_review_service import WeeklyReviewPeriodError

WEEKLY_REVIEW_PERIOD_ERRORS = (WeeklyReviewPeriodError,)


def weekly_review_problem(error: WeeklyReviewPeriodError) -> HTTPException:
    return HTTPException(status.HTTP_422_UNPROCESSABLE_CONTENT, str(error))
