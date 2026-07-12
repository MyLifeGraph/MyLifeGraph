from collections.abc import Iterable
from dataclasses import dataclass
from datetime import UTC, date, datetime
from typing import Any, Protocol
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from app.clients.supabase import SupabaseRestClient
from app.models.scheduled import ScheduledSelectionReason

_PROFILE_PAGE_SIZE = 100


@dataclass(frozen=True)
class ScheduledRefreshTarget:
    user_id: str
    briefing_date: date | None
    selection_reason: ScheduledSelectionReason
    error: str | None = None


class ScheduledRefreshRepository(Protocol):
    async def list_daily_refresh_targets(
        self,
        *,
        limit: int,
        run_at: datetime,
        target_date: date | None,
        profile_ids: list[str],
        include_current: bool,
    ) -> list[ScheduledRefreshTarget]:
        pass


class SupabaseScheduledRefreshRepository:
    def __init__(self, client: SupabaseRestClient) -> None:
        self._client = client

    async def list_daily_refresh_targets(
        self,
        *,
        limit: int,
        run_at: datetime,
        target_date: date | None,
        profile_ids: list[str],
        include_current: bool,
    ) -> list[ScheduledRefreshTarget]:
        if run_at.tzinfo is None:
            raise ValueError("Scheduled run time must include a timezone.")

        selected: list[ScheduledRefreshTarget] = []
        max_scan_rows = max(limit * 10, _PROFILE_PAGE_SIZE)
        for offset in range(0, max_scan_rows, _PROFILE_PAGE_SIZE):
            profiles = await self._list_onboarded_profiles(
                limit=_PROFILE_PAGE_SIZE,
                offset=offset,
                profile_ids=profile_ids,
            )
            if not profiles:
                break

            page_targets = [
                _target_for_profile(
                    profile=profile,
                    run_at=run_at,
                    target_date=target_date,
                )
                for profile in profiles
            ]
            valid_targets = [
                target for target in page_targets if target.briefing_date is not None
            ]
            snapshots = await self._daily_snapshots(valid_targets)
            briefings = await self._daily_briefings(valid_targets)

            for target in page_targets:
                if target.briefing_date is None:
                    selected.append(target)
                else:
                    key = (target.user_id, target.briefing_date.isoformat())
                    snapshot = snapshots.get(key)
                    briefing = briefings.get(key)
                    reason = _selection_reason(
                        snapshot=snapshot,
                        briefing=briefing,
                    )
                    if reason is None:
                        if not include_current:
                            continue
                        reason = "recommendation_refresh"
                    selected.append(
                        ScheduledRefreshTarget(
                            user_id=target.user_id,
                            briefing_date=target.briefing_date,
                            selection_reason=reason,
                        ),
                    )
                if len(selected) >= limit:
                    return selected

        return selected

    async def _list_onboarded_profiles(
        self,
        *,
        limit: int,
        offset: int,
        profile_ids: list[str],
    ) -> list[dict[str, Any]]:
        params = {
            "select": "id,timezone",
            "onboarding_completed_at": "not.is.null",
            "role": "neq.guest",
            "order": "created_at.asc,id.asc",
            "limit": str(limit),
            "offset": str(offset),
        }
        if profile_ids:
            params["id"] = f"in.({','.join(_unique(profile_ids))})"
        rows = await self._client.select(
            "profiles",
            params=params,
        )
        return [
            row
            for row in rows
            if isinstance(row.get("id"), str) and str(row["id"]).strip()
        ]

    async def _daily_snapshots(
        self,
        targets: list[ScheduledRefreshTarget],
    ) -> dict[tuple[str, str], dict[str, Any]]:
        if not targets:
            return {}
        user_ids = _unique(target.user_id for target in targets)
        period_keys = _unique(
            target.briefing_date.isoformat()
            for target in targets
            if target.briefing_date is not None
        )
        rows = await self._client.select(
            "user_state_snapshots",
            params={
                "select": "id,user_id,period_key,generated_at",
                "user_id": f"in.({','.join(user_ids)})",
                "scope": "eq.daily",
                "period_key": f"in.({','.join(period_keys)})",
                "limit": str(len(user_ids) * len(period_keys)),
            },
        )
        return {
            (user_id, period_key): row
            for row in rows
            if isinstance(user_id := row.get("user_id"), str)
            and isinstance(period_key := row.get("period_key"), str)
        }

    async def _daily_briefings(
        self,
        targets: list[ScheduledRefreshTarget],
    ) -> dict[tuple[str, str], dict[str, Any]]:
        if not targets:
            return {}
        user_ids = _unique(target.user_id for target in targets)
        briefing_dates = _unique(
            target.briefing_date.isoformat()
            for target in targets
            if target.briefing_date is not None
        )
        rows = await self._client.select(
            "daily_briefings",
            params={
                "select": "id,user_id,briefing_date,provenance,generated_at",
                "user_id": f"in.({','.join(user_ids)})",
                "briefing_date": f"in.({','.join(briefing_dates)})",
                "limit": str(len(user_ids) * len(briefing_dates)),
            },
        )
        return {
            (user_id, briefing_date): row
            for row in rows
            if isinstance(user_id := row.get("user_id"), str)
            and isinstance(briefing_date := row.get("briefing_date"), str)
        }


