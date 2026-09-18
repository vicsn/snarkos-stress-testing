#!/usr/bin/env bash
# full_run.sh — compose bin entrypoints into a whole run.
#
#   full_run.sh --mode=light --vars=vars --tests=prerelease
#   full_run.sh --mode=heavy --tests=t1,t2
#   full_run.sh --mode=light --vars=vars --tests=none
#   full_run.sh --mode=light --tests=load_saved_transactions \
#     --execution-tx-count=40 --deployment-tx-count=20 --tx-type=executions \
#     --target-master
#   full_run.sh --mode=light --tests=none --utility=pregenerate_transactions \
#     --execution-tx-count=40 --deployment-tx-count=20 --num-validators=5
#
# Like every scripts/bin/* entrypoint, this delegates itself to the
# stress-testing-manager unless it is already running there (see lib/stm.sh).
# On the manager the pipeline enqueues via pueue (see lib/pueue.sh); set
# PUEUE_DISABLED=1 to run it sequentially in that shell instead.
set -euo pipefail
ORIG_ARGS=("$@")
# shellcheck source=/dev/null
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

usage() {
  cat <<'EOF'
full_run.sh — build, provision, setup, run tests, then destroy.

Usage:
  full_run.sh --mode=light|heavy|prerelease [options]

Options:
  -h, --help                 Show this help and exit (does not delegate to STM)
  --mode=MODE                Provision profile: light, heavy, or prerelease
                             (default: light)
  --vars=NAME                Ansible vars file basename without .yml
                             (default: vars)
  --tests=SPEC               Tests to run: <name>, a,b,c, all, prerelease, or
                             none (default: prerelease)
  --utility=NAME             Run a utility after tests (e.g. pregenerate_transactions)
  --execution-tx-count=N     Required for pregenerate_transactions and
                             load_saved_transactions
  --deployment-tx-count=N    Required for pregenerate_transactions and
                             load_saved_transactions
  --num-validators=N         Required for pregenerate_transactions (5 or 40)
  --tx-type=TYPE             Required for load_saved_transactions:
                             executions, deployments, or all
  --target-master            Size validator 0 as master_instance_type
                             (c3d-standard-60) and send every load_saved
                             transaction at that validator
  --delay-between-tests=N    Seconds to wait between tests (default: 0).
                             Serializes tests in pueue; omitted if only one test.

Environment:
  PUEUE_DISABLED=1           Run the pipeline sequentially instead of via pueue
  STM_LOCAL=1                Skip SSH delegation; run on this host
  RUN_ID                     Shared GCS/Slack id for every job in the run
  OWNER, DEVNET_NAME         Naming prefix for GCP resources

Examples:
  full_run.sh --mode=light --vars=vars --tests=prerelease
  full_run.sh --mode=heavy --tests=t1,t2
  full_run.sh --mode=light --tests=none
  full_run.sh --mode=light --tests=load_saved_transactions \
    --execution-tx-count=40 --deployment-tx-count=20 --tx-type=executions
  full_run.sh --mode=light --tests=load_saved_transactions \
    --execution-tx-count=40 --deployment-tx-count=20 --tx-type=executions \
    --target-master
  full_run.sh --mode=light --tests=none --utility=pregenerate_transactions \
    --execution-tx-count=40 --deployment-tx-count=20 --num-validators=5
EOF
}

MODE="light"; TESTS_ARG="prerelease"; UTIL=""
DELAY_BETWEEN_TESTS=0
for arg in "$@"; do
  case "$arg" in
    -h|--help)    usage; exit 0 ;;
    --mode=*)     MODE="${arg#*=}" ;;
    --vars=*)     VARS="${arg#*=}"; export VARS ;;
    --tests=*)    TESTS_ARG="${arg#*=}" ;;
    --utility=*)  UTIL="${arg#*=}" ;;
    --delay-between-tests=*) DELAY_BETWEEN_TESTS="${arg#*=}" ;;
    --queue)      echo "WARNING: --queue is deprecated (pueue is the default); use PUEUE_DISABLED=1 to run inline." >&2 ;;
    *) parse_tx_run_flag "$arg" || die "Unknown argument: $arg" ;;
  esac
done
isuint "$DELAY_BETWEEN_TESTS" \
  || die "--delay-between-tests must be a non-negative integer"
export DELAY_BETWEEN_TESTS
if [[ "${TARGET_MASTER:-0}" == 1 ]]; then
  ADD_MASTER=1
  export ADD_MASTER
fi

discover_tests
mapfile -t RUN_TESTS < <(resolve_tests "$TESTS_ARG")

for t in "${RUN_TESTS[@]}"; do
  if [[ "$t" == "load_saved_transactions" ]]; then
    require_load_saved_transactions_flags
  fi
done
if [[ "$UTIL" == "pregenerate_transactions" ]]; then
  require_pregenerate_transactions_flags
fi
stm_dispatch_self ${ORIG_ARGS[@]+"${ORIG_ARGS[@]}"}

echo "RUN_ID=$RUN_ID  mode=$MODE  vars=$VARS  tests=${RUN_TESTS[*]:-none}  owner=$OWNER"
notify_run_banner "🚀 Run \`$RUN_ID\` — mode=$MODE vars=$VARS tests=${RUN_TESTS[*]:-none} owner=$OWNER"

run_pipeline "$MODE" "$VARS" "$UTIL" "$TESTS_ARG" "${RUN_TESTS[@]}"
