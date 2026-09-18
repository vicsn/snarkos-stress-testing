#!/usr/bin/env bash
# lib/common.sh — shared environment + helpers, SOURCED by every entrypoint.
#
# Rules for this file:
#   * It is sourced, never executed. Do NOT set -e/-u/-o pipefail here:
#     that would change the behaviour of whatever sources it. Each entrypoint
#     sets its own `set -euo pipefail`. Sourcing bash_err_trap.sh enables
#     errtrace + an ERR trap so failures print file:line (callers already
#     use errexit).
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
MONOREPO_ROOT="$(cd "$REPO_ROOT/../.." && pwd)"
# shellcheck source=/dev/null
source "${MONOREPO_ROOT}/scripts/lib/bash_err_trap.sh"
# DEVNET_KEY + ensure_devnet_key: retained for the AWS-based
# snarkos-cdn-tests suite which still relies on a static key pair. The GCP
# snarkos-p2p-tests + stress-testing-manager stack uses OS Login and does
# not read these; new callers should avoid them.
DEVNET_KEY="${MONOREPO_ROOT}/devnet-key"
SHARED_KEYS_PUB="${MONOREPO_ROOT}/keys.pub"
export MONOREPO_ROOT DEVNET_KEY SHARED_KEYS_PUB
# Keep the old name as an alias so existing references still work.
PARENT_DIR="$REPO_ROOT"
export PARENT_DIR
INVENTORY_DIR="$PARENT_DIR/inventory/"
export INVENTORY_DIR

# --- Run identity (shared across every job of one logical run) ---------------
# The orchestrator exports RUN_ID once before enqueuing; pueue snapshots the
# environment at `pueue add` time, so all jobs of a run share this value and
# therefore the same GCS prefix. A bare manual invocation gets its own RUN_ID.
: "${RUN_ID:=$(date -u '+%Y%m%dT%H%M%SZ')}"
export RUN_ID

# Slack notifications (best-effort; no-op unless SLACK_TOKEN + channel are set).
# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/notify.sh"
# Delegation to the stress-testing-manager, then queueing on it — in that order.
# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/stm.sh"
# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/pueue.sh"

# --- Static environment ------------------------------------------------------
ulimit -n 4096 || true

# Non-interactive SSH sessions (e.g. delegated full_run) skip login profiles.
if [[ -d "${HOME}/.cargo/bin" ]]; then
  PATH="${HOME}/.cargo/bin:${PATH}"
fi
export PATH

# tput fails noisily without a TERM (e.g. under pueue); degrade gracefully.
bold=$(tput bold 2>/dev/null || true)
normal=$(tput sgr0 2>/dev/null || true)

export GCP_REGION="${GCP_REGION:-us-central1}"
RELEASE_BUCKET="${RELEASE_BUCKET:-provable-binaries-releases}"
export TF_VAR_RELEASE_BUCKET="$RELEASE_BUCKET"
export OWNER=${OWNER:-$USER}
export ANSIBLE_ENABLE_PLUGINS=google.cloud.gcp_compute
export TF_VAR_devnet_name="${DEVNET_NAME:-snarkos-p2p-tests}"

# Auto-detect a local personal SSH public key to layer on top of the
# always-injected devnet-key.pub (see terraform/locals.tf ssh_metadata).
# Checked in order: gcloud key > ed25519 > rsa. Leave TF_VAR_ssh_public_key
# empty to skip — devnet-key.pub alone remains authorized on every host.
if [[ -z "${TF_VAR_ssh_public_key:-}" ]]; then
  for _key in ~/.ssh/google_compute_engine.pub ~/.ssh/id_ed25519.pub ~/.ssh/id_rsa.pub; do
    if [[ -f "$_key" ]]; then
      TF_VAR_ssh_public_key="$(cat "$_key")"
      break
    fi
  done
  export TF_VAR_ssh_public_key="${TF_VAR_ssh_public_key:-}"
fi

LB_URL="${LB_URL:-}"
export LB_URL
RESULTS_AND_LOGS_BUCKET="${RESULTS_AND_LOGS_BUCKET:-provable-logs-results}"
BASE_BUCKET_PATH="manual_test_runs/$USER/$RUN_ID"
export BASE_BUCKET_PATH

# Ansible vars file basename (without extension). Override per-invocation.
VARS="${VARS:-vars}"
export VARS

