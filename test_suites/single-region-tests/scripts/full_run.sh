#!/usr/bin/env bash
# full_run.sh — compose bin entrypoints into a whole run.
#
#   full_run.sh --mode=light --vars=vars --tests=prerelease
#   full_run.sh --mode=heavy --tests=t1,t2
#
# Jobs enqueue via pueue by default (see lib/pueue.sh). Set PUEUE_DISABLED=1
# to run sequentially in this shell.
#
# When stress-testing-manager-ip.txt exists at the repo root (or can be created
# via tf_stack.sh ip), the run is delegated over SSH to that manager unless
# already running on the manager. Set FULL_RUN_LOCAL=1 to force a local run.
set -euo pipefail
# shellcheck source=/dev/null
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

MANAGER_IP_FILE="${MONOREPO_ROOT}/stress-testing-manager-ip.txt"
TF_STACK="${MONOREPO_ROOT}/stress-testing-manager/infrastructure/tf_stack.sh"
REMOTE_SUITE="/home/ubuntu/snarkos-stress-testing/test_suites/single-region-tests"

populate_manager_ip_file() {
  [[ -x "$TF_STACK" ]] || die "Cannot resolve manager IP: $TF_STACK not found or not executable."
  ensure_devnet_key
  local manager_ip
  manager_ip="$(resolve_manager_ip_from_tf_stack)"
  [[ -n "$manager_ip" ]] || die "tf_stack.sh ip returned no IP (is the manager provisioned?)"
  printf '%s\n' "$manager_ip" > "$MANAGER_IP_FILE"
  echo "Wrote stress-testing-manager IP to $MANAGER_IP_FILE ($manager_ip)"
}

resolve_manager_ip_from_tf_stack() {
  "$TF_STACK" ip 2>/dev/null | tail -n1 | tr -d '[:space:]'
}

# True when this host is the stress-testing manager EC2 instance.
is_stress_testing_manager() {
  local here meta
  here="$(curl -sf --max-time 5 http://checkip.amazonaws.com | tr -d '[:space:]')" || return 1
  meta="$(curl -sf --max-time 2 http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null || true)"
  [[ -n "$meta" && "$here" == "$meta" ]]
}

delegate_full_run() {
  ensure_devnet_key
  local manager_ip
  manager_ip="$(tr -d '[:space:]' < "$MANAGER_IP_FILE")"
  [[ -n "$manager_ip" ]] || die "Empty manager IP in $MANAGER_IP_FILE"

  echo "==> Delegating full_run.sh to stress-testing-manager ($manager_ip)"

  # Load Slack creds from local vars.yml when not exported (same file as tf_stack.sh setup).
  load_slack_config_from_vars_yml || true
  : "${SLACK_CHANNEL_ID:=${CHANNEL_ID:-}}"

  local -a env_args=()
  local var
  for var in RUN_ID SLACK_TOKEN SLACK_CHANNEL_ID CHANNEL_ID NOTIFY_SLACK_DISABLED \
             PUEUE_DISABLED DEVNET_NAME OWNER TF_STATE_REGION \
             RELEASE_BUCKET RESULTS_AND_LOGS_BUCKET; do
    [[ -n "${!var:-}" ]] && env_args+=("$var=${!var}")
  done

  local -a inner=(env)
  inner+=("${env_args[@]+"${env_args[@]}"}")
  inner+=("$REMOTE_SUITE/scripts/full_run.sh")
  inner+=("$@")
  local inner_quoted
  inner_quoted="$(printf '%q ' "${inner[@]}")"
  inner_quoted="${inner_quoted% }"

  # Login shell sources manager profile; explicit source covers non-interactive SSH.
  # $HOME must expand on the remote host, not locally.
  local lc_cmd
  lc_cmd="if [[ -f \"\$HOME/.config/snarkos-stress-testing/slack_env.sh\" ]]; then . \"\$HOME/.config/snarkos-stress-testing/slack_env.sh\"; fi; exec ${inner_quoted}"

  ssh -i "$DEVNET_KEY" \
    -o StrictHostKeyChecking=accept-new \
    -o ForwardAgent=yes \
    "ubuntu@${manager_ip}" \
    bash -lc "$(printf '%q' "$lc_cmd")"
}

if [[ -z "${FULL_RUN_LOCAL:-}" ]]; then
  if is_stress_testing_manager; then
    : # already on the manager; run locally below
  else
    if [[ ! -f "$MANAGER_IP_FILE" ]]; then
      populate_manager_ip_file
    fi
    manager_ip="$(tr -d '[:space:]' < "$MANAGER_IP_FILE")"
    [[ -n "$manager_ip" ]] || die "Empty manager IP in $MANAGER_IP_FILE"
    delegate_full_run "$@"
    exit 0
  fi
fi

MODE="prerelease"; TESTS_ARG="prerelease"; UTIL=""
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

echo "RUN_ID=$RUN_ID  mode=$MODE  vars=$VARS  tests=${RUN_TESTS[*]:-none}"
notify_run_banner "🚀 Run \`$RUN_ID\` — mode=$MODE vars=$VARS tests=${RUN_TESTS[*]:-none}"

run_pipeline "$MODE" "$VARS" "$UTIL" "${RUN_TESTS[@]}"
