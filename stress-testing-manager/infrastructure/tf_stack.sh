#!/usr/bin/env bash
set -euo pipefail

TF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE="default"
ACTION=""
AUTO_APPROVE=0
FORCE=0
EXTRA_TF_ARGS=()

TALISKER_BRANCH="master"
STRESS_TESTING_BRANCH="main"

usage() {
  cat <<'EOF'
Usage:
  tf_stack.sh apply [--staging|--workspace NAME] [--talisker-branch BR] [--stress-testing-branch BR] [--auto-approve] [-- ...extra terraform args]
  tf_stack.sh provision [--staging|--workspace NAME] [--talisker-branch BR] [--stress-testing-branch BR] [--auto-approve] [-- ...extra terraform args]
  tf_stack.sh destroy [--staging|--workspace NAME] [--auto-approve] [--force] [-- ...extra terraform args]
  tf_stack.sh plan [--staging|--workspace NAME] [-- ...extra terraform args]
  tf_stack.sh output [--staging|--workspace NAME] [-- ...extra terraform args]
  tf_stack.sh ip [--staging|--workspace NAME] [-- ...extra terraform args]

Notes:
  - default workspace is your current prod stack.
  - --staging maps to workspace "staging".
  - destroy on default is blocked unless --force is provided.
  - pass extra terraform args after -- (e.g. -- -var-file=staging.tfvars)
EOF
}

die() { echo "ERROR: $*" >&2; exit 1; }

if [[ $# -lt 1 ]]; then usage; exit 1; fi
ACTION="$1"; shift

while [[ $# -gt 0 ]]; do
  case "$1" in
    --staging) WORKSPACE="staging"; shift ;;
    --workspace) WORKSPACE="${2:?missing workspace name}"; shift 2 ;;
    --talisker-branch)
      TALISKER_BRANCH="${2:?missing branch name}"
      shift 2
      ;;
    --stress-testing-branch)
      STRESS_TESTING_BRANCH="${2:?missing branch name}"
      shift 2
      ;;
    --auto-approve) AUTO_APPROVE=1; shift ;;
    --force) FORCE=1; shift ;;
    --) shift; EXTRA_TF_ARGS+=("$@"); break ;;
    -h|--help) usage; exit 0 ;;
    *) EXTRA_TF_ARGS+=("$1"); shift ;;
  esac
done

if [[ "$WORKSPACE" == "default" && "$TALISKER_BRANCH" != "master" ]]; then
  die "--talisker-branch is only allowed with --staging/--workspace (non-default)"
fi

if [[ "$WORKSPACE" == "default" && "$STRESS_TESTING_BRANCH" != "main" ]]; then
  die "--stress-testing-branch is only allowed with --staging/--workspace (non-default)"
fi

case "$ACTION" in
  apply|destroy|plan|output|ip|provision) ;;
  *) usage; die "Unknown action: $ACTION" ;;
esac

cd "$TF_DIR"

echo "==> terraform init"
terraform init -upgrade

echo "==> selecting workspace: $WORKSPACE"
if terraform workspace list | sed 's/*//g' | awk '{$1=$1};1' | grep -qx "$WORKSPACE"; then
  terraform workspace select "$WORKSPACE"
else
  terraform workspace new "$WORKSPACE"
fi

if [[ "$ACTION" == "destroy" && "$WORKSPACE" == "default" && "$FORCE" -ne 1 ]]; then
  die "Refusing to destroy the DEFAULT workspace. Re-run with --force if you really mean it."
fi

APPROVE_ARGS=()
if [[ "$AUTO_APPROVE" -eq 1 ]]; then
  APPROVE_ARGS+=("-auto-approve")
fi

TF_COMMON_ARGS=(
  "-var=TALISKER_BRANCH=${TALISKER_BRANCH}"
  "-var=STRESS_TESTING_BRANCH=${STRESS_TESTING_BRANCH}"
)
if ((${#EXTRA_TF_ARGS[@]})); then
  TF_COMMON_ARGS+=("${EXTRA_TF_ARGS[@]}")
fi

TF_APPLY_ARGS=()
if ((${#APPROVE_ARGS[@]})); then
  TF_APPLY_ARGS+=("${APPROVE_ARGS[@]}")
fi

echo "==> terraform $ACTION (workspace=$WORKSPACE)"
case "$ACTION" in
  plan)
    terraform plan "${TF_COMMON_ARGS[@]}"
    ;;
  provision)
    terraform apply \
      ${TF_APPLY_ARGS[@]+"${TF_APPLY_ARGS[@]}"} \
      -target=null_resource.ansible_provisioner \
      -var="PROVISION_RUN_ID=$(date +%s)" \
      "${TF_COMMON_ARGS[@]}"
    ;;
  apply)
    terraform apply \
      ${TF_APPLY_ARGS[@]+"${TF_APPLY_ARGS[@]}"} \
      "${TF_COMMON_ARGS[@]}"
    ;;
  destroy)
    terraform destroy \
      ${TF_APPLY_ARGS[@]+"${TF_APPLY_ARGS[@]}"} \
      "${TF_COMMON_ARGS[@]}"
    ;;
  output)
    terraform output ${EXTRA_TF_ARGS[@]+"${EXTRA_TF_ARGS[@]}"}
    ;;
  ip)
    terraform show ${EXTRA_TF_ARGS[@]+"${EXTRA_TF_ARGS[@]}"} | grep public_ip
    ;;
esac