# --- Tiny helpers ------------------------------------------------------------
isuint() { [[ "$1" =~ ^[0-9]+$ ]]; }
runner_manages_logs() { [ "${RUNNER_MANAGES_LOGS:-}" = "1" ]; }

die() {
  echo "ERROR: $* (${BASH_SOURCE[1]}:${BASH_LINENO[0]} ${FUNCNAME[1]}())" >&2
  exit 1
}

# Runtime flags for pregenerate_transactions / load_saved_transactions.
# These are not in vars.yml — parse from the CLI, then pass as ansible extra-vars.
parse_tx_run_flag() {
  case "$1" in
    --execution-tx-count=*)
      PREGENERATION_EXECUTION_TX_COUNT="${1#*=}"
      export PREGENERATION_EXECUTION_TX_COUNT
      ;;
    --deployment-tx-count=*)
      PREGENERATION_DEPLOYMENT_TX_COUNT="${1#*=}"
      export PREGENERATION_DEPLOYMENT_TX_COUNT
      ;;
    --num-validators=*)
      PREGENERATE_TRANSACTIONS_NUM_VALIDATORS="${1#*=}"
      export PREGENERATE_TRANSACTIONS_NUM_VALIDATORS
      ;;
    --tx-type=*)
      LOAD_SAVED_TRANSACTIONS_TYPE="${1#*=}"
      export LOAD_SAVED_TRANSACTIONS_TYPE
      ;;
    --target-master|--target-master=true|--target-master=1)
      TARGET_MASTER=1
      export TARGET_MASTER
      ;;
    --target-master=false|--target-master=0)
      TARGET_MASTER=0
      export TARGET_MASTER
      ;;
    *) return 1 ;;
  esac
}

tx_run_flag_args() {
  # shellcheck disable=SC2178
  local -n _tx_flags_out=$1
  _tx_flags_out=()
  # Use `if`, not `[[ -n ]] && append`: a trailing `&&` returns 1 when the
  # flag is unset and aborts the caller under `set -e` (see say_done).
  if [[ -n "${PREGENERATION_EXECUTION_TX_COUNT:-}" ]]; then
    _tx_flags_out+=("--execution-tx-count=${PREGENERATION_EXECUTION_TX_COUNT}")
  fi
  if [[ -n "${PREGENERATION_DEPLOYMENT_TX_COUNT:-}" ]]; then
    _tx_flags_out+=("--deployment-tx-count=${PREGENERATION_DEPLOYMENT_TX_COUNT}")
  fi
  if [[ -n "${PREGENERATE_TRANSACTIONS_NUM_VALIDATORS:-}" ]]; then
    _tx_flags_out+=("--num-validators=${PREGENERATE_TRANSACTIONS_NUM_VALIDATORS}")
  fi
  if [[ -n "${LOAD_SAVED_TRANSACTIONS_TYPE:-}" ]]; then
    _tx_flags_out+=("--tx-type=${LOAD_SAVED_TRANSACTIONS_TYPE}")
  fi
  if [[ "${TARGET_MASTER:-0}" == 1 ]]; then
    _tx_flags_out+=("--target-master")
  fi
}

# Best-effort listing of pregenerated TX zips so callers can pick
# --execution-tx-count / --deployment-tx-count. Names look like
# transactions-<network>-<N>val-<cv>-<height>-<release>-<exec>-<deploy>.zip
list_pregenerated_transaction_files() {
  local vars_file="$PARENT_DIR/playbooks/${VARS}.yml"
  local bucket="provable-pregenerated-transactions"
  local prefix
  prefix=$(read_yml_field pregeneration_bucket_path "$vars_file" 2>/dev/null || true)
  prefix="${prefix:-pregenerated_transactions}"
  local uri="gs://${bucket}/${prefix}/"
  echo "Existing files in ${uri}"
  if ! gcloud storage ls "$uri" 2>/dev/null; then
    echo "(could not list ${uri})"
    echo "Fix gcloud auth: ${MONOREPO_ROOT}/scripts/ensure_gcloud_auth.sh"
    "${MONOREPO_ROOT}/scripts/ensure_gcloud_auth.sh" 2>/dev/null || true
  fi
}

