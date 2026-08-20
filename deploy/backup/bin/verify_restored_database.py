#!/usr/bin/env python3
"""Render and validate aggregate postconditions for an isolated DB restore."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from pathlib import Path
from typing import Any


IDENTIFIER = re.compile(r"[A-Za-z_][A-Za-z0-9_]*")
VERSION = re.compile(r"(?P<major>[0-9]+)(?:\.[0-9]+)+(?:[-+].*)?")


class RestoreVerificationError(ValueError):
    pass


def _load(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        raise RestoreVerificationError("restore verification input is invalid") from exc
    if not isinstance(value, dict):
        raise RestoreVerificationError("restore verification input is not an object")
    return value


def _quote_identifier(value: str) -> str:
    if IDENTIFIER.fullmatch(value) is None:
        raise RestoreVerificationError("backup inventory identifier is invalid")
    return f'"{value}"'


def _expected(payload: Path) -> tuple[dict[str, Any], dict[str, Any], dict[str, Any]]:
    manifest = _load(payload / "backup-manifest.json")
    inventory = _load(payload / "inventory.json")
    migrations = _load(payload / "migration-inventory.json")
    migration_rows = migrations.get("migrations")
    if (
        manifest.get("schema_version") != "mylifegraph-supabase-backup-v2"
        or manifest.get("inventory") != inventory
        or manifest.get("project_ref") is None
        or migrations.get("schema_version")
        != "mylifegraph-migration-inventory-v1"
        or not isinstance(migration_rows, list)
        or not migration_rows
    ):
        raise RestoreVerificationError("backup inventories do not match the manifest")
    identities: list[str] = []
    for row in migration_rows:
        if (
            not isinstance(row, dict)
            or set(row) != {"version", "name", "file", "sha256"}
            or not isinstance(row["version"], str)
            or re.fullmatch(r"[0-9]{14}", row["version"]) is None
            or not isinstance(row["name"], str)
            or re.fullmatch(r"[a-z0-9_]+", row["name"]) is None
            or row["file"] != f"{row['version']}_{row['name']}.sql"
            or not isinstance(row["sha256"], str)
            or re.fullmatch(r"[0-9a-f]{64}", row["sha256"]) is None
        ):
            raise RestoreVerificationError("backup migration inventory is invalid")
        identities.append(f"{row['version']}_{row['name']}.sql")
    if (
        identities != sorted(identities)
        or manifest.get("migration_head") != identities[-1]
    ):
        raise RestoreVerificationError("backup migration boundary is inconsistent")
    return manifest, inventory, migrations


def _migration_versions(migrations: dict[str, Any]) -> set[str]:
    return {row["version"] for row in migrations["migrations"]}


def _excluded_storage_report_sql(inventory: dict[str, Any]) -> str:
    expected = inventory.get("excluded_storage_relation_counts")
    relations = ("storage.buckets_vectors", "storage.vector_indexes")
    if not isinstance(expected, dict) or set(expected) != set(relations):
        raise RestoreVerificationError(
            "backup excluded Storage inventory is invalid"
        )
    descriptors: list[str] = []
    for qualified_name in relations:
        descriptor = expected[qualified_name]
        if (
            not isinstance(descriptor, dict)
            or set(descriptor) != {"present", "row_count"}
            or not isinstance(descriptor["present"], bool)
            or descriptor["row_count"] != 0
        ):
            raise RestoreVerificationError(
                "backup excluded Storage inventory is invalid"
            )
        schema, table = qualified_name.split(".")
        relation = f"{_quote_identifier(schema)}.{_quote_identifier(table)}"
        present_sql = f"to_regclass('{qualified_name}') is not null"
        count_sql = (
            f"(select count(*)::bigint from {relation})"
            if descriptor["present"]
            else "0::bigint"
        )
        descriptors.append(
            f"'{qualified_name}', jsonb_build_object("
            f"'present', {present_sql}, 'row_count', {count_sql})"
        )
    return "jsonb_build_object(" + ", ".join(descriptors) + ")"


def render_sql(payload: Path) -> str:
    _, inventory, migrations = _expected(payload)
    versions = _migration_versions(migrations)
    counts = inventory.get("table_row_counts")
    if not isinstance(counts, dict) or not counts:
        raise RestoreVerificationError("backup table inventory is invalid")
    count_queries: list[str] = []
    for qualified_name in sorted(counts):
        if not isinstance(qualified_name, str) or qualified_name.count(".") != 1:
            raise RestoreVerificationError("backup table identity is invalid")
        schema, table = qualified_name.split(".")
        relation = f"{_quote_identifier(schema)}.{_quote_identifier(table)}"
        literal = qualified_name.replace("'", "''")
        count_queries.append(
            f"select '{literal}'::text as relation, count(*)::bigint as row_count "
            f"from {relation}"
        )
    count_sql = "\nunion all\n".join(count_queries)
    excluded_storage_sql = _excluded_storage_report_sql(inventory)
    expected_gate = inventory.get("pilot_participation_gate")
    if not isinstance(expected_gate, dict) or set(expected_gate) not in (
        {"present"},
        {
            "present",
            "project_ref",
            "participation_required",
            "notice_version",
        },
    ):
        raise RestoreVerificationError("backup participation gate inventory is invalid")
    if expected_gate.get("present") is True:
        gate_present_sql = "to_regclass('private.pilot_participation_gate_v1') is not null"
        gate_sql = """(
      select jsonb_build_object(
        'project_ref', gate.project_ref,
        'participation_required', gate.participation_required,
        'notice_version', gate.notice_version
      )
      from private.pilot_participation_gate_v1 as gate
      where gate.singleton
    )"""
    elif expected_gate == {"present": False}:
        gate_present_sql = "to_regclass('private.pilot_participation_gate_v1') is not null"
        gate_sql = "null::jsonb"
    else:
        raise RestoreVerificationError("backup participation gate inventory is invalid")
    critical_rpcs: list[str] = []
    if "20260714100000" in versions:
        critical_rpcs.append(
            "public.apply_notification_action_v1(uuid,uuid,uuid,text,timestamp with time zone)"
        )
    if "20260802083219" in versions:
        critical_rpcs.append(
            "public.start_focus_session_v2(uuid,uuid,text,text,uuid,integer,integer,text,uuid,text,timestamp with time zone)"
        )
    if "20260813200057" in versions:
        critical_rpcs.append(
            "public.persist_weekly_review_v3(uuid,text,timestamp with time zone,jsonb)"
        )
    if "20260819203000" in versions:
        critical_rpcs.append(
            "public.claim_coach_request_v8(uuid,text,uuid,text,date,text,text,text,text,timestamp with time zone,timestamp with time zone,integer,boolean)"
        )
    elif "20260815075711" in versions:
        critical_rpcs.append(
            "public.claim_coach_request_v7(uuid,uuid,text,date,text,text,text,text,timestamp with time zone,timestamp with time zone,integer)"
        )
    if "20260819185740" in versions:
        critical_rpcs.append("public.accept_pilot_participation_v1(uuid,text)")
    if "20260820170000" in versions:
        critical_rpcs.extend(
            [
                "public.prepare_account_deletion_v2(uuid,uuid,text)",
                "public.mark_account_deletion_appending_v2(uuid,uuid)",
                "public.accept_account_deletion_journal_v2(uuid,uuid,timestamp with time zone,text,text,timestamp with time zone)",
                "public.complete_account_deletion_v2(uuid,uuid,text,timestamp with time zone)",
                "public.list_pending_account_deletions_v2(integer)",
                "public.get_account_deletion_pending_v2(uuid)",
                "public.get_account_deletion_intent_v2(uuid)",
                "public.get_account_deletion_recovery_status_v2()",
            ]
        )
    quoted_rpcs = ",\n        ".join(
        "'" + identity.replace("'", "''") + "'" for identity in critical_rpcs
    )
    if "20260713233000" not in versions:
        legacy_delete_drift_sql = "false"
    elif "20260820170000" in versions:
        legacy_delete_drift_sql = (
            "has_function_privilege('service_role', "
            "'public.delete_account_v1(uuid,text)', 'EXECUTE')"
        )
    else:
        legacy_delete_drift_sql = (
            "not has_function_privilege('service_role', "
            "'public.delete_account_v1(uuid,text)', 'EXECUTE')"
        )
    replayer_role_drift_sql = (
        "not coalesce((with target_role as (select role.oid, "
        "not role.rolcanlogin and not role.rolsuper "
        "and not role.rolcreatedb and not role.rolcreaterole "
        "and not role.rolinherit and not role.rolreplication "
        "and not role.rolbypassrls and role.rolconnlimit = 0 "
        "and role.rolconfig is null as safe_attributes "
        "from pg_catalog.pg_roles as role "
        "where role.rolname = 'mylifegraph_deletion_replayer'), "
        "incident_memberships as (select membership.*, "
        "to_jsonb(membership) as membership_facts "
        "from pg_catalog.pg_auth_members as membership "
        "join target_role on membership.roleid = target_role.oid "
        "or membership.member = target_role.oid) "
        "select (select safe_attributes from target_role) and ("
        "(current_setting('server_version_num')::integer < 160000 "
        "and not exists (select 1 from incident_memberships)) or "
        "(current_setting('server_version_num')::integer >= 160000 "
        "and 1 = (select count(*) from incident_memberships) "
        "and exists (select 1 from incident_memberships as membership "
        "where membership.roleid = (select oid from target_role) "
        "and membership.member = current_user::regrole "
        "and membership.grantor = 10 and membership.admin_option "
        "and (membership.membership_facts ->> 'inherit_option')::boolean "
        "is false and (membership.membership_facts ->> 'set_option')::boolean "
        "is false)))), false)"
        if "20260820200000" in versions
        else "false"
    )
    replay_authority_drift_sql = (
        "has_function_privilege('service_role', "
        "'public.replay_account_deletion_v2(uuid,uuid,timestamp with time zone,text,text,timestamp with time zone)', 'EXECUTE') "
        "or has_function_privilege('authenticated', "
        "'public.replay_account_deletion_v2(uuid,uuid,timestamp with time zone,text,text,timestamp with time zone)', 'EXECUTE') "
        "or not has_function_privilege('mylifegraph_deletion_replayer', "
        "'public.replay_account_deletion_v2(uuid,uuid,timestamp with time zone,text,text,timestamp with time zone)', 'EXECUTE') "
        f"or ({replayer_role_drift_sql})"
        if "20260820170000" in versions
        else "false"
    )
    return f"""\\set ON_ERROR_STOP on
