import asyncio
from datetime import UTC, date, datetime, timedelta
from zoneinfo import ZoneInfo

import pytest

from app.models.push import PushCommand, PushSettings
from app.services.streak_push import (
    streak_window,
    streak_reminders,
    still_needs_streak_reminder,
)
from app.services.checkin_streak import streak_deadline
from app.services.important_reminder_rules import ImportantReminder
from app.services.push_delivery import deliver_for_owner
from tests.test_push import command, preferences, Sender
from tests.test_today_overview_service import _capture_row

DAY = date(2026, 11, 12)
OWNER = "streak-owner"


class Evidence:
    def __init__(self):
        self.rows = [
            _capture_row(DAY - timedelta(days=1)),
            _capture_row(DAY, evening=False),
        ]
        self.calls = []
        self.completed_before_send = False
        self.reads = 0

    async def select(self, table, params):
        self.calls.append((table, params))
        assert params["user_id"] == f"eq.{OWNER}"
        if table == "daily_logs":
            self.reads += 1
            if self.completed_before_send and self.reads == 2:
                self.rows[-1] = _capture_row(DAY)
            return self.rows
        assert table == "daily_capture_request_identities"
        return [
            {
                "entry_date": r["entry_date"],
                "branch": branch,
                "created_at": r["entry_date"] + "T21:00:00Z",
                "result_daily_log_id": r["id"],
            }
            for r in self.rows
            for branch in r["metadata"]["captures"]
        ]

    async def rpc(self, name, params):
        self.calls.append((name, params))
        if name == "get_streak_push_candidates_v1":
            return [
                {
                    "kind": "streak_10h",
                    "dedupe_key": f"streak:{DAY}:10h",
                    "expires_at": "2026-11-14T14:15:00Z",
                }
            ]
        if name == "reserve_push_v1":
            return {
                "attempt_id": "attempt",
                "registration_id": "registration",
                "session_id": "session",
                "token": "synthetic-device-token",
            }
        if name == "check_push_reservation_v1":
            return True
        assert name == "finish_push_v1"


def candidate(hours=10, zone="UTC"):
    starts, expires = streak_window(DAY, hours, ZoneInfo(zone))
    return ImportantReminder(
        f"streak_{hours}h",
        f"streak:{DAY}:{hours}h",
        "/dashboard",
        "Check-in reminder",
        "Catch up",
        expires,
    ), starts


@pytest.mark.parametrize(
    "zone,day",
    [
        ("UTC", date(2026, 11, 12)),
        ("Europe/Berlin", date(2026, 3, 28)),
        ("Europe/Berlin", date(2026, 10, 24)),
        ("America/Havana", date(2026, 10, 31)),
        ("America/Santiago", date(2026, 9, 5)),
        ("Pacific/Apia", date(2011, 12, 29)),
        ("Asia/Kathmandu", date(2026, 11, 12)),
    ],
)
@pytest.mark.parametrize("hours", [10, 5])
def test_windows_use_exact_48_elapsed_hour_deadline(zone, day, hours):
    start, end = streak_window(day, hours, ZoneInfo(zone))
    assert start == streak_deadline(day, ZoneInfo(zone)) - timedelta(hours=hours)
    assert end - start == timedelta(minutes=15)


@pytest.mark.parametrize(
    "seconds,expected",
    [(-1, False), (0, True), (899, True), (900, False), (3600, False)],
)
def test_window_boundaries_and_no_catchup(seconds, expected):
    c, starts = candidate()
    assert (
        asyncio.run(
            still_needs_streak_reminder(
                Evidence(), OWNER, c, "UTC", starts + timedelta(seconds=seconds)
            )
        )
        is expected
    )


