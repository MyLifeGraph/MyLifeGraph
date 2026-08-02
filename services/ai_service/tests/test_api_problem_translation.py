from collections.abc import Callable

import pytest
from fastapi import HTTPException

from app.api.problems.account import (
    account_delete_problem,
    account_export_problem,
    account_preparation_budget_problem,
    account_profile_problem,
)
from app.api.problems.calendar_integrations import calendar_problem
from app.api.problems.coach import (
    coach_service_problem,
    coach_unavailable_problem,
    invalid_coach_request_problem,
)
from app.api.problems.daily_capture import daily_capture_problem
from app.api.problems.deadline_plans import deadline_plan_problem
from app.api.problems.feedback import feedback_problem
from app.api.problems.focus import focus_problem
from app.api.problems.insights import personal_patterns_problem
from app.api.problems.intake import intake_problem
from app.api.problems.learning import (
    learning_clear_problem,
    learning_read_problem,
    learning_update_problem,
)
from app.api.problems.notifications import (
    notification_action_problem,
    notification_delivery_problem,
    notification_settings_read_problem,
    notification_settings_update_problem,
)
from app.api.problems.planner import planner_problem
from app.api.problems.today import today_overview_problem
from app.api.problems.weekly_reviews import weekly_review_problem
from app.services.account_service import (
    AccountConflictError,
    AccountExportTooLargeError,
    AccountNotFoundError,
    AccountOutcomeUnknownError,
    AccountUnavailableError,
    InvalidAccountTimezoneError,
    InvalidPreparationBudgetError,
)
from app.services.calendar_ical_parser import CalendarParseError
from app.services.calendar_integration_service import (
    CalendarConflictError,
    CalendarConnectionNotFoundError,
    CalendarCursorError,
    CalendarCursorStaleError,
)
from app.services.coach_service import CoachServiceError
from app.services.daily_capture_service import (
    DailyCaptureConflictError,
    DailyCaptureUnavailableError,
    InvalidDailyCaptureError,
)
from app.services.feedback_service import FeedbackConflictError, FeedbackNotFoundError
from app.services.focus_service import FocusConflictError, FocusNotFoundError
from app.services.intake_service import IntakeRevisionConflict
from app.services.learning_service import (
    LearningConflictError,
    LearningContractError,
    LearningNotFoundError,
    LearningOutcomeUnknownError,
    LearningUnavailableError,
)
from app.services.notification_service import (
    NotificationConflictError,
    NotificationNotFoundError,
    NotificationOutcomeUnknownError,
    NotificationServiceUnavailableError,
)
from app.services.personal_patterns_service import (
    PersonalPatternsDataError,
    PersonalPatternsNotFoundError,
    PersonalPatternsUnavailableError,
)
from app.services.planner_errors import (
    DeadlinePlanConflictError,
    DeadlinePlanNotFoundError,
    DeadlinePlanValidationError,
    PlannerConflictError,
    PlannerNotFoundError,
    PlannerValidationError,
)
from app.services.today_overview_service import TodayOverviewUnavailableError
from app.services.weekly_review_service import WeeklyReviewPeriodError


ProblemTranslator = Callable[[object], HTTPException]
_DETAIL = "service detail"


