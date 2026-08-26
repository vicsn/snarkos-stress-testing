#!/usr/bin/env bash
# lib/slack_config.sh — load Slack creds from vars.yml (same paths as tf_stack.sh).
#
# Sourced by full_run.sh / notify.sh. Sets SLACK_TOKEN and SLACK_CHANNEL_ID when
# found; leaves existing exports untouched.

[[ -n "${_SLACK_CONFIG_SH_SOURCED:-}" ]] && return 0
_SLACK_CONFIG_SH_SOURCED=1

_slack_read_var() {
  local key="$1" file="$2"
  awk -v key="$key" '
    $1 == key ":" {
      val = $2
      for (i = 3; i <= NF; i++) val = val " " $i
      gsub(/^"|"$|^'\''|'\''$/, "", val)
      print val
      exit
    }
  ' "$file"
}

# load_slack_config_from_vars_yml [monorepo_root]
# Returns 0 when both slack_token and slack_channel_id were loaded.
load_slack_config_from_vars_yml() {
  local root="${MONOREPO_ROOT:-}"
  local vars_file="${root}/test_suites/single-region-tests/playbooks/vars.yml";
  SLACK_TOKEN="$(_slack_read_var slack_token "$vars_file")"
  SLACK_CHANNEL_ID="$(_slack_read_var slack_channel_id "$vars_file")"
  export SLACK_TOKEN SLACK_CHANNEL_ID CHANNEL_ID="$SLACK_CHANNEL_ID"
  return 0
}

# load_slack_config_from_profile — manager-side slack_env.sh from ansible setup.
load_slack_config_from_profile() {
  local f="${HOME:-}/.config/snarkos-stress-testing/slack_env.sh"
  [[ -f "$f" ]] || return 1
  # shellcheck source=/dev/null
  . "$f"
  [[ -n "${SLACK_TOKEN:-}" && -n "${SLACK_CHANNEL_ID:-${CHANNEL_ID:-}}" ]]
}

# load_slack_config_from_secret_manager — fetch from GCP Secret Manager
# using the STM SA's implicit metadata-server credentials (works from the
# manager itself) or the local user's ADC (works from laptops).
load_slack_config_from_secret_manager() {
  command -v gcloud &>/dev/null || return 1
  local project="${GCP_PROJECT:-protocol-development-sandbox}"
  SLACK_TOKEN="$(gcloud secrets versions access latest --secret=stress-testing-manager-slack-token --project="$project" 2>/dev/null)" || return 1
  SLACK_CHANNEL_ID="$(gcloud secrets versions access latest --secret=stress-testing-manager-slack-channel-id --project="$project" 2>/dev/null)" || return 1
  [[ -n "$SLACK_TOKEN" && -n "$SLACK_CHANNEL_ID" ]] || return 1
  export SLACK_TOKEN SLACK_CHANNEL_ID CHANNEL_ID="$SLACK_CHANNEL_ID"
  return 0
}

# load_slack_config — best-effort; prefers existing env, then profile, then
# Secret Manager, then vars.yml (legacy fallback).
load_slack_config() {
  : "${SLACK_CHANNEL_ID:=${CHANNEL_ID:-}}"
  [[ -n "${SLACK_TOKEN:-}" && -n "${SLACK_CHANNEL_ID:-}" ]] && return 0
  load_slack_config_from_profile && return 0
  load_slack_config_from_secret_manager && return 0
  load_slack_config_from_vars_yml && return 0
  return 1
}
