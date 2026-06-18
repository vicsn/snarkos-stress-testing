#!/usr/bin/env bash
# bin/setup.sh [--vars=NAME]
# Builds the snarkOS binary if missing, then runs the setup playbook.
set -euo pipefail
# shellcheck source=/dev/null
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"
install_exit_trap

for arg in "$@"; do
  case "$arg" in
    --vars=*) VARS="${arg#*=}"; export VARS ;;
    *) die "Unknown argument: $arg" ;;
  esac
done

require_provisioned
notify_job_begin "setup"
cd "$PARENT_DIR/playbooks"
set_network_vars || exit 1

VARS_FILE="$PARENT_DIR/playbooks/${VARS}.yml"
SNARKOS_GIT_HASH=$(grep -E '^snarkos_git_hash:' "$VARS_FILE" | awk '{print $2}' | tr -d "\"'")
FEATURES=$(grep -E '^features:'  "$VARS_FILE" | awk '{print $2}' | tr -d "\"'" || true)
S3_BUCKET=$(grep -E '^s3_bucket:' "$VARS_FILE" | awk '{print $2}' | tr -d "\"'" || true)
S3_BUCKET="${S3_BUCKET:-$RELEASE_BUCKET}"
RELEASE_NAME="$SNARKOS_GIT_HASH"
[[ -n "$FEATURES" ]] && RELEASE_NAME="${RELEASE_NAME}_${FEATURES}"

if aws s3api head-object --bucket "$S3_BUCKET" --key "$RELEASE_NAME" --profile ephnet &>/dev/null; then
  echo "snarkOS binary '$RELEASE_NAME' found in S3, skipping build."
else
  echo "Binary '$RELEASE_NAME' missing; spinning up ephemeral builder..."
  ( cd "$PARENT_DIR/terraform"
    terraform apply \
      -target=aws_iam_policy.snarkos_s3_access \
      -target=aws_iam_role_policy_attachment.snarkos_s3_access_attach \
      -target=aws_instance.snarkos_builder \
      -var="owner=$OWNER" -var="add_builder=true" -auto-approve )
  sleep 30
  BUILDER_IP=$(cd "$PARENT_DIR/terraform" && TF_CLI_ARGS="-no-color" terraform output -raw snarkos_builder_ip)
  [[ -n "$BUILDER_IP" ]] || die "Could not retrieve builder IP."
  echo "Builder running at $BUILDER_IP"

  BUILDER_INVENTORY="$PARENT_DIR/builder_inventory.tmp"
  printf '[builder]\n%s ansible_user=ubuntu\n' "$BUILDER_IP" > "$BUILDER_INVENTORY"
  ( cd "$PARENT_DIR/playbooks"
    ansible-playbook -i "$BUILDER_INVENTORY" build_binary.yml \
      --extra-vars="devnet_name=${DEVNET_NAME}" \
      --extra-vars="snarkos_network=${NETWORK}" \
      --extra-vars="snarkos_network_int=${NETWORK_INT}" \
      --extra-vars="base_workspace_folder=${PARENT_DIR}/playbooks" \
      --extra-vars="@${VARS}.yml" )
  rm -f "$BUILDER_INVENTORY"

  echo "Destroying ephemeral builder..."
  ( cd "$PARENT_DIR/terraform"
    terraform destroy -target=aws_instance.snarkos_builder \
      -var="owner=$OWNER" -var="add_builder=true" -auto-approve )
fi

cd "$PARENT_DIR/playbooks"
common_ansible setup.yml
say_done "Finished running setup"
echo "Setup complete (run=$RUN_ID)."