require_load_saved_transactions_flags() {
  if [[ -z "${PREGENERATION_EXECUTION_TX_COUNT:-}" \
     || -z "${PREGENERATION_DEPLOYMENT_TX_COUNT:-}" \
     || -z "${LOAD_SAVED_TRANSACTIONS_TYPE:-}" ]]; then
    list_pregenerated_transaction_files >&2 || true
  fi
  [[ -n "${PREGENERATION_EXECUTION_TX_COUNT:-}" ]] \
    || die "--execution-tx-count=N is required for load_saved_transactions"
  [[ -n "${PREGENERATION_DEPLOYMENT_TX_COUNT:-}" ]] \
    || die "--deployment-tx-count=N is required for load_saved_transactions"
  [[ -n "${LOAD_SAVED_TRANSACTIONS_TYPE:-}" ]] \
    || die "--tx-type=executions|deployments|all is required for load_saved_transactions"
  isuint "$PREGENERATION_EXECUTION_TX_COUNT" \
    || die "--execution-tx-count must be a non-negative integer"
  isuint "$PREGENERATION_DEPLOYMENT_TX_COUNT" \
    || die "--deployment-tx-count must be a non-negative integer"
  case "$LOAD_SAVED_TRANSACTIONS_TYPE" in
    executions|deployments|all) ;;
    *) die "--tx-type must be executions, deployments, or all" ;;
  esac
}

require_pregenerate_transactions_flags() {
  [[ -n "${PREGENERATION_EXECUTION_TX_COUNT:-}" ]] \
    || die "--execution-tx-count=N is required for pregenerate_transactions"
  [[ -n "${PREGENERATION_DEPLOYMENT_TX_COUNT:-}" ]] \
    || die "--deployment-tx-count=N is required for pregenerate_transactions"
  [[ -n "${PREGENERATE_TRANSACTIONS_NUM_VALIDATORS:-}" ]] \
    || die "--num-validators=N is required for pregenerate_transactions"
  isuint "$PREGENERATION_EXECUTION_TX_COUNT" \
    || die "--execution-tx-count must be a non-negative integer"
  isuint "$PREGENERATION_DEPLOYMENT_TX_COUNT" \
    || die "--deployment-tx-count must be a non-negative integer"
  isuint "$PREGENERATE_TRANSACTIONS_NUM_VALIDATORS" \
    || die "--num-validators must be a positive integer"
  [[ "$PREGENERATE_TRANSACTIONS_NUM_VALIDATORS" -gt 0 ]] \
    || die "--num-validators must be a positive integer"
}

ensure_devnet_key() {
  bash "${MONOREPO_ROOT}/scripts/ensure_devnet_key.sh"
}

# macOS spoken notification; silent no-op elsewhere. Returns 0 unconditionally
# so it is safe as the LAST statement of a function/script under `set -e`
# (a bare `[ ... ] && say` returns 1 on non-Darwin and would abort the script).
say_done() { if [ "$(uname)" = "Darwin" ]; then say "$*" || true; fi; return 0; }

# Fail fast with a clear message if a phase's precondition is missing, instead
# of failing deep inside terraform/ansible. Call at the top of an entrypoint.
require_provisioned() {
  if [[ ! -f "$PARENT_DIR/lb_url.txt" ]]; then
    ensure_lb_url_file \
      || die "lb_url.txt not found and LB IP could not be read from terraform state — run provision.sh first."
  fi
}

# Best-effort: recreate lb_url.txt from the local terraform state. Lets a
# host that did not run provision (e.g. setup on the manager, provision on a
# laptop) still resolve the load balancer IP.
ensure_lb_url_file() {
  [[ -f "$PARENT_DIR/lb_url.txt" ]] && return 0
  local url
  url=$(cd "$PARENT_DIR/terraform" && tf_init >/dev/null 2>&1 \
    && TF_CLI_ARGS="-no-color" terraform output -raw snarkos_lb_ip 2>/dev/null) || true
  if [[ -n "$url" && "$url" != *"No outputs found"* ]]; then
    printf '%s\n' "$url" > "$PARENT_DIR/lb_url.txt"
    return 0
  fi
  return 1
}

# Initialise terraform (local backend configured in terraform/provider.tf).
tf_init() {
  terraform init -input=false
}

