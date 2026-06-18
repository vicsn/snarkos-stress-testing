#!/usr/bin/env bash
# lib/common.sh — shared environment + helpers, SOURCED by every entrypoint.
#
# Rules for this file:
#   * It is sourced, never executed. Do NOT set -e/-u/-o pipefail here:
#     that would change the behaviour of whatever sources it. Each entrypoint
#     sets its own `set -euo pipefail`.
#   * It must NEVER prompt (no `read -r -p` without a `[ -t 0 ]` guard). A
#     pueue/background job has no TTY and would block forever.
#   * Path resolution uses BASH_SOURCE, not $0, so it is correct regardless of
#     which script sourced it.

# Guard against double-sourcing.
[[ -n "${_COMMON_SH_SOURCED:-}" ]] && return 0
_COMMON_SH_SOURCED=1

# --- Paths -------------------------------------------------------------------
# This file lives at <project>/scripts/lib/common.sh. So:
#   SCRIPTS_DIR = <project>/scripts   (holds full_run.sh, bin/, lib/, notify_slack.sh)
#   REPO_ROOT   = <project>           (holds terraform/, playbooks/, inventory/,
#                                      tests/, utils/, destroy_infra.sh, lb_url.txt)
SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_ROOT="$(cd "$SCRIPTS_DIR/.." && pwd)"
export SCRIPTS_DIR REPO_ROOT
# Keep the old name as an alias so existing references still work.
PARENT_DIR="$REPO_ROOT"
export PARENT_DIR
INVENTORY_DIR="$PARENT_DIR/inventory/"
export INVENTORY_DIR

# --- Run identity (shared across every job of one logical run) ---------------
# The orchestrator exports RUN_ID once before enqueuing; pueue snapshots the
# environment at `pueue add` time, so all jobs of a run share this value and
# therefore the same S3 prefix. A bare manual invocation gets its own RUN_ID.
: "${RUN_ID:=$(date -u '+%Y%m%dT%H%M%SZ')}"
export RUN_ID

# Slack notifications (best-effort; no-op unless SLACK_TOKEN + channel are set).
# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/notify.sh"

# --- Static environment ------------------------------------------------------
ulimit -n 4096 || true

# tput fails noisily without a TERM (e.g. under pueue); degrade gracefully.
bold=$(tput bold 2>/dev/null || true)
normal=$(tput sgr0 2>/dev/null || true)

export AWS_REGION="${TF_STATE_REGION:-us-west-2}"
export TF_STATE_BUCKET="${TF_STATE_BUCKET:-ephnet-terraform-state-bucket-eq}"
export TF_VAR_state_bucket="$TF_STATE_BUCKET"
RELEASE_BUCKET="${RELEASE_BUCKET:-provable-binaries-releases}"
export TF_VAR_RELEASE_BUCKET="$RELEASE_BUCKET"
export OWNER="${OWNER:-$USER}"
export ANSIBLE_ENABLE_PLUGINS=amazon.aws.aws_ec2
export TF_VAR_devnet_name="${DEVNET_NAME:-single-region-tests}"

RESULTS_AND_LOGS_BUCKET="${RESULTS_AND_LOGS_BUCKET:-provable-logs-results}"
BASE_BUCKET_PATH="manual_test_runs/$USER/$RUN_ID"
export BASE_BUCKET_PATH

# Ansible vars file basename (without extension). Override per-invocation.
VARS="${VARS:-vars}"
export VARS

# --- Tiny helpers ------------------------------------------------------------
isuint() { [[ "$1" =~ ^[0-9]+$ ]]; }
runner_manages_logs() { [ "${RUNNER_MANAGES_LOGS:-}" = "1" ]; }

die() { echo "ERROR: $*" >&2; exit 1; }

# macOS spoken notification; silent no-op elsewhere. Returns 0 unconditionally
# so it is safe as the LAST statement of a function/script under `set -e`
# (a bare `[ ... ] && say` returns 1 on non-Darwin and would abort the script).
say_done() { if [ "$(uname)" = "Darwin" ]; then say "$*" || true; fi; return 0; }

# Fail fast with a clear message if a phase's precondition is missing, instead
# of failing deep inside terraform/ansible. Call at the top of an entrypoint.
require_provisioned() {
  [[ -f "$PARENT_DIR/lb_url.txt" ]] \
    || die "lb_url.txt not found — run provision.sh (and setup.sh) first."
}

# --- Discovery ---------------------------------------------------------------
discover_tests() {
  mapfile -t TESTS < <(find "$PARENT_DIR/tests" -maxdepth 1 -mindepth 1 -type d \
    -printf '%f\n' | sort)
  export TESTS
}
discover_utilities() {
  mapfile -t UTILITIES < <(find "$PARENT_DIR/utils" -maxdepth 1 -mindepth 1 -type d \
    -printf '%f\n' | sort)
  export UTILITIES
}

