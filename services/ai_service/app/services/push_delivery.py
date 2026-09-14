"""Optional in-process VPS scheduler. No billed Firebase compute or LLM calls."""

import asyncio
import json
import logging
from datetime import UTC, datetime, time, timedelta
from zoneinfo import ZoneInfo

import httpx

from app.models.push import PUSH_CONTRACT_VERSION, PushSettings
from app.services.important_reminder_rules import (
    ReminderPreferences,
    important_reminders,
)

logger = logging.getLogger(__name__)


class FcmSender:
    def __init__(self, project_id: str, credentials_json: str):
        # Loaded only when explicitly enabled; never exposed to a client or logger.
        from google.oauth2 import service_account

        info = json.loads(credentials_json)
        if (
            not isinstance(info, dict)
            or project_id != "mylifegraph-5d234"
            or info.get("project_id") != project_id
            or info.get("type") != "service_account"
            or info.get("client_email")
            != f"mylifegraph-push-sender@{project_id}.iam.gserviceaccount.com"
            or info.get("token_uri") != "https://oauth2.googleapis.com/token"
        ):
            raise ValueError(
                "FCM service identity does not match the configured project"
            )
        self._credentials = service_account.Credentials.from_service_account_info(
            info, scopes=["https://www.googleapis.com/auth/firebase.messaging"]
        )
        self._url = f"https://fcm.googleapis.com/v1/projects/{project_id}/messages:send"

    async def send(
        self, *, registration: dict, owner: str, reminder
    ) -> tuple[bool, bool]:
        from google.auth.transport.requests import Request

        if not self._credentials.valid:
            # The worker is serial. Refresh before sending; no message retry.
            request = Request()
            await asyncio.to_thread(
                self._credentials.refresh,
                lambda **kwargs: request(**{**kwargs, "timeout": 10}),
            )
        async with httpx.AsyncClient(timeout=10) as client:
            response = await client.post(
                self._url,
                headers={"Authorization": f"Bearer {self._credentials.token}"},
                json={
                    "message": {
                        "token": registration["token"],
                        "android": {"priority": "HIGH", "ttl": "0s"},
                        "data": {
                            "contract_version": PUSH_CONTRACT_VERSION,
                            "owner": owner,
                            "registration_id": registration["registration_id"],
                            "session_id": registration["session_id"],
                            "attempt_id": registration["attempt_id"],
                            "kind": reminder.kind,
                            "expires_epoch": str(int(reminder.expires_at.timestamp())),
                            "destination": reminder.destination,
                        },
                    },
                },
            )
        invalid = False
        if response.status_code == 404:
            try:
                invalid = any(
                    d.get("errorCode") == "UNREGISTERED"
                    for d in response.json().get("error", {}).get("details", [])
                )
            except (ValueError, AttributeError, TypeError):
                pass
        return response.is_success, invalid


async def deliver_for_owner(
    client, composition, sender, row: dict, *, now: datetime | None = None
) -> int:
    prefs = PushSettings.model_validate(row["push_settings"])
    owner, timezone = row["id"], row["timezone"]
    now = now or datetime.now(UTC)
    local = now.astimezone(ZoneInfo(timezone))
    preferences = ReminderPreferences(
        enabled=prefs.enabled,
        sleep=prefs.sleep,
        deadlines=prefs.deadlines,
        patterns=prefs.patterns,
        quiet_start=time.fromisoformat(prefs.quiet_start),
        quiet_end=time.fromisoformat(prefs.quiet_end),
    )
    # Avoid expensive read-only analysis in quiet hours and disabled categories.
    clock = local.time().replace(tzinfo=None)
    start, end = preferences.quiet_start, preferences.quiet_end
    quiet = start == end or (
        start <= clock < end if start < end else clock >= start or clock < end
    )
    if not prefs.enabled or quiet:
        return 0
    deadlines = False
    if prefs.deadlines and time(9) <= clock < time(9, 15):
        lower = datetime.combine(local.date(), time(), tzinfo=local.tzinfo).astimezone(
            UTC
        )
        upper = datetime.combine(
            local.date() + timedelta(days=1), time(), tzinfo=local.tzinfo
        ).astimezone(UTC)
        tasks = await client.select(
            "tasks",
            params={
                "select": "id",
                "user_id": f"eq.{owner}",
                "status": "in.(todo,in_progress)",
                "and": f"(deadline.gte.{lower.isoformat()},deadline.lt.{upper.isoformat()})",
                "limit": "1",
            },
        )
        # Confirmed exam/assignment plans already project their deadline to an
        # ordinary open managed task. Draft proposals must not generate reminders.
        deadlines = bool(tasks)
    sleep, patterns = None, None
    if prefs.sleep:
        try:
            sleep = await composition.sleep_recommendation_service.get_recommendation(
                user_id=owner
            )
        except Exception:
            logger.warning("Sleep reminder analysis unavailable; no sleep candidate.")
    if prefs.patterns and time(12) <= clock < time(12, 15):
        try:
            patterns = await composition.personal_patterns_service.get_patterns(
                user_id=owner
            )
        except Exception:
            logger.warning(
                "Pattern reminder analysis unavailable; no pattern candidate."
            )
    # SQL is the authority for cross-worker cap, dedupe and monthly cooldown.
    candidates = important_reminders(
        now=now,
        timezone=timezone,
        preferences=preferences,
        reserved_today=0,
        reserved_keys=set(),
        has_open_deadlines_today=deadlines,
        sleep=sleep,
        patterns=patterns,
    )
    accepted = 0
    for candidate in candidates:
        registration = await client.rpc(
            "reserve_push_v1",
            params={
                "p_user_id": owner,
                "p_kind": candidate.kind,
                "p_key": candidate.dedupe_key,
                "p_timezone": timezone,
                "p_revision": prefs.revision,
                "p_expires_at": candidate.expires_at.isoformat(),
            },
        )
        if not registration:
            continue
        success, invalid = False, False
        try:
            current = await client.rpc(
                "check_push_reservation_v1",
                params={
                    "p_user_id": owner,
                    "p_attempt_id": registration["attempt_id"],
                    "p_registration_id": registration["registration_id"],
                    "p_revision": prefs.revision,
                    "p_timezone": timezone,
                },
            )
            if current is True:
                success, invalid = await sender.send(
                    registration=registration, owner=owner, reminder=candidate
                )
        finally:
            # Ambiguous/crashed sends retain their reservation. Never resend them.
            await client.rpc(
                "finish_push_v1",
                params={
                    "p_user_id": owner,
                    "p_attempt_id": registration["attempt_id"],
                    "p_accepted": success,
                    "p_invalid_token": registration["token"] if invalid else None,
                },
            )
        accepted += int(success)
    return accepted


async def run_push_scheduler(client, composition, sender):
    cursor = None
    while True:
        try:
            rows = await client.rpc("list_push_owners_v1", params={"p_after": cursor})
            if not isinstance(rows, list) or len(rows) > 25:
                raise ValueError("Invalid push page")
            for row in rows:
                cursor = row["id"]
                try:
                    async with asyncio.timeout(45):
                        await deliver_for_owner(client, composition, sender, row)
                except asyncio.CancelledError:
                    raise
                except Exception:
                    logger.warning("Push evaluation failed; no automatic send retry.")
            if len(rows) < 25:
                cursor = None
        except asyncio.CancelledError:
            raise
        except Exception:
            logger.warning("Push scheduler unavailable; retrying reads later.")
        await asyncio.sleep(300)
