"""Shared read-only check-in grace boundary; never grants completion credit."""

from datetime import UTC, date, datetime, time, timedelta
from zoneinfo import ZoneInfo


def streak_deadline(entry_date: date, zone: ZoneInfo) -> datetime:
    # 48 elapsed hours after profile-local day end, including DST transitions.
    midnight = datetime.combine(entry_date + timedelta(days=1), time.min)
    # Some IANA zones skip or repeat midnight (or an entire calendar date).
    # Use the earliest instant at/after the boundary, never a guessed offset.
    boundaries = [
        midnight.replace(tzinfo=zone, fold=fold).astimezone(UTC) for fold in (0, 1)
    ]
    end = min(
        instant
        for instant in boundaries
        if instant.astimezone(zone).replace(tzinfo=None) >= midnight
    )
    return end + timedelta(hours=48)