# Map --mode to the terraform var-file used at provision time.
tfvars_for_mode() {
  case "${1:-}" in
    light|l)       echo "light.tfvars" ;;
    heavy|h)       echo "heavy.tfvars" ;;
    prerelease|pr) echo "prerelease.tfvars" ;;
    *)             return 1 ;;
  esac
}

# Last uncommented `key = value` in the given tfvars files wins (later files
# override), then TF_VAR_$key. Matches terraform's auto.tfvars + -var-file
# merge well enough for a static preflight — not a full HCL parser.
_tfvars_file_get() {
  local key="$1" file="$2"
  [[ -f "$file" ]] || return 0
  awk -v key="$key" '
    /^[[:space:]]*#/ || NF == 0 { next }
    $1 == key && $2 == "=" {
      val = $0
      sub(/^[^=]*=[[:space:]]*/, "", val)
      sub(/[[:space:]]+#.*$/, "", val)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", val)
      gsub(/^["'\'']|["'\'']$/, "", val)
      last = val
    }
    END { if (last != "") print last }
  ' "$file"
}

_tfvars_get() {
  local key="$1" default="$2"; shift 2
  local file got val="$default" env_name="TF_VAR_${key}"
  for file in "$@"; do
    got="$(_tfvars_file_get "$key" "$file")"
    [[ -n "$got" ]] && val="$got"
  done
  if [[ -n "${!env_name:-}" ]]; then
    val="${!env_name}"
  fi
  printf '%s' "$val"
}

# GCE named types put vCPU last (`c3d-standard-60` → 60). Returns 0 if the
# name does not end in a number (custom / GPU shapes we do not use).
machine_type_vcpu() {
  local tail="${1##*-}"
  if [[ "$tail" =~ ^[0-9]+$ ]]; then
    printf '%s' "$tail"
  else
    printf '0'
  fi
}

_tf_bool_true() { [[ "${1:-}" == "true" || "${1:-}" == "1" ]]; }

# Static C3D CPUS_PER_VM_FAMILY preflight. us-central1 is capped at 1500;
# terraform apply otherwise dies mid-create after spinning up a partial fleet.
# Counts planned C3D vCPU from default.auto.tfvars + the mode profile (and
# TF_VAR_*), not live quota, so it is approximate. Override the cap with
# C3D_FAMILY_VCPU_CAP.
assert_c3d_family_vcpu_cap() {
  local profile="$1"
  local cap="${C3D_FAMILY_VCPU_CAP:-1500}"
  local auto="$PARENT_DIR/terraform/default.auto.tfvars"
  local -a files=("$auto")
  [[ -n "$profile" && -f "$profile" ]] && files+=("$profile")

  # Defaults match terraform/variables.tf so a key omitted from both files
  # still counts (e.g. light.tfvars leaves validator_instance_type commented).
  local v_count c_count p_count cannon_count
  local v_type c_type p_type tx_type cannon_type builder_type master_type
  local add_cannons add_builder prom_enabled add_master
  v_count="$(_tfvars_get validator_instance_count 5 "${files[@]}")"
  c_count="$(_tfvars_get client_instance_count 0 "${files[@]}")"
  p_count="$(_tfvars_get prover_instance_count 0 "${files[@]}")"
  v_type="$(_tfvars_get validator_instance_type c3d-standard-30 "${files[@]}")"
  c_type="$(_tfvars_get client_instance_type c3d-standard-8 "${files[@]}")"
  p_type="$(_tfvars_get prover_instance_type c3d-standard-8 "${files[@]}")"
  tx_type="$(_tfvars_get tx_runner_instance_type c3d-standard-30 "${files[@]}")"
  cannon_count="$(_tfvars_get tx_cannon_instance_count 4 "${files[@]}")"
  cannon_type="$(_tfvars_get tx_cannon_instance_type c3d-standard-30 "${files[@]}")"
  builder_type="$(_tfvars_get builder_instance_type c3d-standard-60 "${files[@]}")"
  add_cannons="$(_tfvars_get add_tx_cannons false "${files[@]}")"
  add_builder="$(_tfvars_get add_builder false "${files[@]}")"
  prom_enabled="$(_tfvars_get prometheus_enabled false "${files[@]}")"
  add_master="$(_tfvars_get add_master false "${files[@]}")"
  master_type="$(_tfvars_get master_instance_type c3d-standard-60 "${files[@]}")"
  if [[ "${ADD_MASTER:-0}" == 1 ]]; then add_master=true; fi

  local total=0 vcpu n
  local -a breakdown=()
  _c3d_add() {
    local role="$1" count="$2" type="$3"
    [[ "$count" =~ ^[0-9]+$ ]] || count=0
    (( count > 0 )) || return 0
    [[ "$type" == c3d-* ]] || return 0
    vcpu="$(machine_type_vcpu "$type")"
    if (( vcpu == 0 )); then
      die "cannot parse vCPU from C3D machine type '$type' (role $role)"
    fi
    n=$((count * vcpu))
    breakdown+=("${role}: ${count} × \`${type}\` = ${n}")
    total=$((total + n))
  }

  if _tf_bool_true "$add_master" && (( v_count > 0 )); then
    _c3d_add master 1 "$master_type"
    _c3d_add validators $((v_count - 1)) "$v_type"
  else
    _c3d_add validators "$v_count" "$v_type"
  fi
  _c3d_add clients "$c_count" "$c_type"
  _c3d_add provers "$p_count" "$p_type"
  _c3d_add tx_runner 1 "$tx_type"
  if _tf_bool_true "$prom_enabled"; then _c3d_add prometheus 1 "$c_type"; fi
  if _tf_bool_true "$add_builder"; then _c3d_add builder 1 "$builder_type"; fi
  if _tf_bool_true "$add_cannons"; then _c3d_add tx_cannons "$cannon_count" "$cannon_type"; fi

  echo "C3D vCPU preflight: ${total}/${cap} ($(basename "$profile"))"
  local line
  for line in "${breakdown[@]}"; do
    echo "  - $line"
  done

  (( total > cap )) || return 0

  local msg
  msg="❌ *Refusing provision:* planned C3D vCPU \`${total}\` exceeds the \`${cap}\` \`CPUS_PER_VM_FAMILY\` cap in us-central1."
  msg+=$'\n'
  for line in "${breakdown[@]}"; do
    msg+=$'\n'"• ${line}"
  done
  msg+=$'\n'$'\n'"Total C3D: \`${total}\` > \`${cap}\`. Lower count/size, or switch family (n2d/c2d). Remaining quota may be lower because of other C3D VMs (e.g. the STM)."
  notify_job_alert "$msg" danger
  die "planned C3D vCPU ${total} exceeds cap ${cap}"
}

# Args that must match the original provision. Without them, a targeted
# builder apply uses default.auto.tfvars (devnet_name=snarkos-p2p-tests)
# and tags the VM for a different firewall than the fleet — STM SSH to the
# private IP then times out (GCP default-deny ingress).
_ephemeral_builder_tf_args() {
  local -n _out=$1
  local tfvars
  _out=()
  if tfvars=$(tfvars_for_mode "${MODE:-}"); then
    _out+=(-var-file="$tfvars")
  fi
  if [[ -n "${DEVNET_NAME:-}" ]]; then
    _out+=(-var="devnet_name=${DEVNET_NAME}")
  fi
  _out+=(-var="owner=$OWNER" -var="add_builder=true")
}

# Ephemeral snarkOS builder. Also apply the node SA's GCS bindings: a
# -target on the instance only pulls in the SA itself, not IAM members that
# depend on it, so uploads would 403 without these.
apply_ephemeral_builder() {
  local tf_args=()
  _ephemeral_builder_tf_args tf_args
  echo "Applying ephemeral builder (devnet_name=${DEVNET_NAME:-} mode=${MODE:-})"
  ( cd "$PARENT_DIR/terraform" || exit 1
    tf_init
    terraform apply \
      -target=google_compute_instance.snarkos_builder \
      -target=google_project_iam_member.snarkos_gcs_object_viewer \
      -target=google_project_iam_member.snarkos_gcs_object_creator \
      "${tf_args[@]}" \
      -auto-approve )
}

destroy_ephemeral_builder() {
  local tf_args=()
  _ephemeral_builder_tf_args tf_args
  ( cd "$PARENT_DIR/terraform" || exit 1
    tf_init
    terraform destroy \
      -target=google_compute_instance.snarkos_builder \
      "${tf_args[@]}" \
      -auto-approve )
}

# --- Discovery ---------------------------------------------------------------
discover_tests() {
  mapfile -t TESTS < <(
    shopt -s nullglob
    for d in "$PARENT_DIR/tests"/*/; do basename "$d"; done | sort
  )
  export TESTS
}
discover_utilities() {
  mapfile -t UTILITIES < <(
    shopt -s nullglob
    for d in "$PARENT_DIR/utils"/*/; do basename "$d"; done | sort
  )
  export UTILITIES
}

resolve_tests() {
  case "$1" in
    ""|none|-)  return 0 ;;
    all)        printf '%s\n' "${TESTS[@]}" | grep -v '^_' ;;
    prerelease) printf '%s\n' "${TESTS[@]}" | grep '^prerelease_' ;;
    *)          tr ',' '\n' <<<"$1" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' ;;
  esac
}

