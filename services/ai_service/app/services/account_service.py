import json
from collections.abc import Callable
from dataclasses import dataclass
from datetime import UTC, datetime
from decimal import Decimal
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from app.models.account import (
    ACCOUNT_EXPORT_CONTRACT_VERSION,
    ACCOUNT_EXPORT_MAX_JSON_BYTES,
    ACCOUNT_EXPORT_MAX_ROWS_PER_TABLE,
    ACCOUNT_EXPORT_MAX_TOTAL_ROWS,
    ACCOUNT_EXPORT_OMITTED_TABLES,
    ACCOUNT_EXPORT_SANITIZED_TABLES,
    ACCOUNT_EXPORT_TABLE_NAMES,
    AccountExportLedgerPolicy,
    AccountExportLimits,
    AccountExportResponse,
    AccountPreparationBudgetResponse,
    AccountProfileResponse,
    DAILY_PREPARATION_BUDGET_MINUTES_MAX,
    DAILY_PREPARATION_BUDGET_MINUTES_MIN,
)
from app.repositories.account_repository import (
    AccountExportSourceTooLargeError,
    AccountExportTable,
    AccountNotFoundError,
    AccountPersistenceError,
    AccountRepository,
)


ACCOUNT_EXPORT_PAGE_SIZE = 1_000
ACCOUNT_EXPORT_PAGE_BYTE_CUSHION = 4096
ACCOUNT_EXPORT_WATERMARK_MAX_BYTES = 4096


class InvalidAccountTimezoneError(ValueError):
    pass


class InvalidPreparationBudgetError(ValueError):
    pass


class AccountExportTooLargeError(RuntimeError):
    pass


@dataclass(frozen=True)
class PreparedAccountExport:
    envelope: AccountExportResponse
    content: bytes


def _table(
    name: str,
    select: str,
    *,
    owner_column: str = "user_id",
    cursor_column: str = "id",
    watermark_column: str = "created_at",
) -> AccountExportTable:
    return AccountExportTable(
        name=name,
        owner_column=owner_column,
        select=select,
        cursor_column=cursor_column,
        watermark_column=watermark_column,
    )


