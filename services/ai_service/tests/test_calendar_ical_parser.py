from datetime import date
from uuid import UUID

import pytest

from app.services.calendar_ical_parser import (
    CalendarDuplicateConflictError,
    CalendarEnvelopeError,
    CalendarImportLimitError,
    parse_ical_snapshot,
)


CONNECTION_ID = UUID("11111111-1111-4111-8111-111111111111")


def _calendar(*events: str) -> str:
    return "\r\n".join(
        ["BEGIN:VCALENDAR", "VERSION:2.0", *events, "END:VCALENDAR", ""],
    )


def _event(*lines: str) -> str:
    return "\r\n".join(["BEGIN:VEVENT", *lines, "END:VEVENT"])


def _parse(text: str):
    return parse_ical_snapshot(
        calendar_text=text,
        connection_id=CONNECTION_ID,
        profile_timezone="Europe/Berlin",
        starts_on=date(2026, 6, 29),
        ends_before=date(2026, 10, 12),
    )


def test_parses_unfolded_timed_all_day_and_profile_fallback_events() -> None:
    snapshot = _parse(
        _calendar(
            _event(
                "UID:timed@example.test",
                "DTSTART;TZID=Europe/Berlin:20260713T090000",
                "DTEND;TZID=Europe/Berlin:20260713T100000",
                "SUMMARY:Planning ",
                " session",
                "LOCATION:Room 1",
                "TRANSP:OPAQUE",
            ),
            _event(
                "UID:floating@example.test",
                "DTSTART:20260714T110000",
                "DTEND:20260714T113000",
            ),
            _event(
                "UID:all-day@example.test",
                "DTSTART;VALUE=DATE:20260715",
                "SUMMARY:Away",
                "TRANSP:TRANSPARENT",
            ),
        ),
    )

    assert snapshot.counts.accepted == 3
    timed, floating, all_day = snapshot.events
    assert timed.title == "Planning session"
    assert timed.starts_at.isoformat() == "2026-07-13T07:00:00+00:00"
    assert timed.local_starts_at.isoformat() == "2026-07-13T09:00:00"
    assert timed.timezone_source == "event"
    assert floating.timezone_source == "profile"
    assert all_day.event_kind == "all_day"
    assert all_day.starts_on == date(2026, 7, 15)
    assert all_day.ends_on == date(2026, 7, 16)
    assert all_day.busy_status == "free"


def test_recurring_master_is_skipped_but_explicit_occurrence_is_stable() -> None:
    master = _event(
        "UID:series@example.test",
        "DTSTART;TZID=Europe/Berlin:20260713T090000",
        "DTEND;TZID=Europe/Berlin:20260713T100000",
        "RRULE:FREQ=WEEKLY",
    )
    occurrence = _event(
        "UID:series@example.test",
        "RECURRENCE-ID;TZID=Europe/Berlin:20260720T090000",
        "DTSTART;TZID=Europe/Berlin:20260720T100000",
        "DTEND;TZID=Europe/Berlin:20260720T110000",
        "SUMMARY:Moved occurrence",
    )
    first = _parse(_calendar(master, occurrence))
    moved_again = _parse(
        _calendar(
            master,
            occurrence.replace("20260720T100000", "20260720T120000").replace(
                "20260720T110000",
                "20260720T130000",
            ),
        ),
    )

    assert first.counts.unsupported_recurring == 1
    assert first.counts.accepted == 1
    assert first.events[0].id == moved_again.events[0].id
    assert first.events[0].source_fingerprint != moved_again.events[0].source_fingerprint


def test_cancelled_component_is_a_tombstone_and_not_a_visible_event() -> None:
    snapshot = _parse(
        _calendar(
            _event(
                "UID:cancelled@example.test",
                "STATUS:CANCELLED",
            ),
        ),
    )

    assert snapshot.events == ()
    assert snapshot.counts.cancelled == 1
    assert len(snapshot.cancelled_source_keys) == 1


def test_conflicting_duplicate_rejects_the_complete_snapshot() -> None:
    base = _event(
        "UID:duplicate@example.test",
        "DTSTART:20260713T090000Z",
        "DTEND:20260713T100000Z",
        "SUMMARY:First",
    )
    conflict = base.replace("SUMMARY:First", "SUMMARY:Second")

    with pytest.raises(CalendarDuplicateConflictError):
        _parse(_calendar(base, conflict))


def test_identical_duplicate_is_deduplicated_without_changing_fingerprint() -> None:
    event = _event(
        "UID:duplicate@example.test",
        "DTSTART:20260713T090000Z",
        "DTEND:20260713T100000Z",
        "SUMMARY:Same",
    )

    single = _parse(_calendar(event))
    duplicate = _parse(_calendar(event, event))

    assert duplicate.counts.accepted == 1
    assert duplicate.events == single.events
    assert duplicate.source_fingerprint == single.source_fingerprint


