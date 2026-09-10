#!/usr/bin/env bash
# bin/setup.sh [--vars=NAME]
# Builds the snarkOS binary if missing, then runs the setup playbook.
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
pueue_dispatch_self "setup" -- "$0" "${ORIG_ARGS[@]}"

install_exit_trap
require_provisioned
notify_job_begin "setup"
cd "$PARENT_DIR/playbooks"
set_network_vars || exit 1

VARS_FILE="$PARENT_DIR/playbooks/${VARS}.yml"
SNARKOS_GIT_HASH=$(grep -E '^snarkos_git_hash:' "$VARS_FILE" | awk '{print $2}' | tr -d "\"'")
FEATURES=$(grep -E '^features:'  "$VARS_FILE" | awk '{print $2}' | tr -d "\"'" || true)
GCS_BUCKET=$(grep -E '^gcs_bucket:' "$VARS_FILE" | awk '{print $2}' | tr -d "\"'" || true)
GCS_BUCKET="${GCS_BUCKET:-$RELEASE_BUCKET}"
RELEASE_NAME="$SNARKOS_GIT_HASH"
[[ -n "$FEATURES" ]] && RELEASE_NAME="${RELEASE_NAME}_${FEATURES}"

if gcloud storage ls "gs://$GCS_BUCKET/$RELEASE_NAME" &>/dev/null; then
  echo "snarkOS binary '$RELEASE_NAME' found in GCS, skipping build."
else
  echo "Binary '$RELEASE_NAME' missing; spinning up ephemeral builder..."
  apply_ephemeral_builder
  sleep 30
  BUILDER_IP=$(cd "$PARENT_DIR/terraform" && TF_CLI_ARGS="-no-color" terraform output -raw snarkos_builder_ip)
  [[ -n "$BUILDER_IP" ]] || die "Could not retrieve builder IP."
  echo "Builder running at $BUILDER_IP"

  BUILDER_INVENTORY="$PARENT_DIR/builder_inventory.tmp"
  printf '[builder]\n%s ansible_user=ubuntu ansible_ssh_private_key_file=/home/ubuntu/snarkos-stress-testing/devnet-key\n' "$BUILDER_IP" > "$BUILDER_INVENTORY"
  ( cd "$PARENT_DIR/playbooks"
    ansible-playbook -i "$BUILDER_INVENTORY" build_binary.yml \
      --extra-vars="devnet_name=${DEVNET_NAME}" \
      --extra-vars="snarkos_network=${NETWORK}" \
      --extra-vars="snarkos_network_int=${NETWORK_INT}" \
      --extra-vars="base_workspace_folder=${PARENT_DIR}/playbooks" \
      --extra-vars="@${VARS}.yml" )
  rm -f "$BUILDER_INVENTORY"

  echo "Destroying ephemeral builder..."
  destroy_ephemeral_builder
fi

cd "$PARENT_DIR/playbooks"
common_ansible setup.yml
say_done "Finished running setup"
echo "Setup complete (run=$RUN_ID)."
