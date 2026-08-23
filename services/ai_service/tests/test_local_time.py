from datetime import UTC, date, time
from zoneinfo import ZoneInfo

import pytest

from app.services.local_time import (
    LocalTimeResolutionError,
    resolve_local_datetime,
    resolve_local_interval,
)


BERLIN = ZoneInfo("Europe/Berlin")


def test_berlin_dst_gap_fails_closed_with_source_identity() -> None:
    with pytest.raises(LocalTimeResolutionError) as caught:
        resolve_local_datetime(
            local_date=date(2026, 3, 29),
            local_time=time(2, 30),
            zone=BERLIN,
            source_id="setup:lecture-gap",
        )

    assert caught.value.reason == "nonexistent"
    assert caught.value.local_date == date(2026, 3, 29)
    assert caught.value.source_id == "setup:lecture-gap"


def test_berlin_dst_fold_fails_closed_instead_of_choosing_an_offset() -> None:
    with pytest.raises(LocalTimeResolutionError) as caught:
        resolve_local_datetime(
            local_date=date(2026, 10, 25),
            local_time=time(2, 30),
            zone=BERLIN,
            source_id="planner:habit-fold",
        )

    assert caught.value.reason == "ambiguous"
    assert caught.value.source_id == "planner:habit-fold"


def test_cross_midnight_interval_resolves_both_dates_exactly() -> None:
    starts_at, ends_at = resolve_local_interval(
        local_date=date(2026, 7, 29),
        starts_at=time(23, 30),
        ends_at=time(1, 15),
        zone=BERLIN,
        source_id="setup:night-lab",
    )

    assert starts_at.date() == date(2026, 7, 29)
    assert ends_at.date() == date(2026, 7, 30)
    assert starts_at.astimezone(UTC).isoformat() == "2026-07-29T21:30:00+00:00"
    assert ends_at.astimezone(UTC).isoformat() == "2026-07-29T23:15:00+00:00"


def test_same_wall_time_is_re_resolved_after_timezone_change() -> None:
    berlin = resolve_local_datetime(
        local_date=date(2026, 7, 29),
        local_time=time(9),
        zone=BERLIN,
        source_id="setup:seminar",
    )
    utc = resolve_local_datetime(
        local_date=date(2026, 7, 29),
        local_time=time(9),
        zone=ZoneInfo("UTC"),
        source_id="setup:seminar",
    )

    assert berlin.astimezone(UTC) != utc.astimezone(UTC)
