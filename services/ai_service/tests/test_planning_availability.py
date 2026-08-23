from datetime import UTC, date, datetime, timedelta, timezone
from zoneinfo import ZoneInfo

import pytest

from app.services.planning_availability import (
    BusySources,
    allocate_task_intervals,
    busy_intervals_by_day,
    ceil_local_five_minutes,
    choose_recurring_habit_slots,
    is_unambiguous_local,
    round_up_quarter_hour,
    used_setup_timing_fallback,
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


def test_earliest_clustered_allocation_exhausts_today_before_advancing() -> None:
    zone = ZoneInfo("UTC")
    common = {
        "starts_on": date(2026, 7, 20),
        "ends_on": date(2026, 7, 22),
        "total_minutes": 180,
        "preferred_session_minutes": 60,
        "max_daily_minutes": 180,
        "zone": zone,
        "local_now": datetime(2026, 7, 19, 12, tzinfo=UTC),
        "energy_window": "morning",
        "busy_sources": BusySources(),
        "duration_increment_minutes": 5,
    }

    spread = allocate_task_intervals(**common)
    clustered = allocate_task_intervals(
        **common,
        allocation_policy="earliest_clustered",
    )

    assert [block.starts_at.date() for block in spread] == [
        date(2026, 7, 20),
        date(2026, 7, 21),
        date(2026, 7, 22),
    ]
    assert {block.starts_at.date() for block in clustered} == {
        date(2026, 7, 20),
    }
    assert sum(block.minutes for block in clustered) == 180


def test_earliest_clustered_allocation_stops_at_the_block_bound() -> None:
    blocks = allocate_task_intervals(
        starts_on=date(2026, 7, 20),
        ends_on=date(2026, 7, 22),
        total_minutes=60,
        preferred_session_minutes=5,
        max_daily_minutes=360,
        zone=ZoneInfo("UTC"),
        local_now=datetime(2026, 7, 19, 12, tzinfo=UTC),
        energy_window="morning",
        busy_sources=BusySources(),
        max_blocks=3,
        duration_increment_minutes=5,
        allocation_policy="earliest_clustered",
    )

    assert len(blocks) == 3
    assert [block.minutes for block in blocks] == [5, 5, 5]
    assert {block.starts_at.date() for block in blocks} == {date(2026, 7, 20)}


def test_clustered_allocation_obeys_busy_time_and_account_capacity() -> None:
    zone = ZoneInfo("UTC")
    blocks = allocate_task_intervals(
        starts_on=date(2026, 7, 20),
        ends_on=date(2026, 7, 22),
        total_minutes=360,
        preferred_session_minutes=60,
        max_daily_minutes=360,
        zone=zone,
        local_now=datetime(2026, 7, 19, 12, tzinfo=UTC),
        energy_window="morning",
        busy_sources=BusySources(
            timed_intervals=[
                {
                    "starts_at": "2026-07-20T09:00:00+00:00",
                    "ends_at": "2026-07-20T21:00:00+00:00",
                },
            ],
        ),
        daily_reserved_minutes={date(2026, 7, 20): 60},
        account_daily_budget_minutes=180,
        duration_increment_minutes=5,
        allocation_policy="earliest_clustered",
    )

    minutes_by_day = {
        day: sum(block.minutes for block in blocks if block.starts_at.date() == day)
        for day in {block.starts_at.date() for block in blocks}
    }
    assert minutes_by_day == {
        date(2026, 7, 20): 60,
        date(2026, 7, 21): 180,
        date(2026, 7, 22): 120,
    }
    assert all(
        not (
            datetime(2026, 7, 20, 9, tzinfo=UTC)
            < (block.reserved_ends_at or block.ends_at)
            and block.starts_at < datetime(2026, 7, 20, 21, tzinfo=UTC)
        )
        for block in blocks
    )


def test_clustered_study_recovery_uses_time_without_charging_active_cap() -> None:
    blocks = allocate_task_intervals(
        starts_on=date(2026, 7, 20),
        ends_on=date(2026, 7, 22),
        total_minutes=100,
        preferred_session_minutes=45,
        max_daily_minutes=360,
        zone=ZoneInfo("UTC"),
        local_now=datetime(2026, 7, 19, 12, tzinfo=UTC),
        energy_window="morning",
        busy_sources=BusySources(),
        duration_increment_minutes=1,
        recovery_minutes=10,
        exact_session_blocks=True,
        allocation_policy="earliest_clustered",
    )

    assert [block.minutes for block in blocks] == [45, 45, 10]
    assert {block.starts_at.date() for block in blocks} == {date(2026, 7, 20)}
    assert all(block.recovery_minutes == 10 for block in blocks)
    assert sum(block.minutes for block in blocks) == 100
    assert blocks[1].starts_at == blocks[0].reserved_ends_at
    assert blocks[2].starts_at == blocks[1].reserved_ends_at


def test_clustered_assignment_is_dst_safe_on_the_earliest_day() -> None:
    zone = ZoneInfo("Europe/Berlin")
    blocks = allocate_task_intervals(
        starts_on=date(2026, 3, 29),
        ends_on=date(2026, 3, 30),
        total_minutes=180,
        preferred_session_minutes=60,
        max_daily_minutes=360,
        zone=zone,
        local_now=datetime(2026, 3, 28, 12, tzinfo=zone),
        energy_window="morning",
        busy_sources=BusySources(),
        duration_increment_minutes=5,
        allocation_policy="earliest_clustered",
    )

    assert {block.starts_at.date() for block in blocks} == {date(2026, 3, 29)}
    assert all(block.starts_at.utcoffset() == timedelta(hours=2) for block in blocks)
    assert all(
        block.ends_at.astimezone(UTC) - block.starts_at.astimezone(UTC)
        == timedelta(minutes=block.minutes)
        for block in blocks
    )


def test_ceiling_helpers_advance_subminute_values_only() -> None:
    fixed_offset = timezone(timedelta(hours=5, minutes=30))

    assert ceil_local_five_minutes(
        datetime(2026, 7, 20, 8, tzinfo=fixed_offset),
    ) == datetime(2026, 7, 20, 8, tzinfo=fixed_offset)
    assert ceil_local_five_minutes(
        datetime(2026, 7, 20, 8, 0, 30, tzinfo=fixed_offset),
    ) == datetime(2026, 7, 20, 8, 5, tzinfo=fixed_offset)
    assert ceil_local_five_minutes(
        datetime(2026, 7, 20, 8, 0, 0, 1, tzinfo=fixed_offset),
    ) == datetime(2026, 7, 20, 8, 5, tzinfo=fixed_offset)

    assert round_up_quarter_hour(
        datetime(2026, 7, 20, 8, 15, tzinfo=fixed_offset),
    ) == datetime(2026, 7, 20, 8, 15, tzinfo=fixed_offset)
    assert round_up_quarter_hour(
        datetime(2026, 7, 20, 8, 15, 30, tzinfo=fixed_offset),
    ) == datetime(2026, 7, 20, 8, 30, tzinfo=fixed_offset)
    assert round_up_quarter_hour(
        datetime(2026, 7, 20, 8, 15, 0, 1, tzinfo=fixed_offset),
    ) == datetime(2026, 7, 20, 8, 30, tzinfo=fixed_offset)


def test_subminute_busy_end_cannot_overlap_a_planned_block() -> None:
    cases = (
        (
            ZoneInfo("UTC"),
            "2026-07-20T07:59:00+00:00",
            "2026-07-20T08:00:30+00:00",
        ),
        (
            ZoneInfo("Asia/Kolkata"),
            "2026-07-20T07:59:00+05:30",
            "2026-07-20T08:00:00.000001+05:30",
        ),
    )

    for zone, busy_start, busy_end in cases:
        blocks = allocate_task_intervals(
            starts_on=date(2026, 7, 20),
            ends_on=date(2026, 7, 20),
            total_minutes=30,
            preferred_session_minutes=30,
            max_daily_minutes=30,
            zone=zone,
            local_now=datetime(2026, 7, 19, 12, tzinfo=zone),
            energy_window="morning",
            busy_sources=BusySources(
                timed_intervals=[
                    {
                        "starts_at": busy_start,
                        "ends_at": busy_end,
                    },
                ],
            ),
            duration_increment_minutes=5,
        )

        assert len(blocks) == 1
        assert blocks[0].starts_at == datetime(2026, 7, 20, 8, 5, tzinfo=zone)
        assert blocks[0].starts_at >= datetime.fromisoformat(busy_end)


def test_study_blocks_reserve_recovery_without_charging_focus_budget() -> None:
    zone = ZoneInfo("UTC")
    blocks = allocate_task_intervals(
        starts_on=date(2026, 7, 20),
        ends_on=date(2026, 7, 20),
        total_minutes=90,
        preferred_session_minutes=45,
        max_daily_minutes=90,
        zone=zone,
        local_now=datetime(2026, 7, 20, 7, tzinfo=UTC),
        energy_window="morning",
        busy_sources=BusySources(),
        account_daily_budget_minutes=90,
        duration_increment_minutes=5,
        recovery_minutes=10,
        exact_session_blocks=True,
    )

    assert [block.minutes for block in blocks] == [45, 45]
    assert all(block.recovery_minutes == 10 for block in blocks)
    assert all(
        block.reserved_ends_at == block.ends_at + timedelta(minutes=10)
        for block in blocks
    )
    assert blocks[1].starts_at == blocks[0].reserved_ends_at
    assert sum(block.minutes for block in blocks) == 90


def test_study_block_never_uses_a_gap_that_cannot_hold_full_recovery() -> None:
    zone = ZoneInfo("UTC")
    blocks = allocate_task_intervals(
        starts_on=date(2026, 7, 20),
        ends_on=date(2026, 7, 20),
        total_minutes=45,
        preferred_session_minutes=45,
        max_daily_minutes=45,
        zone=zone,
        local_now=datetime(2026, 7, 20, 7, tzinfo=UTC),
        energy_window="morning",
        busy_sources=BusySources(
            recurring_commitments=[
                    {
                        "weekday": 1,
                        "starts_at": "08:50:00",
                        "ends_at": "21:00:00",
                    },
            ],
        ),
        duration_increment_minutes=5,
        recovery_minutes=10,
        exact_session_blocks=True,
    )

    assert blocks == []


def test_study_remainder_is_not_backfilled_before_full_blocks() -> None:
    zone = ZoneInfo("UTC")
    blocks = allocate_task_intervals(
        starts_on=date(2026, 7, 20),
        ends_on=date(2026, 7, 22),
        total_minutes=120,
        preferred_session_minutes=45,
        max_daily_minutes=120,
        zone=zone,
        local_now=datetime(2026, 7, 20, 7, tzinfo=UTC),
        energy_window="morning",
        busy_sources=BusySources(
            recurring_commitments=[
                {
                    "weekday": 1,
                    "starts_at": "08:40:00",
                    "ends_at": "13:00:00",
                },
            ],
        ),
        duration_increment_minutes=5,
        recovery_minutes=10,
        exact_session_blocks=True,
    )

    assert [block.minutes for block in blocks] == [45, 45, 30]
    assert blocks[-1].starts_at.date() == date(2026, 7, 22)
    assert blocks[-1].starts_at >= blocks[-2].reserved_ends_at
    assert all(
        block.minutes == 45 for block in blocks[:-1]
    )


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


@pytest.mark.parametrize(
    ("first_day", "invalid_start", "valid_later_day"),
    [
        (date(2026, 3, 30), "02:15:00", date(2026, 4, 5)),
        (date(2026, 10, 26), "02:15:00", date(2026, 11, 1)),
    ],
)
def test_nonoverlapping_previous_dst_anchor_is_not_resolved(
    first_day: date,
    invalid_start: str,
    valid_later_day: date,
) -> None:
    days = [
        first_day + timedelta(days=offset)
        for offset in range((valid_later_day - first_day).days + 1)
    ]

    busy = busy_intervals_by_day(
        days=days,
        sources=BusySources(
            recurring_commitments=[
                {
                    "id": "weekly-dst",
                    "weekday": 7,
                    "starts_at": invalid_start,
                    "ends_at": "03:15:00",
                },
            ],
        ),
        zone=ZoneInfo("Europe/Berlin"),
        local_now=datetime.combine(
            first_day - timedelta(days=1),
            datetime.min.time(),
            tzinfo=ZoneInfo("Europe/Berlin"),
        ),
    )

    assert busy[first_day] == []
    assert len(busy[valid_later_day]) == 1


def test_invalid_previous_dst_anchor_is_resolved_when_it_can_spill() -> None:
    first_day = date(2026, 10, 26)

    with pytest.raises(ValueError, match="weekly-dst"):
        busy_intervals_by_day(
            days=[first_day],
            sources=BusySources(
                recurring_commitments=[
                    {
                        "id": "weekly-dst",
                        "weekday": 7,
                        "starts_at": "02:15:00",
                        "ends_at": "01:00:00",
                    },
                ],
            ),
            zone=ZoneInfo("Europe/Berlin"),
            local_now=datetime(2026, 10, 26, tzinfo=ZoneInfo("Europe/Berlin")),
        )


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

    gap_boundary = ceil_local_five_minutes(
        datetime(2026, 3, 29, 1, 59, 30, tzinfo=zone),
    )
    fold_boundary = ceil_local_five_minutes(
        datetime(2026, 10, 25, 2, 0, 30, tzinfo=zone, fold=0),
    )

    assert gap_boundary.hour == 2
    assert not is_unambiguous_local(gap_boundary, zone)
    assert fold_boundary.hour == 2
    assert not is_unambiguous_local(fold_boundary, zone)
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


def test_learned_window_is_softly_preferred_when_free() -> None:
    blocks = allocate_task_intervals(
        starts_on=date(2026, 7, 20),
        ends_on=date(2026, 7, 20),
        total_minutes=60,
        preferred_session_minutes=60,
        max_daily_minutes=120,
        zone=ZoneInfo("UTC"),
        local_now=datetime(2026, 7, 19, 12, tzinfo=UTC),
        energy_window="morning",
        learned_focus_window="18-23",
        busy_sources=BusySources(),
        duration_increment_minutes=5,
    )

    assert len(blocks) == 1
    assert blocks[0].starts_at == datetime(2026, 7, 20, 18, tzinfo=UTC)
    assert (
        used_setup_timing_fallback(
            blocks,
            learned_focus_window="18-23",
        )
        is False
    )


def test_busy_learned_window_falls_back_without_losing_minutes() -> None:
    blocks = allocate_task_intervals(
        starts_on=date(2026, 7, 20),
        ends_on=date(2026, 7, 20),
        total_minutes=120,
        preferred_session_minutes=60,
        max_daily_minutes=120,
        zone=ZoneInfo("UTC"),
        local_now=datetime(2026, 7, 19, 12, tzinfo=UTC),
        energy_window="morning",
        learned_focus_window="18-23",
        busy_sources=BusySources(
            recurring_commitments=[
                {
                    "weekday": 1,
                    "starts_at": "18:00:00",
                    "ends_at": "23:00:00",
                },
            ],
        ),
        duration_increment_minutes=5,
    )

    assert sum(block.minutes for block in blocks) == 120
    assert all(block.starts_at.hour < 18 for block in blocks)
    assert (
        used_setup_timing_fallback(
            blocks,
            learned_focus_window="18-23",
        )
        is True
    )


def test_learned_window_cannot_override_deadline_budget_or_recovery() -> None:
    blocks = allocate_task_intervals(
        starts_on=date(2026, 7, 20),
        ends_on=date(2026, 7, 20),
        total_minutes=90,
        preferred_session_minutes=45,
        max_daily_minutes=90,
        zone=ZoneInfo("UTC"),
        local_now=datetime(2026, 7, 19, 12, tzinfo=UTC),
        energy_window="morning",
        learned_focus_window="18-23",
        busy_sources=BusySources(),
        deadline_at=datetime(2026, 7, 20, 17, tzinfo=UTC),
        account_daily_budget_minutes=45,
        duration_increment_minutes=5,
        recovery_minutes=10,
        exact_session_blocks=True,
    )

    assert [block.minutes for block in blocks] == [45]
    assert blocks[0].starts_at.hour == 8
    assert blocks[0].reserved_ends_at == blocks[0].ends_at + timedelta(minutes=10)
    assert (
        used_setup_timing_fallback(
            blocks,
            learned_focus_window="18-23",
        )
        is True
    )