ACCOUNT_EXPORT_TABLES = (
    _table(
        "profiles",
        "id,email,display_name,timezone,daily_preparation_budget_minutes,"
        "role,auth_provider,"
        "onboarding_completed_at,setup_revision,created_at,updated_at",
        owner_column="id",
        cursor_column="id",
    ),
    _table(
        "notification_preferences",
        "user_id,focus_prompts_enabled,recovery_prompts_enabled,"
        "weekly_summary_enabled,quiet_hours_start,quiet_hours_end,"
        "created_at,updated_at",
        cursor_column="user_id",
    ),
    _table("daily_logs", "*"),
    _table("behavioral_events", "*"),
    _table("lifestyle_entries", "*"),
    _table("tasks", "*"),
    _table("schedule_items", "*"),
    _table("notifications", "*"),
    _table(
        "coach_messages",
        "id,user_id,request_id,contract_version,role,content,metadata,created_at",
    ),
    _table("memory_entries", "*"),
    _table("ai_insights", "*"),
    _table("recommendations", "*", watermark_column="generated_at"),
    _table("skillset_profiles", "*", watermark_column="generated_at"),
    _table("goals", "*"),
    _table("habits", "*"),
    _table("habit_logs", "*"),
    _table("focus_sessions", "*"),
    _table("intake_responses", "*"),
    _table(
        "study_setup_profiles",
        "user_id,contract_version,focus_minutes,recovery_minutes,"
        "preparation_items,current_semester,next_semester,setup_revision,"
        "created_at,updated_at",
        cursor_column="user_id",
    ),
    _table(
        "user_state_snapshots",
        "*",
        watermark_column="generated_at",
    ),
    _table("daily_briefings", "*"),
    _table("decision_feedback", "*"),
    _table("weekly_reviews", "*"),
    _table(
        "calendar_connections",
        "id,user_id,contract_version,origin,source_kind,source_label,status,"
        "consent_version,read_calendar_events,store_event_basics,provider_writes,"
        "llm_processing,consented_at,connected_at,disconnected_at,"
        "imported_data_deleted_at,last_import_id,created_at,updated_at",
    ),
    _table(
        "calendar_imports",
        "id,user_id,connection_id,contract_version,origin,source_kind,"
        "window_starts_on,window_ends_before,timezone,accepted_count,"
        "cancelled_count,out_of_window_count,unsupported_recurring_count,"
        "invalid_count,imported_at,created_at",
    ),
    _table(
        "calendar_events",
        "id,user_id,connection_id,import_id,contract_version,origin,source_kind,"
        "source_fingerprint,title,location,event_kind,busy_status,event_status,"
        "event_timezone,timezone_source,starts_at,ends_at,local_starts_at,"
        "local_ends_at,starts_on,ends_on,last_modified_at,imported_at,"
        "last_seen_at,created_at,updated_at",
    ),
    _table(
        "coach_requests",
        "request_id,user_id,contract_version,context_scope,local_date,state,"
        "provider,provider_mode,model_requested,model_reported,model_source,"
        "prompt_version,context_version,response,used_context,created_at,"
        "completed_at,failed_at,deleted_at,updated_at",
        cursor_column="request_id",
    ),
    _table(
        "coach_usage_events",
        "request_id,user_id,local_date,outcome,provider,provider_mode,"
        "model_requested,model_reported,model_source,error_code,counters,created_at",
        cursor_column="request_id",
    ),
    _table(
        "coach_memory_selections",
        "user_id,memory_id,selection_version,selected_at",
        cursor_column="memory_id",
        watermark_column="selected_at",
    ),
    _table(
        "deadline_plans",
        "id,user_id,contract_version,origin,status,kind,title,managed_task_id,"
        "original_estimated_total_minutes,original_credited_prior_minutes,"
        "current_revision,latest_revision,first_activated_at,completed_at,"
        "cancelled_at,created_at,updated_at",
    ),
    _table(
        "deadline_plan_revisions",
        "id,user_id,plan_id,revision,base_revision,state,kind,title,deadline_at,"
        "estimated_total_minutes,credited_prior_minutes,preferred_session_minutes,"
        "max_daily_minutes,planning_start_on,buffer_days,source_kind,"
        "source_calendar_event_id,source_calendar_event_fingerprint,"
        "use_calendar_availability,availability_connection_id,"
        "availability_import_id,timezone,best_energy_window,planning_fingerprint,"
        "study_setup_revision,recovery_minutes,"
        "tracked_focus_minutes_at_proposal,remaining_minutes_at_proposal,"
        "planned_minutes,unscheduled_minutes,created_at,activated_at,superseded_at",
    ),
    _table(
        "deadline_plan_blocks",
        "id,user_id,plan_id,revision,sequence,reservation_state,starts_at,ends_at,"
        "reserved_ends_at,local_date,local_start_time,local_end_time,"
        "planned_minutes,recovery_minutes,created_at,updated_at",
    ),
    _table(
        "planner_preferences",
        "user_id,contract_version,use_calendar_busy_time,created_at,updated_at",
        cursor_column="user_id",
    ),
    _table("planner_action_plans", "*"),
    _table("planner_action_plan_revisions", "*"),
    _table("planner_task_blocks", "*"),
    _table("planner_habit_slots", "*"),
    _table("planner_commitments", "*"),
)


ACCOUNT_EXPORT_LEDGER_POLICY = AccountExportLedgerPolicy(
    sanitized_tables=list(ACCOUNT_EXPORT_SANITIZED_TABLES),
    omitted_tables=dict(ACCOUNT_EXPORT_OMITTED_TABLES),
)


