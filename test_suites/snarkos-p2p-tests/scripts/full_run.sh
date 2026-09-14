#!/usr/bin/env bash
# full_run.sh — compose bin entrypoints into a whole run.
#
#   full_run.sh --mode=light --vars=vars --tests=prerelease
#   full_run.sh --mode=heavy --tests=t1,t2
#   full_run.sh --mode=light --vars=vars --tests=none
#   full_run.sh --mode=light --tests=load_saved_transactions \
#     --execution-tx-count=40 --deployment-tx-count=20 --tx-type=executions
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

MODE="light"; TESTS_ARG="prerelease"; UTIL=""
for arg in "$@"; do
  case "$arg" in
    --mode=*)     MODE="${arg#*=}" ;;
    --vars=*)     VARS="${arg#*=}"; export VARS ;;
    --tests=*)    TESTS_ARG="${arg#*=}" ;;
    --utility=*)  UTIL="${arg#*=}" ;;
    --queue)      echo "WARNING: --queue is deprecated (pueue is the default); use PUEUE_DISABLED=1 to run inline." >&2 ;;
    *) parse_tx_run_flag "$arg" || die "Unknown argument: $arg" ;;
  esac
done

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
