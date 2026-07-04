from datetime import date
from typing import Protocol

from app.clients.supabase import SupabaseRestClient

_PROFILE_PAGE_SIZE = 100


class ScheduledRefreshRepository(Protocol):
    async def list_daily_refresh_user_ids(
        self,
        *,
        limit: int,
        target_date: date,
    ) -> list[str]:
        pass


class SupabaseScheduledRefreshRepository:
    def __init__(self, client: SupabaseRestClient) -> None:
        self._client = client

    async def list_daily_refresh_user_ids(
        self,
        *,
        limit: int,
        target_date: date,
    ) -> list[str]:
        missing_snapshot_user_ids = await self._list_missing_daily_snapshot_user_ids(
            limit=limit,
            period_key=target_date.isoformat(),
        )
        if len(missing_snapshot_user_ids) >= limit:
            return missing_snapshot_user_ids[:limit]

        selected = list(missing_snapshot_user_ids)
        selected_ids = set(selected)
        oldest_snapshot_user_ids = await self._list_oldest_daily_snapshot_user_ids(
            limit=limit,
        )
        for user_id in oldest_snapshot_user_ids:
            if user_id in selected_ids:
                continue
            selected.append(user_id)
            selected_ids.add(user_id)
            if len(selected) >= limit:
                break

        return selected

    async def _list_missing_daily_snapshot_user_ids(
        self,
        *,
        limit: int,
        period_key: str,
    ) -> list[str]:
        selected: list[str] = []
        selected_ids: set[str] = set()
        max_scan_rows = max(limit * 10, _PROFILE_PAGE_SIZE)

        for offset in range(0, max_scan_rows, _PROFILE_PAGE_SIZE):
            profile_ids = await self._list_onboarded_profile_ids(
                limit=_PROFILE_PAGE_SIZE,
                offset=offset,
            )
            if not profile_ids:
                break

            users_with_daily_snapshots = await self._daily_snapshot_user_ids(
                profile_ids,
                period_key=period_key,
            )
            for user_id in profile_ids:
                if user_id in users_with_daily_snapshots or user_id in selected_ids:
                    continue
                selected.append(user_id)
                selected_ids.add(user_id)
                if len(selected) >= limit:
                    return selected

        return selected

    async def _list_onboarded_profile_ids(
        self,
        *,
        limit: int,
        offset: int,
    ) -> list[str]:
        rows = await self._client.select(
            "profiles",
            params={
                "select": "id",
                "onboarding_completed_at": "not.is.null",
                "role": "neq.guest",
                "order": "created_at.asc,id.asc",
                "limit": str(limit),
                "offset": str(offset),
            },
        )
        return [
            user_id
            for row in rows
            if isinstance(user_id := row.get("id"), str) and user_id.strip()
        ]

    async def _daily_snapshot_user_ids(
        self,
        user_ids: list[str],
        *,
        period_key: str,
    ) -> set[str]:
        if not user_ids:
            return set()
        rows = await self._client.select(
            "user_state_snapshots",
            params={
                "select": "user_id",
                "user_id": f"in.({','.join(user_ids)})",
                "scope": "eq.daily",
                "period_key": f"eq.{period_key}",
                "limit": str(len(user_ids)),
            },
        )
        return {
            user_id
            for row in rows
            if isinstance(user_id := row.get("user_id"), str) and user_id.strip()
        }

    async def _list_oldest_daily_snapshot_user_ids(self, *, limit: int) -> list[str]:
        rows = await self._client.select(
            "user_state_snapshots",
            params={
                "select": "user_id",
                "scope": "eq.daily",
                "order": "generated_at.asc",
                "limit": str(limit),
            },
        )
        selected: list[str] = []
        selected_ids: set[str] = set()
        for row in rows:
            user_id = row.get("user_id")
            if not isinstance(user_id, str) or not user_id.strip():
                continue
            if user_id in selected_ids:
                continue
            selected.append(user_id)
            selected_ids.add(user_id)
        return selected
