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
pueue_dispatch_self "provision:$MODE" -- "$0" "${ORIG_ARGS[@]}"

install_exit_trap

ensure_devnet_key

case "$MODE" in
  light|l)        cp "$PARENT_DIR/terraform/variables.tf.light"      "$PARENT_DIR/terraform/variables.tf" ;;
  heavy|h)        cp "$PARENT_DIR/terraform/variables.tf.heavy"      "$PARENT_DIR/terraform/variables.tf" ;;
  prerelease|pr)  cp "$PARENT_DIR/terraform/variables.tf.prerelease" "$PARENT_DIR/terraform/variables.tf" ;;
  *) die "Invalid --mode (light|heavy|prerelease), got: '$MODE'" ;;
esac

notify_job_begin "provision:$MODE"
init_and_apply_terraform
echo "Provisioning complete (mode=$MODE, run=$RUN_ID)."
