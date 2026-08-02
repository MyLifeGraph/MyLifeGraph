import asyncio
from collections import Counter
from datetime import UTC, datetime

from app.models.deadline_plans import DeadlinePlansResponse
from app.services.today_planner_read_context import TodayPlannerReadContextFactory


class Tracker:
    def __init__(self) -> None:
        self.active = 0
        self.maximum = 0
        self.calls: Counter[str] = Counter()

    async def value(self, name: str, value):
        self.calls[name] += 1
        self.active += 1
        self.maximum = max(self.maximum, self.active)
        try:
            await asyncio.sleep(0.005)
            return value
        finally:
            self.active -= 1


class Repository:
    def __init__(self, tracker: Tracker) -> None:
        self.tracker = tracker

    async def get_profile_timezone(self, *, user_id: str) -> str:
        return await self.tracker.value("profile", "Europe/Berlin")

    async def list_active_habits(self, *, user_id: str):
        return await self.tracker.value("habits", [{"id": "habit-1"}])


class DeadlinePlans:
    def __init__(self, tracker: Tracker) -> None:
        self.tracker = tracker

    async def list_plans(self, *, user_id: str) -> DeadlinePlansResponse:
        return await self.tracker.value(
            "deadlines",
            DeadlinePlansResponse(
                contract_version="deadline-plan-v1",
                origin="authenticated_backend",
                plans=[],
            ),
        )


def _factory(tracker: Tracker, *, maximum: int = 2):
    return TodayPlannerReadContextFactory(
        repository=Repository(tracker),
        deadline_plans=DeadlinePlans(tracker),
        max_concurrency=maximum,
    )


def test_context_caches_shared_reads_and_limits_independent_concurrency() -> None:
    async def scenario():
        tracker = Tracker()
        context = _factory(tracker).create(
            user_id="owner-1",
            generated_at=datetime(2026, 8, 2, 12, tzinfo=UTC),
        )
        try:
            results = await asyncio.gather(
                context.profile_timezone(),
                context.profile_timezone(),
                context.active_habits(),
                context.active_habits(),
                context.deadline_response(),
                context.deadline_response(),
                context.read(
                    "extra:first",
                    lambda: tracker.value("first", "first"),
                ),
                context.read(
                    "extra:second",
                    lambda: tracker.value("second", "second"),
                ),
            )
            return tracker, results
        finally:
            await context.aclose()

    tracker, results = asyncio.run(scenario())

    assert results[0:2] == ["Europe/Berlin", "Europe/Berlin"]
    assert results[2:4] == [[{"id": "habit-1"}], [{"id": "habit-1"}]]
    assert results[6:] == ["first", "second"]
    assert tracker.calls == Counter(
        profile=1,
        habits=1,
        deadlines=1,
        first=1,
        second=1,
    )
    assert tracker.maximum == 2


def test_factory_keeps_cache_request_local() -> None:
    async def scenario() -> Tracker:
        tracker = Tracker()
        factory = _factory(tracker)
        for user_id in ("owner-1", "owner-1"):
            context = factory.create(
                user_id=user_id,
                generated_at=datetime(2026, 8, 2, 12, tzinfo=UTC),
            )
            try:
                assert await context.profile_timezone() == "Europe/Berlin"
            finally:
                await context.aclose()
        return tracker

    tracker = asyncio.run(scenario())

    assert tracker.calls["profile"] == 2


def test_closing_context_cancels_and_settles_shielded_source_work() -> None:
    async def scenario() -> bool:
        tracker = Tracker()
        context = _factory(tracker, maximum=1).create(
            user_id="owner-1",
            generated_at=datetime(2026, 8, 2, 12, tzinfo=UTC),
        )
        started = asyncio.Event()
        settled = False

        async def blocked() -> None:
            nonlocal settled
            started.set()
            try:
                await asyncio.Event().wait()
            finally:
                settled = True

        waiter = asyncio.create_task(context.read("blocked", blocked))
        await started.wait()
        waiter.cancel()
        try:
            await waiter
        except asyncio.CancelledError:
            pass
        await context.aclose()
        return settled

    assert asyncio.run(scenario()) is True
