import asyncio
from datetime import UTC, datetime
from decimal import Decimal

import pytest
from pydantic import ValidationError

import app.services.account_service as account_module
from app.models.account import (
    ACCOUNT_EXPORT_MAX_JSON_BYTES,
    ACCOUNT_EXPORT_MAX_ROWS_PER_TABLE,
    ACCOUNT_EXPORT_MAX_TOTAL_ROWS,
    ACCOUNT_EXPORT_OMITTED_TABLES,
    ACCOUNT_EXPORT_SANITIZED_TABLES,
    ACCOUNT_EXPORT_TABLE_NAMES,
    AccountExportLedgerPolicy,
    AccountExportLimits,
    AccountExportResponse,
)
from app.repositories.account_repository import (
    AccountExportSourceTooLargeError,
    AccountExportTable,
    AccountPersistenceError,
)
from app.services.account_service import (
    ACCOUNT_EXPORT_PAGE_SIZE,
    ACCOUNT_EXPORT_TABLES,
    AccountExportTooLargeError,
    AccountService,
    InvalidAccountTimezoneError,
)


NOW = datetime(2026, 7, 13, 12, tzinfo=UTC)


class Repository:
    def __init__(self) -> None:
        self.timezone_result: str | None = "Europe/Berlin"
        self.update_calls: list[tuple[str, str]] = []
        self.export_calls: list[
            tuple[str, AccountExportTable, str | None, str, int, int]
        ] = []
        self.watermark_calls: list[tuple[str, AccountExportTable, int]] = []
        self.rows: dict[str, list[dict[str, object]]] = {}
        self.oversized_source_table: str | None = None
        self.delete_calls: list[tuple[str, str]] = []

    async def update_timezone(self, *, user_id: str, timezone: str):
        self.update_calls.append((user_id, timezone))
        return self.timezone_result

    async def list_export_rows(
        self,
        *,
        user_id: str,
        table: AccountExportTable,
        after_cursor: str | None,
        not_after: str,
        limit: int,
        max_response_bytes: int,
    ):
        self.export_calls.append(
            (
                user_id,
                table,
                after_cursor,
                not_after,
                limit,
                max_response_bytes,
            ),
        )
        if table.name == self.oversized_source_table:
            raise AccountExportSourceTooLargeError("bounded source page")
        rows = sorted(
            self.rows.get(table.name, []),
            key=lambda row: str(row[table.cursor_column]),
        )
        if after_cursor is not None:
            rows = [
                row
                for row in rows
                if str(row[table.cursor_column]) > after_cursor
            ]
        return rows[:limit]

    async def get_export_watermark(
        self,
        *,
        user_id: str,
        table: AccountExportTable,
        max_response_bytes: int,
    ):
        self.watermark_calls.append((user_id, table, max_response_bytes))
        if (
            not self.rows.get(table.name)
            and table.name != self.oversized_source_table
        ):
            return None
        return NOW.isoformat()

    async def delete_account(self, *, user_id: str, confirmation: str):
        self.delete_calls.append((user_id, confirmation))


def test_timezone_update_validates_iana_name_and_derives_owner() -> None:
    repository = Repository()
    repository.timezone_result = "America/New_York"
    service = AccountService(repository=repository)

    result = asyncio.run(
        service.update_timezone(user_id="owner-1", timezone="America/New_York"),
    )

    assert result.model_dump() == {"timezone": "America/New_York"}
    assert repository.update_calls == [("owner-1", "America/New_York")]


@pytest.mark.parametrize(
    "timezone",
    [
        "Mars/Olympus_Mons",
        " Europe/Berlin",
        "Europe/Berlin ",
        "localtime",
        "posixrules",
        "right/UTC",
    ],
)
def test_timezone_update_rejects_unstable_or_unknown_zone(timezone: str) -> None:
    repository = Repository()
    service = AccountService(repository=repository)

    with pytest.raises(InvalidAccountTimezoneError):
        asyncio.run(service.update_timezone(user_id="owner-1", timezone=timezone))

    assert repository.update_calls == []


def test_export_is_owner_scoped_versioned_complete_and_sanitizes_ledgers() -> None:
    repository = Repository()
    repository.rows = {
        "profiles": [{"id": "owner-1", "timezone": "Europe/Berlin"}],
        "daily_logs": [{"id": "log-1", "user_id": "owner-1"}],
        "coach_requests": [
            {
                "request_id": "request-1",
                "user_id": "owner-1",
                "state": "deleted",
            },
        ],
    }
    service = AccountService(repository=repository, now=lambda: NOW)

    prepared = asyncio.run(service.export_account(user_id="owner-1"))
    result = prepared.envelope

    assert result.contract_version == "account-export-v1"
    assert result.exported_at == NOW
    assert list(result.data) == [table.name for table in ACCOUNT_EXPORT_TABLES]
    assert result.record_counts["profiles"] == 1
    assert result.record_counts["daily_logs"] == 1
    assert result.record_counts["coach_requests"] == 1
    assert result.record_counts["lifestyle_entries"] == 0
    assert result.ledger_policy.sanitized_tables == list(
        ACCOUNT_EXPORT_SANITIZED_TABLES,
    )
    assert result.ledger_policy.omitted_tables == ACCOUNT_EXPORT_OMITTED_TABLES
    assert len(prepared.content) <= ACCOUNT_EXPORT_MAX_JSON_BYTES
    assert prepared.content == result.model_dump_json().encode("utf-8")
    assert {call[1].name for call in repository.watermark_calls} == {
        table.name for table in ACCOUNT_EXPORT_TABLES
    }
    assert all(call[0] == "owner-1" for call in repository.export_calls)
    assert next(
        call[1] for call in repository.export_calls if call[1].name == "profiles"
    ).owner_column == "id"
    assert next(
        call[1]
        for call in repository.export_calls
        if call[1].name == "daily_logs"
    ).owner_column == "user_id"