def test_out_of_window_components_are_counted_without_accepting_them() -> None:
    snapshot = _parse(
        _calendar(
            _event(
                "UID:old-timed@example.test",
                "DTSTART:20260628T090000Z",
                "DTEND:20260628T100000Z",
            ),
            _event(
                "UID:future-all-day@example.test",
                "DTSTART;VALUE=DATE:20261012",
                "DTEND;VALUE=DATE:20261013",
            ),
        ),
    )

    assert snapshot.counts.out_of_window == 2
    assert snapshot.counts.accepted == 0
    assert snapshot.events == ()


def test_incoherent_start_and_end_timezones_are_invalid() -> None:
    snapshot = _parse(
        _calendar(
            _event(
                "UID:incoherent@example.test",
                "DTSTART;TZID=Europe/Berlin:20260713T090000",
                "DTEND:20260713T100000Z",
            ),
        ),
    )

    assert snapshot.counts.invalid == 1
    assert snapshot.events == ()


def test_uid_whitespace_is_invalid_instead_of_colliding_after_trim() -> None:
    snapshot = _parse(
        _calendar(
            _event(
                "UID: exact@example.test ",
                "DTSTART:20260713T090000Z",
                "DTEND:20260713T100000Z",
            ),
        ),
    )

    assert snapshot.counts.invalid == 1
    assert snapshot.events == ()


def test_floating_recurrence_identity_does_not_depend_on_profile_timezone() -> None:
    text = _calendar(
        _event(
            "UID:floating-series@example.test",
            "RECURRENCE-ID:20260720T090000",
            "DTSTART:20260720T100000Z",
            "DTEND:20260720T110000Z",
        ),
    )
    berlin = parse_ical_snapshot(
        calendar_text=text,
        connection_id=CONNECTION_ID,
        profile_timezone="Europe/Berlin",
        starts_on=date(2026, 6, 29),
        ends_before=date(2026, 10, 12),
    )
    new_york = parse_ical_snapshot(
        calendar_text=text,
        connection_id=CONNECTION_ID,
        profile_timezone="America/New_York",
        starts_on=date(2026, 6, 29),
        ends_before=date(2026, 10, 12),
    )

    assert berlin.events[0].id == new_york.events[0].id


def test_nested_vcalendar_is_rejected() -> None:
    with pytest.raises(CalendarEnvelopeError):
        _parse(
            "\r\n".join(
                [
                    "BEGIN:VCALENDAR",
                    "VERSION:2.0",
                    "BEGIN:VCALENDAR",
                    "VERSION:2.0",
                    "END:VCALENDAR",
                    "END:VCALENDAR",
                ],
            ),
        )


@pytest.mark.parametrize(
    "start,end",
    [
        ("20260329T023000", "20260329T033000"),
        ("20261025T023000", "20261025T033000"),
    ],
)
def test_dst_gap_and_fold_are_invalid_components(start: str, end: str) -> None:
    snapshot = parse_ical_snapshot(
        calendar_text=_calendar(
            _event(
                "UID:dst@example.test",
                f"DTSTART;TZID=Europe/Berlin:{start}",
                f"DTEND;TZID=Europe/Berlin:{end}",
            ),
        ),
        connection_id=CONNECTION_ID,
        profile_timezone="Europe/Berlin",
        starts_on=date(2026, 1, 1),
        ends_before=date(2026, 4, 16),
    )

    assert snapshot.counts.invalid == 1
    assert snapshot.events == ()


def test_invalid_envelope_and_byte_bound_are_fatal() -> None:
    with pytest.raises(CalendarEnvelopeError):
        _parse("BEGIN:VCALENDAR\r\nEND:VCALENDAR\r\n")

    oversized = _calendar(
        _event(
            "UID:large@example.test",
            "DTSTART:20260713T090000Z",
            "DTEND:20260713T100000Z",
            f"SUMMARY:{'ä' * 300_000}",
        ),
    )
    assert len(oversized) < 524_288
    assert len(oversized.encode("utf-8")) > 524_288
    with pytest.raises(CalendarImportLimitError):
        _parse(oversized)


def test_component_and_accepted_bounds_reject_without_truncation() -> None:
    too_many_components = _calendar(
        *[
            _event(
                f"UID:outside-{index}@example.test",
                "DTSTART:20250101T090000Z",
                "DTEND:20250101T100000Z",
            )
            for index in range(2_001)
        ],
    )
    with pytest.raises(CalendarImportLimitError):
        _parse(too_many_components)

    too_many_accepted = _calendar(
        *[
            _event(
                f"UID:accepted-{index}@example.test",
                "DTSTART:20260713T090000Z",
                "DTEND:20260713T100000Z",
            )
            for index in range(501)
        ],
    )
    with pytest.raises(CalendarImportLimitError):
        _parse(too_many_accepted)
