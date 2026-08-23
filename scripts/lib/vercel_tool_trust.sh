#!/usr/bin/env bash

# Pure trust predicates for scripts/vercel_build.sh. Keeping the decision
# separate makes the production policy executable under synthetic negative
# tests without adding a build-only bypass.

vercel_tool_owner_is_trusted() {
  local tool="${1-}"
  local resolved="${2-}"
  local tool_uid="${3-}"

  [[ "${tool_uid}" =~ ^[0-9]+$ ]] || return 1
  [[ "${tool_uid}" == '0' ]] && return 0
  [[ "${tool}" == 'node' && "${resolved}" == '/node24/bin/node' ]]
}

vercel_tool_parent_owner_is_trusted() {
  local tool="${1-}"
  local resolved="${2-}"
  local tool_uid="${3-}"
  local parent="${4-}"
  local parent_uid="${5-}"

  [[ "${tool_uid}" =~ ^[0-9]+$ && "${parent_uid}" =~ ^[0-9]+$ ]] || return 1
  [[ "${parent_uid}" == '0' ]] && return 0
  [[ "${tool}" == 'node' && "${resolved}" == '/node24/bin/node' &&
    "${parent_uid}" == "${tool_uid}" ]] || return 1
  case "${parent}" in
    /node24|/node24/bin) return 0 ;;
    *) return 1 ;;
  esac
}

vercel_tool_mode_is_trusted() {
  local mode="${1-}"

  [[ "${mode}" =~ ^[0-7]{3,4}$ ]] || return 1
  (( (8#${mode} & 022) == 0 ))
}