# --- Centralised ansible invocation -----------------------------------------
# All playbooks share the same big --extra-vars block; centralise it so the
# network/LB/devnet wiring lives in exactly one place.
#   common_ansible <playbook.yml> [extra ansible-playbook args...]
common_ansible() {
  local playbook="$1"; shift
  ansible-playbook -i "$INVENTORY_DIR" "$playbook" \
    --limit "$LIMIT" \
    --extra-vars="devnet_name=${DEVNET_NAME}" \
    --extra-vars="snarkos_network=${NETWORK}" \
    --extra-vars="snarkos_network_int=${NETWORK_INT}" \
    --extra-vars="test_network_url=${LB_URL}" \
    --extra-vars="base_workspace_folder=${PARENT_DIR}/playbooks" \
    --extra-vars="@${VARS}.yml" \
    "$@"
}

# --- Network vars (re-derived from terraform state; safe to call repeatedly) -
set_network_vars() {
  NETWORK=$(cd "$PARENT_DIR/terraform" && TF_CLI_ARGS="-no-color" terraform output -raw snarkos_network)
  export NETWORK

  if [[ -z "${NETWORK}" || "$NETWORK" == *"No outputs found"* ]]; then
    echo "Output 'snarkos_network' not found. Applying noop target to generate it..."
    cp "$PARENT_DIR/terraform/variables.tf.light" "$PARENT_DIR/terraform/variables.tf"
    ( cd "$PARENT_DIR/terraform" || exit 1
      terraform init > /dev/null
      terraform apply -target=null_resource.noop -var="owner=$OWNER" -auto-approve > /dev/null )
    NETWORK=$(cd "$PARENT_DIR/terraform" && TF_CLI_ARGS="-no-color" terraform output -raw snarkos_network)
    export NETWORK
  fi

  DEVNET_NAME=$(cd "$PARENT_DIR/terraform" && TF_CLI_ARGS="-no-color" terraform output -raw devnet_name)
  export DEVNET_NAME

  export ANSIBLE_DEVNET_GROUP="${DEVNET_NAME//-/_}"
  export ANSIBLE_OWNER_GROUP="${OWNER//-/_}"
  export TARGET_PATTERN="devnet_${ANSIBLE_DEVNET_GROUP}:&owner_${ANSIBLE_OWNER_GROUP}"
  export LIMIT="${TARGET_PATTERN}"

  cat > "$PARENT_DIR/inventory/local" <<EOF
[local]
localhost ansible_connection=local

[devnet_${ANSIBLE_DEVNET_GROUP}]
localhost ansible_connection=local

[owner_${ANSIBLE_OWNER_GROUP}]
localhost ansible_connection=local
EOF

  echo "devnet_name : $DEVNET_NAME"

  case "$NETWORK" in
    mainnet) export NETWORK_INT=0 ;;
    testnet) export NETWORK_INT=1 ;;
    canary)  export NETWORK_INT=2 ;;
    *) echo "Error: Unknown network '$NETWORK'" >&2; return 1 ;;
  esac

  # LB_URL is needed by every playbook call; load it whenever it exists. Use a
  # real `if` (not `[[ ]] && ...`) so this isn't a 1-returning last statement.
  if [[ -f "$PARENT_DIR/lb_url.txt" ]]; then
    LB_URL=$(cat "$PARENT_DIR/lb_url.txt"); export LB_URL
  fi
}

# --- Test / utility runners (single item each) -------------------------------
run_test() {
  echo "${bold}$(date +"%T") - Running test: $SELECTED${normal}"
  if [ -x "$PARENT_DIR/tests/$SELECTED/pre-test.sh" ]; then
    ( cd "$PARENT_DIR/tests/$SELECTED/" && ./pre-test.sh )
  fi
  set_network_vars || return 1
  ( cd "$PARENT_DIR/playbooks" && common_ansible run_test.yml --extra-vars="test_name=$SELECTED" )
  if [ -x "$PARENT_DIR/tests/$SELECTED/check.sh" ]; then
    ( cd "$PARENT_DIR/tests/$SELECTED/" && ./check.sh "$NETWORK" )
  fi
  if [ -x "$PARENT_DIR/tests/$SELECTED/post-test.sh" ]; then
    ( cd "$PARENT_DIR/tests/$SELECTED/" && ./post-test.sh )
  fi
  say_done "Finished running $SELECTED"
  return 0
}

run_utility() {
  echo "${bold}$(date +"%T") - Running utility: $SELECTED${normal}"
  if [ -x "$PARENT_DIR/utils/$SELECTED/pre-utility.sh" ]; then
    ( cd "$PARENT_DIR/utils/$SELECTED/" && ./pre-utility.sh )
  fi
  set_network_vars || return 1
  ( cd "$PARENT_DIR/playbooks" && common_ansible run_utility.yml --extra-vars="utility_name=$SELECTED" )
  if [ -x "$PARENT_DIR/utils/$SELECTED/check.sh" ]; then
    ( cd "$PARENT_DIR/utils/$SELECTED/" && ./check.sh "$NETWORK" )
  fi
  if [ -x "$PARENT_DIR/utils/$SELECTED/post-utility.sh" ]; then
    ( cd "$PARENT_DIR/utils/$SELECTED/" && ./post-utility.sh )
  fi
  say_done "Finished running utility $SELECTED"
  return 0
}

