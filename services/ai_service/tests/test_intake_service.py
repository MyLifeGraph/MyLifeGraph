import asyncio
from copy import deepcopy
from datetime import UTC, datetime
from uuid import NAMESPACE_URL, UUID, uuid5

import pytest

from app.models.intake import IntakeCompleteRequest
from app.repositories.intake_repository import (
    AtomicSetupApply,
    IntakeApplyConflict,
    IntakeClaimConflict,
    SetupMaterialization,
    SetupOwnershipConflict,
)
from app.services.intake_service import IntakeRevisionConflict, IntakeService


USER_ID = "principal-user-123"
REQUEST_1 = "00000000-0000-4000-8000-000000000001"
REQUEST_2 = "00000000-0000-4000-8000-000000000002"
GOAL_KEY = "10000000-0000-4000-8000-000000000001"
ROUTINE_KEY = "20000000-0000-4000-8000-000000000001"
COMMITMENT_KEY = "30000000-0000-4000-8000-000000000001"
NOW = datetime(2026, 7, 10, 10, 0, tzinfo=UTC)


class FakeIntakeRepository:
    def __init__(self) -> None:
        self.intakes: list[dict] = []
        self.preferences: dict[str, dict] = {}
        self.goals: dict[str, dict] = {}
        self.habits: dict[str, dict] = {}
        self.schedule: dict[str, dict] = {}
        self.memories: dict[str, dict] = {}
        self.snapshots: dict[tuple[str, str, str], dict] = {}
        self.profile_updates: list[tuple[str, dict]] = []
        self.profile_values: dict = {"setup_revision": 0}
        self.atomic_apply_calls: list[tuple[str, str, int]] = []
        self.fail_atomic_once_after_preferences = False
        self.return_stale_pending_once_for: str | None = None
        self.apply_entered: asyncio.Event | None = None
        self.release_apply: asyncio.Event | None = None
        self._claim_lock = asyncio.Lock()
        self._apply_lock = asyncio.Lock()

    async def load_intake_by_request(self, *, user_id: str, request_id: UUID):
        await asyncio.sleep(0)
        row = next(
            (
                deepcopy(row)
                for row in self.intakes
                if row["user_id"] == user_id
                and row["request_id"] == str(request_id)
            ),
            None,
        )
        if (
            row is not None
            and self.return_stale_pending_once_for == str(request_id)
        ):
            self.return_stale_pending_once_for = None
            row["state"] = "pending"
        return row

    async def load_latest_intake(self, *, user_id: str):
        await asyncio.sleep(0)
        rows = [row for row in self.intakes if row["user_id"] == user_id]
        if not rows:
            return None
        return deepcopy(max(rows, key=lambda row: row["revision"]))

    async def load_latest_applied_intake(self, *, user_id: str):
        await asyncio.sleep(0)
        rows = [
            row
            for row in self.intakes
            if row["user_id"] == user_id and row["state"] == "applied"
        ]
        if not rows:
            return None
        return deepcopy(max(rows, key=lambda row: row["revision"]))

    async def insert_pending_intake(self, *, user_id: str, row: dict):
        await asyncio.sleep(0)
        async with self._claim_lock:
            if any(
                existing["user_id"] == user_id
                and existing["version"] == row["version"]
                and (
                    existing["request_id"] == row["request_id"]
                    or existing["revision"] == row["revision"]
                )
                for existing in self.intakes
            ):
                raise IntakeClaimConflict
            stored = {"user_id": user_id, **deepcopy(row)}
            self.intakes.append(stored)
            return deepcopy(stored)

    async def apply_setup_revision(
        self,
        *,
        user_id: str,
        intake_response_id: str,
        request_id: UUID,
        base_revision: int,
        revision: int,
        apply: AtomicSetupApply,
    ):
        self.atomic_apply_calls.append((user_id, intake_response_id, revision))
        async with self._apply_lock:
            if self.apply_entered is not None:
                self.apply_entered.set()
            if self.release_apply is not None:
                await self.release_apply.wait()

            target = next(
                row
                for row in self.intakes
                if row["user_id"] == user_id and row["id"] == intake_response_id
            )
            if (
                target["request_id"] != str(request_id)
                or target["base_revision"] != base_revision
                or target["revision"] != revision
            ):
                raise IntakeApplyConflict("atomic apply rejected stale identity")
            if target["state"] == "applied":
                latest_applied = max(
                    (
                        row
                        for row in self.intakes
                        if row["user_id"] == user_id and row["state"] == "applied"
                    ),
                    key=lambda row: row["revision"],
                )
                if latest_applied["id"] == target["id"]:
                    self._project_profile(user_id=user_id, row=target)
                return _apply_result(target)

            latest = max(
                (row for row in self.intakes if row["user_id"] == user_id),
                key=lambda row: row["revision"],
            )
            if latest["id"] != target["id"]:
                raise IntakeApplyConflict("atomic apply rejected stale revision")
            if int(self.profile_values.get("setup_revision") or 0) >= revision:
                raise IntakeApplyConflict("profile already has this revision")

            before = self._transaction_state()
            try:
                self._assert_no_ownership_collisions(apply.materialization)
                self.preferences[user_id] = {
                    "user_id": user_id,
                    **deepcopy(apply.notification_preferences),
                }
                if self.fail_atomic_once_after_preferences:
                    self.fail_atomic_once_after_preferences = False
                    raise RuntimeError("simulated atomic backend failure")
                _reconcile_archived(
                    self.goals,
                    apply.materialization.goals,
                    revision=revision,
                    archived_values={"status": "archived"},
                )
                _reconcile_archived(
                    self.habits,
                    apply.materialization.habits,
                    revision=revision,
                    archived_values={"active": False},
                )
                _reconcile_deleted(
                    self.schedule,
                    apply.materialization.schedule_items,
                    include_legacy_default=True,
                )
                _reconcile_deleted(
                    self.memories,
                    apply.materialization.memory_entries,
                )
                snapshot_key = (user_id, "onboarding", "setup:intake-v1")
                existing_snapshot = self.snapshots.get(snapshot_key)
                snapshot = {
                    "id": (
                        existing_snapshot["id"]
                        if existing_snapshot
                        else "snapshot-123"
                    ),
                    **deepcopy(apply.snapshot),
                }
                self.snapshots[snapshot_key] = snapshot
                target.update(
                    {
                        "state": "applied",
                        "completed_at": apply.completed_at,
                        "updated_at": apply.completed_at,
                        "metadata": {
                            **deepcopy(apply.intake_metadata),
                            "snapshot_id": snapshot["id"],
                        },
                    },
                )
                self._project_profile(user_id=user_id, row=target)
            except Exception:
                self._restore_transaction_state(before)
                raise
            return _apply_result(target)

    def _project_profile(self, *, user_id: str, row: dict) -> None:
        revision = int(row["revision"])
        if int(self.profile_values.get("setup_revision") or 0) >= revision:
            return
        values = {
            "onboarding_completed_at": row["completed_at"],
            "updated_at": row["completed_at"],
            "setup_revision": revision,
        }
        responses = row.get("responses")
        if isinstance(responses, dict) and "display_name" in responses:
            values["display_name"] = responses["display_name"]
        self.profile_updates.append((user_id, deepcopy(values)))
        self.profile_values.update(values)

    def _assert_no_ownership_collisions(
        self,
        materialization: SetupMaterialization,
    ) -> None:
        for store, desired in (
            (self.goals, materialization.goals),
            (self.habits, materialization.habits),
            (self.schedule, materialization.schedule_items),
            (self.memories, materialization.memory_entries),
        ):
            for row in desired:
                existing = store.get(row["id"])
                if existing is not None and not _is_setup(existing):
                    raise SetupOwnershipConflict(
                        "Setup id collides with a non-Setup row",
                    )

    def _transaction_state(self) -> dict:
        return deepcopy(
            {
                "intakes": self.intakes,
                "preferences": self.preferences,
                "goals": self.goals,
                "habits": self.habits,
                "schedule": self.schedule,
                "memories": self.memories,
                "snapshots": self.snapshots,
                "profile_updates": self.profile_updates,
                "profile_values": self.profile_values,
            },
        )

    def _restore_transaction_state(self, state: dict) -> None:
        self.intakes = state["intakes"]
        self.preferences = state["preferences"]
        self.goals = state["goals"]
        self.habits = state["habits"]
        self.schedule = state["schedule"]
        self.memories = state["memories"]
        self.snapshots = state["snapshots"]
        self.profile_updates = state["profile_updates"]
        self.profile_values = state["profile_values"]

    async def load_latest_onboarding_snapshot(self, *, user_id: str):
        rows = [
            row
            for (snapshot_user_id, scope, _), row in self.snapshots.items()
            if snapshot_user_id == user_id and scope == "onboarding"
        ]
        return deepcopy(rows[-1]) if rows else None


