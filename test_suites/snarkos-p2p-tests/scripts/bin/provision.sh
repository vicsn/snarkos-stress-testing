#!/usr/bin/env bash
# bin/provision.sh --mode=light|heavy|prerelease [--vars=NAME] [--add-master]
# Provisions infrastructure with terraform. One job, no prompts.
# --add-master sizes validator 0 as master_instance_type (default c3d-standard-60).
set -euo pipefail
ORIG_ARGS=("$@")
# shellcheck source=/dev/null
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"

MODE=""
ADD_MASTER="${ADD_MASTER:-0}"
for arg in "$@"; do
  case "$arg" in
    --mode=*) MODE="${arg#*=}" ;;
    --vars=*) VARS="${arg#*=}"; export VARS ;;
    --add-master) ADD_MASTER=1 ;;
    --add-master=true|--add-master=1) ADD_MASTER=1 ;;
    --add-master=false|--add-master=0) ADD_MASTER=0 ;;
    *) die "Unknown argument: $arg" ;;
  esac
done
[[ -n "$MODE" ]] || die "--mode=light|heavy|prerelease is required."
export ADD_MASTER
stm_dispatch_self ${ORIG_ARGS[@]+"${ORIG_ARGS[@]}"}
pueue_dispatch_self "provision:$MODE" -- "$0" "${ORIG_ARGS[@]}"

ensure_devnet_key

TFVARS=$(tfvars_for_mode "$MODE") \
  || die "Invalid --mode (light|heavy|prerelease), got: '$MODE'"

[[ -f "$PARENT_DIR/terraform/$TFVARS" ]] || die "Profile not found: terraform/$TFVARS"

# Slack-only trap around the static quota check so a refusal does not try to
# collect node logs (there is no fleet yet). install_exit_trap replaces this
# before terraform apply, so a real provision failure still gathers logs.
notify_job_begin "provision:$MODE"
trap 'notify_job_end $?' EXIT
assert_c3d_family_vcpu_cap "$PARENT_DIR/terraform/$TFVARS"

install_exit_trap
tf_extra=()
if [[ "$ADD_MASTER" == 1 ]]; then
  echo "add_master: validator 0 will use master_instance_type (default c3d-standard-60)"
  tf_extra+=(-var=add_master=true)
fi
init_and_apply_terraform -var-file="$TFVARS" ${tf_extra[@]+"${tf_extra[@]}"}
echo "Provisioning complete (mode=$MODE, run=$RUN_ID)."
