#!/usr/bin/env bash
# bin/collect-logs.sh [--label=NAME] [--vars=NAME]
# Standalone download + analyze + upload, under the shared RUN_ID prefix.
# --label sets the S3 sub-path (defaults to whatever SELECTED was, else generic).
set -euo pipefail
# shellcheck source=/dev/null
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"
install_exit_trap

for arg in "$@"; do
  case "$arg" in
    --label=*) export SELECTED="${arg#*=}" ;;
    --vars=*)  VARS="${arg#*=}"; export VARS ;;
    *) die "Unknown argument: $arg" ;;
  esac
done
require_provisioned
notify_job_begin "collect-logs:${SELECTED:-logs}"
download_and_upload_logs
