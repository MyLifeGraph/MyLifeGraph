from typing import Any, Protocol

from app.clients.supabase import SupabaseRestClient


class IntakeRepository(Protocol):
    async def insert_intake_response(
        self,
        *,
        user_id: str,
        row: dict[str, Any],
    ) -> dict[str, Any]:
        pass

    async def update_profile_onboarding(
        self,
        *,
        user_id: str,
        values: dict[str, Any],
    ) -> None:
        pass

    async def upsert_notification_preferences(
        self,
        *,
        row: dict[str, Any],
    ) -> None:
        pass

    async def insert_goals(
        self,
        *,
        rows: list[dict[str, Any]],
    ) -> None:
        pass

    async def insert_habits(
        self,
        *,
        rows: list[dict[str, Any]],
    ) -> None:
        pass

    async def insert_schedule_items(
        self,
        *,
        rows: list[dict[str, Any]],
    ) -> None:
        pass

    async def insert_memory_entries(
        self,
        *,
        rows: list[dict[str, Any]],
    ) -> None:
        pass

    async def insert_user_state_snapshot(
        self,
        *,
        row: dict[str, Any],
    ) -> dict[str, Any]:
        pass


class SupabaseIntakeRepository:
    def __init__(self, client: SupabaseRestClient) -> None:
        self._client = client

    async def insert_intake_response(
        self,
        *,
        user_id: str,
        row: dict[str, Any],
    ) -> dict[str, Any]:
        inserted = await self._client.insert(
            "intake_responses",
            rows=[{"user_id": user_id, **row}],
        )
        return inserted[0]

    async def update_profile_onboarding(
        self,
        *,
        user_id: str,
        values: dict[str, Any],
    ) -> None:
        await self._client.update(
            "profiles",
            values=values,
            params={"id": f"eq.{user_id}"},
        )

    async def upsert_notification_preferences(
        self,
        *,
        row: dict[str, Any],
    ) -> None:
        await self._client.upsert(
            "notification_preferences",
            rows=[row],
            on_conflict="user_id",
        )

    async def insert_goals(
        self,
        *,
        rows: list[dict[str, Any]],
    ) -> None:
        await self._client.insert("goals", rows=rows)

    async def insert_habits(
        self,
        *,
        rows: list[dict[str, Any]],
    ) -> None:
        await self._client.insert("habits", rows=rows)

    async def insert_schedule_items(
        self,
        *,
        rows: list[dict[str, Any]],
    ) -> None:
        await self._client.insert("schedule_items", rows=rows)

    async def insert_memory_entries(
        self,
        *,
        rows: list[dict[str, Any]],
    ) -> None:
        await self._client.insert("memory_entries", rows=rows)

    async def insert_user_state_snapshot(
        self,
        *,
        row: dict[str, Any],
    ) -> dict[str, Any]:
        inserted = await self._client.insert("user_state_snapshots", rows=[row])
        return inserted[0]
