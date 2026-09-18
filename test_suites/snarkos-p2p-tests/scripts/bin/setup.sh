#!/usr/bin/env bash
# bin/setup.sh [--vars=NAME]
# Runs the setup playbook (install snarkOS from GCS, configure systemd, keys).
# The snarkOS binary itself is produced by bin/build.sh (run before provision).
set -euo pipefail
ORIG_ARGS=("$@")
# shellcheck source=/dev/null
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"

for arg in "$@"; do
  case "$arg" in
    --vars=*)  VARS="${arg#*=}"; export VARS ;;
    --mode=*)  MODE="${arg#*=}"; export MODE ;;
    --tests=*) TESTS="${arg#*=}"; export TESTS ;;
    *) die "Unknown argument: $arg" ;;
  esac
done
stm_dispatch_self ${ORIG_ARGS[@]+"${ORIG_ARGS[@]}"}
pueue_dispatch_self "setup" -- "$0" ${ORIG_ARGS[@]+"${ORIG_ARGS[@]}"}

install_exit_trap
require_provisioned
notify_job_begin "setup"
cd "$PARENT_DIR/playbooks"
set_network_vars || exit 1

common_ansible setup.yml
say_done "Finished running setup"
echo "Setup complete (run=$RUN_ID)."
