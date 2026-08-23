import asyncio
from datetime import UTC, date, datetime

from app.repositories.personal_patterns_repository import (
    SupabasePersonalPatternsRepository,
)


class Client:
    def __init__(self) -> None:
        self.calls: list[tuple[str, object]] = []

    async def select(self, table, *, params):
        self.calls.append((table, params))
        return []


def test_evidence_query_bounds_terminal_sessions_at_both_window_edges() -> None:
    client = Client()
    repository = SupabasePersonalPatternsRepository(client)
    starts_at = datetime(2026, 4, 27, 12, tzinfo=UTC)
    ends_at = datetime(2026, 7, 26, 12, tzinfo=UTC)

    asyncio.run(
        repository.load_evidence(
            user_id="owner",
            starts_at=starts_at,
            ends_at=ends_at,
            local_starts_on=date(2026, 4, 25),
            local_ends_on=date(2026, 7, 26),
        ),
    )

    focus_params = next(
        params for table, params in client.calls if table == "focus_sessions"
    )
    assert ("status", "in.(completed,abandoned)") in focus_params
    assert ("started_at", f"gte.{starts_at.isoformat()}") in focus_params
    assert ("started_at", f"lt.{ends_at.isoformat()}") in focus_params
    daily_params = next(
        params for table, params in client.calls if table == "daily_logs"
    )
    assert daily_params["entry_date"] == "gte.2026-04-25"
    assert daily_params["and"] == "(entry_date.lte.2026-07-26)"