class AccountService:
    def __init__(
        self,
        *,
        repository: AccountRepository,
        now: Callable[[], datetime] | None = None,
    ) -> None:
        self._repository = repository
        self._now = now or (lambda: datetime.now(UTC))

    async def update_timezone(
        self,
        *,
        user_id: str,
        timezone: str,
    ) -> AccountProfileResponse:
        _validate_timezone(timezone)
        stored = await self._repository.update_timezone(
            user_id=user_id,
            timezone=timezone,
        )
        if stored is None:
            raise AccountNotFoundError("Account profile is unavailable.")
        return AccountProfileResponse(timezone=stored)

    async def update_preparation_budget(
        self,
        *,
        user_id: str,
        minutes: int | None,
    ) -> AccountPreparationBudgetResponse:
        _validate_preparation_budget(minutes)
        stored = await self._repository.update_preparation_budget(
            user_id=user_id,
            minutes=minutes,
        )
        if stored is None:
            raise AccountNotFoundError("Account profile is unavailable.")
        return AccountPreparationBudgetResponse(
            daily_preparation_budget_minutes=stored.minutes,
        )

    async def export_account(self, *, user_id: str) -> PreparedAccountExport:
        _validate_export_configuration()
        exported_at = self._now()
        data: dict[str, list[dict[str, object]]] = {
            name: [] for name in ACCOUNT_EXPORT_TABLE_NAMES
        }
        empty_response = AccountExportResponse(
            contract_version=ACCOUNT_EXPORT_CONTRACT_VERSION,
            exported_at=exported_at,
            data=data,
            record_counts={name: 0 for name in ACCOUNT_EXPORT_TABLE_NAMES},
            ledger_policy=ACCOUNT_EXPORT_LEDGER_POLICY,
            limits=_export_limits(),
        )
        estimated_json_bytes = len(_compact_json_bytes(empty_response))
        total_rows = 0
        # Capture all table-local upper bounds before retaining any product
        # rows. Together with immutable keyset cursors this prevents offset
        # shifts and excludes normal inserts committed after each watermark.
        # This deliberately does not claim a cross-table transaction snapshot.
        watermarks = {
            table.name: await self._repository.get_export_watermark(
                user_id=user_id,
                table=table,
                max_response_bytes=ACCOUNT_EXPORT_WATERMARK_MAX_BYTES,
            )
            for table in ACCOUNT_EXPORT_TABLES
        }
        for table in ACCOUNT_EXPORT_TABLES:
            rows = data[table.name]
            not_after = watermarks[table.name]
            if not_after is None:
                continue
            after_cursor: str | None = None
            while True:
                remaining = ACCOUNT_EXPORT_MAX_ROWS_PER_TABLE - len(rows)
                request_limit = min(ACCOUNT_EXPORT_PAGE_SIZE, remaining + 1)
                response_budget = (
                    ACCOUNT_EXPORT_MAX_JSON_BYTES - estimated_json_bytes
                )
                source_page_bound = max(
                    2,
                    min(
                        ACCOUNT_EXPORT_MAX_JSON_BYTES,
                        response_budget + ACCOUNT_EXPORT_PAGE_BYTE_CUSHION,
                    ),
                )
                try:
                    page = await self._repository.list_export_rows(
                        user_id=user_id,
                        table=table,
                        after_cursor=after_cursor,
                        not_after=not_after,
                        limit=request_limit,
                        max_response_bytes=source_page_bound,
                    )
                except AccountExportSourceTooLargeError as exc:
                    raise AccountExportTooLargeError(
                        "Account export exceeds the V1 JSON size bound.",
                    ) from exc
                if not isinstance(page, list) or any(
                    not isinstance(row, dict) for row in page
                ):
                    raise AccountPersistenceError(
                        "Account export persistence returned an invalid page.",
                    )
                if len(page) > request_limit:
                    raise AccountPersistenceError(
                        "Account export persistence returned an invalid page.",
                    )
                if any(
                    not isinstance(row.get(table.owner_column), str)
                    or row[table.owner_column] != user_id
                    for row in page
                ):
                    raise AccountPersistenceError(
                        "Account export persistence returned an invalid owner.",
                    )
                if len(page) > remaining:
                    raise AccountExportTooLargeError(
                        f"Account export table {table.name} exceeds the V1 row bound.",
                    )
                if total_rows + len(page) > ACCOUNT_EXPORT_MAX_TOTAL_ROWS:
                    raise AccountExportTooLargeError(
                        "Account export exceeds the V1 total row bound.",
                    )
                for row in page:
                    cursor = row.get(table.cursor_column)
                    if (
                        not isinstance(cursor, str)
                        or not cursor
                        or (after_cursor is not None and cursor <= after_cursor)
                    ):
                        raise AccountPersistenceError(
                            "Account export persistence returned an invalid cursor.",
                        )
                    row_bytes = len(_compact_json_bytes(row))
                    separator_bytes = 1 if rows else 0
                    old_count_digits = len(str(len(rows)))
                    new_count_digits = len(str(len(rows) + 1))
                    growth = (
                        row_bytes
                        + separator_bytes
                        + new_count_digits
                        - old_count_digits
                    )
                    if estimated_json_bytes + growth > ACCOUNT_EXPORT_MAX_JSON_BYTES:
                        raise AccountExportTooLargeError(
                            "Account export exceeds the V1 JSON size bound.",
                        )
                    rows.append(row)
                    total_rows += 1
                    estimated_json_bytes += growth
                    after_cursor = cursor
                if len(page) < request_limit:
                    break

        envelope = AccountExportResponse(
            contract_version=ACCOUNT_EXPORT_CONTRACT_VERSION,
            exported_at=exported_at,
            data=data,
            record_counts={name: len(rows) for name, rows in data.items()},
            ledger_policy=ACCOUNT_EXPORT_LEDGER_POLICY,
            limits=_export_limits(),
        )
        content = _compact_json_bytes(envelope)
        if (
            len(content) != estimated_json_bytes
            or len(content) > ACCOUNT_EXPORT_MAX_JSON_BYTES
        ):
            raise AccountExportTooLargeError(
                "Account export exceeds the V1 JSON size bound.",
            )
        return PreparedAccountExport(envelope=envelope, content=content)

    async def delete_account(
        self,
        *,
        user_id: str,
        confirmation: str,
    ) -> None:
        if confirmation != "DELETE":
            raise ValueError("Exact account deletion confirmation is required.")
        await self._repository.delete_account(
            user_id=user_id,
            confirmation=confirmation,
        )


