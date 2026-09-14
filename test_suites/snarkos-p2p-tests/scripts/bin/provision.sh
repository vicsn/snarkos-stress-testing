#!/usr/bin/env bash
# bin/provision.sh --mode=light|heavy|prerelease [--vars=NAME]
# Provisions infrastructure with terraform. One job, no prompts.
set -euo pipefail
ORIG_ARGS=("$@")
# shellcheck source=/dev/null
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"

MODE=""
for arg in "$@"; do
  case "$arg" in
    --mode=*) MODE="${arg#*=}" ;;
    --vars=*) VARS="${arg#*=}"; export VARS ;;
    *) die "Unknown argument: $arg" ;;
  esac
done
[[ -n "$MODE" ]] || die "--mode=light|heavy|prerelease is required."
stm_dispatch_self ${ORIG_ARGS[@]+"${ORIG_ARGS[@]}"}
pueue_dispatch_self "provision:$MODE" -- "$0" "${ORIG_ARGS[@]}"

install_exit_trap

ensure_devnet_key

TFVARS=$(tfvars_for_mode "$MODE") \
  || die "Invalid --mode (light|heavy|prerelease), got: '$MODE'"

[[ -f "$PARENT_DIR/terraform/$TFVARS" ]] || die "Profile not found: terraform/$TFVARS"

notify_job_begin "provision:$MODE"
init_and_apply_terraform -var-file="$TFVARS"
echo "Provisioning complete (mode=$MODE, run=$RUN_ID)."
