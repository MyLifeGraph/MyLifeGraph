from app.clients.supabase import SupabaseRestClient
from app.models.coach_phone_data import PhoneCommand, PhoneState


class CoachPhoneDataService:
    def __init__(self, client: SupabaseRestClient):
        self.client = client

    async def read(self, user_id: str) -> PhoneState:
        rows = await self.client.select(
            "profiles",
            params={
                "select": "timezone,coach_phone_data",
                "id": f"eq.{user_id}",
                "limit": "1",
            },
        )
        if len(rows) != 1:
            raise ValueError("Profile unavailable")
        return PhoneState(**rows[0]["coach_phone_data"], timezone=rows[0]["timezone"])

    async def apply(self, user_id: str, command: PhoneCommand) -> PhoneState:
        row = await self.client.rpc(
            "apply_coach_phone_data_v1",
            params={
                "p_user_id": user_id,
                "p_request": command.model_dump(mode="json"),
            },
        )
        return PhoneState(**row["coach_phone_data"], timezone=row["timezone"])
