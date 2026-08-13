from fastapi import HTTPException, status

from app.services.today_overview_service import TodayOverviewUnavailableError
from app.services.today_week_agenda_service import TodayWeekAgendaUnavailableError

TODAY_OVERVIEW_ERRORS = (TodayOverviewUnavailableError,)
TODAY_WEEK_AGENDA_ERRORS = (TodayWeekAgendaUnavailableError,)


def today_overview_problem(error: TodayOverviewUnavailableError) -> HTTPException:
    return HTTPException(status.HTTP_503_SERVICE_UNAVAILABLE, str(error))


def today_week_agenda_problem(
    error: TodayWeekAgendaUnavailableError,
) -> HTTPException:
    return HTTPException(status.HTTP_503_SERVICE_UNAVAILABLE, str(error))
