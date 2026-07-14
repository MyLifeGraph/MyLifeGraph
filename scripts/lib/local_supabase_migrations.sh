#!/usr/bin/env bash

# Shared local Supabase migration safety helpers.
#
# Repository scripts source this file, then define `supabase_cli` before calling
# the preparation functions.
# The default path is inspection-only: it compares repository migration files
# with the local database history and refuses to continue when they differ.

local_supabase_validate_boolean() {
  local name="$1"
  local value="$2"

  case "$value" in
    true | false) return 0 ;;
    *)
      printf 'Local Supabase migration error: %s must be exactly true or false (received %q).\n' \
        "$name" "$value" >&2
      return 2
      ;;
  esac
}

local_supabase_validate_migration_flags() {
  local reset_db="$1"
  local apply_migrations="$2"
  local allow_reset="${3:-true}"

  local_supabase_validate_boolean RESET_DB "$reset_db" || return $?
  local_supabase_validate_boolean APPLY_MIGRATIONS "$apply_migrations" || return $?
  local_supabase_validate_boolean allow_reset "$allow_reset" || return $?

  if [[ "$reset_db" == "true" && "$apply_migrations" == "true" ]]; then
    printf '%s\n' \
      'Local Supabase migration error: RESET_DB=true and APPLY_MIGRATIONS=true are mutually exclusive.' >&2
    return 2
  fi

  if [[ "$reset_db" == "true" && "$allow_reset" != "true" ]]; then
    printf '%s\n' \
      'Local Supabase migration error: this command never resets the database.' \
      'Use RESET_DB=true only with scripts/verify_supabase_local.sh or scripts/e2e_web.sh when destroying the local database is explicitly intended.' >&2
    return 2
  fi
}

local_supabase_compare_migration_history() {
  awk -F '[|]' '
    function trim(value) {
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
      return value
    }
    function is_version(value) {
      return length(value) == 14 && value ~ /^[0-9]+$/
    }
    {
      if (NF < 2) {
        next
      }
      local_version = trim($1)
      database_version = trim($2)
      local_is_version = is_version(local_version)
      database_is_version = is_version(database_version)
      if (!local_is_version && !database_is_version) {
        next
      }
      saw_version = 1
      if (!local_is_version || !database_is_version || local_version != database_version) {
        printf "repository=%s database=%s\n", \
          (local_is_version ? local_version : "missing"), \
          (database_is_version ? database_version : "missing")
        mismatch = 1
      }
    }
    END {
      if (!saw_version) {
        print "No migration versions could be parsed from Supabase CLI output."
        exit 2
      }
      if (mismatch) {
        exit 1
      }
    }
  '
}

local_supabase_assert_migration_history_current() {
  local allow_reset="${1:-true}"
  local migration_output comparison_output comparison_status

  if ! migration_output="$(supabase_cli migration list --local 2>&1)"; then
    printf '%s\n' "$migration_output" >&2
    printf '%s\n' \
      "Local Supabase migration error: 'supabase migration list --local' failed." \
      'No migration was applied automatically.' >&2
    return 1
  fi

  if comparison_output="$(
    printf '%s\n' "$migration_output" | local_supabase_compare_migration_history
  )"; then
    comparison_status=0
  else
    comparison_status=$?
  fi

  if [[ "$comparison_status" -eq 0 ]]; then
    printf '%s\n' 'Local Supabase migration history matches the repository.'
    return 0
  fi

  printf '%s\n' "$migration_output" >&2
  if [[ -n "$comparison_output" ]]; then
    printf 'Migration history difference: %s\n' "$comparison_output" >&2
  fi
  if [[ "$comparison_status" -eq 1 ]]; then
    printf '%s\n' \
      'Local Supabase migration error: repository migration files and local database history differ.' \
      'No migration was applied automatically.' \
      'Review the pending SQL and local data first. Re-run the same command with APPLY_MIGRATIONS=true only when those local changes are intended.' >&2
    if [[ "$allow_reset" == "true" ]]; then
      printf '%s\n' \
        'Use RESET_DB=true only when deliberately destroying and recreating the local database.' >&2
    else
      printf '%s\n' \
        'This command never resets the database. Use RESET_DB=true only with scripts/verify_supabase_local.sh or scripts/e2e_web.sh when destruction is explicitly intended.' >&2
    fi
  else
    printf '%s\n' \
      'Local Supabase migration error: the migration history output could not be verified safely.' \
      'No migration was applied automatically.' >&2
  fi
  return 1
}

local_supabase_prepare_migration_state() {
  local reset_db="$1"
  local apply_migrations="$2"
  local allow_reset="${3:-true}"

  local_supabase_validate_migration_flags \
    "$reset_db" "$apply_migrations" "$allow_reset" || return $?

  if [[ "$reset_db" == "true" ]]; then
    printf '%s\n' \
      'WARNING: RESET_DB=true destroys and recreates the local Supabase database.' >&2
    supabase_cli db reset || return $?
  elif [[ "$apply_migrations" == "true" ]]; then
    printf '%s\n' \
      'WARNING: APPLY_MIGRATIONS=true runs pending SQL against the local database.' \
      'Pending migrations may change or delete local rows. Continue only when that local data change is intended.' >&2
    supabase_cli migration up --local || return $?
  fi

  local_supabase_assert_migration_history_current "$allow_reset"
}