class FakeRecommendationResponse:
    items: list = []


class FakeRecommendationEngine:
    def __init__(self) -> None:
        self.calls: list[tuple[str, object]] = []

    async def generate_recommendations(self, *, user_id: str, request):
        self.calls.append((user_id, request))
        return FakeRecommendationResponse()


def _is_setup(row: dict) -> bool:
    metadata = row.get("metadata", {})
    return metadata.get("managed_by") == "setup" or metadata.get("source") == "intake-v1"


def _apply_result(row: dict) -> dict:
    return {
        "intake_response_id": row["id"],
        "request_id": row["request_id"],
        "base_revision": row["base_revision"],
        "revision": row["revision"],
        "state": row["state"],
        "completed_at": row["completed_at"],
        "snapshot_id": row.get("metadata", {}).get("snapshot_id"),
    }


def _reconcile_archived(
    store: dict[str, dict],
    desired: list[dict],
    *,
    revision: int,
    archived_values: dict,
) -> None:
    desired_ids = {row["id"] for row in desired}
    for row in desired:
        store[row["id"]] = deepcopy(row)
    for row_id, row in store.items():
        if row_id in desired_ids or not _is_setup(row):
            continue
        row.update(archived_values)
        row["metadata"] = {
            **row.get("metadata", {}),
            "setup_state": "archived",
            "revision": revision,
        }


