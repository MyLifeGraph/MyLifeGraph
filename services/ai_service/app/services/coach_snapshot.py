import asyncio
import json
import os
import re
import sqlite3
import tempfile
from dataclasses import dataclass
from decimal import Decimal
from pathlib import Path
from typing import Any

from app.core.lossless_json import lossless_json_text
from app.core.private_files import (
    PrivateFileCleanupError,
    remove_private_directory,
    remove_private_directory_despite_cancellation,
)
from app.models.account import (
    ACCOUNT_EXPORT_MAX_JSON_BYTES,
    ACCOUNT_EXPORT_MAX_ROWS_PER_TABLE,
    ACCOUNT_EXPORT_MAX_TOTAL_ROWS,
)
from app.owner_data_catalog import (
    COACH_SNAPSHOT_DESCRIPTIONS,
    COACH_SNAPSHOT_TABLES,
    OWNER_DATA_PAGE_BYTE_CUSHION,
    OWNER_DATA_PAGE_SIZE,
    OWNER_DATA_WATERMARK_MAX_BYTES,
)
from app.repositories.account_repository import (
    AccountExportSourceTooLargeError,
    AccountExportTable,
    AccountPersistenceError,
    AccountRepository,
)
from app.services.owner_data_reader import (
    OwnerDataInvalidCursorError,
    OwnerDataInvalidOwnerError,
    OwnerDataInvalidPageError,
    OwnerDataReadPolicy,
    OwnerDataReader,
    OwnerDataSerializedBytesExceededError,
    OwnerDataSourceRowsExceededError,
    OwnerDataTotalRowsExceededError,
)


COACH_SNAPSHOT_CONTRACT_VERSION = "personal-snapshot-v1"
_PROFILE_PROHIBITED_FIELDS = {"email", "role", "auth_provider"}
_IDENTIFIER = re.compile(r"^[a-z][a-z0-9_]*$")
_FIELD_NAME_BOUNDARIES = re.compile(
    r"(?<=[a-z0-9])(?=[A-Z])|(?<=[A-Z])(?=[A-Z][a-z])|[^A-Za-z0-9]+",
)
_SENSITIVE_FIELD_PARTS = {
    "accesskey",
    "accesstoken",
    "apikey",
    "authorization",
    "authorizationcode",
    "authtoken",
    "bearer",
    "bearertoken",
    "clientsecret",
    "codeverifier",
    "cookie",
    "cookies",
    "credential",
    "credentials",
    "idtoken",
    "oauth",
    "oauth2",
    "passwd",
    "password",
    "passwords",
    "privatekey",
    "refreshtoken",
    "secret",
    "secrets",
    "token",
    "tokens",
}
_SENSITIVE_FIELD_PAIRS = {
    ("access", "key"),
    ("api", "key"),
    ("authorization", "code"),
    ("client", "secret"),
    ("code", "verifier"),
    ("encryption", "key"),
    ("key", "material"),
    ("private", "key"),
    ("service", "key"),
    ("signing", "key"),
}
_SENSITIVE_COMPACT_FIELD_SUFFIXES = (
    "accesskey",
    "apikey",
    "authorizationcode",
    "clientsecret",
    "codeverifier",
    "credential",
    "credentials",
    "oauth",
    "oauth2",
    "passwd",
    "password",
    "passwords",
    "privatekey",
    "secret",
    "secrets",
    "token",
    "tokens",
)

_RELATIONSHIPS = (
    ("focus_session_reflections", "focus_session_id", "focus_sessions", "id"),
    ("focus_sessions", "task_id", "tasks", "id"),
    ("focus_sessions", "habit_id", "habits", "id"),
    ("habit_logs", "habit_id", "habits", "id"),
    ("deadline_plan_revisions", "plan_id", "deadline_plans", "id"),
    ("deadline_plan_blocks", "plan_id", "deadline_plans", "id"),
    ("planner_action_plan_revisions", "plan_id", "planner_action_plans", "id"),
    ("planner_task_blocks", "plan_id", "planner_action_plans", "id"),
    ("planner_habit_slots", "plan_id", "planner_action_plans", "id"),
    ("calendar_events", "import_id", "calendar_imports", "id"),
)


class CoachSnapshotTooLargeError(RuntimeError):
    pass


class CoachSnapshotCleanupError(RuntimeError):
    pass


@dataclass(frozen=True)
class CoachSnapshotCoverage:
    table: str
    description: str
    record_count: int
    period_start: str | None
    period_end: str | None


