from datetime import UTC, datetime
from typing import Any

from app.models.intake import (
    IntakeCompleteRequest,
    IntakeCompleteResponse,
    SnapshotSummary,
)
from app.repositories.intake_repository import IntakeRepository


class IntakeService:
    def __init__(self, repository: IntakeRepository) -> None:
        self._repository = repository

    async def complete_intake(
        self,
        *,
        user_id: str,
        request: IntakeCompleteRequest,
    ) -> IntakeCompleteResponse:
        completed_at = datetime.now(tz=UTC)
        responses = request.responses
        responses_json = responses.model_dump(mode="json", exclude_none=True)

        intake_row = await self._repository.insert_intake_response(
            user_id=user_id,
            row={
                "version": request.version,
                "responses": responses_json,
                "completed_at": completed_at.isoformat(),
                "metadata": {
                    **request.metadata,
                    "source": request.metadata.get("source", "onboarding"),
                },
            },
        )

        profile_values: dict[str, Any] = {
            "onboarding_completed_at": completed_at.isoformat(),
            "updated_at": completed_at.isoformat(),
        }
        if responses.display_name:
            profile_values["display_name"] = responses.display_name
        await self._repository.update_profile_onboarding(
            user_id=user_id,
            values=profile_values,
        )

        reminder = responses.reminder_preference
        await self._repository.upsert_notification_preferences(
            row={
                "user_id": user_id,
                "focus_prompts_enabled": reminder.enabled,
                "recovery_prompts_enabled": reminder.enabled,
                "weekly_summary_enabled": reminder.enabled,
                "quiet_hours_start": reminder.quiet_hours.starts_at,
                "quiet_hours_end": reminder.quiet_hours.ends_at,
                "updated_at": completed_at.isoformat(),
            },
        )

        await self._repository.insert_goals(
            rows=[
                {
                    "user_id": user_id,
                    "title": goal,
                    "status": "active",
                    "metadata": {
                        "source": "intake-v1",
                        "focus_areas": responses.primary_focus_areas,
                    },
                    "updated_at": completed_at.isoformat(),
                }
                for goal in responses.goals
            ],
        )

        await self._repository.insert_habits(
            rows=[
                {
                    "user_id": user_id,
                    "title": habit,
                    "frequency": "daily",
                    "metadata": {"source": "intake-v1"},
                    "updated_at": completed_at.isoformat(),
                }
                for habit in responses.existing_habits
            ],
        )

        await self._repository.insert_schedule_items(
            rows=[
                {
                    "user_id": user_id,
                    "title": commitment.title,
                    "location": commitment.location,
                    "weekday": commitment.weekday,
                    "starts_at": commitment.starts_at,
                    "ends_at": commitment.ends_at,
                    "source": "onboarding",
                    "metadata": {"source": "intake-v1"},
                    "updated_at": completed_at.isoformat(),
                }
                for commitment in responses.fixed_commitments
            ],
        )

        memory_rows = _memory_rows(
            user_id=user_id,
            completed_at=completed_at,
            request=request,
        )
        await self._repository.insert_memory_entries(rows=memory_rows)

        summary = SnapshotSummary(
            primary_focus_areas=responses.primary_focus_areas,
            goals=responses.goals,
            friction_points=responses.friction_points,
            best_energy_window=responses.best_energy_window,
            coaching_style=responses.coaching_style,
            reminder_enabled=responses.reminder_preference.enabled,
            fixed_commitment_count=len(responses.fixed_commitments),
            existing_habit_count=len(responses.existing_habits),
        )
        snapshot_row = await self._repository.insert_user_state_snapshot(
            row={
                "user_id": user_id,
                "scope": "onboarding",
                "period_key": f"onboarding:{completed_at.date().isoformat()}",
                "summary": summary.model_dump(mode="json"),
                "signals": {
                    "focus_areas": responses.primary_focus_areas,
                    "friction_points": responses.friction_points,
                    "calendar_connection_intent": responses.calendar_connection_intent,
                },
                "source": "backend",
                "generated_at": completed_at.isoformat(),
                "metadata": {
                    "source": "intake-v1",
                    "intake_response_id": str(intake_row["id"]),
                },
            },
        )

        return IntakeCompleteResponse(
            intake_response_id=str(intake_row["id"]),
            snapshot_id=str(snapshot_row["id"]),
            completed_at=completed_at,
            summary=summary,
            recommendations=[],
        )


def _memory_rows(
    *,
    user_id: str,
    completed_at: datetime,
    request: IntakeCompleteRequest,
) -> list[dict[str, Any]]:
    responses = request.responses
    evidence = [
        {
            "source": "intake-v1",
            "completed_at": completed_at.isoformat(),
        },
    ]
    rows: list[dict[str, Any]] = []
    for goal in responses.goals:
        rows.append(
            _memory_row(
                user_id=user_id,
                completed_at=completed_at,
                memory_type="goal",
                title=f"Goal: {goal}",
                content=goal,
                evidence=evidence,
            ),
        )
    rows.append(
        _memory_row(
            user_id=user_id,
            completed_at=completed_at,
            memory_type="preference",
            title="Preferred coaching style",
            content=f"{responses.coaching_style} coaching",
            evidence=evidence,
        ),
    )
    rows.append(
        _memory_row(
            user_id=user_id,
            completed_at=completed_at,
            memory_type="pattern",
            title="Best energy window",
            content=responses.best_energy_window,
            evidence=evidence,
        ),
    )
    if responses.context_note:
        rows.append(
            _memory_row(
                user_id=user_id,
                completed_at=completed_at,
                memory_type="preference",
                title="Intake context note",
                content=responses.context_note,
                evidence=evidence,
            ),
        )
    return rows


def _memory_row(
    *,
    user_id: str,
    completed_at: datetime,
    memory_type: str,
    title: str,
    content: str,
    evidence: list[dict[str, str]],
) -> dict[str, Any]:
    return {
        "user_id": user_id,
        "type": memory_type,
        "title": title,
        "content": content,
        "strength": 0.7,
        "evidence": evidence,
        "metadata": {"source": "intake-v1"},
        "last_seen_at": completed_at.isoformat(),
        "updated_at": completed_at.isoformat(),
    }
