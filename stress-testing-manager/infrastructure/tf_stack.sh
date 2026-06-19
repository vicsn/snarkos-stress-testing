#!/usr/bin/env bash
set -euo pipefail

TF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$TF_DIR/../.." && pwd)"
WORKSPACE="default"
ACTION=""
AUTO_APPROVE=0
FORCE=0
EXTRA_TF_ARGS=()

PUEUE_VERSION=""
STRESS_TESTING_BRANCH="main"
UPDATE_TARGET="both"

usage() {
  cat <<'EOF'
Usage:
  tf_stack.sh plan [--staging|--workspace NAME] [-- ...extra terraform args]
  tf_stack.sh provision [--staging|--workspace NAME] [--pueue-version VER] [--stress-testing-branch BR] [--auto-approve] [-- ...extra terraform args]
  tf_stack.sh setup [--staging|--workspace NAME] [--pueue-version VER] [--stress-testing-branch BR] [-- ...extra terraform args]
  tf_stack.sh update [--staging|--workspace NAME] [--pueue-version VER] [--stress-testing-branch BR] [--update-target both|pueue|stress-testing]
  tf_stack.sh destroy [--staging|--workspace NAME] [--auto-approve] [--force] [-- ...extra terraform args]
  tf_stack.sh output [--staging|--workspace NAME] [-- ...extra terraform args]
  tf_stack.sh ip [--staging|--workspace NAME] [-- ...extra terraform args]
EOF
}

die() { echo "ERROR: $*" >&2; exit 1; }

NOTIFY_SLACK="${REPO_ROOT}/scripts/notify_slack.sh"

# Read a simple "key: value" field from vars.yml (best-effort).
read_slack_var() {
  local key="$1" file="$2"
  awk -v key="$key" '
    $1 == key ":" {
      val = $2
      for (i = 3; i <= NF; i++) val = val " " $i
      gsub(/^"|"$|^'\''|'\''$/, "", val)
      print val
      exit
    }
  ' "$file"
}

load_slack_config() {
  local candidate vars_file=""
  for candidate in \
    "${TF_DIR}/ansible/templates/vars.yml" \
    "${TF_DIR}/vars.yml"; do
    if [[ -f "$candidate" ]]; then
      vars_file="$candidate"
      break
    fi
  done
  [[ -n "$vars_file" ]] || return 1

  SLACK_TOKEN="$(read_slack_var slack_token "$vars_file")"
  SLACK_CHANNEL_ID="$(read_slack_var slack_channel_id "$vars_file")"
  [[ -n "$SLACK_TOKEN" && -n "$SLACK_CHANNEL_ID" ]]
}

notify_action_start() {
  load_slack_config || return 0
  [[ -x "$NOTIFY_SLACK" ]] || return 0

  local msg="▶️ stress-testing-manager \`${ACTION}\` starting (workspace=${WORKSPACE}"
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

  "$NOTIFY_SLACK" -m "$msg" -c "$SLACK_CHANNEL_ID" -k "$SLACK_TOKEN" -o warning >/dev/null || true
}

if [[ $# -lt 1 ]]; then usage; exit 1; fi
ACTION="$1"; shift

while [[ $# -gt 0 ]]; do
  case "$1" in
    --staging) WORKSPACE="staging"; shift ;;
    --workspace) WORKSPACE="${2:?missing workspace name}"; shift 2 ;;
    --pueue-version)
      PUEUE_VERSION="${2:?missing pueue version}"
      shift 2
      ;;
    --stress-testing-branch)
      STRESS_TESTING_BRANCH="${2:?missing branch name}"
      shift 2
      ;;
    --update-target)
      UPDATE_TARGET="${2:?missing update target (both|pueue|stress-testing)}"
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
  provision|destroy|plan|output|ip|setup|update) ;;
  *) usage; die "Unknown action: $ACTION" ;;
esac

cd "$TF_DIR"

# Run Ansible against the manager instance (reads IP from terraform output). Does not run terraform apply.
run_ansible_playbook() {
  local playbook="${1:?missing playbook name}"
  local setup_target="${2:-full}"
  local manager_ip
  bash "${REPO_ROOT}/scripts/ensure_devnet_key.sh"
  manager_ip="$(terraform output -raw stress_testing_manager_public_ip)"

  echo "==> waiting for SSH on $manager_ip"
  until nc -z -v -w5 "$manager_ip" 22; do
    echo "Waiting for $manager_ip to be ready..."
    sleep 2
  done
  ssh-keyscan -H "$manager_ip" >> ~/.ssh/known_hosts

  echo "==> ansible-playbook $playbook (inventory $manager_ip)"
  local ansible_extra_vars=(
    --extra-vars "ansible_ssh_common_args='-o ForwardAgent=yes'"
    --extra-vars "stress_testing_local_path=${REPO_ROOT}"
    --extra-vars "pueue_version=${PUEUE_VERSION}"
    --extra-vars "setup_target=${setup_target}"
  )
  (
    cd "${TF_DIR}/ansible"
    ANSIBLE_ROLES_PATH="${REPO_ROOT}/common/roles" \
      ansible-playbook \
      --private-key "${REPO_ROOT}/devnet-key" \
      "${ansible_extra_vars[@]}" \
      -i "${manager_ip}," "$playbook"
  )
}

init_terraform() {
  bash "${REPO_ROOT}/scripts/ensure_devnet_key.sh"
  echo "==> terraform init"
  terraform init -upgrade

  echo "==> selecting workspace: $WORKSPACE"
  if terraform workspace list | sed 's/*//g' | awk '{$1=$1};1' | grep -qx "$WORKSPACE"; then
    terraform workspace select "$WORKSPACE"
  else
    terraform workspace new "$WORKSPACE"
  fi
}

if [[ "$ACTION" == "destroy" && "$WORKSPACE" == "default" && "$FORCE" -ne 1 ]]; then
  die "Refusing to destroy the DEFAULT workspace. Re-run with --force if you really mean it."
fi

APPROVE_ARGS=()
if [[ "$AUTO_APPROVE" -eq 1 ]]; then
  APPROVE_ARGS+=("-auto-approve")
fi

TF_COMMON_ARGS=(
  "-var=STRESS_TESTING_BRANCH=${STRESS_TESTING_BRANCH}"
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
    echo "==> setup: ansible-playbook setup.yml (workspace=$WORKSPACE, target=full)"
    run_ansible_playbook setup.yml full
    ;;
  update)
    case "$UPDATE_TARGET" in
      both|pueue|stress-testing) ;;
      *) die "Invalid --update-target: $UPDATE_TARGET (expected both, pueue, or stress-testing)" ;;
    esac
    echo "==> update: ansible-playbook setup.yml (workspace=$WORKSPACE, target=$UPDATE_TARGET)"
    run_ansible_playbook setup.yml "$UPDATE_TARGET"
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
    ;;
esac