def _reconcile_deleted(
    store: dict[str, dict],
    desired: list[dict],
    *,
    include_legacy_default: bool = False,
) -> None:
    desired_ids = {row["id"] for row in desired}
    for row in desired:
        store[row["id"]] = deepcopy(row)
    for row_id in list(store):
        should_manage = _is_setup(store[row_id]) or (
            include_legacy_default and _is_exact_legacy_default_schedule(store[row_id])
        )
        if row_id not in desired_ids and should_manage:
            del store[row_id]


def _is_exact_legacy_default_schedule(row: dict) -> bool:
    return (
        row.get("source") == "onboarding"
        and row.get("metadata", {}) == {}
        and row.get("title") == "Math"
        and row.get("location") == "Room 204"
        and row.get("weekday") == 1
        and str(row.get("starts_at") or "")[:5] == "08:15"
        and str(row.get("ends_at") or "")[:5] == "09:45"
        and row.get("notes") is None
    )


def run(coro):
    return asyncio.run(coro)


def payload(
    *,
    request_id: str = REQUEST_1,
    base_revision: int = 0,
    goals: list[dict] | None = None,
    routines: list[dict] | None = None,
    commitments: list[dict] | None = None,
    friction_points: list[str] | None = None,
    context_note: str | None = None,
    calendar_connection_intent: str | None = None,
    reminders_enabled: bool = True,
    display_name: str = "Ada",
) -> dict:
    reminder: dict = {"enabled": reminders_enabled}
    if reminders_enabled:
        reminder["quiet_hours"] = {"starts_at": "21:30", "ends_at": "07:00"}
    responses = {
        "display_name": display_name,
        "primary_focus_areas": ["focus", "planning"],
        "goals": goals or [],
        "friction_points": friction_points or [],
        "weekday_shape": "Mornings are structured; afternoons are flexible.",
        "best_energy_window": "morning",
        "coaching_style": "analytical",
        "reminder_preference": reminder,
        "routines": routines or [],
        "fixed_commitments": commitments or [],
    }
    if context_note is not None:
        responses["context_note"] = context_note
    if calendar_connection_intent is not None:
        responses["calendar_connection_intent"] = calendar_connection_intent
    return {
        "request_id": request_id,
        "base_revision": base_revision,
        "version": "intake-v1",
        "responses": responses,
        "metadata": {"client": "test", "source": "attacker-controlled"},
    }


