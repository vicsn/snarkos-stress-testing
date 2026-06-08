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
  TF_VAR_PUBLIC_KEY_PATH={path} tf_stack.sh provision [--staging|--workspace NAME] [--talisker-branch BR] [--stress-testing-branch BR] [--auto-approve] [-- ...extra terraform args]
  TF_VAR_PUBLIC_KEY_PATH={path} tf_stack.sh setup [--staging|--workspace NAME] [--talisker-branch BR] [--stress-testing-branch BR] [-- ...extra terraform args]
  tf_stack.sh destroy [--staging|--workspace NAME] [--auto-approve] [--force] [-- ...extra terraform args]
  tf_stack.sh plan [--staging|--workspace NAME] [-- ...extra terraform args]
  tf_stack.sh output [--staging|--workspace NAME] [-- ...extra terraform args]
  tf_stack.sh ip [--staging|--workspace NAME] [-- ...extra terraform args]

Notes:
  - provision runs terraform apply only. setup runs Ansible against the instance IP from terraform output (no terraform apply).
  - default workspace is production, --staging maps to workspace "staging".
  - set TF_VAR_github_token and other TF_VAR_* the same way as for terraform (e.g. when running provision); see env-default / env-staging.
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

case "$ACTION" in
  provision|destroy|plan|output|ip|setup) ;;
  *) usage; die "Unknown action: $ACTION" ;;
esac

if [[ "$WORKSPACE" == "default" && "$TALISKER_BRANCH" != "master" ]]; then
  die "--talisker-branch is only allowed with --staging/--workspace (non-default)"
fi

if [[ "$WORKSPACE" == "default" && "$STRESS_TESTING_BRANCH" != "main" ]]; then
  die "--stress-testing-branch is only allowed with --staging/--workspace (non-default)"
fi

cd "$TF_DIR"

# Run Ansible against the manager instance (reads IP from terraform output). Does not run terraform apply.
run_ansible_playbook() {
  : "${TF_VAR_github_token:?Set TF_VAR_github_token (e.g. source your .env)}"
  local manager_ip
  manager_ip="$(terraform output -raw stress_testing_manager_public_ip)"

  echo "==> waiting for SSH on $manager_ip"
  until nc -z -v -w5 "$manager_ip" 22; do
    echo "Waiting for $manager_ip to be ready..."
    sleep 2
  done
  ssh-keyscan -H "$manager_ip" >> ~/.ssh/known_hosts

  local pre_release_prefix="${TF_VAR_PRE_RELEASE_PREFIX:-prerelease}"
  local sync_prefix="${TF_VAR_SYNC_PREFIX:-sync}"
  local load_ledger_prefix="${TF_VAR_LOAD_LEDGER_PREFIX:-load-ledger}"
  local releases_bucket="${TF_VAR_RELEASES_BUCKET:-provable-binaries-releases}"
  local results_bucket="${TF_VAR_RESULTS_BUCKET:-provable-logs-results}"
  local elastic_cloud_id="${TF_VAR_ELASTIC_CLOUD_ID:-your_elastic_cloud_id_here}"
  local elastic_api_key="${TF_VAR_ELASTIC_API_KEY:-your_elastic_api_key_here}"
  local grafana_cloud_api_key="${TF_VAR_GRAFANA_CLOUD_API_KEY:-your_grafana_cloud_api_key_here}"

  echo "==> ansible-playbook (inventory $manager_ip)"
  (
    cd "${TF_DIR}/ansible"
    ansible-playbook \
      --extra-vars "ansible_ssh_common_args='-o ForwardAgent=yes'" \
      --extra-vars "github_token=${TF_VAR_github_token}" \
      --extra-vars "stress_testing_branch=${STRESS_TESTING_BRANCH}" \
      --extra-vars "talisker_branch=${TALISKER_BRANCH}" \
      --extra-vars "pre_release_prefix=${pre_release_prefix}" \
      --extra-vars "sync_prefix=${sync_prefix}" \
      --extra-vars "load_ledger_prefix=${load_ledger_prefix}" \
      --extra-vars "slack_channel_id=${TF_VAR_SLACK_CHANNEL_ID:-}" \
      --extra-vars "slack_token=${TF_VAR_SLACK_TOKEN:-}" \
      --extra-vars "releases_bucket=${releases_bucket}" \
      --extra-vars "results_bucket=${results_bucket}" \
      --extra-vars "elastic_cloud_id=${elastic_cloud_id}" \
      --extra-vars "elastic_api_key=${elastic_api_key}" \
      --extra-vars "grafana_cloud_api_key=${grafana_cloud_api_key}" \
      -i "${manager_ip}," setup.yml
  )
}

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

case "$ACTION" in
  plan)
    echo "==> terraform plan (workspace=$WORKSPACE)"
    terraform plan "${TF_COMMON_ARGS[@]}"
    ;;
  setup)
    echo "==> setup: ansible-playbook (workspace=$WORKSPACE)"
    run_ansible_playbook
    ;;
  provision)
    echo "==> terraform apply via provision (workspace=$WORKSPACE)"
    terraform apply \
      ${TF_APPLY_ARGS[@]+"${TF_APPLY_ARGS[@]}"} \
      "${TF_COMMON_ARGS[@]}"
    ;;
  destroy)
    echo "==> terraform destroy (workspace=$WORKSPACE)"
    terraform destroy \
      ${TF_APPLY_ARGS[@]+"${TF_APPLY_ARGS[@]}"} \
      "${TF_COMMON_ARGS[@]}"
    ;;
  output)
    echo "==> terraform output (workspace=$WORKSPACE)"
    terraform output ${EXTRA_TF_ARGS[@]+"${EXTRA_TF_ARGS[@]}"}
    ;;
  ip)
    echo "==> stress_testing_manager_public_ip (workspace=$WORKSPACE)"
    terraform output -raw stress_testing_manager_public_ip
    ;;
esac
