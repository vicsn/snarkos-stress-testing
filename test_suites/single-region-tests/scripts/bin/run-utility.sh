#!/usr/bin/env bash
# bin/run-utility.sh --utility=NAME [--vars=NAME]
set -euo pipefail
# shellcheck source=/dev/null
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"
install_exit_trap

UTIL=""
for arg in "$@"; do
  case "$arg" in
    --utility=*) UTIL="${arg#*=}" ;;
    --vars=*)    VARS="${arg#*=}"; export VARS ;;
    *) die "Unknown argument: $arg" ;;
  esac
done
[[ -n "$UTIL" ]] || die "--utility=NAME is required."
require_provisioned
notify_job_begin "run-utility:$UTIL"

if [ "$UTIL" == "upload_logs_to_s3" ]; then
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