def request(**overrides) -> IntakeCompleteRequest:
    return IntakeCompleteRequest.model_validate(payload(**overrides))


def goal(title: str = "Protect focus time", status: str = "active") -> dict:
    return {"key": GOAL_KEY, "title": title, "status": status}


def candidate_routine() -> dict:
    return {
        "key": ROUTINE_KEY,
        "title": "Walk after lunch",
        "status": "candidate",
        "cadence_confirmed": False,
    }


def active_routine(status: str = "active") -> dict:
    return {
        "key": ROUTINE_KEY,
        "title": "Walk after lunch",
        "status": status,
        "cadence_confirmed": True,
        "frequency": "weekly",
        "target": 3,
    }


def commitment() -> dict:
    return {
        "key": COMMITMENT_KEY,
        "title": "Math",
        "location": "Room 204",
        "weekday": 1,
        "starts_at": "08:15",
        "ends_at": "09:45",
        "status": "active",
    }


def test_zero_optional_answers_create_no_optional_commitments() -> None:
    repository = FakeIntakeRepository()
    response = run(
        IntakeService(repository, now_provider=lambda: NOW).complete_intake(
            user_id=USER_ID,
            request=request(reminders_enabled=False),
        ),
    )

    assert response.exists is True
    assert response.revision == 1
    assert response.responses.goals == []
    assert response.responses.friction_points == []
    assert response.responses.calendar_connection_intent is None
    assert repository.goals == {}
    assert repository.habits == {}
    assert repository.schedule == {}
    assert {row["title"] for row in repository.memories.values()} == {
        "Preferred coaching style",
        "Best energy window",
    }
    assert repository.preferences[USER_ID]["quiet_hours_start"] is None
    assert repository.intakes[0]["metadata"]["source"] == "onboarding"
    assert repository.intakes[0]["metadata"]["request_metadata"]["source"] == (
        "attacker-controlled"
    )


def test_candidate_routine_never_creates_habit_row() -> None:
    repository = FakeIntakeRepository()

    response = run(
        IntakeService(repository, now_provider=lambda: NOW).complete_intake(
            user_id=USER_ID,
            request=request(routines=[candidate_routine()]),
        ),
    )

    assert repository.habits == {}
    assert response.summary.routine_candidate_count == 1
    assert response.summary.active_habit_count == 0


def test_confirmed_routine_creates_one_exact_habit() -> None:
    repository = FakeIntakeRepository()

    run(
        IntakeService(repository, now_provider=lambda: NOW).complete_intake(
            user_id=USER_ID,
            request=request(routines=[active_routine()]),
        ),
    )

    assert len(repository.habits) == 1
    row = next(iter(repository.habits.values()))
    assert row["frequency"] == "weekly"
    assert row["target"] == 3
    assert row["active"] is True
    assert row["metadata"]["setup_item_id"] == ROUTINE_KEY


def test_archived_routine_is_not_counted_as_existing_habit() -> None:
    repository = FakeIntakeRepository()
    service = IntakeService(repository, now_provider=lambda: NOW)
    run(
        service.complete_intake(
            user_id=USER_ID,
            request=request(routines=[active_routine()]),
        ),
    )

    archived = run(
        service.complete_intake(
            user_id=USER_ID,
            request=request(
                request_id=REQUEST_2,
                base_revision=1,
                routines=[active_routine(status="archived")],
            ),
        ),
    )

    assert archived.summary.existing_habit_count == 0
    assert archived.summary.active_habit_count == 0
    snapshot = repository.snapshots[(USER_ID, "onboarding", "setup:intake-v1")]
    assert snapshot["summary"]["existing_habit_count"] == 0
    assert snapshot["summary"]["active_habit_count"] == 0