def test_export_paginates_stably_and_rejects_partial_table_output() -> None:
    repository = Repository()
    repository.rows["daily_logs"] = [
        {"id": f"log-{index:05d}", "user_id": "owner-1"}
        for index in range(ACCOUNT_EXPORT_MAX_ROWS_PER_TABLE + 1)
    ]
    service = AccountService(repository=repository, now=lambda: NOW)

    with pytest.raises(AccountExportTooLargeError, match="daily_logs"):
        asyncio.run(service.export_account(user_id="owner-1"))

    daily_calls = [
        call for call in repository.export_calls if call[1].name == "daily_logs"
    ]
    assert (daily_calls[0][2], daily_calls[0][4]) == (
        None,
        ACCOUNT_EXPORT_PAGE_SIZE,
    )
    assert (daily_calls[-1][2], daily_calls[-1][4]) == ("log-09999", 1)
    assert all(call[3] == NOW.isoformat() for call in daily_calls)
    assert all(2 <= call[5] <= ACCOUNT_EXPORT_MAX_JSON_BYTES for call in daily_calls)


def test_export_keyset_does_not_skip_after_an_earlier_row_is_deleted() -> None:
    class MutatingRepository(Repository):
        daily_page_count = 0

        async def list_export_rows(self, **kwargs):
            page = await super().list_export_rows(**kwargs)
            if kwargs["table"].name == "daily_logs":
                self.daily_page_count += 1
                if self.daily_page_count == 1:
                    self.rows["daily_logs"].pop(0)
            return page

    repository = MutatingRepository()
    row_count = ACCOUNT_EXPORT_PAGE_SIZE + 30
    repository.rows["daily_logs"] = [
        {"id": f"log-{index:05d}", "user_id": "owner-1"}
        for index in range(row_count)
    ]
    service = AccountService(repository=repository, now=lambda: NOW)

    result = asyncio.run(service.export_account(user_id="owner-1")).envelope

    assert [row["id"] for row in result.data["daily_logs"]] == [
        f"log-{index:05d}" for index in range(row_count)
    ]
    assert repository.daily_page_count == 2


def test_export_rejects_a_repository_row_for_another_owner() -> None:
    repository = Repository()
    repository.rows["daily_logs"] = [{"id": "log-1", "user_id": "other-owner"}]
    service = AccountService(repository=repository, now=lambda: NOW)

    with pytest.raises(AccountPersistenceError, match="invalid owner"):
        asyncio.run(service.export_account(user_id="owner-1"))


def test_export_rejects_oversized_json_instead_of_returning_truncated_data(
) -> None:
    repository = Repository()
    repository.rows["profiles"] = [
        {"id": "owner-1", "display_name": "x" * ACCOUNT_EXPORT_MAX_JSON_BYTES},
    ]
    service = AccountService(repository=repository, now=lambda: NOW)

    with pytest.raises(AccountExportTooLargeError, match="JSON size"):
        asyncio.run(service.export_account(user_id="owner-1"))


def test_export_serializes_source_numbers_without_precision_loss() -> None:
    repository = Repository()
    repository.rows["daily_logs"] = [
        {
            "id": "log-exact",
            "user_id": "owner-1",
            "metadata": {
                "exact": Decimal("0.12345678901234567890"),
                "large": 9007199254740993,
            },
        },
    ]
    service = AccountService(repository=repository, now=lambda: NOW)

    content = asyncio.run(service.export_account(user_id="owner-1")).content

    assert b'"exact":0.12345678901234567890' in content
    assert b'"large":9007199254740993' in content


def test_export_maps_a_stream_bounded_source_page_to_413_outcome() -> None:
    repository = Repository()
    repository.oversized_source_table = "profiles"
    service = AccountService(repository=repository, now=lambda: NOW)

    with pytest.raises(AccountExportTooLargeError, match="JSON size"):
        asyncio.run(service.export_account(user_id="owner-1"))

    assert len(repository.export_calls) == 1
    assert repository.export_calls[0][5] <= ACCOUNT_EXPORT_MAX_JSON_BYTES


