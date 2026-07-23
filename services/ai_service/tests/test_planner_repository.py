import asyncio
from datetime import date
from uuid import UUID

from app.repositories.planner_repository import SupabasePlannerRepository


class Client:
    def __init__(self) -> None:
        self.calls = []

    async def select(self, table, *, params):
        self.calls.append((table, params))
        if table == "profiles":
            return [{"timezone": "Europe/Berlin"}]
        if table == "intake_responses":
            return [{"responses": {"best_energy_window": "morning"}}]
        return []


def test_availability_schedule_read_includes_semester_metadata() -> None:
    client = Client()
    repository = SupabasePlannerRepository(client)

    context = asyncio.run(
        repository.load_availability_context(
            user_id="owner",
            plan_id=UUID("10000000-0000-4000-8000-000000000001"),
            target_kind="task",
            target_id=UUID("20000000-0000-4000-8000-000000000001"),
            starts_on=date(2026, 7, 20),
            ends_on=date(2026, 7, 27),
        ),
    )

    assert context.schedule_items == []
    params = next(
        params for table, params in client.calls if table == "schedule_items"
    )
    assert "metadata" in params["select"]