def test_same_request_twice_returns_same_ids_without_duplicates() -> None:
    repository = FakeIntakeRepository()
    recommendation_engine = FakeRecommendationEngine()
    service = IntakeService(
        repository,
        recommendation_engine=recommendation_engine,
        now_provider=lambda: NOW,
    )
    intake_request = request(
        goals=[goal()],
        routines=[active_routine()],
        commitments=[commitment()],
    )

    first = run(service.complete_intake(user_id=USER_ID, request=intake_request))
    second = run(service.complete_intake(user_id=USER_ID, request=intake_request))

    assert first.intake_response_id == second.intake_response_id
    assert first.snapshot_id == second.snapshot_id
    assert first.revision == second.revision == 1
    assert len(repository.intakes) == 1
    assert len(repository.goals) == 1
    assert len(repository.habits) == 1
    assert len(repository.schedule) == 1
    assert len(repository.snapshots) == 1
    assert len(recommendation_engine.calls) == 2


def test_parallel_same_request_workers_converge_through_atomic_apply() -> None:
    async def scenario():
        repository = FakeIntakeRepository()
        repository.apply_entered = asyncio.Event()
        repository.release_apply = asyncio.Event()
        service = IntakeService(repository, now_provider=lambda: NOW)
        intake_request = request(
            goals=[goal()],
            routines=[active_routine()],
            commitments=[commitment()],
        )

        first_task = asyncio.create_task(
            service.complete_intake(user_id=USER_ID, request=intake_request),
        )
        await repository.apply_entered.wait()
        second_task = asyncio.create_task(
            service.complete_intake(user_id=USER_ID, request=intake_request),
        )
        for _ in range(20):
            if len(repository.atomic_apply_calls) == 2:
                break
            await asyncio.sleep(0)
        repository.release_apply.set()
        first, second = await asyncio.gather(first_task, second_task)
        return repository, first, second

    repository, first, second = run(scenario())

    assert first.intake_response_id == second.intake_response_id
    assert first.snapshot_id == second.snapshot_id
    assert first.revision == second.revision == 1
    assert len(repository.atomic_apply_calls) == 2
    assert len(repository.intakes) == 1
    assert len(repository.goals) == 1
    assert len(repository.habits) == 1
    assert len(repository.schedule) == 1
    assert len(repository.snapshots) == 1
    assert len(repository.profile_updates) == 1


def test_later_revision_cannot_claim_while_atomic_apply_is_in_flight() -> None:
    async def scenario():
        repository = FakeIntakeRepository()
        repository.apply_entered = asyncio.Event()
        repository.release_apply = asyncio.Event()
        service = IntakeService(repository, now_provider=lambda: NOW)
        first_task = asyncio.create_task(
            service.complete_intake(
                user_id=USER_ID,
                request=request(goals=[goal("Revision 1")]),
            ),
        )
        await repository.apply_entered.wait()
        with pytest.raises(IntakeRevisionConflict) as error:
            await service.complete_intake(
                user_id=USER_ID,
                request=request(
                    request_id=REQUEST_2,
                    base_revision=1,
                    goals=[goal("Revision 2")],
                ),
            )
        repository.release_apply.set()
        first = await first_task
        return repository, first, error.value

    repository, first, conflict = run(scenario())

    assert first.revision == 1
    assert conflict.current_revision == 0
    assert conflict.pending_request_id == REQUEST_1
    assert len(repository.intakes) == 1
    assert repository.goals[next(iter(repository.goals))]["title"] == "Revision 1"


def test_reusing_request_id_with_changed_payload_is_rejected() -> None:
    repository = FakeIntakeRepository()
    service = IntakeService(repository, now_provider=lambda: NOW)
    run(service.complete_intake(user_id=USER_ID, request=request(goals=[goal()])))
    before = deepcopy(repository.goals)

    with pytest.raises(IntakeRevisionConflict, match="different setup payload"):
        run(
            service.complete_intake(
                user_id=USER_ID,
                request=request(goals=[goal("Changed under the same request id")]),
            ),
        )

    assert repository.goals == before
    assert len(repository.intakes) == 1