@pytest.mark.parametrize(
    ("translator", "error", "expected_status", "expected_detail"),
    [
        (account_profile_problem, InvalidAccountTimezoneError(_DETAIL), 422, _DETAIL),
        (
            account_profile_problem,
            AccountNotFoundError(_DETAIL),
            404,
            "Account profile is unavailable.",
        ),
        (account_profile_problem, AccountConflictError(_DETAIL), 409, _DETAIL),
        (
            account_profile_problem,
            AccountOutcomeUnknownError(_DETAIL),
            502,
            "Account profile update outcome could not be determined.",
        ),
        (
            account_profile_problem,
            AccountUnavailableError(_DETAIL),
            503,
            "Account profile could not be updated.",
        ),
        (
            account_preparation_budget_problem,
            InvalidPreparationBudgetError(_DETAIL),
            422,
            _DETAIL,
        ),
        (
            account_preparation_budget_problem,
            AccountNotFoundError(_DETAIL),
            404,
            "Account profile is unavailable.",
        ),
        (
            account_preparation_budget_problem,
            AccountConflictError(_DETAIL),
            409,
            _DETAIL,
        ),
        (
            account_preparation_budget_problem,
            AccountOutcomeUnknownError(_DETAIL),
            502,
            "Preparation budget update outcome could not be determined.",
        ),
        (
            account_preparation_budget_problem,
            AccountUnavailableError(_DETAIL),
            503,
            "Preparation budget could not be updated.",
        ),
        (
            account_export_problem,
            AccountExportTooLargeError(_DETAIL),
            413,
            _DETAIL,
        ),
        (
            account_export_problem,
            AccountUnavailableError(_DETAIL),
            503,
            "Account export could not be generated.",
        ),
        (
            account_delete_problem,
            AccountNotFoundError(_DETAIL),
            404,
            "Account is unavailable.",
        ),
        (
            account_delete_problem,
            AccountOutcomeUnknownError(_DETAIL),
            502,
            "Account deletion outcome could not be determined.",
        ),
        (
            account_delete_problem,
            AccountUnavailableError(_DETAIL),
            503,
            "Account deletion could not be completed.",
        ),
        (calendar_problem, CalendarConnectionNotFoundError(_DETAIL), 404, _DETAIL),
        (calendar_problem, CalendarConflictError(_DETAIL), 409, _DETAIL),
        (calendar_problem, CalendarCursorStaleError(_DETAIL), 409, _DETAIL),
        (calendar_problem, CalendarCursorError(_DETAIL), 422, _DETAIL),
        (calendar_problem, CalendarParseError(_DETAIL), 422, _DETAIL),
        (daily_capture_problem, InvalidDailyCaptureError(_DETAIL), 422, _DETAIL),
        (daily_capture_problem, DailyCaptureConflictError(_DETAIL), 409, _DETAIL),
        (
            daily_capture_problem,
            DailyCaptureUnavailableError(_DETAIL),
            503,
            "Daily Capture could not be saved.",
        ),
        (deadline_plan_problem, DeadlinePlanNotFoundError(_DETAIL), 404, _DETAIL),
        (deadline_plan_problem, DeadlinePlanConflictError(_DETAIL), 409, _DETAIL),
        (deadline_plan_problem, DeadlinePlanValidationError(_DETAIL), 422, _DETAIL),
        (feedback_problem, FeedbackConflictError(_DETAIL), 409, _DETAIL),
        (feedback_problem, FeedbackNotFoundError(_DETAIL), 404, _DETAIL),
        (focus_problem, FocusNotFoundError(_DETAIL), 404, _DETAIL),
        (focus_problem, FocusConflictError(_DETAIL), 409, _DETAIL),
        (
            personal_patterns_problem,
            PersonalPatternsNotFoundError(_DETAIL),
            404,
            "Personal pattern profile is unavailable.",
        ),
        (
            personal_patterns_problem,
            PersonalPatternsUnavailableError(_DETAIL),
            503,
            "Personal patterns could not be loaded.",
        ),
        (
            personal_patterns_problem,
            PersonalPatternsDataError(_DETAIL),
            503,
            "Personal patterns could not be loaded.",
        ),
        (
            learning_read_problem,
            LearningNotFoundError(_DETAIL),
            404,
            "Personal learning settings are unavailable.",
        ),
        (
            learning_read_problem,
            LearningUnavailableError(_DETAIL),
            503,
            "Personal learning settings could not be loaded.",
        ),
        (
            learning_read_problem,
            LearningContractError(_DETAIL),
            503,
            "Personal learning settings could not be loaded.",
        ),
        (learning_update_problem, LearningConflictError(_DETAIL), 409, _DETAIL),
        (
            learning_update_problem,
            LearningNotFoundError(_DETAIL),
            404,
            "Personal learning settings are unavailable.",
        ),
        (
            learning_update_problem,
            LearningOutcomeUnknownError(_DETAIL),
            502,
            "Personal learning update outcome could not be determined.",
        ),
        (
            learning_update_problem,
            LearningContractError(_DETAIL),
            502,
            "Personal learning update returned an invalid result.",
        ),
        (
            learning_update_problem,
            LearningUnavailableError(_DETAIL),
            503,
            "Personal learning settings could not be updated.",
        ),
        (learning_clear_problem, LearningConflictError(_DETAIL), 409, _DETAIL),
        (
            learning_clear_problem,
            LearningNotFoundError(_DETAIL),
            404,
            "Personal learning settings are unavailable.",
        ),
        (
            learning_clear_problem,
            LearningOutcomeUnknownError(_DETAIL),
            502,
            "Focus reflection clear outcome could not be determined.",
        ),
        (
            learning_clear_problem,
            LearningContractError(_DETAIL),
            502,
            "Focus reflection clear returned an invalid result.",
        ),
        (
            learning_clear_problem,
            LearningUnavailableError(_DETAIL),
            503,
            "Focus reflection history could not be cleared.",
        ),
        (
            notification_settings_read_problem,
            NotificationNotFoundError(_DETAIL),
            404,
            "Notification settings are unavailable.",
        ),
        (
            notification_settings_read_problem,
            NotificationServiceUnavailableError(_DETAIL),
            503,
            "Notification settings persistence is unavailable.",
        ),
        (
            notification_settings_update_problem,
            NotificationNotFoundError(_DETAIL),
            404,
            "Notification settings are unavailable.",
        ),
        (
            notification_settings_update_problem,
            NotificationConflictError(_DETAIL),
            409,
            _DETAIL,
        ),
        (
            notification_settings_update_problem,
            NotificationOutcomeUnknownError(_DETAIL),
            502,
            "Notification settings outcome could not be determined.",
        ),
        (
            notification_settings_update_problem,
            NotificationServiceUnavailableError(_DETAIL),
            503,
            "Notification settings persistence is unavailable.",
        ),
        (
            notification_action_problem,
            NotificationNotFoundError(_DETAIL),
            404,
            "Notification is unavailable.",
        ),
        (
            notification_action_problem,
            NotificationConflictError(_DETAIL),
            409,
            _DETAIL,
        ),
        (
            notification_action_problem,
            NotificationOutcomeUnknownError(_DETAIL),
            502,
            "Notification action outcome could not be determined.",
        ),
        (
            notification_action_problem,
            NotificationServiceUnavailableError(_DETAIL),
            503,
            "Notification lifecycle persistence is unavailable.",
        ),
        (
            notification_delivery_problem,
            NotificationNotFoundError(_DETAIL),
            404,
            "Notification is unavailable.",
        ),
        (
            notification_delivery_problem,
            NotificationConflictError(_DETAIL),
            409,
            _DETAIL,
        ),
        (
            notification_delivery_problem,
            NotificationOutcomeUnknownError(_DETAIL),
            502,
            "In-app delivery outcome could not be determined.",
        ),
        (
            notification_delivery_problem,
            NotificationServiceUnavailableError(_DETAIL),
            503,
            "In-app delivery persistence is unavailable.",
        ),
        (planner_problem, PlannerNotFoundError(_DETAIL), 404, _DETAIL),
        (planner_problem, PlannerConflictError(_DETAIL), 409, _DETAIL),
        (planner_problem, PlannerValidationError(_DETAIL), 422, _DETAIL),
        (today_overview_problem, TodayOverviewUnavailableError(_DETAIL), 503, _DETAIL),
        (weekly_review_problem, WeeklyReviewPeriodError(_DETAIL), 422, _DETAIL),
    ],
)
def test_service_problem_matrix_is_exact(
    translator: ProblemTranslator,
    error: object,
    expected_status: int,
    expected_detail: str,
) -> None:
    problem = translator(error)

    assert problem.status_code == expected_status
    assert problem.detail == expected_detail
    assert problem.headers is None