# --- Log collection ----------------------------------------------------------
prepare_log_files_dir() {
  if [ -d "$PARENT_DIR/log_files" ]; then
    local _ans
    if [ -t 0 ]; then
      read -r -p "The folder '$PARENT_DIR/log_files' exists. Delete and overwrite it? [y/N]: " _ans || _ans="n"
    else
      _ans="${OVERWRITE_LOG_FILES:-y}"
      echo "Non-interactive run: log_files overwrite = $_ans"
    fi
    case "$_ans" in
      [yY]) rm -rf "$PARENT_DIR/log_files" ;;
      *) echo "Keeping existing 'log_files' (new logs may merge with old ones)." ;;
    esac
  fi
  mkdir -p "$PARENT_DIR/log_files"
}

download_and_upload_logs() {
  if runner_manages_logs; then
    echo "RUNNER_MANAGES_LOGS set: external caller handles logs; skipping."
    return 0
  fi
  echo "Downloading test logs..."
  local test_ran="${SELECTED:-download_and_upload_logs}"   # capture label first
  prepare_log_files_dir

  local u
  for u in download_logs_clients download_logs_provers \
           download_logs_validators download_logs_tx_runner; do
    export SELECTED="$u"; run_utility
  done

  export SELECTED=analyze_logs
  run_utility || echo "WARNING: analyze_logs failed; continuing without landing stats."

  echo "Uploading test logs to S3..."
  if [ -d "$PARENT_DIR/log_files" ]; then
    local log_file destination
    for log_file in "$PARENT_DIR/log_files/"*; do
      [ -f "$log_file" ] || continue
      destination="s3://$RESULTS_AND_LOGS_BUCKET/$BASE_BUCKET_PATH/$test_ran/$(basename "$log_file")"
      echo "Copying $log_file to $destination ..."
      aws s3 cp "$log_file" "$destination" --profile ephnet
    done
  fi
  if [ -f "$PARENT_DIR/observability_runner.log" ]; then
    aws s3 cp "$PARENT_DIR/observability_runner.log" \
      "s3://$RESULTS_AND_LOGS_BUCKET/$BASE_BUCKET_PATH/$test_ran/observability_runner.log" \
      --profile ephnet
    rm -f "$PARENT_DIR/observability_runner.log"
  fi
  echo "Logs: https://console.aws.amazon.com/s3/buckets/$RESULTS_AND_LOGS_BUCKET?prefix=$BASE_BUCKET_PATH/$test_ran/"
}

# --- EXIT trap ---------------------------------------------------------------
# Each entrypoint installs this so a failing *job* collects its own logs.
react_on_exit() {
  local rc=$?
  echo "EXIT (rc: $rc)"
  # Terminal Slack status for this job (best-effort; reflects the true rc).
  notify_job_end "$rc" || true
  if [ $rc -ne 0 ] && ! runner_manages_logs; then
    echo "Error detected! Collecting logs before exiting..."
    local _do_collect="y"
    [ -t 0 ] && { read -r -p "Download and upload logs now? (y/n): " _do_collect || _do_collect="n"; }
    if [[ "$_do_collect" =~ ^[yY]$ ]]; then
      download_and_upload_logs || echo "WARNING: log collection failed; preserving rc=$rc"
    fi
  fi
  exit $rc
}
install_exit_trap() { trap react_on_exit EXIT; }

# --- Terraform apply ---------------------------------------------------------
init_and_apply_terraform() {
  ( cd "$PARENT_DIR/terraform" || exit 1
    terraform init
    terraform apply -auto-approve -var="owner=$OWNER"
    terraform output -raw snarkos_lb_dns_name > "$PARENT_DIR/lb_url.txt" )
  LB_URL=$(cat "$PARENT_DIR/lb_url.txt"); export LB_URL
  set_network_vars || return 1

  echo "Terraform finished; waiting for AWS to sync tags..."
  local MAX_RETRIES=20 SLEEP_INTERVAL=5 RETRY_COUNT=0 HOST_COUNT
  while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    HOST_COUNT=$(ansible -i "$INVENTORY_DIR" "$TARGET_PATTERN" --list-hosts 2>/dev/null \
      | grep -o 'hosts ([0-9]*)' | grep -o '[0-9]*')
    if [[ -n "$HOST_COUNT" && "$HOST_COUNT" -gt 0 ]]; then
      echo "AWS synced tags. Ansible sees $HOST_COUNT hosts."; break
    fi
    echo "Waiting for tags... ($((RETRY_COUNT+1))/$MAX_RETRIES)"
    sleep $SLEEP_INTERVAL; RETRY_COUNT=$((RETRY_COUNT+1))
  done
  [ $RETRY_COUNT -eq $MAX_RETRIES ] && die "Timeout waiting for AWS tag propagation."

  ( cd "$PARENT_DIR/playbooks" && common_ansible ips.yml )
  say_done "Finished running Terraform"
}