def test_edit_keeps_stable_goal_id_and_updates_title() -> None:
    repository = FakeIntakeRepository()
    service = IntakeService(repository, now_provider=lambda: NOW)
    first = run(
        service.complete_intake(
            user_id=USER_ID,
            request=request(goals=[goal()]),
        ),
    )
    record_id = next(iter(repository.goals))

    second = run(
        service.complete_intake(
            user_id=USER_ID,
            request=request(
                request_id=REQUEST_2,
                base_revision=1,
                goals=[goal("Protect two focus blocks")],
            ),
        ),
    )

    assert first.revision == 1
    assert second.revision == 2
    assert list(repository.goals) == [record_id]
    assert repository.goals[record_id]["title"] == "Protect two focus blocks"
    assert second.snapshot_id == first.snapshot_id


def test_replaying_old_applied_revision_does_not_revert_latest_profile() -> None:
    repository = FakeIntakeRepository()
    service = IntakeService(repository, now_provider=lambda: NOW)
    revision_1_request = request(display_name="Ada")
    first = run(
        service.complete_intake(user_id=USER_ID, request=revision_1_request),
    )
    second = run(
        service.complete_intake(
            user_id=USER_ID,
            request=request(
                request_id=REQUEST_2,
                base_revision=1,
                display_name="Grace",
            ),
        ),
    )
    profile_updates_before_replay = len(repository.profile_updates)

    replay = run(
        service.complete_intake(user_id=USER_ID, request=revision_1_request),
    )

    assert first.revision == replay.revision == 1
    assert first.intake_response_id == replay.intake_response_id
    assert second.revision == 2
    assert replay.responses.display_name == "Ada"
    assert repository.profile_values["display_name"] == "Grace"
    assert repository.profile_values["setup_revision"] == 2
    assert len(repository.profile_updates) == profile_updates_before_replay


def test_replaying_latest_applied_revision_repairs_missing_profile_marker() -> None:
    repository = FakeIntakeRepository()
    service = IntakeService(repository, now_provider=lambda: NOW)
    intake_request = request(display_name="Stored canonical name")
    first = run(service.complete_intake(user_id=USER_ID, request=intake_request))
    repository.profile_values = {
        "setup_revision": 0,
        "display_name": "Incomplete projection",
    }
    repository.profile_updates.clear()

    replay = run(service.complete_intake(user_id=USER_ID, request=intake_request))

    assert replay.intake_response_id == first.intake_response_id
    assert repository.profile_values["setup_revision"] == 1
    assert repository.profile_values["display_name"] == "Stored canonical name"
    assert len(repository.profile_updates) == 1


def test_stale_duplicate_worker_cannot_reapply_after_newer_revision() -> None:
    repository = FakeIntakeRepository()
    service = IntakeService(repository, now_provider=lambda: NOW)
    revision_1_request = request(
        goals=[goal("Revision 1 goal")],
        display_name="Revision 1",
    )
    first = run(
        service.complete_intake(user_id=USER_ID, request=revision_1_request),
    )
    run(
        service.complete_intake(
            user_id=USER_ID,
            request=request(
                request_id=REQUEST_2,
                base_revision=1,
                goals=[goal("Revision 2 goal")],
                display_name="Revision 2",
            ),
        ),
    )
    state_before_stale_worker = {
        "preferences": deepcopy(repository.preferences),
        "goals": deepcopy(repository.goals),
        "habits": deepcopy(repository.habits),
        "schedule": deepcopy(repository.schedule),
        "memories": deepcopy(repository.memories),
        "snapshots": deepcopy(repository.snapshots),
        "profile": deepcopy(repository.profile_values),
        "profile_update_count": len(repository.profile_updates),
    }
    # Simulate worker B having cached revision 1 while worker A and then
    # revision 2 already committed in the shared repository.
    repository.return_stale_pending_once_for = REQUEST_1

    replay = run(
        service.complete_intake(user_id=USER_ID, request=revision_1_request),
    )

    assert replay.revision == first.revision == 1
    assert replay.intake_response_id == first.intake_response_id
    assert repository.preferences == state_before_stale_worker["preferences"]
    assert repository.goals == state_before_stale_worker["goals"]
    assert repository.habits == state_before_stale_worker["habits"]
    assert repository.schedule == state_before_stale_worker["schedule"]
    assert repository.memories == state_before_stale_worker["memories"]
    assert repository.snapshots == state_before_stale_worker["snapshots"]
    assert repository.profile_values == state_before_stale_worker["profile"]
    assert len(repository.profile_updates) == state_before_stale_worker[
        "profile_update_count"
    ]


