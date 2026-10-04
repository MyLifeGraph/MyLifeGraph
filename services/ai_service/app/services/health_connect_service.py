from datetime import UTC, datetime, timedelta
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from app.clients.supabase import SupabaseRestClient
from app.models.health_connect import HealthConnectCommand, HealthConnectDay, HealthConnectState


class HealthConnectService:
    """Owner-scoped commands and the current timezone-aware sharing projection."""

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
        state = self._state(rows[0])
        values = await self._client.select("behavioral_events", params={
            "select": "event_type,value,metadata",
            "user_id": f"eq.{user_id}", "source": "eq.health_connect",
            "metadata->>date": f"eq.{state.window_end.isoformat()}",
            "metadata->>timezone": f"eq.{state.timezone}",
            "event_type": "in.(health_connect_steps,health_connect_sleep_minutes,health_connect_heart_rate,health_connect_resting_heart_rate)",
            "limit": "4",
        })
        latest = {"date": state.window_end}
        for item in values:
            metric = item.get("event_type", "").removeprefix("health_connect_")
            if metric not in {"steps", "sleep_minutes", "heart_rate", "resting_heart_rate"}:
                continue
            value = item.get("value")
            latest[metric] = int(value) if value is not None and metric != "sleep_minutes" else value
            if metric in {"heart_rate", "resting_heart_rate"}:
                latest[metric + "_read"] = True
        return state.model_copy(update={"latest": HealthConnectDay(**latest)})

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
