from dataclasses import dataclass
from datetime import UTC, date, datetime, time, timedelta
from zoneinfo import ZoneInfo


@dataclass
class LocalTimeResolutionError(ValueError):
    local_date: date
    local_time: time
    source_id: str
    reason: str

    def __str__(self) -> str:
        return (
            f"Local time {self.local_date.isoformat()} "
            f"{self.local_time.isoformat(timespec='minutes')} for "
            f"{self.source_id} is {self.reason}."
        )


def resolve_local_datetime(
    *,
    local_date: date,
    local_time: time,
    zone: ZoneInfo,
    source_id: str,
) -> datetime:
    """Resolve one wall time only when it maps to exactly one UTC instant."""

    if local_time.tzinfo is not None:
        raise ValueError("Local wall time must be timezone-naive.")
    naive = datetime.combine(local_date, local_time)
    candidates: dict[datetime, datetime] = {}
    for fold in (0, 1):
        candidate = naive.replace(tzinfo=zone, fold=fold)
        utc_candidate = candidate.astimezone(UTC)
        roundtrip = utc_candidate.astimezone(zone)
        if roundtrip.replace(tzinfo=None) == naive:
            candidates[utc_candidate] = roundtrip
    if len(candidates) != 1:
        raise LocalTimeResolutionError(
            local_date=local_date,
            local_time=local_time,
            source_id=source_id,
            reason="nonexistent" if not candidates else "ambiguous",
        )
    return next(iter(candidates.values()))


def resolve_local_interval(
    *,
    local_date: date,
    starts_at: time,
    ends_at: time,
    zone: ZoneInfo,
    source_id: str,
) -> tuple[datetime, datetime]:
    start = resolve_local_datetime(
        local_date=local_date,
        local_time=starts_at,
        zone=zone,
        source_id=source_id,
    )
    end_date = local_date + timedelta(days=1) if ends_at <= starts_at else local_date
    end = resolve_local_datetime(
        local_date=end_date,
        local_time=ends_at,
        zone=zone,
        source_id=source_id,
    )
    if end.astimezone(UTC) <= start.astimezone(UTC):
        raise LocalTimeResolutionError(
            local_date=local_date,
            local_time=starts_at,
            source_id=source_id,
            reason="not an ordered interval",
        )
    return start, end
