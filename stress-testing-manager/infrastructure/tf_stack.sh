#!/usr/bin/env bash
# tf_stack.sh — Stress Testing Manager orchestrator (GCP).
#
# Actions:
#   plan      terraform plan
#   provision terraform apply
#   setup     ansible-playbook setup.yml (target=full)
#   update    ansible-playbook setup.yml (target=<--update-target>)
#   destroy   terraform destroy
#   output    terraform output
#   ip        print stm_public_ip
#
# Instance / user discovery: `terraform output` + `gcloud compute ssh whoami`.
# No SSH keys on disk (OS Login), no stress-testing-manager-ip.txt file.
set -euo pipefail

TF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$TF_DIR/../.." && pwd)"
# shellcheck source=/dev/null
source "${REPO_ROOT}/scripts/lib/bash_err_trap.sh"
# Set only for terraform actions (or via --workspace/--staging). Do not call
# terraform here: sync/--help must work without it.
WORKSPACE=""
ACTION=""
AUTO_APPROVE=0
FORCE=0
EXTRA_TF_ARGS=()
TARGET_USER="ubuntu"

# default value for GCP_PROJECT
GCP_PROJECT="protocol-development-sandbox"

PUEUE_VERSION=""
# STRESS_TESTING_BRANCH is currently a dormant hook. It is passed through to
# Terraform (var.stress_testing_branch) and Ansible (extra-var), but no .tf
# resource or setup.yml task consumes it: the STM pulls its code via
# `gcloud storage cp gs://<releases_bucket>/stress-testing/latest.tar.gz`
# (see scripts/bin/upload-artifact.sh), which is branch-agnostic. Vestige
# from the AWS-era `git clone` pattern. Kept for compatibility with the
# existing --stress-testing-branch flag; either remove or wire into the
# artifact path if per-branch STMs become a real requirement.
STRESS_TESTING_BRANCH="${STRESS_TESTING_BRANCH:-main}"
UPDATE_TARGET="both"

_NOTIFY_SLACK_SH="${REPO_ROOT}/scripts/notify_slack.sh"

usage() {
  cat <<'EOF'
Usage:
  tf_stack.sh plan       [--staging|--workspace NAME] [--gcp-project ID] [-- ...extra terraform args]
  tf_stack.sh provision  [--staging|--workspace NAME] [--gcp-project ID] [--stress-testing-branch BR] [--auto-approve] [-- ...extra terraform args]
  tf_stack.sh setup      [--staging|--workspace NAME] [--gcp-project ID] [--pueue-version VER] [--stress-testing-branch BR]
  tf_stack.sh update     [--staging|--workspace NAME] [--gcp-project ID] [--pueue-version VER] [--stress-testing-branch BR] [--update-target both|pueue|stress-testing]
  tf_stack.sh sync       [--gcp-project ID]
  tf_stack.sh destroy    [--staging|--workspace NAME] [--gcp-project ID] [--auto-approve] [--force] [-- ...extra terraform args]
  tf_stack.sh output     [--staging|--workspace NAME]
  tf_stack.sh ip         [--staging|--workspace NAME]
EOF
}

die() {
  echo "ERROR: $* (${BASH_SOURCE[1]}:${BASH_LINENO[0]} ${FUNCNAME[1]}())" >&2
  exit 1
}

# ------------------------------------------------
# Slack — best-effort notification via GCP Secret Manager.

load_slack_config() {
  : "${SLACK_CHANNEL_ID:=${CHANNEL_ID:-}}"
  [[ -n "${SLACK_TOKEN:-}" && -n "${SLACK_CHANNEL_ID:-}" ]] && return 0
  command -v gcloud &>/dev/null || return 1
  SLACK_TOKEN="$(gcloud secrets versions access latest --secret=stress-testing-manager-slack-token --project="$GCP_PROJECT" 2>/dev/null)" || return 1
  SLACK_CHANNEL_ID="$(gcloud secrets versions access latest --secret=stress-testing-manager-slack-channel-id --project="$GCP_PROJECT" 2>/dev/null)" || return 1
  [[ -n "$SLACK_TOKEN" && -n "$SLACK_CHANNEL_ID" ]] || return 1
  return 0
}

notify_action_start() {
  load_slack_config || return 0
  [[ -x "$_NOTIFY_SLACK_SH" ]] || return 0

  local msg="▶️ stress-testing-manager \`${ACTION}\` starting (owner=${OWNER:-$USER}"
  if [[ -n "${WORKSPACE}" ]]; then
    msg+=", workspace=${WORKSPACE}"
  fi
  if [[ "$STRESS_TESTING_BRANCH" != "main" ]]; then
    msg+=", branch=${STRESS_TESTING_BRANCH}"
  fi
  if [[ -n "$PUEUE_VERSION" ]]; then
    msg+=", pueue=${PUEUE_VERSION}"
  fi
  if [[ "$ACTION" == "update" ]]; then
    msg+=", target=${UPDATE_TARGET}"
  fi
  if [[ "$AUTO_APPROVE" -eq 1 ]]; then
    msg+=", auto-approve"
  fi
  if [[ "$ACTION" == "destroy" && "$FORCE" -eq 1 ]]; then
    msg+=", force"
  fi
  msg+=")"

  "$_NOTIFY_SLACK_SH" -m "$msg" -c "$SLACK_CHANNEL_ID" -k "$SLACK_TOKEN" -o warning >/dev/null || true
}

