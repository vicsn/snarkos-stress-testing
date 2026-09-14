#!/usr/bin/env bash
# bin/collect-logs.sh [--label=NAME] [--vars=NAME]
# Standalone download + analyze + upload, under the shared RUN_ID prefix.
# --label sets the GCS sub-path (defaults to whatever SELECTED was, else generic).
set -euo pipefail
ORIG_ARGS=("$@")
# shellcheck source=/dev/null
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"

LABEL="logs"
for arg in "$@"; do
  case "$arg" in
    --label=*) LABEL="${arg#*=}"; export SELECTED="$LABEL" ;;
    --vars=*)  VARS="${arg#*=}"; export VARS ;;
    *) die "Unknown argument: $arg" ;;
  esac
done
stm_dispatch_self ${ORIG_ARGS[@]+"${ORIG_ARGS[@]}"}
pueue_dispatch_self "collect-logs:$LABEL" -- "$0" ${ORIG_ARGS[@]+"${ORIG_ARGS[@]}"}

install_exit_trap
require_provisioned
notify_job_begin "collect-logs:${SELECTED:-logs}"
download_and_upload_logs
