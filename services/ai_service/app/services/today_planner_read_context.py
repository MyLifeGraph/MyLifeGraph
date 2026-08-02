import asyncio
from collections.abc import Awaitable, Callable
from datetime import datetime
from typing import Any, Protocol, TypeVar, cast

from app.models.deadline_plans import DeadlinePlansResponse
from app.repositories.today_planner_read_repository import (
    TodayPlannerReadRepository,
)


class DeadlinePlanReader(Protocol):
    async def list_plans(self, *, user_id: str) -> DeadlinePlansResponse: ...


Result = TypeVar("Result")


class TodayPlannerReadContextFactory:
    def __init__(
        self,
        *,
        repository: TodayPlannerReadRepository,
        deadline_plans: DeadlinePlanReader,
        max_concurrency: int = 6,
    ) -> None:
        if max_concurrency <= 0:
            raise ValueError("Today/Planner read concurrency must be positive.")
        self._repository = repository
        self._deadline_plans = deadline_plans
        self._max_concurrency = max_concurrency

    def create(
        self,
        *,
        user_id: str,
        generated_at: datetime,
    ) -> "TodayPlannerReadContext":
        return TodayPlannerReadContext(
            user_id=user_id,
            generated_at=generated_at,
            repository=self._repository,
            deadline_plans=self._deadline_plans,
            max_concurrency=self._max_concurrency,
        )


class TodayPlannerReadContext:
    def __init__(
        self,
        *,
        user_id: str,
        generated_at: datetime,
        repository: TodayPlannerReadRepository,
        deadline_plans: DeadlinePlanReader,
        max_concurrency: int,
    ) -> None:
        self.user_id = user_id
        self.generated_at = generated_at
        self._repository = repository
        self._deadline_plans = deadline_plans
        self._semaphore = asyncio.Semaphore(max_concurrency)
        self._tasks: dict[str, asyncio.Task[object]] = {}
        self._closed = False

    async def read(
        self,
        key: str,
        operation: Callable[[], Awaitable[Result]],
    ) -> Result:
        if self._closed:
            raise RuntimeError("Today/Planner read context is closed.")
        task = self._tasks.get(key)
        if task is None:
            task = asyncio.create_task(self._run(operation))
            self._tasks[key] = task
        return cast(Result, await asyncio.shield(task))

    async def profile_timezone(self) -> str:
        return await self.read(
            "shared:profile_timezone",
            lambda: self._repository.get_profile_timezone(user_id=self.user_id),
        )

    async def active_habits(self) -> list[dict[str, Any]]:
        return await self.read(
            "shared:active_habits",
            lambda: self._repository.list_active_habits(user_id=self.user_id),
        )

    async def deadline_response(self) -> DeadlinePlansResponse:
        return await self.read(
            "shared:deadline_plans",
            lambda: self._deadline_plans.list_plans(user_id=self.user_id),
        )

    async def aclose(self) -> None:
        self._closed = True
        tasks = list(self._tasks.values())
        for task in tasks:
            if not task.done():
                task.cancel()
        if tasks:
            await asyncio.gather(*tasks, return_exceptions=True)

    async def _run(
        self,
        operation: Callable[[], Awaitable[Result]],
    ) -> Result:
        async with self._semaphore:
            return await operation()