\\pset tuples_only on
\\pset format unaligned
with restored_counts as (
{count_sql}
), report as (
  select jsonb_build_object(
    'schema_version', 'mylifegraph-restore-report-v1',
    'postgres_server_version', current_setting('server_version'),
    'table_row_counts', (
      select jsonb_object_agg(relation, row_count order by relation)
      from restored_counts
    ),
    'excluded_storage_relation_counts', {excluded_storage_sql},
    'migration_identities', (
      select coalesce(
        jsonb_agg(jsonb_build_array(version, name) order by version, name),
        '[]'::jsonb
      )
      from supabase_migrations.schema_migrations
    ),
    'profiles_without_auth', (
      select count(*) from public.profiles as profile
      where not exists (select 1 from auth.users where id = profile.id)
    ),
    'auth_without_profiles', (
      select count(*) from auth.users as account
      where not exists (select 1 from public.profiles where id = account.id)
    ),
    'public_rls_unforced', (
      select count(*)
      from pg_catalog.pg_class as class
      where class.relnamespace = 'public'::regnamespace
        and class.relkind in ('r', 'p')
        and (not class.relrowsecurity or not class.relforcerowsecurity)
    ),
    'application_executable_security_definers', (
      select count(*)
      from pg_catalog.pg_proc as procedure
      where procedure.pronamespace = 'public'::regnamespace
        and procedure.prosecdef
        and (
          has_function_privilege('anon', procedure.oid, 'EXECUTE')
          or has_function_privilege('authenticated', procedure.oid, 'EXECUTE')
        )
    ),
    'anon_table_privilege_drift', (
      select count(*)
      from pg_catalog.pg_class as class
      where class.relnamespace = 'public'::regnamespace
        and class.relkind in ('r', 'p')
        and (
          has_table_privilege('anon', class.oid, 'SELECT')
          or has_table_privilege('anon', class.oid, 'INSERT')
          or has_table_privilege('anon', class.oid, 'UPDATE')
          or has_table_privilege('anon', class.oid, 'DELETE')
          or has_table_privilege('anon', class.oid, 'TRUNCATE')
          or has_table_privilege('anon', class.oid, 'REFERENCES')
          or has_table_privilege('anon', class.oid, 'TRIGGER')
        )
    ),
    'authenticated_dangerous_privilege_drift', (
      select count(*)
      from pg_catalog.pg_class as class
      where class.relnamespace = 'public'::regnamespace
        and class.relkind in ('r', 'p')
        and (
          has_table_privilege('authenticated', class.oid, 'TRUNCATE')
          or has_table_privilege('authenticated', class.oid, 'REFERENCES')
          or has_table_privilege('authenticated', class.oid, 'TRIGGER')
        )
    ),
    'anon_table_default_privilege_drift', (
      select count(*)
      from pg_catalog.pg_default_acl as defaults
      join pg_catalog.pg_namespace as namespace
        on namespace.oid = defaults.defaclnamespace
      cross join lateral pg_catalog.aclexplode(defaults.defaclacl) as privilege
      join pg_catalog.pg_roles as grantee on grantee.oid = privilege.grantee
      where defaults.defaclrole = 'postgres'::regrole
        and namespace.nspname = 'public'
        and defaults.defaclobjtype = 'r'
        and grantee.rolname = 'anon'
    ),
    'authenticated_dangerous_table_default_privilege_drift', (
      select count(*)
      from pg_catalog.pg_default_acl as defaults
      join pg_catalog.pg_namespace as namespace
        on namespace.oid = defaults.defaclnamespace
      cross join lateral pg_catalog.aclexplode(defaults.defaclacl) as privilege
      join pg_catalog.pg_roles as grantee on grantee.oid = privilege.grantee
      where defaults.defaclrole = 'postgres'::regrole
        and namespace.nspname = 'public'
        and defaults.defaclobjtype = 'r'
        and grantee.rolname = 'authenticated'
        and privilege.privilege_type in ('TRUNCATE', 'REFERENCES', 'TRIGGER')
    ),
    'generated_projection_grant_drift', (
      select count(*)
      from pg_catalog.pg_class as class
      where class.relnamespace = 'public'::regnamespace
        and class.relname in (
          'notifications', 'ai_insights', 'daily_briefings', 'skillset_profiles'
        )
        and (
          not has_table_privilege('authenticated', class.oid, 'SELECT')
          or has_table_privilege('authenticated', class.oid, 'INSERT')
          or has_table_privilege('authenticated', class.oid, 'UPDATE')
          or has_table_privilege('authenticated', class.oid, 'DELETE')
        )
    ),
    'critical_service_rpc_missing', (
      select count(*)
      from unnest(array[
        {quoted_rpcs}
      ]::text[]) as expected(identity)
      where to_regprocedure(expected.identity) is null
        or not has_function_privilege(
          'service_role', to_regprocedure(expected.identity), 'EXECUTE'
        )
    ),
    'legacy_delete_privilege_drift', (
      select case when {legacy_delete_drift_sql} then 1 else 0 end
    ),
    'deletion_replay_authority_drift', (
      select case when {replay_authority_drift_sql} then 1 else 0 end
    ),
    'critical_owner_policy_missing', (
      select count(*)
      from unnest(array[
        'profiles_own_or_admin_all',
        'behavioral_events_own_or_admin_all',
        'daily_logs_own_or_admin_all',
        'focus_sessions_own_or_admin_all',
        'habit_logs_own_or_admin_all',
        'habits_own_or_admin_all',
        'lifestyle_entries_own_or_admin_all',
        'notification_preferences_own_or_admin_all',
        'schedule_items_own_or_admin_all',
        'tasks_own_or_admin_all'
      ]::text[]) as expected(policy_name)
      where not exists (
        select 1
        from pg_catalog.pg_policy as policy
        join pg_catalog.pg_class as class on class.oid = policy.polrelid
        where policy.polname = expected.policy_name
          and class.relnamespace = 'public'::regnamespace
      )
    ),
    'auth_profile_trigger_missing', (
      select count(*)
      from unnest(array[
        'on_auth_user_created', 'on_auth_user_created_app_user'
      ]::text[]) as expected(trigger_name)
      where not exists (
        select 1 from pg_catalog.pg_trigger as trigger
        where trigger.tgrelid = 'auth.users'::regclass
          and not trigger.tgisinternal
          and trigger.tgname = expected.trigger_name
      )
    ),
    'participation_policy_missing', (
      case
        when to_regclass('private.pilot_participation_gate_v1') is null then 0
        else (
          select count(*)
          from pg_catalog.pg_class as class
          where class.relnamespace = 'public'::regnamespace
            and class.relkind in ('r', 'p')
            and class.relrowsecurity
            and (
              (
                class.relname <> 'profiles'
                and not exists (
                  select 1 from pg_catalog.pg_policy as policy
                  where policy.polrelid = class.oid
                    and policy.polname = 'pilot_participation_required_v1'
                    and not policy.polpermissive
                )
              )
              or (
                class.relname = 'profiles'
                and 3 <> (
                  select count(*) from pg_catalog.pg_policy as policy
                  where policy.polrelid = class.oid
                    and policy.polname in (
                      'pilot_participation_profile_insert_v1',
                      'pilot_participation_profile_update_v1',
                      'pilot_participation_profile_delete_v1'
                    )
                    and not policy.polpermissive
                )
              )
            )
        )
      end
    ),
    'participation_gate_present', {gate_present_sql},
    'participation_gate', {gate_sql}
  ) as value
)
select value::text from report;
"""


def validate_report(
    payload: Path,
    report_path: Path,
    *,
    recovery_migration_head: str | None = None,
) -> dict[str, Any]:
    manifest, inventory, migrations = _expected(payload)
    report = _load(report_path)
    expected_keys = {
        "schema_version",
        "postgres_server_version",
        "table_row_counts",
        "excluded_storage_relation_counts",
        "migration_identities",
        "profiles_without_auth",
        "auth_without_profiles",
        "public_rls_unforced",
        "application_executable_security_definers",
        "anon_table_privilege_drift",
        "authenticated_dangerous_privilege_drift",
        "anon_table_default_privilege_drift",
        "authenticated_dangerous_table_default_privilege_drift",
        "generated_projection_grant_drift",
        "critical_service_rpc_missing",
        "legacy_delete_privilege_drift",
        "deletion_replay_authority_drift",
        "critical_owner_policy_missing",
        "auth_profile_trigger_missing",
        "participation_policy_missing",
        "participation_gate_present",
        "participation_gate",
    }
    if set(report) != expected_keys or report["schema_version"] != (
        "mylifegraph-restore-report-v1"
    ):
        raise RestoreVerificationError("restore report shape is invalid")
    if report["table_row_counts"] != inventory["table_row_counts"]:
        raise RestoreVerificationError("restored table counts differ from backup")
    if report["excluded_storage_relation_counts"] != inventory.get(
        "excluded_storage_relation_counts"
    ):
        raise RestoreVerificationError(
            "restored excluded Storage inventory differs from backup"
        )
    expected_migrations = [
        [item["version"], item["name"]]
        for item in migrations.get("migrations", [])
        if isinstance(item, dict)
    ]
    if report["migration_identities"] != expected_migrations:
        raise RestoreVerificationError("restored migration history differs from backup")
    source_version = VERSION.fullmatch(inventory["postgres_server_version"])
    target_version = VERSION.fullmatch(report["postgres_server_version"])
    if (
        source_version is None
        or target_version is None
        or source_version["major"] != target_version["major"]
    ):
        raise RestoreVerificationError("restored PostgreSQL major version is incompatible")
    for key in (
        "profiles_without_auth",
        "auth_without_profiles",
        "public_rls_unforced",
        "application_executable_security_definers",
        "anon_table_privilege_drift",
        "authenticated_dangerous_privilege_drift",
        "anon_table_default_privilege_drift",
        "authenticated_dangerous_table_default_privilege_drift",
        "generated_projection_grant_drift",
        "critical_service_rpc_missing",
        "legacy_delete_privilege_drift",
        "deletion_replay_authority_drift",
        "critical_owner_policy_missing",
        "auth_profile_trigger_missing",
        "participation_policy_missing",
    ):
        if report[key] != 0:
            raise RestoreVerificationError(f"restore postcondition failed: {key}")
    gate_inventory = inventory["pilot_participation_gate"]
    if report["participation_gate_present"] is not gate_inventory["present"]:
        raise RestoreVerificationError("restored participation gate presence differs")
    expected_gate = (
        {
            "project_ref": gate_inventory["project_ref"],
            "participation_required": gate_inventory["participation_required"],
            "notice_version": gate_inventory["notice_version"],
        }
        if gate_inventory["present"]
        else None
    )
    if report["participation_gate"] != expected_gate:
        raise RestoreVerificationError("restored participation gate state differs")
    recovery_head = recovery_migration_head or manifest["migration_head"]
    if (
        not isinstance(recovery_head, str)
        or re.fullmatch(r"[0-9]{14}_[a-z0-9_]+\.sql", recovery_head) is None
        or recovery_head < manifest["migration_head"]
    ):
        raise RestoreVerificationError("restore recovery migration head is invalid")
    return {
        "schema_version": "mylifegraph-restore-attestation-v1",
        "project_ref": manifest["project_ref"],
        "migration_head": manifest["migration_head"],
        "recovery_migration_head": recovery_head,
        "postgres_source_version": inventory["postgres_server_version"],
        "postgres_restore_version": report["postgres_server_version"],
        "table_count": inventory["table_count"],
        "total_row_count": inventory["total_row_count"],
        "postconditions": "passed",
        "deletion_replay_required": (
            recovery_head
            >= "20260820170000_account_deletion_recovery_v2.sql"
        ),
        "participation_gate": gate_inventory,
    }


def validate_deletion_replay_watermark(
    payload: Path,
    path: Path,
) -> dict[str, Any]:
    manifest = _load(payload / "backup-manifest.json")
    value = _load(path)
    expected_keys = {
        "schema_version",
        "project_ref",
        "backup_manifest_sha256",
        "backup_cutoff_utc",
        "journal_capture_through_utc",
        "journal_export_manifest_sha256",
        "journal_source_inventory_sha256",
        "replay_set_sha256",
        "replayed_entry_count",
        "last_replayed_accepted_at",
        "owner_relation_count",
        "postconditions",
    }
    manifest_sha256 = hashlib.sha256(
        (payload / "backup-manifest.json").read_bytes()
    ).hexdigest()
    if (
        set(value) != expected_keys
        or value.get("schema_version")
        != "mylifegraph-deletion-replay-watermark-v1"
        or value.get("project_ref") != manifest.get("project_ref")
        or value.get("backup_manifest_sha256") != manifest_sha256
        or value.get("backup_cutoff_utc") != manifest.get("started_at_utc")
        or re.fullmatch(
            r"[0-9a-f]{64}",
            str(value.get("journal_export_manifest_sha256")),
        )
        is None
        or re.fullmatch(
            r"[0-9a-f]{64}",
            str(value.get("journal_source_inventory_sha256")),
        )
        is None
        or re.fullmatch(r"[0-9a-f]{64}", str(value.get("replay_set_sha256")))
        is None
        or not isinstance(value.get("replayed_entry_count"), int)
        or value["replayed_entry_count"] < 0
        or not isinstance(value.get("owner_relation_count"), int)
        or value["owner_relation_count"] < 1
        or value.get("postconditions") != "passed"
    ):
        raise RestoreVerificationError("deletion replay watermark is invalid")
    for name in (
        "backup_cutoff_utc",
        "journal_capture_through_utc",
        "last_replayed_accepted_at",
    ):
        item = value.get(name)
        if item is not None and re.fullmatch(
            r"[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z",
            str(item),
        ) is None:
            raise RestoreVerificationError("deletion replay timestamp is invalid")
    if value["journal_capture_through_utc"] < value["backup_cutoff_utc"]:
        raise RestoreVerificationError("deletion replay does not cover the backup")
    return value


def validate_schema_comparison(path: Path) -> str:
    value = _load(path)
    if (
        set(value) != {
            "schema_version",
            "normalization",
            "restored_sha256",
            "reference_sha256",
            "match",
        }
        or value.get("schema_version") != "mylifegraph-schema-comparison-v2"
        or value.get("normalization") != {
            "acl_authority": "strict-schema-digest",
            "boolean_check_constraints": sorted(
                {
                    "multi_exam_plan_batch_items_shape_check",
                    "multi_exam_plan_batch_links_shape_check",
                    "assignment_series_shape_check",
                    "assignment_series_items_shape_check",
                    "assignment_series_revisions_input_check",
                    "calendar_connections_label_length",
                    "calendar_events_text_bounds",
                    "calendar_imports_counts",
                    "deadline_plan_blocks_recovery_check",
                    "deadline_plan_blocks_shape_check",
                    "focus_session_reflections_obstacles_check",
                    "planner_habit_slots_shape_check",
                    "planner_task_blocks_recovery_check",
                    "planner_task_blocks_shape_check",
                    "profiles_daily_preparation_budget_minutes_check",
                }
            ),
        }
        or re.fullmatch(r"[0-9a-f]{64}", str(value.get("restored_sha256")))
        is None
        or re.fullmatch(r"[0-9a-f]{64}", str(value.get("reference_sha256")))
        is None
        or value.get("match") is not True
        or value["restored_sha256"] != value["reference_sha256"]
    ):
        raise RestoreVerificationError(
            "restored schema differs from the repository migration reference"
        )
    return value["reference_sha256"]


def main() -> int:
    parser = argparse.ArgumentParser()
    subparsers = parser.add_subparsers(dest="operation", required=True)
    render = subparsers.add_parser("render-sql")
    render.add_argument("--payload", required=True)
    render.add_argument("--output", required=True)
    validate = subparsers.add_parser("validate")
    validate.add_argument("--payload", required=True)
    validate.add_argument("--report", required=True)
    validate.add_argument("--schema-comparison", required=True)
    validate.add_argument("--deletion-replay-watermark")
    validate.add_argument("--recovery-migration-head")
    validate.add_argument("--output", required=True)
    args = parser.parse_args()
    try:
        payload = Path(args.payload).resolve(strict=True)
        if args.operation == "render-sql":
            Path(args.output).write_text(render_sql(payload), encoding="utf-8")
        else:
            attestation = validate_report(
                payload,
                Path(args.report),
                recovery_migration_head=args.recovery_migration_head,
            )
            attestation["schema_reference_sha256"] = validate_schema_comparison(
                Path(args.schema_comparison),
            )
            if attestation["deletion_replay_required"]:
                if not args.deletion_replay_watermark:
                    raise RestoreVerificationError(
                        "deletion replay watermark is required",
                    )
                attestation["deletion_replay"] = validate_deletion_replay_watermark(
                    payload,
                    Path(args.deletion_replay_watermark),
                )
            else:
                if args.deletion_replay_watermark:
                    raise RestoreVerificationError(
                        "pre-contract restore cannot claim deletion replay",
                    )
                attestation["deletion_replay"] = {
                    "status": "not_applicable_contract_absent",
                }
            Path(args.output).write_text(
                json.dumps(attestation, indent=2, sort_keys=True) + "\n",
                encoding="utf-8",
            )
    except (RestoreVerificationError, OSError, UnicodeError, KeyError, TypeError) as exc:
        print(f"restore verification error: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