@dataclass(frozen=True)
class PreparedCoachSnapshot:
    path: Path
    working_directory: Path
    row_count: int
    source_bytes: int
    coverage: tuple[CoachSnapshotCoverage, ...]

    def cleanup(self) -> None:
        try:
            remove_private_directory(
                self.working_directory,
                expected_name_prefix="mylifegraph-snapshot-",
            )
        except PrivateFileCleanupError as exc:
            raise CoachSnapshotCleanupError(
                "The private Coach snapshot could not be securely removed.",
            ) from exc


class CoachSnapshotService:
    def __init__(self, *, repository: AccountRepository) -> None:
        self._repository = repository
        self._owner_data_reader = OwnerDataReader(repository=repository)

    async def create(self, *, user_id: str) -> PreparedCoachSnapshot:
        rows_by_table = await self._collect_rows(user_id=user_id)
        try:
            source_bytes = len(
                lossless_json_text(rows_by_table).encode("utf-8"),
            )
        except (RecursionError, TypeError, ValueError) as exc:
            raise AccountPersistenceError(
                "Coach snapshot returned invalid JSON data.",
            ) from exc
        if source_bytes > ACCOUNT_EXPORT_MAX_JSON_BYTES:
            raise CoachSnapshotTooLargeError(
                "Personal data exceeds the 8 MiB Coach snapshot limit.",
            )
        row_count = sum(len(rows) for rows in rows_by_table.values())
        working_directory = Path(tempfile.mkdtemp(prefix="mylifegraph-snapshot-"))
        os.chmod(working_directory, 0o700)
        path = working_directory / "personal-data.sqlite"
        try:
            coverage = await asyncio.to_thread(
                _write_snapshot,
                path,
                rows_by_table,
            )
            # The parent stays owner-only (0700). The file itself is readable
            # by the fixed non-root container UID after its read-only bind mount.
            os.chmod(path, 0o444)
            return PreparedCoachSnapshot(
                path=path,
                working_directory=working_directory,
                row_count=row_count,
                source_bytes=source_bytes,
                coverage=coverage,
            )
        except BaseException:
            try:
                await remove_private_directory_despite_cancellation(
                    working_directory,
                    expected_name_prefix="mylifegraph-snapshot-",
                )
            except PrivateFileCleanupError as cleanup_exc:
                raise CoachSnapshotCleanupError(
                    "The private Coach snapshot could not be securely removed.",
                ) from cleanup_exc
            raise

    async def _collect_rows(
        self,
        *,
        user_id: str,
    ) -> dict[str, list[dict[str, Any]]]:
        empty_rows = {table.name: [] for table in COACH_SNAPSHOT_TABLES}
        try:
            initial_serialized_bytes = len(
                lossless_json_text(empty_rows).encode("utf-8"),
            )
            collection = await self._owner_data_reader.collect(
                user_id=user_id,
                sources=COACH_SNAPSHOT_TABLES,
                policy=OwnerDataReadPolicy(
                    page_size=OWNER_DATA_PAGE_SIZE,
                    max_rows_per_source=ACCOUNT_EXPORT_MAX_ROWS_PER_TABLE,
                    max_total_rows=ACCOUNT_EXPORT_MAX_TOTAL_ROWS,
                    max_serialized_bytes=ACCOUNT_EXPORT_MAX_JSON_BYTES,
                    watermark_max_response_bytes=(OWNER_DATA_WATERMARK_MAX_BYTES),
                ),
                initial_serialized_bytes=initial_serialized_bytes,
                transform_row=lambda table, row: _sanitize_row(
                    row=row,
                    table=table,
                ),
                serialized_row_growth=_coach_snapshot_row_growth,
                page_response_bytes=lambda _serialized_bytes: (
                    ACCOUNT_EXPORT_MAX_JSON_BYTES + OWNER_DATA_PAGE_BYTE_CUSHION
                ),
            )
        except (RecursionError, TypeError, ValueError) as exc:
            raise AccountPersistenceError(
                "Coach snapshot returned invalid JSON data.",
            ) from exc
        except AccountExportSourceTooLargeError as exc:
            raise CoachSnapshotTooLargeError(
                "Personal data exceeds the 8 MiB Coach snapshot limit.",
            ) from exc
        except OwnerDataInvalidPageError as exc:
            raise AccountPersistenceError(
                "Coach snapshot returned an invalid page.",
            ) from exc
        except OwnerDataInvalidOwnerError as exc:
            raise AccountPersistenceError(
                "Coach snapshot returned another owner.",
            ) from exc
        except OwnerDataInvalidCursorError as exc:
            raise AccountPersistenceError(
                "Coach snapshot cursor is invalid.",
            ) from exc
        except OwnerDataSourceRowsExceededError as exc:
            raise CoachSnapshotTooLargeError(
                f"{exc.source_name} exceeds the 10,000-row snapshot limit.",
            ) from exc
        except OwnerDataTotalRowsExceededError as exc:
            raise CoachSnapshotTooLargeError(
                "Personal data exceeds the 50,000-row Coach snapshot limit.",
            ) from exc
        except OwnerDataSerializedBytesExceededError as exc:
            raise CoachSnapshotTooLargeError(
                "Personal data exceeds the 8 MiB Coach snapshot limit.",
            ) from exc
        return collection.rows_by_source


