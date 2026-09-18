#!/usr/bin/env bash
# bin/run-test.sh --test=NAME [--vars=NAME] [--no-collect]
#   load_saved_transactions also requires:
#     --execution-tx-count=N --deployment-tx-count=N --tx-type=executions|deployments|all
#     optional: --target-master (blast every TX at validator index 0)
# Runs ONE test and (by default) collects its logs. This is the fine-grained
# unit you enqueue in pueue — one job per test.
set -euo pipefail
ORIG_ARGS=("$@")
# shellcheck source=/dev/null
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"

TEST=""
COLLECT=1
for arg in "$@"; do
  case "$arg" in
    --test=*) TEST="${arg#*=}" ;;
    --vars=*) VARS="${arg#*=}"; export VARS ;;
    --no-collect) COLLECT=0 ;;
    *) parse_tx_run_flag "$arg" || die "Unknown argument: $arg" ;;
  esac
done
[[ -n "$TEST" ]] || die "--test=NAME is required."
if [[ "$TEST" == "load_saved_transactions" ]]; then
  require_load_saved_transactions_flags
fi
stm_dispatch_self ${ORIG_ARGS[@]+"${ORIG_ARGS[@]}"}
pueue_dispatch_self "run-test:$TEST" -- "$0" "${ORIG_ARGS[@]}"

install_exit_trap
require_provisioned
notify_job_begin "run-test:$TEST"

export SELECTED="$TEST"
run_test | tee -a "$PARENT_DIR/observability_runner.log"
rc=${PIPESTATUS[0]}

# Collect this test's logs under the shared RUN_ID prefix (label = test name),
# mirroring the per-test behaviour of the original loop.
if (( COLLECT )); then
  export SELECTED="$TEST"
  download_and_upload_logs
fi

(( rc == 0 )) || exit "$rc"
echo "Test complete: $TEST (run=$RUN_ID)."