def _validate_timezone(value: str) -> None:
    if value in {"localtime", "posixrules"} or value.startswith(("posix/", "right/")):
        raise InvalidAccountTimezoneError("timezone must be a stable IANA name")
    try:
        zone = ZoneInfo(value)
    except (ZoneInfoNotFoundError, ValueError) as exc:
        raise InvalidAccountTimezoneError("timezone must be a valid IANA name") from exc
    if zone.key != value:
        raise InvalidAccountTimezoneError("timezone must be a valid IANA name")


def _validate_preparation_budget(value: int | None) -> None:
    if value is None:
        return
    if (
        type(value) is not int
        or value < DAILY_PREPARATION_BUDGET_MINUTES_MIN
        or value > DAILY_PREPARATION_BUDGET_MINUTES_MAX
        or value % 5 != 0
    ):
        raise InvalidPreparationBudgetError(
            "daily preparation budget must be 25 through 480 minutes "
            "in five-minute increments",
        )


def _validate_export_configuration() -> None:
    configured_tables = tuple(table.name for table in ACCOUNT_EXPORT_TABLES)
    if configured_tables != ACCOUNT_EXPORT_TABLE_NAMES:
        raise AccountPersistenceError(
            "Account export contract configuration is invalid.",
        )
    configured_sanitized = tuple(
        ACCOUNT_EXPORT_LEDGER_POLICY.sanitized_tables,
    )
    if (
        configured_sanitized != ACCOUNT_EXPORT_SANITIZED_TABLES
        or ACCOUNT_EXPORT_LEDGER_POLICY.omitted_tables
        != ACCOUNT_EXPORT_OMITTED_TABLES
    ):
        raise AccountPersistenceError(
            "Account export contract configuration is invalid.",
        )
    if (
        ACCOUNT_EXPORT_MAX_ROWS_PER_TABLE,
        ACCOUNT_EXPORT_MAX_TOTAL_ROWS,
        ACCOUNT_EXPORT_MAX_JSON_BYTES,
    ) != (10_000, 50_000, 8 * 1024 * 1024):
        raise AccountPersistenceError(
            "Account export contract configuration is invalid.",
        )


def _export_limits() -> AccountExportLimits:
    return AccountExportLimits(
        max_rows_per_table=ACCOUNT_EXPORT_MAX_ROWS_PER_TABLE,
        max_total_rows=ACCOUNT_EXPORT_MAX_TOTAL_ROWS,
        max_json_bytes=ACCOUNT_EXPORT_MAX_JSON_BYTES,
    )


def _compact_json_bytes(value: AccountExportResponse | dict[str, object]) -> bytes:
    serializable = (
        value.model_dump(mode="python")
        if isinstance(value, AccountExportResponse)
        else value
    )
    try:
        return _lossless_json_text(serializable, depth=0).encode("utf-8")
    except (RecursionError, TypeError, ValueError) as exc:
        raise AccountPersistenceError(
            "Account export persistence returned invalid JSON data.",
        ) from exc


def _lossless_json_text(value: object, *, depth: int) -> str:
    if depth > 64:
        raise ValueError("Account export JSON nesting is too deep.")
    if value is None:
        return "null"
    if value is True:
        return "true"
    if value is False:
        return "false"
    if isinstance(value, str):
        return json.dumps(value, ensure_ascii=False)
    if isinstance(value, int):
        return str(value)
    if isinstance(value, Decimal):
        if not value.is_finite():
            raise ValueError("Account export contains a non-finite number.")
        return str(value)
    if isinstance(value, float):
        return json.dumps(value, allow_nan=False, separators=(",", ":"))
    if isinstance(value, datetime):
        if value.tzinfo is None:
            raise ValueError("Account export contains a naive timestamp.")
        timestamp = value.isoformat()
        if value.utcoffset() == UTC.utcoffset(value):
            timestamp = timestamp.replace("+00:00", "Z")
        return json.dumps(timestamp, ensure_ascii=False)
    if isinstance(value, (list, tuple)):
        return "[" + ",".join(
            _lossless_json_text(item, depth=depth + 1) for item in value
        ) + "]"
    if isinstance(value, dict):
        chunks: list[str] = []
        for key, item in value.items():
            if not isinstance(key, str):
                raise TypeError("Account export JSON keys must be strings.")
            chunks.append(
                f"{json.dumps(key, ensure_ascii=False)}:"
                f"{_lossless_json_text(item, depth=depth + 1)}",
            )
        return "{" + ",".join(chunks) + "}"
    raise TypeError("Account export contains a non-JSON value.")