def test_intake_conflict_problem_preserves_structured_detail() -> None:
    problem = intake_problem(
        IntakeRevisionConflict(
            "A newer revision exists.",
            current_revision=7,
            pending_request_id="a-request-id",
        ),
    )

    assert problem.status_code == 409
    assert problem.detail == {
        "code": "intake_revision_conflict",
        "message": "A newer revision exists.",
        "current_revision": 7,
        "pending_request_id": "a-request-id",
    }
    assert problem.headers is None


def test_coach_problem_matrix_preserves_structured_details() -> None:
    service_problem = coach_service_problem(
        CoachServiceError(
            "rate_limited",
            "The daily Coach limit has been reached.",
            retryable=False,
            status_code=429,
        ),
    )
    invalid_problem = invalid_coach_request_problem()
    unavailable_problem = coach_unavailable_problem()

    assert (service_problem.status_code, service_problem.detail) == (
        429,
        {
            "code": "rate_limited",
            "message": "The daily Coach limit has been reached.",
            "retryable": False,
        },
    )
    assert (invalid_problem.status_code, invalid_problem.detail) == (
        422,
        {
            "code": "invalid_request",
            "message": "The Coach request body does not match its strict contract.",
            "retryable": False,
        },
    )
    assert (unavailable_problem.status_code, unavailable_problem.detail) == (
        503,
        {
            "code": "provider_failure",
            "message": "The Coach service is temporarily unavailable.",
            "retryable": True,
        },
    )
    assert service_problem.headers is None
    assert invalid_problem.headers is None
    assert unavailable_problem.headers is None