def test_export_models_reject_non_v1_tables_policy_and_limits() -> None:
    data = {name: [] for name in ACCOUNT_EXPORT_TABLE_NAMES}
    counts = {name: 0 for name in ACCOUNT_EXPORT_TABLE_NAMES}
    policy = AccountExportLedgerPolicy(
        sanitized_tables=list(ACCOUNT_EXPORT_SANITIZED_TABLES),
        omitted_tables=dict(ACCOUNT_EXPORT_OMITTED_TABLES),
    )
    limits = AccountExportLimits(
        max_rows_per_table=ACCOUNT_EXPORT_MAX_ROWS_PER_TABLE,
        max_total_rows=ACCOUNT_EXPORT_MAX_TOTAL_ROWS,
        max_json_bytes=ACCOUNT_EXPORT_MAX_JSON_BYTES,
    )

    with pytest.raises(ValidationError, match="exact V1 export table set"):
        AccountExportResponse(
            contract_version="account-export-v1",
            exported_at=NOW,
            data={"profiles": []},
            record_counts={"profiles": 0},
            ledger_policy=policy,
            limits=limits,
        )
    with pytest.raises(ValidationError, match="V1 ledger policy"):
        AccountExportLedgerPolicy(
            sanitized_tables=["coach_requests"],
            omitted_tables=dict(ACCOUNT_EXPORT_OMITTED_TABLES),
        )
    with pytest.raises(ValidationError, match="account-export-v1"):
        AccountExportLimits(
            max_rows_per_table=1,
            max_total_rows=2,
            max_json_bytes=3,
        )

    valid = AccountExportResponse(
        contract_version="account-export-v1",
        exported_at=NOW,
        data=data,
        record_counts=counts,
        ledger_policy=policy,
        limits=limits,
    )
    assert set(valid.data) == set(ACCOUNT_EXPORT_TABLE_NAMES)


def test_export_uses_explicit_field_allowlists_for_backend_ledgers() -> None:
    tables = {table.name: table for table in ACCOUNT_EXPORT_TABLES}
    forbidden_fields = {
        "calendar_connections": {
            "create_request_id",
            "create_request_fingerprint",
            "disconnect_request_id",
            "delete_request_id",
        },
        "calendar_imports": {
            "request_id",
            "request_fingerprint",
            "input_fingerprint",
            "source_fingerprint",
        },
        "calendar_events": {"source_event_key", "sort_date", "sort_time"},
        "coach_requests": {"id", "message_fingerprint", "lease_expires_at", "error"},
        "coach_usage_events": {"id"},
    }

    assert set(forbidden_fields) == set(ACCOUNT_EXPORT_SANITIZED_TABLES)
    for table_name, forbidden in forbidden_fields.items():
        selected = set(tables[table_name].select.split(","))
        assert "*" not in selected
        assert selected.isdisjoint(forbidden)

    assert "calendar_request_identities" not in tables


def test_export_service_rejects_drifted_table_configuration(monkeypatch) -> None:
    monkeypatch.setattr(
        account_module,
        "ACCOUNT_EXPORT_TABLES",
        ACCOUNT_EXPORT_TABLES[:-1],
    )
    repository = Repository()
    service = AccountService(repository=repository, now=lambda: NOW)

    with pytest.raises(AccountPersistenceError, match="configuration"):
        asyncio.run(service.export_account(user_id="owner-1"))

    assert repository.export_calls == []


def test_export_service_rejects_drifted_policy_configuration(monkeypatch) -> None:
    drifted_policy = account_module.ACCOUNT_EXPORT_LEDGER_POLICY.model_copy(
        update={"sanitized_tables": ["coach_requests"]},
    )
    monkeypatch.setattr(
        account_module,
        "ACCOUNT_EXPORT_LEDGER_POLICY",
        drifted_policy,
    )
    repository = Repository()
    service = AccountService(repository=repository, now=lambda: NOW)

    with pytest.raises(AccountPersistenceError, match="configuration"):
        asyncio.run(service.export_account(user_id="owner-1"))

    assert repository.export_calls == []


def test_export_service_rejects_drifted_limit_configuration(monkeypatch) -> None:
    monkeypatch.setattr(
        account_module,
        "ACCOUNT_EXPORT_MAX_TOTAL_ROWS",
        ACCOUNT_EXPORT_MAX_TOTAL_ROWS - 1,
    )
    repository = Repository()
    service = AccountService(repository=repository, now=lambda: NOW)

    with pytest.raises(AccountPersistenceError, match="configuration"):
        asyncio.run(service.export_account(user_id="owner-1"))

    assert repository.export_calls == []


def test_delete_requires_exact_confirmation_and_calls_atomic_repository() -> None:
    repository = Repository()
    service = AccountService(repository=repository)

    asyncio.run(
        service.delete_account(user_id="owner-1", confirmation="DELETE"),
    )
    assert repository.delete_calls == [("owner-1", "DELETE")]

    with pytest.raises(ValueError, match="Exact"):
        asyncio.run(
            service.delete_account(user_id="owner-1", confirmation="delete"),
        )
    assert repository.delete_calls == [("owner-1", "DELETE")]
