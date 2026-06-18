#!/usr/bin/env bash
# bin/provision.sh --mode=light|heavy|prerelease [--vars=NAME]
# Provisions infrastructure with terraform. One job, no prompts.
set -euo pipefail
# shellcheck source=/dev/null
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"
install_exit_trap

MODE=""
for arg in "$@"; do
  case "$arg" in
    --mode=*) MODE="${arg#*=}" ;;
    --vars=*) VARS="${arg#*=}"; export VARS ;;
    *) die "Unknown argument: $arg" ;;
  esac
done

# Generate SSH key if absent (idempotent).
KEY_NAME="$PARENT_DIR/devnet-key"
if [ ! -f "$KEY_NAME" ]; then
  ssh-keygen -t rsa -b 4096 -f "$KEY_NAME" -N ''
  chmod 400 "$KEY_NAME"
fi

case "$MODE" in
  light|l)        cp "$PARENT_DIR/terraform/variables.tf.light"      "$PARENT_DIR/terraform/variables.tf" ;;
  heavy|h)        cp "$PARENT_DIR/terraform/variables.tf.heavy"      "$PARENT_DIR/terraform/variables.tf" ;;
  prerelease|pr)  cp "$PARENT_DIR/terraform/variables.tf.prerelease" "$PARENT_DIR/terraform/variables.tf" ;;
  *) die "Invalid --mode (light|heavy|prerelease), got: '$MODE'" ;;
esac

notify_job_begin "provision:$MODE"
init_and_apply_terraform
echo "Provisioning complete (mode=$MODE, run=$RUN_ID)."