@pytest.mark.parametrize(
    "change",
    [
        "both_saved",
        "no_previous_streak",
        "previous_late",
        "malformed_previous",
        "truncated",
    ],
)
def test_completed_or_unproven_streak_never_creates_reminder(change):
    client = Evidence()
    original = client.select
    if change == "both_saved":
        client.rows[-1] = _capture_row(DAY)
    if change == "no_previous_streak":
        client.rows = client.rows[1:]
    if change == "malformed_previous":
        client.rows[0]["metadata"]["capture_version"] = "invalid"

    async def select(table, params):
        rows = await original(table, params)
        if table == "daily_capture_request_identities":
            if change == "truncated":
                return rows * 1000
            if change == "previous_late":
                for r in rows:
                    if r["entry_date"] < str(DAY):
                        r["created_at"] = "2026-11-14T14:00:00Z"
        return rows

    client.select = select
    c, now = candidate()
    assert not asyncio.run(still_needs_streak_reminder(client, OWNER, c, "UTC", now))


def test_candidate_lookup_and_payload_identity():
    client = Evidence()
    values = asyncio.run(
        streak_reminders(
            client, OWNER, "UTC", 7, datetime(2026, 11, 14, 14, tzinfo=UTC)
        )
    )
    assert len(values) == 1 and values[0].destination == "/dashboard"
    assert client.calls[0] == (
        "get_streak_push_candidates_v1",
        {"p_user_id": OWNER, "p_timezone": "UTC", "p_revision": 7},
    )


@pytest.mark.parametrize("saved_during_send", [True, False])
def test_worker_fresh_recheck_suppresses_completed_capture(saved_during_send):
    client = Evidence()
    client.completed_before_send = saved_during_send
    sender = Sender()
    result = asyncio.run(
        deliver_for_owner(
            client,
            None,
            sender,
            {
                "id": OWNER,
                "timezone": "UTC",
                "push_settings": preferences(
                    streak=True, sleep=False, deadlines=False, patterns=False
                ),
            },
            now=datetime(2026, 11, 14, 14, tzinfo=UTC),
        )
    )
    assert result == (0 if saved_during_send else 1)
    assert len(sender.calls) == result
    assert client.calls[-1][0] == "finish_push_v1"
    assert client.calls[-1][1]["p_accepted"] is (not saved_during_send)


def test_streak_settings_preserve_legacy_retry_shape_and_do_not_auto_opt_in():
    old = PushCommand.model_validate(command()).rpc_payload()
    assert "streak" not in old
    explicit = PushCommand.model_validate({**command(), "streak": True}).rpc_payload()
    assert explicit["streak"] is True
    assert PushSettings.model_validate(preferences()).streak is None
    assert PushSettings.model_validate(preferences(streak=False)).streak is False
    from pydantic import ValidationError

    for invalid in (1, "true"):
        with pytest.raises(ValidationError):
            PushCommand.model_validate({**command(), "streak": invalid})


@pytest.mark.parametrize(
    "capability,expected", [(None, 503), ("true", 503), (False, 200)]
)
def test_api_requires_migration_capability_before_saving(
    monkeypatch, capability, expected
):
    from tests.test_push import Client, route_request, OWNER as API_OWNER

    original = Client.rpc

    async def rpc(self, name, params):
        value = await original(self, name, params)
        if (
            name in ("get_push_state_v1", "apply_push_command_v1")
            and capability is not None
        ):
            value["settings"]["streak"] = capability
        return value

    monkeypatch.setattr(Client, "rpc", rpc)
    response, client = asyncio.run(route_request(monkeypatch, command(streak=True)))
    assert response.status_code == expected
    assert client.calls[0] == ("get_push_state_v1", {"p_user_id": API_OWNER})
    assert any(name == "apply_push_command_v1" for name, _ in client.calls) is (
        expected == 200
    )


@pytest.mark.parametrize(
    "changes",
    [
        dict(streak=False),
        dict(streak=True, enabled=False),
        dict(streak=True, quiet_start="13:00", quiet_end="15:00"),
    ],
)
def test_optout_and_quiet_hours_make_no_streak_reads_or_sends(changes):
    client, sender = Evidence(), Sender()
    result = asyncio.run(
        deliver_for_owner(
            client,
            None,
            sender,
            {
                "id": OWNER,
                "timezone": "UTC",
                "push_settings": preferences(
                    sleep=False, deadlines=False, patterns=False, **changes
                ),
            },
            now=datetime(2026, 11, 14, 14, tzinfo=UTC),
        )
    )
    assert result == 0 and sender.calls == [] and client.calls == []