def _sanitize_row(
    *,
    row: dict[str, Any],
    table: AccountExportTable,
) -> dict[str, Any]:
    prohibited = _PROFILE_PROHIBITED_FIELDS if table.name == "profiles" else set()
    return {
        key: _sanitize_nested_value(value, depth=1)
        for key, value in row.items()
        if key != table.owner_column
        and key not in prohibited
        and not _is_sensitive_field_name(key)
    }


def _coach_snapshot_row_growth(
    _table: AccountExportTable,
    current_table_rows: int,
    row: dict[str, Any],
) -> int:
    try:
        row_bytes = len(lossless_json_text(row).encode("utf-8"))
    except (RecursionError, TypeError, ValueError) as exc:
        raise AccountPersistenceError(
            "Coach snapshot returned invalid JSON data.",
        ) from exc
    return row_bytes + (1 if current_table_rows else 0)


def _sanitize_nested_value(value: Any, *, depth: int) -> Any:
    if depth > 64:
        raise AccountPersistenceError(
            "Coach snapshot returned invalid JSON data.",
        )
    if isinstance(value, dict):
        return {
            key: _sanitize_nested_value(item, depth=depth + 1)
            for key, item in value.items()
            if isinstance(key, str) and not _is_sensitive_field_name(key)
        }
    if isinstance(value, list):
        return [_sanitize_nested_value(item, depth=depth + 1) for item in value]
    if isinstance(value, tuple):
        return tuple(_sanitize_nested_value(item, depth=depth + 1) for item in value)
    # Values are deliberately not inspected. Notes such as "I rotated my API
    # key" are ordinary product text and must remain available to the Coach.
    return value


def _is_sensitive_field_name(name: object) -> bool:
    if not isinstance(name, str):
        return True
    parts = tuple(
        part.casefold() for part in _FIELD_NAME_BOUNDARIES.split(name) if part
    )
    if not parts:
        return True
    if any(part in _SENSITIVE_FIELD_PARTS for part in parts):
        return True
    if any(
        pair in _SENSITIVE_FIELD_PAIRS for pair in zip(parts, parts[1:], strict=False)
    ):
        return True
    compact = "".join(parts)
    if "oauth" in compact:
        return True
    return any(
        compact == suffix or compact.endswith(suffix)
        for suffix in _SENSITIVE_COMPACT_FIELD_SUFFIXES
    )


def _write_snapshot(
    path: Path,
    rows_by_table: dict[str, list[dict[str, Any]]],
) -> tuple[CoachSnapshotCoverage, ...]:
    connection = sqlite3.connect(path)
    try:
        connection.execute("PRAGMA journal_mode=OFF")
        connection.execute("PRAGMA synchronous=OFF")
        connection.execute("PRAGMA trusted_schema=OFF")
        connection.execute(
            """
            CREATE TABLE _coach_catalog (
              table_name TEXT PRIMARY KEY,
              description TEXT NOT NULL,
              record_count INTEGER NOT NULL,
              period_start TEXT,
              period_end TEXT,
              available_columns TEXT NOT NULL
            )
            """,
        )
        connection.execute(
            """
            CREATE TABLE _coach_relationships (
              from_table TEXT NOT NULL,
              from_column TEXT NOT NULL,
              to_table TEXT NOT NULL,
              to_column TEXT NOT NULL
            )
            """,
        )
        coverage: list[CoachSnapshotCoverage] = []
        columns_by_table: dict[str, set[str]] = {}
        for table_name, rows in rows_by_table.items():
            if not _IDENTIFIER.fullmatch(table_name):
                raise ValueError("Snapshot table name is invalid.")
            columns = sorted(
                {
                    key
                    for row in rows
                    for key in row
                    if _IDENTIFIER.fullmatch(key) and key != "row_json"
                },
            )
            columns_by_table[table_name] = set(columns)
            definitions = [
                f"{_quote(column)} {_sqlite_type(rows, column)}" for column in columns
            ]
            definitions.append('"row_json" TEXT NOT NULL')
            connection.execute(
                f"CREATE TABLE {_quote(table_name)} ({', '.join(definitions)})",
            )
            if rows:
                insert_columns = [*columns, "row_json"]
                placeholders = ",".join("?" for _ in insert_columns)
                statement = (
                    f"INSERT INTO {_quote(table_name)} "
                    f"({', '.join(_quote(value) for value in insert_columns)}) "
                    f"VALUES ({placeholders})"
                )
                connection.executemany(
                    statement,
                    [
                        [
                            *[_sqlite_value(row.get(column)) for column in columns],
                            lossless_json_text(row),
                        ]
                        for row in rows
                    ],
                )
            period_start, period_end = _period(rows)
            item = CoachSnapshotCoverage(
                table=table_name,
                description=COACH_SNAPSHOT_DESCRIPTIONS.get(
                    table_name,
                    "Owner-scoped MyLifeGraph product data.",
                ),
                record_count=len(rows),
                period_start=period_start,
                period_end=period_end,
            )
            coverage.append(item)
            connection.execute(
                "INSERT INTO _coach_catalog VALUES (?, ?, ?, ?, ?, ?)",
                (
                    item.table,
                    item.description,
                    item.record_count,
                    item.period_start,
                    item.period_end,
                    json.dumps(columns, separators=(",", ":")),
                ),
            )
        for relationship in _RELATIONSHIPS:
            if (
                relationship[0] in columns_by_table
                and relationship[2] in columns_by_table
                and relationship[1] in columns_by_table[relationship[0]]
                and relationship[3] in columns_by_table[relationship[2]]
            ):
                connection.execute(
                    "INSERT INTO _coach_relationships VALUES (?, ?, ?, ?)",
                    relationship,
                )
        connection.execute(
            """
            CREATE VIEW v_data_coverage AS
            SELECT table_name, description, record_count, period_start, period_end
            FROM _coach_catalog
            ORDER BY table_name
            """,
        )
        _create_helpful_views(connection, columns_by_table)
        connection.commit()
        connection.execute("VACUUM")
        return tuple(coverage)
    finally:
        connection.close()


