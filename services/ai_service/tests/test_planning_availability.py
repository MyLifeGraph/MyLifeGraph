from datetime import UTC, date, datetime, timedelta
from zoneinfo import ZoneInfo

from app.services.planning_availability import (
    BusySources,
    allocate_task_intervals,
    busy_intervals_by_day,
    choose_recurring_habit_slots,
    is_unambiguous_local,
)


def test_task_allocation_splits_on_five_minutes_and_reports_exact_remainder() -> None:
    zone = ZoneInfo("UTC")
    blocks = allocate_task_intervals(
        starts_on=date(2026, 7, 20),
        ends_on=date(2026, 7, 22),
        total_minutes=32,
        preferred_session_minutes=20,
        max_daily_minutes=480,
        zone=zone,
        local_now=datetime(2026, 7, 20, 7, tzinfo=UTC),
        energy_window="morning",
        busy_sources=BusySources(),
        duration_increment_minutes=5,
    )

    assert [block.minutes for block in blocks] == [20, 10]
    assert 32 - sum(block.minutes for block in blocks) == 2
    assert all(block.starts_at.minute % 5 == 0 for block in blocks)
    assert all(block.ends_at > block.starts_at for block in blocks)
    assert blocks[0].starts_at.date() != blocks[1].starts_at.date()


def test_all_busy_sources_are_authoritative_and_never_overlap() -> None:
    zone = ZoneInfo("UTC")
    busy = BusySources(
        recurring_commitments=[
            {"weekday": 1, "starts_at": "08:00:00", "ends_at": "10:30:00"},
        ],
        timed_intervals=[
            {
                "starts_at": "2026-07-20T10:30:00+00:00",
                "ends_at": "2026-07-20T21:00:00+00:00",
            },
        ],
        all_day_intervals=[
            {"starts_on": "2026-07-21", "ends_on": "2026-07-22"},
        ],
    )
    blocks = allocate_task_intervals(
        starts_on=date(2026, 7, 20),
        ends_on=date(2026, 7, 22),
        total_minutes=120,
        preferred_session_minutes=60,
        max_daily_minutes=120,
        zone=zone,
        local_now=datetime(2026, 7, 20, 7, tzinfo=UTC),
        energy_window="morning",
        busy_sources=busy,
        duration_increment_minutes=5,
    )

    assert sum(block.minutes for block in blocks) == 120
    assert all(block.starts_at.date() == date(2026, 7, 22) for block in blocks)


def test_habit_slot_must_fit_every_occurrence_in_four_week_horizon() -> None:
    zone = ZoneInfo("UTC")
    one_off_conflicts = [
        {
            "starts_at": datetime(2026, 7, 20, 8, tzinfo=UTC)
            + timedelta(days=7 * offset),
            "ends_at": datetime(2026, 7, 20, 9, tzinfo=UTC)
            + timedelta(days=7 * offset),
        }
        for offset in range(4)
    ]

    slots, unplaced = choose_recurring_habit_slots(
        weekdays=[1],
        duration_minutes=30,
        horizon_starts_on=date(2026, 7, 20),
        horizon_days=28,
        zone=zone,
        local_now=datetime(2026, 7, 20, 6, tzinfo=UTC),
        energy_window="morning",
        busy_sources=BusySources(timed_intervals=one_off_conflicts),
    )

    assert unplaced == []
    assert len(slots) == 1
    assert slots[0].weekday == 1
    assert slots[0].starts_at.hour == 9
    assert slots[0].minutes == 30


def test_dst_gap_and_fold_wall_times_are_not_treated_as_safe_slots() -> None:
    zone = ZoneInfo("Europe/Berlin")

    assert not is_unambiguous_local(
        datetime(2026, 3, 29, 2, 30, tzinfo=zone),
        zone,
    )
    assert not is_unambiguous_local(
        datetime(2026, 10, 25, 2, 30, tzinfo=zone),
        zone,
    )
    assert is_unambiguous_local(
        datetime(2026, 3, 29, 8, 0, tzinfo=zone),
        zone,
    )


def test_setup_recurring_commitment_applies_only_inside_semester_dates() -> None:
    zone = ZoneInfo("UTC")
    days = [date(2026, 7, 20), date(2026, 7, 27), date(2026, 8, 3)]

    busy = busy_intervals_by_day(
        days=days,
        sources=BusySources(
            recurring_commitments=[
                {
                    "weekday": 1,
                    "starts_at": "09:00:00",
                    "ends_at": "10:30:00",
                    "metadata": {
                        "managed_by": "setup",
                        "valid_from": "2026-07-27",
                        "valid_until": "2026-08-02",
                    },
                },
            ],
        ),
        zone=zone,
        local_now=datetime(2026, 7, 19, 12, tzinfo=UTC),
    )

    assert busy[date(2026, 7, 20)] == []
    assert busy[date(2026, 7, 27)] == [
        (
            datetime(2026, 7, 27, 9, tzinfo=UTC),
            datetime(2026, 7, 27, 10, 30, tzinfo=UTC),
        ),
    ]
    assert busy[date(2026, 8, 3)] == []
