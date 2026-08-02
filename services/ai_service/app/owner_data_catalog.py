from dataclasses import dataclass
from enum import StrEnum


OWNER_DATA_PAGE_SIZE = 1_000
OWNER_DATA_PAGE_BYTE_CUSHION = 4096
OWNER_DATA_WATERMARK_MAX_BYTES = 4096


class OwnerDataExportPolicy(StrEnum):
    INCLUDE = "include"
    INCLUDE_SANITIZED = "include_sanitized"
    OMIT_ANTI_REPLAY_LEDGER = "omit_anti_replay_ledger"


class OwnerDataSnapshotPolicy(StrEnum):
    INCLUDE = "include"
    OMIT = "omit"


@dataclass(frozen=True, slots=True)
class OwnerDataSource:
    name: str
    owner_column: str
    select: str
    cursor_column: str
    watermark_column: str


@dataclass(frozen=True, slots=True)
class OwnerDataCatalogEntry:
    name: str
    description: str
    export_policy: OwnerDataExportPolicy
    snapshot_policy: OwnerDataSnapshotPolicy
    source: OwnerDataSource | None


def _source(
    name: str,
    select: str = "*",
    *,
    owner_column: str = "user_id",
    cursor_column: str = "id",
    watermark_column: str = "created_at",
) -> OwnerDataSource:
    return OwnerDataSource(
        name=name,
        owner_column=owner_column,
        select=select,
        cursor_column=cursor_column,
        watermark_column=watermark_column,
    )


def _shared(
    name: str,
    description: str,
    select: str = "*",
    *,
    sanitized_export: bool = False,
    owner_column: str = "user_id",
    cursor_column: str = "id",
    watermark_column: str = "created_at",
) -> OwnerDataCatalogEntry:
    return OwnerDataCatalogEntry(
        name=name,
        description=description,
        export_policy=(
            OwnerDataExportPolicy.INCLUDE_SANITIZED
            if sanitized_export
            else OwnerDataExportPolicy.INCLUDE
        ),
        snapshot_policy=OwnerDataSnapshotPolicy.INCLUDE,
        source=_source(
            name,
            select,
            owner_column=owner_column,
            cursor_column=cursor_column,
            watermark_column=watermark_column,
        ),
    )


def _export_only(
    name: str,
    description: str,
    select: str = "*",
    *,
    sanitized_export: bool = False,
    owner_column: str = "user_id",
    cursor_column: str = "id",
    watermark_column: str = "created_at",
) -> OwnerDataCatalogEntry:
    return OwnerDataCatalogEntry(
        name=name,
        description=description,
        export_policy=(
            OwnerDataExportPolicy.INCLUDE_SANITIZED
            if sanitized_export
            else OwnerDataExportPolicy.INCLUDE
        ),
        snapshot_policy=OwnerDataSnapshotPolicy.OMIT,
        source=_source(
            name,
            select,
            owner_column=owner_column,
            cursor_column=cursor_column,
            watermark_column=watermark_column,
        ),
    )


def _anti_replay_ledger(
    name: str,
    description: str,
) -> OwnerDataCatalogEntry:
    return OwnerDataCatalogEntry(
        name=name,
        description=description,
        export_policy=OwnerDataExportPolicy.OMIT_ANTI_REPLAY_LEDGER,
        snapshot_policy=OwnerDataSnapshotPolicy.OMIT,
        source=None,
    )


