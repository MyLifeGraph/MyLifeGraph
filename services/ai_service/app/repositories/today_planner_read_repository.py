from typing import Any, Protocol

from app.clients.supabase import SupabaseRestClient
from app.repositories.repository_pagination import select_offset_pages


class TodayPlannerProfileNotFoundError(RuntimeError):
    pass


class TodayPlannerInvalidTimezoneError(ValueError):
    pass


class TodayPlannerReadRepository(Protocol):
    async def get_profile_timezone(self, *, user_id: str) -> str: ...

    async def list_active_habits(
        self,
        *,
        user_id: str,
    ) -> list[dict[str, Any]]: ...


class SupabaseTodayPlannerReadRepository:
    _page_size = 1_000

    def __init__(self, client: SupabaseRestClient) -> None:
        self._client = client

    async def get_profile_timezone(self, *, user_id: str) -> str:
        rows = await self._client.select(
            "profiles",
            params={
                "select": "timezone",
                "id": f"eq.{user_id}",
                "limit": "1",
            },
        )
        if not rows:
            raise TodayPlannerProfileNotFoundError(
                "Today/Planner profile is unavailable.",
            )
        timezone = rows[0].get("timezone")
        if not isinstance(timezone, str) or not timezone.strip():
            raise TodayPlannerInvalidTimezoneError(
                "Today/Planner profile timezone is invalid.",
            )
        return timezone

    async def list_active_habits(
        self,
        *,
        user_id: str,
    ) -> list[dict[str, Any]]:
        return await select_offset_pages(
            self._client,
            "habits",
            params={
                "select": "id,title,description,frequency,target,active,metadata,"
                "created_at,updated_at",
                "user_id": f"eq.{user_id}",
                "active": "eq.true",
                "order": "created_at.asc,id.asc",
            },
            page_size=self._page_size,
            max_rows=1_001,
            overfull_error=(
                "PostgREST returned more Today/Planner rows than requested."
            ),
        )