def _target_for_profile(
    *,
    profile: dict[str, Any],
    run_at: datetime,
    target_date: date | None,
) -> ScheduledRefreshTarget:
    user_id = str(profile["id"]).strip()
    if target_date is not None:
        return ScheduledRefreshTarget(
            user_id=user_id,
            briefing_date=target_date,
            selection_reason="missing_snapshot",
        )

    raw_timezone = profile.get("timezone")
    timezone_name = raw_timezone if isinstance(raw_timezone, str) else "UTC"
    try:
        timezone = ZoneInfo(timezone_name)
    except ZoneInfoNotFoundError:
        return ScheduledRefreshTarget(
            user_id=user_id,
            briefing_date=None,
            selection_reason="invalid_timezone",
            error="ZoneInfoNotFoundError",
        )
    return ScheduledRefreshTarget(
        user_id=user_id,
        briefing_date=run_at.astimezone(timezone).date(),
        selection_reason="missing_snapshot",
    )


def _selection_reason(
    *,
    snapshot: dict[str, Any] | None,
    briefing: dict[str, Any] | None,
) -> ScheduledSelectionReason | None:
    if snapshot is None:
        return "missing_snapshot"
    if briefing is None:
        return "missing_briefing"
    provenance = briefing.get("provenance")
    if not isinstance(provenance, dict):
        return "stale_briefing"
    source_snapshot_id = provenance.get("source_snapshot_id")
    snapshot_id = snapshot.get("id")
    if (
        not isinstance(source_snapshot_id, str)
        or not source_snapshot_id
        or not isinstance(snapshot_id, str)
        or not snapshot_id
        or source_snapshot_id != snapshot_id
    ):
        return "stale_briefing"
    try:
        source_generated_at = _parse_datetime(
            provenance.get("source_snapshot_generated_at"),
        )
        snapshot_generated_at = _parse_datetime(snapshot.get("generated_at"))
    except ValueError:
        return "stale_briefing"
    if source_generated_at != snapshot_generated_at:
        return "stale_briefing"
    return None


def _parse_datetime(value: Any) -> datetime:
    if isinstance(value, datetime):
        parsed = value
    elif isinstance(value, str):
        try:
            parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
        except ValueError as exc:
            raise ValueError("Scheduled state timestamp is invalid.") from exc
    else:
        raise ValueError("Scheduled state timestamp is invalid.")
    if parsed.tzinfo is None:
        raise ValueError("Scheduled state timestamp must include a timezone.")
    return parsed.astimezone(UTC)


def _unique(values: Iterable[str]) -> list[str]:
    return list(dict.fromkeys(values))
