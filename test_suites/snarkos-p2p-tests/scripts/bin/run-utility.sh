#!/usr/bin/env bash
# bin/run-utility.sh --utility=NAME [--vars=NAME]
#   pregenerate_transactions also requires:
#     --execution-tx-count=N --deployment-tx-count=N --num-validators=N
set -euo pipefail
ORIG_ARGS=("$@")
# shellcheck source=/dev/null
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"

UTIL=""
for arg in "$@"; do
  case "$arg" in
    --utility=*) UTIL="${arg#*=}" ;;
    --vars=*)    VARS="${arg#*=}"; export VARS ;;
    *) parse_tx_run_flag "$arg" || die "Unknown argument: $arg" ;;
  esac
done
[[ -n "$UTIL" ]] || die "--utility=NAME is required."
if [[ "$UTIL" == "pregenerate_transactions" ]]; then
  require_pregenerate_transactions_flags
fi
stm_dispatch_self ${ORIG_ARGS[@]+"${ORIG_ARGS[@]}"}
pueue_dispatch_self "run-utility:$UTIL" -- "$0" "${ORIG_ARGS[@]}"

install_exit_trap
require_provisioned
notify_job_begin "run-utility:$UTIL"

if [ "$UTIL" == "upload_logs_to_gcs" ]; then
  mkdir -p "$PARENT_DIR/log_files"
  download_and_upload_logs
elif [[ "$UTIL" == download_* ]]; then
  if runner_manages_logs; then mkdir -p "$PARENT_DIR/log_files"; else prepare_log_files_dir; fi
  export SELECTED="$UTIL"
  run_utility | tee -a "$PARENT_DIR/observability_runner.log"
else
  export SELECTED="$UTIL"
  run_utility | tee -a "$PARENT_DIR/observability_runner.log"
fi
echo "Utility complete: $UTIL (run=$RUN_ID)."
