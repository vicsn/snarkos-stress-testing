#!/usr/bin/env bash
# full_run.sh — compose bin entrypoints into a whole run.
#
#   full_run.sh --mode=light --vars=vars --tests=prerelease
#   full_run.sh --mode=heavy --tests=t1,t2
#   full_run.sh --mode=light --vars=vars --tests=none
#
# Jobs enqueue via pueue by default (see lib/pueue.sh). Set PUEUE_DISABLED=1
# to run sequentially in this shell.
#
# STM delegation: unless we are already running ON the stress-testing manager
# (detected via GCE metadata `role=stress-testing-manager`), we resolve the
# manager's external IP from stress-testing-manager-ip.txt (written by the
# STM terraform apply) and delegate over plain `ssh ubuntu@<ip>`. The caller
# must be authorized via `external_ssh_users` in the STM tfvars (SSH pubkey
# installed in ~ubuntu/.ssh/authorized_keys + /32 firewall allow). Set
# FULL_RUN_LOCAL=1 to force a local run.
set -euo pipefail
# shellcheck source=/dev/null
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

STM_IP_FILE="${MONOREPO_ROOT}/stress-testing-manager-ip.txt"

# STM external IP. Written by terraform apply as local_file.stm_ip
# (see stress-testing-manager/infrastructure/main.tf). We do NOT shell out
# to `terraform output` here — the file is the canonical source and works
# without terraform installed on the caller.
resolve_manager_ip() {
  [[ -f "$STM_IP_FILE" ]] || return 1
  tr -d '[:space:]' < "$STM_IP_FILE"
}

# True when this host is the stress-testing manager GCE instance.
# Read the `role` metadata attribute set by main.tf; skip DNS lookups.
is_stress_testing_manager() {
  local role
  role="$(curl -sf --max-time 2 -H 'Metadata-Flavor: Google' \
    http://metadata.google.internal/computeMetadata/v1/instance/attributes/role 2>/dev/null || true)"
  [[ "$role" == "stress-testing-manager" ]]
}

delegate_full_run() {
  local stm_ip
  stm_ip="$(resolve_manager_ip)" \
    || die "Cannot resolve STM IP: $STM_IP_FILE is missing. Run 'stress-testing-manager/infrastructure/tf_stack.sh provision' first."
  [[ -n "$stm_ip" ]] \
    || die "STM IP file exists but is empty: $STM_IP_FILE"

  echo "==> Delegating full_run.sh to stress-testing-manager (ubuntu@$stm_ip)"

  # Load Slack creds via profile / Secret Manager / vars.yml (best-effort).
  load_slack_config || true
  : "${SLACK_CHANNEL_ID:=${CHANNEL_ID:-}}"

  # We always log in as `ubuntu`, so the remote suite path is fixed.
  # No $HOME roundtrip needed.
  local remote_suite="/home/ubuntu/snarkos-stress-testing/test_suites/single-region-tests"

  local -a env_args=()
  local var
  for var in RUN_ID SLACK_TOKEN SLACK_CHANNEL_ID CHANNEL_ID NOTIFY_SLACK_DISABLED \
             PUEUE_DISABLED DEVNET_NAME OWNER TF_STATE_REGION \
             RELEASE_BUCKET RESULTS_AND_LOGS_BUCKET; do
    [[ -n "${!var:-}" ]] && env_args+=("$var=${!var}")
  done

  local -a inner=(env)
  inner+=("${env_args[@]+"${env_args[@]}"}")
  inner+=("${remote_suite}/scripts/full_run.sh")
  inner+=("$@")
  local inner_quoted
  inner_quoted="$(printf '%q ' "${inner[@]}")"
  inner_quoted="${inner_quoted% }"

  # Source the manager's Slack profile before running (login shell may not
  # trigger for non-interactive SSH, so do it explicitly).
  # $HOME must expand on the remote host, not locally — hence escaped $.
  # shellcheck disable=SC2016
  local lc_cmd
  lc_cmd="if [[ -f \"\$HOME/.config/snarkos-stress-testing/slack_env.sh\" ]]; then . \"\$HOME/.config/snarkos-stress-testing/slack_env.sh\"; fi; exec ${inner_quoted}"

  ssh -o ForwardAgent=yes "ubuntu@$stm_ip" \
    "bash -lc $(printf '%q' "$lc_cmd")"
}

if [[ -z "${FULL_RUN_LOCAL:-}" ]]; then
  if is_stress_testing_manager; then
    : # already on the manager; run locally below
  else
    delegate_full_run "$@"
    exit 0
  fi
fi

MODE="light"; TESTS_ARG="prerelease"; UTIL=""
for arg in "$@"; do
  case "$arg" in
    --mode=*)     MODE="${arg#*=}" ;;
    --vars=*)     VARS="${arg#*=}"; export VARS ;;
    --tests=*)    TESTS_ARG="${arg#*=}" ;;
    --utility=*)  UTIL="${arg#*=}" ;;
    --queue)      echo "WARNING: --queue is deprecated (pueue is the default); use PUEUE_DISABLED=1 to run inline." >&2 ;;
    *) die "Unknown argument: $arg" ;;
  esac
done

discover_tests
mapfile -t RUN_TESTS < <(resolve_tests "$TESTS_ARG")

echo "RUN_ID=$RUN_ID  mode=$MODE  vars=$VARS  tests=${RUN_TESTS[*]:-none}  owner=$OWNER"
notify_run_banner "🚀 Run \`$RUN_ID\` — mode=$MODE vars=$VARS tests=${RUN_TESTS[*]:-none} owner=$OWNER"

run_pipeline "$MODE" "$VARS" "$UTIL" "$TESTS_ARG" "${RUN_TESTS[@]}"