rsync_package() {
  if [[ -e "$REPO_ROOT/stress-testing-manager-ip.txt" ]] ; then
    stm_public_ip="$(cat $REPO_ROOT/stress-testing-manager-ip.txt)"
    local -a _excludes=(
      --exclude=.git
      --exclude=.github
      --exclude=.terraform
      --exclude=.terraform.lock.hcl
      --exclude=target
      --exclude=__pycache__
      --exclude=.venv*
      --exclude=node_modules
      --exclude='*.tfstate'
      --exclude='*.tfstate.backup'
      --exclude=log_files
      --exclude=graphify-out
      --exclude=.agents
      --exclude=.codegraph
      --exclude=.omo
      --exclude=.opencode/
      --exclude=.claude
      --exclude=.graphifyignore
      --exclude='vars.*.yaml'
      --exclude=.ansible/
      --exclude='test_suites/network-sync-tests/.*'
      --exclude='test_suites/single-region-tests/transaction_files/transaction_files'
    )
    rsync -avzhP --delete "${_excludes[@]}" \
      "${REPO_ROOT}/" \
      "${stm_user:-ubuntu}@${stm_public_ip}:/home/${stm_user:-ubuntu}/snarkos-stress-testing/"
  else
    die "FILE NOT FOUND \"stress-testing-manager-ip.txt\" **OR** Stress-Testing-Manager NOT PROVISIONED"
  fi
}

# ------------------------------------------------
# Argument parsing

if [[ $# -lt 1 ]]; then usage; exit 1; fi
if [[ "$1" == "-h" || "$1" == "--help" ]]; then usage; exit 0; fi
ACTION="$1"; shift

while [[ $# -gt 0 ]]; do
  case "$1" in
    --staging)       WORKSPACE="staging"; shift ;;
    --workspace)     WORKSPACE="${2:?missing workspace name}"; shift 2 ;;
    --gcp-project)   GCP_PROJECT="${2:?missing gcp project id}"; shift 2 ;;
    --pueue-version) PUEUE_VERSION="${2:?missing pueue version}"; shift 2 ;;
    --stress-testing-branch) STRESS_TESTING_BRANCH="${2:?missing branch name}"; shift 2 ;;
    --update-target) UPDATE_TARGET="${2:?missing update target (both|pueue|stress-testing)}"; shift 2 ;;
    --auto-approve)  AUTO_APPROVE=1; shift ;;
    --force)         FORCE=1; shift ;;
    --)              shift; EXTRA_TF_ARGS+=("$@"); break ;;
    -h|--help)       usage; exit 0 ;;
    *)               EXTRA_TF_ARGS+=("$1"); shift ;;
  esac
done

case "$ACTION" in
  provision|destroy|plan|output|ip|setup|update|sync) ;;
  *) usage; die "Unknown action: $ACTION" ;;
esac

cd "$TF_DIR"

# ------------------------------------------------
# Terraform helpers

# Resolve WORKSPACE for terraform actions only. Honours --workspace/--staging
# when already set; otherwise reads the currently selected terraform workspace.
ensure_workspace() {
  if [[ -n "$WORKSPACE" ]]; then
    return 0
  fi
  command -v terraform >/dev/null || die "terraform is required for '${ACTION}' but was not found on PATH."
  WORKSPACE=$(terraform workspace list | awk '($1 == "*") {print $2}')
  WORKSPACE="${WORKSPACE:-default}"
}

init_terraform() {
  echo "==> terraform init"
  terraform init -upgrade >/dev/null

  ensure_workspace
  echo "==> GCP Project: $GCP_PROJECT"
  echo "==> selecting workspace: $WORKSPACE"
  if terraform workspace list | sed 's/*//g' | awk '{$1=$1};1' | grep -qx "$WORKSPACE"; then
    terraform workspace select "$WORKSPACE"
  else
    terraform workspace new "$WORKSPACE"
  fi
}

# ------------------------------------------------
# Ansible runner — resolves instance name / zone / OS Login username from
# terraform outputs and invokes ansible-playbook against the STM's public IP.