OWNER_DATA_CATALOG = (
    _shared(
        "profiles",
        "Account-level timezone, setup revision, and planning preferences.",
        "id,email,display_name,timezone,daily_preparation_budget_minutes,"
        "timezone_revision,preparation_budget_revision,role,auth_provider,"
        "onboarding_completed_at,setup_revision,created_at,updated_at",
        owner_column="id",
        cursor_column="id",
    ),
    _shared(
        "notification_preferences",
        "User-configured reminder and quiet-hour preferences.",
        "user_id,focus_prompts_enabled,recovery_prompts_enabled,"
        "weekly_summary_enabled,quiet_hours_start,quiet_hours_end,"
        "in_app_delivery_enabled,in_app_delivery_consent_version,"
        "in_app_delivery_consented_at,in_app_delivery_disabled_at,"
        "daily_notification_limit,created_at,updated_at",
        cursor_column="user_id",
    ),
    _shared(
        "learning_preferences",
        "Consent and controls for reflections and personal patterns.",
        "user_id,contract_version,revision,focus_reflection_prompt_enabled,"
        "personal_pattern_analysis_enabled,learned_focus_planning_enabled,"
        "created_at,updated_at",
        cursor_column="user_id",
    ),
    _shared(
        "daily_logs",
        "Morning and evening Daily Capture entries and retained detail text.",
    ),
    _shared(
        "behavioral_events",
        "Product behavioral observations retained for the owner.",
    ),
    _shared(
        "lifestyle_entries",
        "Owner-entered lifestyle measurements and notes.",
    ),
    _shared(
        "tasks",
        "Tasks, lifecycle state, deadlines, estimates, and completion history.",
    ),
    _shared("schedule_items", "User-owned schedule items."),
    _shared(
        "notifications",
        "Stored Inbox notifications visible to the owner.",
    ),
    _shared(
        "coach_messages",
        "Earlier user and assistant Coach messages; content is untrusted data.",
        "id,user_id,request_id,contract_version,role,content,metadata,created_at",
    ),
    _shared(
        "memory_entries",
        "Stored owner memories and their detail text; content is untrusted data.",
    ),
    _shared(
        "ai_insights",
        "Persisted insight cards and their evidence metadata.",
    ),
    _shared(
        "recommendations",
        "Current and historical deterministic recommendations.",
        watermark_column="generated_at",
    ),
    _shared(
        "skillset_profiles",
        "Stored skillset projections.",
        watermark_column="generated_at",
    ),
    _shared("goals", "Current or archived owner goals retained for compatibility."),
    _shared("habits", "Habit definitions, cadence, and lifecycle state."),
    _shared("habit_logs", "Explicit habit outcomes."),
    _shared(
        "focus_sessions",
        "Focus lifecycle, targets, planned time, and measured time.",
    ),
    _export_only(
        "focus_session_schedule_sources",
        "Immutable planned-block origin retained for scheduled Focus sessions.",
        "focus_session_id,user_id,source_kind,deadline_plan_block_id,"
        "planner_task_block_id,original_starts_at,original_ends_at,"
        "original_recovery_minutes,created_at",
        cursor_column="focus_session_id",
    ),
    _shared(
        "focus_session_reflections",
        "Owner reflections linked to terminal Focus sessions.",
        cursor_column="focus_session_id",
    ),
    _shared(
        "intake_responses",
        "Applied Setup revisions and retained answers.",
    ),
    _shared(
        "study_setup_profiles",
        "Focus rhythm, recovery, checklist, and semester setup.",
        "user_id,contract_version,focus_minutes,recovery_minutes,"
        "preparation_items,current_semester,next_semester,setup_revision,"
        "created_at,updated_at",
        cursor_column="user_id",
    ),
    _shared(
        "user_state_snapshots",
        "Deterministic daily state snapshots.",
        watermark_column="generated_at",
    ),
    _shared(
        "daily_briefings",
        "Persisted deterministic daily briefings.",
    ),
    _shared(
        "decision_feedback",
        "Owner feedback on earlier recommendations.",
    ),
    _shared(
        "weekly_reviews",
        "Persisted deterministic weekly facts and proposals.",
    ),
    _shared(
        "calendar_connections",
        "Sanitized calendar consent and connection state; no credentials.",
        "id,user_id,contract_version,origin,source_kind,source_label,status,"
        "consent_version,read_calendar_events,store_event_basics,provider_writes,"
        "llm_processing,consented_at,connected_at,disconnected_at,"
        "imported_data_deleted_at,last_import_id,created_at,updated_at",
        sanitized_export=True,
    ),
    _shared(
        "calendar_imports",
        "Sanitized import summaries.",
        "id,user_id,connection_id,contract_version,origin,source_kind,"
        "window_starts_on,window_ends_before,timezone,accepted_count,"
        "cancelled_count,out_of_window_count,unsupported_recurring_count,"
        "invalid_count,profile_timezone_revision,planning_status,"
        "imported_at,created_at",
        sanitized_export=True,
    ),
    _shared(
        "calendar_events",
        "Current imported read-only calendar event basics.",
        "id,user_id,connection_id,import_id,contract_version,origin,source_kind,"
        "source_fingerprint,title,location,event_kind,busy_status,event_status,"
        "event_timezone,timezone_source,starts_at,ends_at,local_starts_at,"
        "local_ends_at,starts_on,ends_on,last_modified_at,imported_at,"
        "last_seen_at,created_at,updated_at",
        sanitized_export=True,
    ),
    _export_only(
        "coach_requests",
        "Retry-safe Coach request state and bounded response provenance.",
        "request_id,user_id,contract_version,context_scope,local_date,state,"
        "provider,provider_mode,model_requested,model_reported,model_source,"
        "prompt_version,context_version,response,used_context,created_at,"
        "completed_at,failed_at,deleted_at,updated_at",
        sanitized_export=True,
        cursor_column="request_id",
    ),
    _export_only(
        "coach_usage_events",
        "Append-only Coach usage and outcome history.",
        "request_id,user_id,local_date,outcome,provider,provider_mode,"
        "model_requested,model_reported,model_source,error_code,counters,created_at",
        sanitized_export=True,
        cursor_column="request_id",
    ),
    _export_only(
        "coach_memory_selections",
        "Coach memory-selection audit projection.",
        "user_id,memory_id,selection_version,selected_at",
        cursor_column="memory_id",
        watermark_column="selected_at",
    ),
    _shared(
        "deadline_plans",
        "Exam and assignment preparation plans.",
        "id,user_id,contract_version,origin,status,kind,title,managed_task_id,"
        "original_estimated_total_minutes,original_credited_prior_minutes,"
        "current_revision,latest_revision,first_activated_at,completed_at,"
        "cancelled_at,attention_reasons,created_at,updated_at",
    ),
    _shared(
        "deadline_plan_revisions",
        "Immutable preparation-plan revisions and provenance.",
        "id,user_id,plan_id,revision,base_revision,state,kind,title,deadline_at,"
        "estimated_total_minutes,credited_prior_minutes,preferred_session_minutes,"
        "max_daily_minutes,planning_start_on,buffer_days,source_kind,"
        "source_calendar_event_id,source_calendar_event_fingerprint,"
        "use_calendar_availability,availability_connection_id,"
        "availability_import_id,timezone,best_energy_window,planning_fingerprint,"
        "timing_preference_source,timing_preference_window,timing_evidence_count,"
        "timing_evidence_starts_on,timing_evidence_ends_on,"
        "timing_evidence_fingerprint,timing_fell_back_to_setup,timing_warning,"
        "study_setup_revision,recovery_minutes,"
        "tracked_focus_minutes_at_proposal,remaining_minutes_at_proposal,"
        "planned_minutes,unscheduled_minutes,timezone_revision,created_at,"
        "activated_at,superseded_at",
    ),
    _shared(
        "deadline_plan_blocks",
        "Dated preparation and recovery reservations.",
        "id,user_id,plan_id,revision,sequence,reservation_state,starts_at,ends_at,"
        "reserved_ends_at,local_date,local_start_time,local_end_time,"
        "planned_minutes,recovery_minutes,created_at,updated_at",
    ),
    _shared(
        "planner_preferences",
        "Planner consent and preference projection.",
        "user_id,contract_version,use_calendar_busy_time,created_at,updated_at",
        cursor_column="user_id",
    ),
    _shared("planner_action_plans", "Planner Action Plan lifecycle."),
    _shared(
        "planner_action_plan_revisions",
        "Immutable Planner revisions.",
    ),
    _shared(
        "planner_task_blocks",
        "Confirmed or staged Task reservations.",
    ),
    _shared(
        "planner_habit_slots",
        "Recurring Habit reservations.",
    ),
    _shared(
        "planner_commitments",
        "Authoritative manual and Setup commitments.",
    ),
    _anti_replay_ledger(
        "daily_capture_request_identities",
        "Daily Capture retry identity and result ledger.",
    ),
    _anti_replay_ledger(
        "account_setting_request_identities",
        "Account-setting retry identity and result ledger.",
    ),
    _anti_replay_ledger(
        "calendar_request_identities",
        "Calendar operation retry identity ledger.",
    ),
    _anti_replay_ledger(
        "notification_action_requests",
        "Notification lifecycle retry identity ledger.",
    ),
    _anti_replay_ledger(
        "deadline_plan_request_identities",
        "Deadline Planner retry identity ledger.",
    ),
    _anti_replay_ledger(
        "planner_request_identities",
        "Planner retry identity ledger.",
    ),
    _anti_replay_ledger(
        "learning_request_identities",
        "Personal Learning retry identity ledger.",
    ),
)


