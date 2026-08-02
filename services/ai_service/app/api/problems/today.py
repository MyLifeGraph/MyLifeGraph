from fastapi import HTTPException, status

from app.services.today_overview_service import TodayOverviewUnavailableError

TODAY_OVERVIEW_ERRORS = (TodayOverviewUnavailableError,)


def today_overview_problem(error: TodayOverviewUnavailableError) -> HTTPException:
    return HTTPException(status.HTTP_503_SERVICE_UNAVAILABLE, str(error))
