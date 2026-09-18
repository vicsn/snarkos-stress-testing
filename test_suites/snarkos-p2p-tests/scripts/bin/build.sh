#!/usr/bin/env bash
# bin/build.sh [--vars=NAME] [--mode=light|heavy|prerelease]
# Builds the snarkOS binary on an ephemeral GCE builder if it is missing from GCS.
# Safe to run before provision: a cache hit is a no-op, a cache miss only
# targets the builder instance (and its terraform dependencies).
set -euo pipefail
ORIG_ARGS=("$@")
# shellcheck source=/dev/null
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"

for arg in "$@"; do
  case "$arg" in
    --vars=*)  VARS="${arg#*=}"; export VARS ;;
    --mode=*)  MODE="${arg#*=}"; export MODE ;;
    *) die "Unknown argument: $arg" ;;
  esac
done
stm_dispatch_self ${ORIG_ARGS[@]+"${ORIG_ARGS[@]}"}
pueue_dispatch_self "build" -- "$0" ${ORIG_ARGS[@]+"${ORIG_ARGS[@]}"}

# Slack-only trap: there is no fleet yet, so do not try to collect node logs.
notify_job_begin "build"
trap 'notify_job_end $?' EXIT

set_network_vars || exit 1

VARS_FILE="$PARENT_DIR/playbooks/${VARS}.yml"
# Mirror playbooks/vars.yml `release_name`: git hash [_features] [_envs with spaces as _].
# Use read_yml_field so values with spaces (RUSTFLAGS=--cfg tokio_unstable) are kept intact.
SNARKOS_GIT_HASH=$(read_yml_field snarkos_git_hash "$VARS_FILE") \
  || die "snarkos_git_hash missing in $VARS_FILE"
FEATURES=$(read_yml_field features "$VARS_FILE" || true)
ENVS=$(read_yml_field envs "$VARS_FILE" || true)
GCS_BUCKET=$(read_yml_field gcs_bucket "$VARS_FILE" || true)
GCS_BUCKET="${GCS_BUCKET:-$RELEASE_BUCKET}"
RELEASE_NAME="$SNARKOS_GIT_HASH"
[[ -n "$FEATURES" ]] && RELEASE_NAME="${RELEASE_NAME}_${FEATURES}"
[[ -n "$ENVS" ]] && RELEASE_NAME="${RELEASE_NAME}_${ENVS// /_}"

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

say_done "Finished building snarkOS"
echo "Build complete (run=$RUN_ID)."