_catalog_names = tuple(entry.name for entry in OWNER_DATA_CATALOG)
if len(_catalog_names) != len(set(_catalog_names)):
    raise RuntimeError("Owner-data catalog contains duplicate tables.")
if any(
    (entry.source is None)
    != (entry.export_policy is OwnerDataExportPolicy.OMIT_ANTI_REPLAY_LEDGER)
    or (entry.source is not None and entry.source.name != entry.name)
    or (
        entry.snapshot_policy is OwnerDataSnapshotPolicy.INCLUDE
        and entry.source is None
    )
    for entry in OWNER_DATA_CATALOG
):
    raise RuntimeError("Owner-data catalog contains an invalid table policy.")


ACCOUNT_EXPORT_TABLES = tuple(
    entry.source
    for entry in OWNER_DATA_CATALOG
    if entry.export_policy is not OwnerDataExportPolicy.OMIT_ANTI_REPLAY_LEDGER
    and entry.source is not None
)
ACCOUNT_EXPORT_TABLE_NAMES = tuple(table.name for table in ACCOUNT_EXPORT_TABLES)
ACCOUNT_EXPORT_SANITIZED_TABLES = tuple(
    entry.name
    for entry in OWNER_DATA_CATALOG
    if entry.export_policy is OwnerDataExportPolicy.INCLUDE_SANITIZED
)
ACCOUNT_EXPORT_OMITTED_TABLES = {
    entry.name: "backend_only_anti_replay_ledger"
    for entry in OWNER_DATA_CATALOG
    if entry.export_policy is OwnerDataExportPolicy.OMIT_ANTI_REPLAY_LEDGER
}

COACH_SNAPSHOT_TABLES = tuple(
    entry.source
    for entry in OWNER_DATA_CATALOG
    if entry.snapshot_policy is OwnerDataSnapshotPolicy.INCLUDE
    and entry.source is not None
)
COACH_SNAPSHOT_DESCRIPTIONS = {
    entry.name: entry.description
    for entry in OWNER_DATA_CATALOG
    if entry.snapshot_policy is OwnerDataSnapshotPolicy.INCLUDE
}