# --- Centralised ansible invocation -----------------------------------------
# All playbooks share the same big --extra-vars block; centralise it so the
# network/LB/devnet wiring lives in exactly one place.
#   common_ansible <playbook.yml> [extra ansible-playbook args...]
common_ansible() {
  local playbook="$1"; shift
  local extra=()
  [[ -n "${PREGENERATION_EXECUTION_TX_COUNT:-}" ]] \
    && extra+=(--extra-vars="pregeneration_execution_tx_count=${PREGENERATION_EXECUTION_TX_COUNT}")
  [[ -n "${PREGENERATION_DEPLOYMENT_TX_COUNT:-}" ]] \
    && extra+=(--extra-vars="pregeneration_deployment_tx_count=${PREGENERATION_DEPLOYMENT_TX_COUNT}")
  [[ -n "${PREGENERATE_TRANSACTIONS_NUM_VALIDATORS:-}" ]] \
    && extra+=(--extra-vars="pregenerate_transactions_num_validators=${PREGENERATE_TRANSACTIONS_NUM_VALIDATORS}")
  [[ -n "${LOAD_SAVED_TRANSACTIONS_TYPE:-}" ]] \
    && extra+=(--extra-vars="load_saved_transactions_type=${LOAD_SAVED_TRANSACTIONS_TYPE}")
  if [[ "${TARGET_MASTER:-0}" == 1 ]]; then
    extra+=(--extra-vars="target_master=true")
  fi
  ansible-playbook -i "$INVENTORY_DIR" "$playbook" \
    --limit "${LIMIT:-all}" \
    --extra-vars="devnet_name=${DEVNET_NAME:-snarkos-p2p-tests}" \
    --extra-vars="snarkos_network=${NETWORK:-testnet}" \
    --extra-vars="snarkos_network_int=${NETWORK_INT:-1}" \
    --extra-vars="test_network_url=${LB_URL:-}" \
    --extra-vars="mode=${MODE:-}" \
    --extra-vars="tests=${TESTS:-}" \
    --extra-vars="base_workspace_folder=${PARENT_DIR}/playbooks" \
    --extra-vars="@${VARS}.yml" \
    ${extra[@]+"${extra[@]}"} \
    "$@"
}

