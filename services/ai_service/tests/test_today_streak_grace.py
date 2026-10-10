import asyncio
from datetime import UTC, date, datetime, timedelta
from zoneinfo import ZoneInfo

import pytest

from app.services.today_overview_service import _streak_deadline
from app.repositories.today_overview_repository import SupabaseTodayOverviewRepository
from test_today_overview_service import Repository, USER_ID, _capture_row, _service


@pytest.mark.parametrize("zone,day,end", [
    ("UTC", "2026-10-08", "2026-10-11T00:00:00+00:00"),
    ("Europe/Berlin", "2026-03-28", "2026-03-30T23:00:00+00:00"),
    ("Europe/Berlin", "2026-10-24", "2026-10-26T22:00:00+00:00"),
    ("America/New_York", "2026-03-07", "2026-03-10T05:00:00+00:00"),
    ("America/Santiago", "2026-09-05", "2026-09-08T04:00:00+00:00"),
    ("Pacific/Apia", "2011-12-29", "2012-01-01T10:00:00+00:00"),
])
def test_deadline_is_48_elapsed_hours_after_actual_local_boundary(zone, day, end):
    assert _streak_deadline(date.fromisoformat(day), ZoneInfo(zone)) == datetime.fromisoformat(end)


def read(repository, now):
    service = _service(repository)
    return asyncio.run(service._load_check_ins(
        user_id=USER_ID, local_date=now.astimezone(ZoneInfo("Europe/Berlin")).date(),
        generated_at=now, zone=ZoneInfo("Europe/Berlin"),
    ))


def test_pending_recent_days_preserve_but_do_not_increment_streak():
    repository = Repository()
    repository.daily_logs = [_capture_row(date(2026, 10, 7))]
    assert read(repository, datetime(2026, 10, 9, 12, tzinfo=UTC)).completed_days_streak == 1
    assert read(repository, datetime(2026, 10, 11, 0, tzinfo=UTC)).completed_days_streak == 0


@pytest.mark.parametrize("late", [False, True])
def test_server_receipt_not_edit_or_client_clock_controls_credit(late):
    repository = Repository()
    day = date(2026, 10, 7)
    repository.daily_logs = [_capture_row(day), _capture_row(day - timedelta(days=1))]
    deadline = _streak_deadline(day, ZoneInfo("Europe/Berlin"))

    async def receipts(*, user_id, entry_dates):
        return [{"entry_date": d.isoformat(), "branch": branch,
                 "created_at": (deadline + timedelta(microseconds=1) if late and d == day
                                else _streak_deadline(d, ZoneInfo("Europe/Berlin"))).isoformat()}
                for d in entry_dates for branch in ("morning", "evening")]
    repository.list_capture_receipts = receipts
    result = read(repository, deadline + timedelta(hours=1))
    assert result.completed_days_streak == (0 if late else 2)


def test_missing_receipt_does_not_fabricate_streak_credit():
    repository = Repository()
    repository.daily_logs = [_capture_row(date(2026, 10, 7))]

    async def receipts(**kwargs):
        return []

    repository.list_capture_receipts = receipts
    result = read(repository, datetime(2026, 10, 8, 12, tzinfo=UTC))
    assert result.completed_days_streak == 0


def test_receipt_read_is_owner_filtered_and_select_only():
    calls = []

    class Client:
        async def select(self, table, *, params):
            calls.append((table, params))
            return []

    repository = SupabaseTodayOverviewRepository(Client())
    assert asyncio.run(repository.list_capture_receipts(
        user_id=USER_ID, entry_dates=[date(2026, 10, 7)],
    )) == []
    assert calls[0][0] == 'daily_capture_request_identities'
    assert calls[0][1]['user_id'] == f'eq.{USER_ID}'
    assert calls[0][1]['entry_date'] == 'in.(2026-10-07)'
    assert calls[0][1]['select'] == 'entry_date,branch,created_at'