run_ansible_playbook() {
  local playbook="${1:?missing playbook name}"
  local setup_target="${2:-full}"

  init_terraform

  local instance zone stm_ip stm_user remote_user
  instance="$(terraform output -raw stm_instance_name 2>/dev/null || true)"
  zone="$(terraform output -raw stm_zone 2>/dev/null || true)"
  stm_ip="$(terraform output -raw stm_public_ip 2>/dev/null || true)"

  [[ -n "$instance" ]] || die "Missing terraform output 'stm_instance_name' (is the STM provisioned?)"
  [[ -n "$zone"     ]] || die "Missing terraform output 'stm_zone' (is the STM provisioned?)"
  [[ -n "$stm_ip"   ]] || die "Missing terraform output 'stm_public_ip' (is the STM provisioned?)"

  echo "==> resolving OS Login username via 'gcloud compute ssh $instance --command=whoami'"
  remote_user="$(gcloud compute ssh "$instance" \
    --zone="$zone" \
    --project="$GCP_PROJECT" \
    --command='whoami' 2>/dev/null | tail -1 | tr -d '[:space:]')"
  [[ -n "$remote_user" ]] || die "Could not resolve OS Login username (instance ready? gcloud auth OK?)"

  stm_user="${TARGET_USER:-$remote_user}"
  echo "==> STM user: $stm_user"

  echo "==> ansible-playbook $playbook (inventory ${stm_ip},, user=${remote_user:-$stm_user}, target=${setup_target})"
  local -a ansible_extra_vars=(
    --extra-vars "stm_user=${stm_user}"
    --extra-vars "stm_home=/home/${stm_user}"
    --extra-vars "ansible_user=${remote_user}"
    --extra-vars "pueue_version=${PUEUE_VERSION}"
    --extra-vars "stress_testing_branch=${STRESS_TESTING_BRANCH}"
    --extra-vars "setup_target=${setup_target}"
    --extra-vars "gcp_project=${GCP_PROJECT}"
  )

  (
    cd "${TF_DIR}/ansible"
    ANSIBLE_ROLES_PATH="${REPO_ROOT}/common/roles" \
      ANSIBLE_REMOTE_USER="$stm_user" \
      ansible-playbook \
      "${ansible_extra_vars[@]}" \
      --diff \
      --ssh-common-args="-o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=/dev/null" \
      -i "${stm_ip}," "$playbook"
  )
}

# ------------------------------------------------
# Terraform apply args (used by plan/provision/destroy only).
APPROVE_ARGS=()
if [[ "$AUTO_APPROVE" -eq 1 ]]; then
  APPROVE_ARGS+=("-auto-approve")
fi

TF_COMMON_ARGS=(
  #"-var=owner=${OWNER:?OWNER environment variable must be set (e.g. export OWNER=\$USER)}"
  "-var=owner=${OWNER:-$USER}"
  "-var=gcp_project=${GCP_PROJECT}"
  "-var=stress_testing_branch=${STRESS_TESTING_BRANCH}"
)
if ((${#EXTRA_TF_ARGS[@]})); then
  TF_COMMON_ARGS+=("${EXTRA_TF_ARGS[@]}")
fi

TF_APPLY_ARGS=()
if ((${#APPROVE_ARGS[@]})); then
  TF_APPLY_ARGS+=("${APPROVE_ARGS[@]}")
fi

notify_action_start

case "$ACTION" in
  setup)
    echo "==> setup: ansible-playbook setup.yml (target=full)"
    run_ansible_playbook setup.yml full
    ;;
  update)
    case "$UPDATE_TARGET" in
      both|pueue|stress-testing) ;;
      *) die "Invalid --update-target: $UPDATE_TARGET (expected both, pueue, or stress-testing)" ;;
    esac
    echo "==> update: ansible-playbook setup.yml (target=$UPDATE_TARGET)"
    run_ansible_playbook setup.yml "$UPDATE_TARGET"
    ;;
  sync)
    echo "==> sync: uploading stress-testing artifact via scripts/bin/upload-artifact.sh"
    # "${REPO_ROOT}/scripts/bin/upload-artifact.sh"
    rsync_package
    ;;
  *)
    init_terraform
    case "$ACTION" in
      plan)
        echo "==> terraform plan (workspace=$WORKSPACE)"
        terraform plan "${TF_COMMON_ARGS[@]}"
        ;;
      provision)
        echo "==> terraform apply via provision (workspace=$WORKSPACE)"
        terraform apply \
          ${TF_APPLY_ARGS[@]+"${TF_APPLY_ARGS[@]}"} \
          "${TF_COMMON_ARGS[@]}"

        # Wait for the instance to reach RUNNING state.
        local_instance="$(terraform output -raw stm_instance_name 2>/dev/null || true)"
        local_zone="$(terraform output -raw stm_zone 2>/dev/null || true)"
        if [[ -n "$local_instance" && -n "$local_zone" ]]; then
          echo "==> waiting for $local_instance to reach RUNNING"
          for _ in {1..60}; do
            status="$(gcloud compute instances describe "$local_instance" \
              --zone="$local_zone" \
              --project="$GCP_PROJECT" \
              --format='get(status)' 2>/dev/null || true)"
            [[ "$status" == "RUNNING" ]] && { echo "==> $local_instance is RUNNING"; break; }
            sleep 3
          done
        fi
        ;;
      destroy)
        if [[ "$WORKSPACE" == "default" && "$FORCE" -ne 1 ]]; then
          die "Refusing to destroy the DEFAULT workspace. Re-run with --force if you really mean it."
        fi
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
        echo "==> stm_public_ip (workspace=$WORKSPACE)"
        terraform output -raw stm_public_ip
        ;;
    esac
    ;;
esac