# Read a simple "key: value" field from a YAML file (best-effort).
# Keeps spaces inside quotes (e.g. RUSTFLAGS=--cfg tokio_unstable) and
# drops an unquoted inline comment after the value.
read_yml_field() {
  local key="$1" file="$2"
  [[ -f "$file" ]] || return 1
  awk -v key="$key" '
    $1 == key ":" {
      val = substr($0, index($0, ":") + 1)
      sub(/^[[:space:]]+/, "", val)
      if (val ~ /^"/) {
        if (match(val, /^"[^"]*"/)) val = substr(val, RSTART, RLENGTH)
      } else if (val ~ /^'\''/) {
        if (match(val, /^'\''[^'\'']*'\''/)) val = substr(val, RSTART, RLENGTH)
      } else {
        sub(/[[:space:]]+#.*$/, "", val)
        sub(/[[:space:]]+$/, "", val)
      }
      gsub(/^["'\'']|["'\'']$/, "", val)
      print val
      exit
    }
  ' "$file"
}

# Read a string local from terraform/variables.tf (best-effort).
read_tf_local_string() {
  local key="$1" file="$PARENT_DIR/terraform/variables.tf"
  [[ -f "$file" ]] || return 1
  grep -E "^[[:space:]]*${key}[[:space:]]*=" "$file" 2>/dev/null | head -1 \
    | sed -E 's/.*=[[:space:]]*"([^"]*)".*/\1/'
}

# --- Network vars (re-derived from terraform state; safe to call repeatedly) -
set_network_vars() {
  # lb_url.txt is written at the end of a successful provision; trust it when present.
  if [[ -f "$PARENT_DIR/lb_url.txt" ]]; then
    LB_URL=$(tr -d '[:space:]' < "$PARENT_DIR/lb_url.txt"); export LB_URL
  fi

  NETWORK=$(cd "$PARENT_DIR/terraform" && TF_CLI_ARGS="-no-color" terraform output -raw snarkos_network 2>/dev/null) || true
  if [[ -z "${NETWORK}" || "$NETWORK" == *"No outputs found"* ]]; then
    NETWORK=$(read_tf_local_string snarkos_network || echo testnet)
  fi
  export NETWORK

  DEVNET_NAME=$(cd "$PARENT_DIR/terraform" && TF_CLI_ARGS="-no-color" terraform output -raw devnet_name 2>/dev/null) || true
  if [[ -z "${DEVNET_NAME}" || "$DEVNET_NAME" == *"No outputs found"* ]]; then
    DEVNET_NAME=$(read_yml_field devnet_name "$PARENT_DIR/playbooks/${VARS}.yml") \
      || DEVNET_NAME="${TF_VAR_devnet_name:-snarkos-p2p-tests}"
  fi
  export DEVNET_NAME
  # Keep TF_VAR in sync so later terraform applies (ephemeral builder)
  # cannot silently fall back to default.auto.tfvars' snarkos-p2p-tests.
  export TF_VAR_devnet_name="$DEVNET_NAME"

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

  echo "Uploading test logs to GCS..."
  if [ -d "$PARENT_DIR/log_files" ]; then
    local log_file destination
    for log_file in "$PARENT_DIR/log_files/"*; do
      [ -f "$log_file" ] || continue
      destination="gs://$RESULTS_AND_LOGS_BUCKET/$BASE_BUCKET_PATH/$test_ran/$(basename "$log_file")"
      echo "Copying $log_file to $destination ..."
      gcloud storage cp "$log_file" "$destination"
    done
  fi
  if [ -f "$PARENT_DIR/observability_runner.log" ]; then
    gcloud storage cp "$PARENT_DIR/observability_runner.log" \
      "gs://$RESULTS_AND_LOGS_BUCKET/$BASE_BUCKET_PATH/$test_ran/observability_runner.log"
    rm -f "$PARENT_DIR/observability_runner.log"
  fi
  echo "Logs: https://console.cloud.google.com/storage/browser/$RESULTS_AND_LOGS_BUCKET/$BASE_BUCKET_PATH/$test_ran/"
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
# Usage: init_and_apply_terraform [extra terraform args...]
# Example: init_and_apply_terraform -var-file=light.tfvars
init_and_apply_terraform() {
  rm -f "$PARENT_DIR/lb_url.txt"
  ( cd "$PARENT_DIR/terraform" || exit 1
    tf_init
    terraform apply -auto-approve -var="owner=$OWNER" "$@"
    terraform output -raw snarkos_lb_ip > "$PARENT_DIR/lb_url.txt" )
  LB_URL=$(cat "$PARENT_DIR/lb_url.txt"); export LB_URL
  set_network_vars || return 1

  echo "Terraform finished; waiting for GCP labels to propagate..."
  local MAX_RETRIES=20 SLEEP_INTERVAL=5 RETRY_COUNT=0 HOST_COUNT
  while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    HOST_COUNT=$(ansible -i "$INVENTORY_DIR" "$TARGET_PATTERN" --list-hosts 2>/dev/null \
      | grep -o 'hosts ([0-9]*)' | grep -o '[0-9]*')
    if [[ -n "$HOST_COUNT" && "$HOST_COUNT" -gt 0 ]]; then
      echo "GCP labels synced. Ansible sees $HOST_COUNT hosts."; break
    fi
    echo "Waiting for labels... ($((RETRY_COUNT+1))/$MAX_RETRIES)"
    sleep $SLEEP_INTERVAL; RETRY_COUNT=$((RETRY_COUNT+1))
  done
  [ $RETRY_COUNT -eq $MAX_RETRIES ] && die "Timeout waiting for GCP label propagation."

  ( cd "$PARENT_DIR/playbooks" && common_ansible ips.yml )
  say_done "Finished running Terraform"
}