def test_omission_archives_or_deletes_only_setup_owned_rows() -> None:
    repository = FakeIntakeRepository()
    service = IntakeService(repository, now_provider=lambda: NOW)
    run(
        service.complete_intake(
            user_id=USER_ID,
            request=request(
                goals=[goal()],
                routines=[active_routine()],
                commitments=[commitment()],
                context_note="Prefer short prompts.",
            ),
        ),
    )
    setup_goal_id = next(iter(repository.goals))
    setup_habit_id = next(iter(repository.habits))
    repository.goals["manual-goal"] = {
        "id": "manual-goal",
        "user_id": USER_ID,
        "title": "Manual",
        "status": "active",
        "metadata": {"source": "manual"},
    }
    repository.habits["manual-habit"] = {
        "id": "manual-habit",
        "user_id": USER_ID,
        "title": "Manual",
        "active": True,
        "metadata": {},
    }
    repository.schedule["manual-schedule"] = {
        "id": "manual-schedule",
        "user_id": USER_ID,
        "source": "manual",
        "metadata": {},
    }
    repository.memories["manual-memory"] = {
        "id": "manual-memory",
        "user_id": USER_ID,
        "title": "Manual",
        "metadata": {"source": "manual"},
    }

    run(
        service.complete_intake(
            user_id=USER_ID,
            request=request(request_id=REQUEST_2, base_revision=1),
        ),
    )

    assert repository.goals[setup_goal_id]["status"] == "archived"
    assert repository.habits[setup_habit_id]["active"] is False
    assert repository.goals["manual-goal"]["status"] == "active"
    assert repository.habits["manual-habit"]["active"] is True
    assert list(repository.schedule) == ["manual-schedule"]
    assert "manual-memory" in repository.memories
    assert all(
        row["title"] != "Intake context note"
        for row in repository.memories.values()
    )


def test_manual_stable_id_collision_rolls_back_every_atomic_effect() -> None:
    repository = FakeIntakeRepository()
    stable_goal_id = str(
        uuid5(NAMESPACE_URL, f"mylifegraph:{USER_ID}:goal:{GOAL_KEY}"),
    )
    repository.goals[stable_goal_id] = {
        "id": stable_goal_id,
        "user_id": USER_ID,
        "title": "Manual row at colliding id",
        "status": "active",
        "metadata": {"source": "manual"},
    }

    with pytest.raises(SetupOwnershipConflict):
        run(
            IntakeService(repository, now_provider=lambda: NOW).complete_intake(
                user_id=USER_ID,
                request=request(goals=[goal()]),
            ),
        )

    assert repository.goals == {
        stable_goal_id: {
            "id": stable_goal_id,
            "user_id": USER_ID,
            "title": "Manual row at colliding id",
            "status": "active",
            "metadata": {"source": "manual"},
        },
    }
    assert repository.preferences == {}
    assert repository.snapshots == {}
    assert repository.profile_values == {"setup_revision": 0}
    assert repository.intakes[0]["state"] == "pending"


def test_legacy_schedule_cleanup_matches_only_exact_empty_metadata_signature() -> None:
    repository = FakeIntakeRepository()
    exact = {
        "id": "exact-legacy-default",
        "user_id": USER_ID,
        "title": "Math",
        "location": "Room 204",
        "weekday": 1,
        "starts_at": "08:15:00",
        "ends_at": "09:45:00",
        "source": "onboarding",
        "metadata": {},
    }
    near_location = {**exact, "id": "near-location", "location": "Room 205"}
    with_metadata = {
        **exact,
        "id": "with-metadata",
        "metadata": {"note": "user-authored"},
    }
    manual_source = {**exact, "id": "manual-source", "source": "manual"}
    with_notes = {**exact, "id": "with-notes", "notes": "Keep this class"}
    repository.schedule = {
        row["id"]: row
        for row in (exact, near_location, with_metadata, manual_source, with_notes)
    }

    run(
        IntakeService(repository, now_provider=lambda: NOW).complete_intake(
            user_id=USER_ID,
            request=request(commitments=[commitment()]),
        ),
    )

    assert "exact-legacy-default" not in repository.schedule
    assert "near-location" in repository.schedule
    assert "with-metadata" in repository.schedule
    assert "manual-source" in repository.schedule
    assert "with-notes" in repository.schedule
    setup_rows = [row for row in repository.schedule.values() if _is_setup(row)]
    assert len(setup_rows) == 1
    assert setup_rows[0]["title"] == "Math"
    assert setup_rows[0]["metadata"]["setup_item_id"] == COMMITMENT_KEY


