"""Read-only catch-up reminders, independent of normal check-in reminders."""

from datetime import UTC, date, datetime, timedelta
from zoneinfo import ZoneInfo

from app.services.checkin_streak import streak_deadline
from app.services.important_reminder_rules import ImportantReminder
from app.services.snapshot_daily_state import valid_explicit_capture_kinds

STREAK_HOURS = {"streak_10h": 10, "streak_5h": 5}


def streak_window(day: date, hours: int, zone: ZoneInfo) -> tuple[datetime, datetime]:
    if hours not in (10, 5):
        raise ValueError("Unsupported streak reminder offset")
    starts = streak_deadline(day, zone) - timedelta(hours=hours)
    return starts, starts + timedelta(minutes=15)


async def still_needs_streak_reminder(
    client, owner: str, candidate: ImportantReminder, timezone: str, now: datetime
) -> bool:
    hours = STREAK_HOURS.get(candidate.kind)
    if hours is None or now.utcoffset() is None:
        return False
    try:
        day = date.fromisoformat(candidate.dedupe_key.split(":")[1])
    except (ValueError, IndexError):
        return False
    if candidate.dedupe_key != f"streak:{day}:{hours}h":
        return False
    zone = ZoneInfo(timezone)
    starts, expires = streak_window(day, hours, zone)
    if not starts <= now < expires or candidate.expires_at != expires:
        return False
    previous = day - timedelta(days=1)
    days = f"in.({previous},{day})"
    rows = await client.select(
        "daily_logs",
        params={
            "select": "id,entry_date,sleep_hours,mood_score,energy_level,stress_level,metadata",
            "user_id": f"eq.{owner}",
            "entry_date": days,
            "limit": "3",
        },
    )
    if len(rows) > 2:
        return False
    by_date = {row["entry_date"]: row for row in rows}
    if len(by_date) != len(rows):
        return False
    receipts = await client.select(
        "daily_capture_request_identities",
        params={
            "select": "entry_date,branch,created_at,result_daily_log_id",
            "user_id": f"eq.{owner}",
            "entry_date": days,
            "order": "created_at.asc,request_id.asc",
            "limit": "1001",
        },
    )
    # A bounded or silently server-truncated read is not sufficient authority.
    if len(receipts) >= 1000:
        return False

    def complete(entry: date) -> bool:
        row = by_date.get(entry.isoformat())
        if row is None:
            return False
        timely = set()
        for receipt in receipts:
            if receipt.get("entry_date") != entry.isoformat() or receipt.get(
                "result_daily_log_id"
            ) != row.get("id"):
                continue
            saved = datetime.fromisoformat(receipt["created_at"].replace("Z", "+00:00"))
            if saved.utcoffset() is None:
                raise ValueError("Invalid streak receipt timestamp")
            if saved <= min(now, streak_deadline(entry, zone)):
                timely.add(receipt.get("branch"))
        return {"morning", "evening"}.issubset(
            valid_explicit_capture_kinds(row) & timely
        )

    return complete(previous) and not complete(day)


async def streak_reminders(
    client, owner: str, timezone: str, revision: int, now: datetime
) -> list[ImportantReminder]:
    rows = await client.rpc(
        "get_streak_push_candidates_v1",
        params={
            "p_user_id": owner,
            "p_timezone": timezone,
            "p_revision": revision,
        },
    )
    if not isinstance(rows, list) or len(rows) > 2:
        raise ValueError("Invalid streak reminder candidates")
    result = []
    for row in rows:
        kind = row.get("kind")
        hours = STREAK_HOURS.get(kind)
        if hours is None:
            raise ValueError("Invalid streak reminder kind")
        expires = datetime.fromisoformat(row["expires_at"].replace("Z", "+00:00"))
        if expires.utcoffset() is None:
            raise ValueError("Invalid streak reminder expiry")
        candidate = ImportantReminder(
            kind,
            row["dedupe_key"],
            "/dashboard",
            "Check-in reminder",
            f"About {hours} hours left to catch up on missed check-ins. Open Today to finish.",
            expires.astimezone(UTC),
        )
        if await still_needs_streak_reminder(client, owner, candidate, timezone, now):
            result.append(candidate)
    return result
