"""Pure candidate rules; NOT a sender, consent store or delivery claim.

The push dispatcher must atomically recheck consent, quiet hours, dedupe
and the daily cap immediately before reserving a send. Never wire these into the
existing foreground V1 generator, whose source/category contract is unchanged.
"""

from dataclasses import dataclass
from datetime import UTC, date, datetime, time, timedelta
from typing import Literal
from zoneinfo import ZoneInfo

from app.models.personal_patterns import PersonalPatternsResponse
from app.models.sleep_recommendation import SleepRecommendationResponse


@dataclass(frozen=True)
class ImportantReminder:
    kind: Literal["sleep", "deadlines", "pattern"]
    dedupe_key: str
    destination: Literal["/insights", "/planner"]
    title: str
    body: str
    expires_at: datetime


@dataclass(frozen=True)
class ReminderPreferences:
    enabled: bool = False
    sleep: bool = True
    deadlines: bool = True
    patterns: bool = True
    quiet_start: time = time(22)
    quiet_end: time = time(7)


def important_reminders(
    *,
    now: datetime,
    timezone: str,
    preferences: ReminderPreferences,
    reserved_today: int,
    reserved_keys: set[str],
    has_open_deadlines_today: bool = False,
    sleep: SleepRecommendationResponse | None = None,
    patterns: PersonalPatternsResponse | None = None,
    last_pattern_reserved_at: datetime | None = None,
) -> list[ImportantReminder]:
    """Choose at most two useful, short-lived reminders; no catch-up or LLM."""
    if now.utcoffset() is None:
        raise ValueError("An aware evaluation time is required.")
    if reserved_today < 0:
        raise ValueError("Reservation count cannot be negative.")
    zone = ZoneInfo(timezone)
    local = now.astimezone(zone)
    clock = local.time().replace(tzinfo=None)
    start, end = preferences.quiet_start, preferences.quiet_end
    quiet = start == end or (
        start <= clock < end if start < end else clock >= start or clock < end
    )
    if not preferences.enabled or reserved_today >= 2 or quiet:
        return []
    today = local.date()
    candidates: list[ImportantReminder] = []

    if (
        preferences.deadlines
        and has_open_deadlines_today
        and time(9) <= clock < time(9, 15)
    ):
        expiry = _local_instant(today, time(9, 15), zone)
        if expiry is not None:
            candidates.append(
                ImportantReminder(
                    "deadlines",
                    f"deadlines:{today}",
                    "/planner",
                    "Check today's deadlines",
                    "Open Planner to review what is still due today.",
                    expiry,
                )
            )

    if (
        preferences.sleep
        and sleep is not None
        and sleep.status == "ready"
        and sleep.timezone == timezone
        and _fresh(sleep.generated_at, now)
        and sleep.recommendation is not None
        and sleep.recommendation.warning is None
    ):
        bedtime = time.fromisoformat(sleep.recommendation.bedtime.start_local_time)
        for bedtime_date in (today, today + timedelta(days=1)):
            instant = _local_instant(bedtime_date, bedtime, zone)
            if instant is None:
                continue
            reminder_at = instant - timedelta(minutes=30)
            if reminder_at <= now < reminder_at + timedelta(minutes=15):
                candidates.append(
                    ImportantReminder(
                        "sleep",
                        f"sleep:{bedtime_date}",
                        "/insights",
                        "Time to wind down?",
                        "Your observed sleep window is coming up. Review it in Insights.",
                        reminder_at + timedelta(minutes=15),
                    )
                )

    pattern_due = last_pattern_reserved_at is None or (
        last_pattern_reserved_at.utcoffset() is not None
        and now - last_pattern_reserved_at >= timedelta(days=30)
    )
    if (
        preferences.patterns
        and pattern_due
        and time(12) <= clock < time(12, 15)
        and patterns is not None
        and patterns.status == "stable"
        and patterns.timezone == timezone
        and _fresh(patterns.generated_at, now)
        and patterns.planner_preference.eligible
    ):
        # The existing eligible timing projection already requires comparison
        # days, coverage and matching chronological halves. Require a larger
        # effect too; exploratory correlations alone never produce a push.
        strong = any(
            pattern.kind == "focus_timing"
            and pattern.maturity == "stable"
            and pattern.evidence.preferred_group
            == patterns.planner_preference.window_label
            and pattern.evidence.useful_progress_median_delta >= 1
            and pattern.evidence.focus_quality_median_delta >= 0
            and pattern.evidence.completion_rate_delta >= 0
            for pattern in patterns.patterns
        )
        expiry = _local_instant(today, time(12, 15), zone)
        if strong and expiry is not None:
            candidates.append(
                ImportantReminder(
                    "pattern",
                    f"pattern:focus_timing:{today}",
                    "/insights",
                    "A useful pattern is ready",
                    "Review a consistent study-time observation in Insights.",
                    expiry,
                )
            )
    return [
        candidate
        for candidate in candidates
        if candidate.dedupe_key not in reserved_keys
    ][: 2 - reserved_today]


def _fresh(generated_at: datetime, now: datetime) -> bool:
    return generated_at.utcoffset() is not None and timedelta(
        0
    ) <= now - generated_at < timedelta(minutes=15)


def _local_instant(day: date, clock: time, zone: ZoneInfo) -> datetime | None:
    local = datetime.combine(day, clock, tzinfo=zone)
    instant = local.astimezone(UTC)
    # Nonexistent DST times are skipped. An ambiguous time uses the first fold;
    # stable local-date keys must suppress a second send in the later fold.
    if instant.astimezone(zone).replace(tzinfo=None) != local.replace(tzinfo=None):
        return None
    return instant