def _create_helpful_views(
    connection: sqlite3.Connection,
    columns: dict[str, set[str]],
) -> None:
    if {"role", "content", "created_at"} <= columns.get("coach_messages", set()):
        connection.execute(
            """
            CREATE VIEW v_coach_conversation AS
            SELECT role, content, created_at
            FROM coach_messages
            ORDER BY created_at
            """,
        )
    if {"id"} <= columns.get("focus_sessions", set()) and {
        "focus_session_id"
    } <= columns.get("focus_session_reflections", set()):
        connection.execute(
            """
            CREATE VIEW v_focus_with_reflection AS
            SELECT f.*, r.row_json AS reflection_json
            FROM focus_sessions AS f
            LEFT JOIN focus_session_reflections AS r
              ON r.focus_session_id = f.id
            """,
        )


def _sqlite_type(rows: list[dict[str, Any]], column: str) -> str:
    values = [row.get(column) for row in rows if row.get(column) is not None]
    if values and all(type(value) in {bool, int} for value in values):
        return "INTEGER"
    if values and all(
        type(value) in {bool, int, float}
        or (isinstance(value, Decimal) and value.is_finite())
        for value in values
    ):
        return "REAL"
    return "TEXT"


def _sqlite_value(value: Any) -> Any:
    if isinstance(value, bool):
        return int(value)
    if value is None or isinstance(value, (str, int, float)):
        return value
    if isinstance(value, Decimal):
        if not value.is_finite():
            raise ValueError("Snapshot contains a non-finite number.")
        if value == value.to_integral_value():
            return int(value)
        return float(value)
    return lossless_json_text(value)


def _period(rows: list[dict[str, Any]]) -> tuple[str | None, str | None]:
    candidates: list[str] = []
    for row in rows:
        for key, value in row.items():
            if (
                isinstance(value, str)
                and key
                in {
                    "date",
                    "entry_date",
                    "local_date",
                    "period_start",
                    "period_end",
                    "week_starts_on",
                    "week_ends_on",
                    "window_starts_on",
                    "window_ends_before",
                    "starts_on",
                    "ends_on",
                    "deadline",
                    "deadline_at",
                    "created_at",
                    "updated_at",
                    "occurred_at",
                    "started_at",
                    "local_started_at",
                    "starts_at",
                    "ends_at",
                    "completed_at",
                    "cancelled_at",
                    "failed_at",
                    "deleted_at",
                    "archived_at",
                    "activated_at",
                    "generated_at",
                    "imported_at",
                    "selected_at",
                }
                and re.match(r"^\d{4}-\d{2}-\d{2}", value)
            ):
                candidates.append(value)
    return (
        min(candidates) if candidates else None,
        max(candidates) if candidates else None,
    )


def _quote(identifier: str) -> str:
    if not _IDENTIFIER.fullmatch(identifier):
        raise ValueError("SQLite identifier is invalid.")
    return f'"{identifier}"'
