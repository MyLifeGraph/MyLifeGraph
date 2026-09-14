from datetime import UTC, datetime, timedelta
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from app.clients.supabase import SupabaseRestClient
from app.models.health_connect import HealthConnectCommand, HealthConnectState


class HealthConnectRepository:
    """Owner-scoped reads and one atomic, service-only command boundary."""

    def __init__(self, client: SupabaseRestClient):
        self._client = client

    async def read(self, user_id: str) -> HealthConnectState:
        rows = await self._client.select(
            "profiles",
            params={
                "select": "timezone,health_connect_settings",
                "id": f"eq.{user_id}",
                "limit": "1",
            },
        )
        if len(rows) != 1:
            raise ValueError("Health Connect profile unavailable.")
        return self._state(rows[0])

    async def apply(
        self, user_id: str, command: HealthConnectCommand
    ) -> HealthConnectState:
        row = await self._client.rpc(
            "apply_health_connect_v1",
            params={
                "p_user_id": user_id,
                "p_request": command.model_dump(mode="json"),
            },
        )
        return self._state(row)

    @staticmethod
    def _state(row: dict) -> HealthConnectState:
        try:
            timezone = row["timezone"]
            today = datetime.now(UTC).astimezone(ZoneInfo(timezone)).date()
            return HealthConnectState(
                **row["health_connect_settings"],
                timezone=timezone,
                window_start=today - timedelta(days=6),
                window_end=today,
            )
        except (KeyError, TypeError, ZoneInfoNotFoundError) as error:
            raise ValueError("Health Connect returned invalid state.") from error
