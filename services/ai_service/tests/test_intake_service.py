import asyncio

from app.models.intake import IntakeCompleteRequest
from app.services.intake_service import IntakeService


class FakeIntakeRepository:
    def __init__(self) -> None:
        self.intake_rows: list[dict[str, object]] = []
        self.profile_updates: list[tuple[str, dict[str, object]]] = []
        self.preference_rows: list[dict[str, object]] = []
        self.goal_rows: list[dict[str, object]] = []
        self.habit_rows: list[dict[str, object]] = []
        self.schedule_rows: list[dict[str, object]] = []
        self.memory_rows: list[dict[str, object]] = []
        self.snapshot_rows: list[dict[str, object]] = []

    async def insert_intake_response(self, *, user_id: str, row: dict):
        stored = {"id": "intake-123", "user_id": user_id, **row}
        self.intake_rows.append(stored)
        return stored

    async def update_profile_onboarding(self, *, user_id: str, values: dict):
        self.profile_updates.append((user_id, values))

    async def upsert_notification_preferences(self, *, row: dict):
        self.preference_rows.append(row)

    async def insert_goals(self, *, rows: list[dict]):
        self.goal_rows.extend(rows)

    async def insert_habits(self, *, rows: list[dict]):
        self.habit_rows.extend(rows)

    async def insert_schedule_items(self, *, rows: list[dict]):
        self.schedule_rows.extend(rows)

    async def insert_memory_entries(self, *, rows: list[dict]):
        self.memory_rows.extend(rows)

    async def insert_user_state_snapshot(self, *, row: dict):
        stored = {"id": "snapshot-123", **row}
        self.snapshot_rows.append(stored)
        return stored


def run(coro):
    return asyncio.run(coro)


def request() -> IntakeCompleteRequest:
    return IntakeCompleteRequest.model_validate(
        {
            "version": "intake-v1",
            "responses": {
                "display_name": "Ada",
                "primary_focus_areas": ["focus", "planning"],
                "goals": ["Protect focus time", "Plan tomorrow before dinner"],
                "friction_points": ["Too many context switches"],
                "weekday_shape": "Mornings are school, afternoons are open.",
                "best_energy_window": "morning",
                "coaching_style": "analytical",
                "reminder_preference": {
                    "enabled": True,
                    "quiet_hours": {"starts_at": "21:30", "ends_at": "07:00"},
                },
                "existing_habits": ["Walk after lunch"],
                "fixed_commitments": [
                    {
                        "title": "Math",
                        "location": "Room 204",
                        "weekday": 1,
                        "starts_at": "08:15",
                        "ends_at": "09:45",
                    },
                ],
                "context_note": "Prefer concise prompts.",
                "calendar_connection_intent": "later",
            },
            "metadata": {"client": "test"},
        },
    )


def test_complete_intake_derives_all_writes_from_principal_user_id() -> None:
    repository = FakeIntakeRepository()
    response = run(
        IntakeService(repository).complete_intake(
            user_id="principal-user-123",
            request=request(),
        ),
    )

    assert response.intake_response_id == "intake-123"
    assert response.snapshot_id == "snapshot-123"
    assert repository.intake_rows[0]["user_id"] == "principal-user-123"
    assert repository.profile_updates[0][0] == "principal-user-123"
    assert repository.preference_rows[0]["user_id"] == "principal-user-123"
    assert {row["user_id"] for row in repository.goal_rows} == {
        "principal-user-123",
    }
    assert {row["user_id"] for row in repository.habit_rows} == {
        "principal-user-123",
    }
    assert {row["user_id"] for row in repository.schedule_rows} == {
        "principal-user-123",
    }
    assert {row["user_id"] for row in repository.memory_rows} == {
        "principal-user-123",
    }
    assert repository.snapshot_rows[0]["user_id"] == "principal-user-123"


def test_complete_intake_stores_raw_answers_and_snapshot_summary() -> None:
    repository = FakeIntakeRepository()
    run(
        IntakeService(repository).complete_intake(
            user_id="principal-user-123",
            request=request(),
        ),
    )

    responses = repository.intake_rows[0]["responses"]
    assert responses["primary_focus_areas"] == ["focus", "planning"]
    assert responses["goals"] == [
        "Protect focus time",
        "Plan tomorrow before dinner",
    ]
    assert responses["calendar_connection_intent"] == "later"
    assert repository.goal_rows[0]["title"] == "Protect focus time"
    assert repository.habit_rows[0]["title"] == "Walk after lunch"
    assert repository.schedule_rows[0]["source"] == "onboarding"
    assert repository.preference_rows[0]["quiet_hours_start"] == "21:30"
    assert repository.preference_rows[0]["quiet_hours_end"] == "07:00"
    assert repository.snapshot_rows[0]["scope"] == "onboarding"
    assert repository.snapshot_rows[0]["summary"]["best_energy_window"] == "morning"
    assert repository.snapshot_rows[0]["signals"]["calendar_connection_intent"] == "later"
    assert any(row["type"] == "goal" for row in repository.memory_rows)
    assert any(row["title"] == "Preferred coaching style" for row in repository.memory_rows)