def test_stale_revision_conflict_does_not_mutate_state() -> None:
    repository = FakeIntakeRepository()
    service = IntakeService(repository, now_provider=lambda: NOW)
    run(service.complete_intake(user_id=USER_ID, request=request(goals=[goal()])))
    before = deepcopy(repository.goals)

    with pytest.raises(IntakeRevisionConflict) as error:
        run(
            service.complete_intake(
                user_id=USER_ID,
                request=request(
                    request_id=REQUEST_2,
                    base_revision=0,
                    goals=[goal("Stale edit")],
                ),
            ),
        )

    assert error.value.current_revision == 1
    assert repository.goals == before
    assert len(repository.intakes) == 1


def test_pending_revision_is_readable_and_same_request_resumes() -> None:
    repository = FakeIntakeRepository()
    repository.fail_atomic_once_after_preferences = True
    service = IntakeService(repository, now_provider=lambda: NOW)
    intake_request = request(goals=[goal()])

    with pytest.raises(RuntimeError, match="simulated atomic"):
        run(service.complete_intake(user_id=USER_ID, request=intake_request))

    pending = run(service.get_setup(user_id=USER_ID))
    assert pending.exists is True
    assert pending.status == "pending"
    assert pending.request_id == UUID(REQUEST_1)
    assert pending.revision == 1
    assert repository.preferences == {}
    assert repository.goals == {}
    assert repository.snapshots == {}
    assert repository.profile_updates == []

    applied = run(service.complete_intake(user_id=USER_ID, request=intake_request))
    assert applied.status == "applied"
    assert len(repository.intakes) == 1
    assert len(repository.goals) == 1
    assert repository.profile_updates[-1][0] == USER_ID


def test_get_setup_without_state_is_explicit_empty_read_model() -> None:
    response = run(IntakeService(FakeIntakeRepository()).get_setup(user_id=USER_ID))

    assert response.exists is False
    assert response.revision == 0
    assert response.base_revision == 0
    assert response.responses is None
    assert response.status is None


def test_legacy_default_commitment_is_removed_only_when_keyless() -> None:
    repository = FakeIntakeRepository()
    legacy_responses = payload()["responses"]
    legacy_responses["fixed_commitments"] = [
        {
            "title": "Math",
            "location": "Room 204",
            "weekday": 1,
            "startTime": "08:15",
            "endTime": "09:45",
        },
        {
            "title": "Math",
            "location": "Room 205",
            "weekday": 1,
            "starts_at": "08:15",
            "ends_at": "09:45",
        },
        {
            "key": COMMITMENT_KEY,
            "title": "Math",
            "location": "Room 204",
            "weekday": 1,
            "starts_at": "08:15",
            "ends_at": "09:45",
            "status": "active",
        },
    ]
    repository.intakes.append(
        {
            "id": "00000000-0000-4000-8000-000000000099",
            "user_id": USER_ID,
            "request_id": REQUEST_1,
            "base_revision": 0,
            "revision": 1,
            "state": "applied",
            "version": "intake-v1",
            "responses": legacy_responses,
            "completed_at": NOW.isoformat(),
            "metadata": {"snapshot_id": "snapshot-123"},
        },
    )

    setup = run(IntakeService(repository).get_setup(user_id=USER_ID))

    assert setup.responses is not None
    assert len(setup.responses.fixed_commitments) == 2
    commitments = setup.responses.fixed_commitments
    assert {item.location for item in commitments} == {"Room 204", "Room 205"}
    keyed = next(item for item in commitments if item.location == "Room 204")
    assert str(keyed.key) == COMMITMENT_KEY
    assert keyed.title == "Math"
