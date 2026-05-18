#!/bin/bash

ulimit -n 2048

PARENT_DIR=$(cd "$(dirname "$0")" && pwd)

STACK_NAME="load-ledger-tests"
LB_FILE="$PARENT_DIR/lb_url_${STACK_NAME}.txt"

TF_DATA_DIR="${PARENT_DIR}/.terraform-load-ledger"
export TF_DATA_DIR

TFSTATE_BUCKET="${TF_STATE_BUCKET:-ephnet-terraform-state-bucket-eq}"
TFSTATE_KEY="${TF_STATE_KEY:-${STACK_NAME}/terraform.tfstate}"

export AWS_REGION="${TF_STATE_REGION:-us-west-2}"
RELEASE_BUCKET="${RELEASE_BUCKET:-provable-binaries-releases}"
export TF_RELEASE_BUCKET=$RELEASE_BUCKET

# --- Configuration specific to load_ledger test ---
# Canonical order for mapping IPs to networks: canary, testnet, mainnet
CANONICAL_NETWORKS=("testnet" "mainnet")
NETWORKS=("${CANONICAL_NETWORKS[@]}")  # default: all, in canonical order

TERRAFORM_NETWORK_FOR_TEMPLATE="mainnet"  # used just to fill the NETWORK placeholder
VOLUME_SIZE=5000

# --- CLI options ---
TF_APPLY_ARGS=""
DESTROY_ONLY=0
USE_LATEST_SNAPSHOT=0

# Parse --networks=<list> or --networks <list>, keep canonical order.
parse_networks() {
  local raw="$1"
  local n
  local want_canary=0
  local want_testnet=0
  local want_mainnet=0
  local sel

  IFS=',' read -r -a sel <<<"$raw"
  for n in "${sel[@]}"; do
    # lowercase + trim
    n="$(echo "$n" | tr '[:upper:]' '[:lower:]' | xargs)"
    case "$n" in
      canary)  want_canary=1 ;;
      testnet) want_testnet=1 ;;
      mainnet) want_mainnet=1 ;;
      "" ) ;;  # ignore empties
      * )
        echo "Unknown network in --networks: $n" >&2
        exit 2
        ;;
    esac
  done

  NETWORKS=()
  (( want_canary ))  && NETWORKS+=("canary")
  (( want_testnet )) && NETWORKS+=("testnet")
  (( want_mainnet )) && NETWORKS+=("mainnet")

  if [[ ${#NETWORKS[@]} -eq 0 ]]; then
    echo "No valid networks selected in --networks." >&2
    exit 2
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --apply|-y)
      TF_APPLY_ARGS="-auto-approve"; shift;;
    --destroy)
      DESTROY_ONLY=1; shift;;
    --networks=*)
      parse_networks "${1#*=}"; shift;;
    --networks)
      [[ $# -ge 2 ]] || { echo "--networks requires an argument"; exit 2; }
      parse_networks "$2"; shift 2;;
    --use-latest-snapshot)
      USE_LATEST_SNAPSHOT=1; shift;;
    -h|--help)
      echo "Usage: $0 [--apply|-y] [--destroy] [--networks canary[,testnet|mainnet]] [--use-latest-snapshot]"
      exit 0;;
    *)
      echo "Unknown option: $1"
      exit 2;;
  esac
done

# Set NUMCLIENTS based on selected networks (default = all three)
NUMCLIENTS="${#NETWORKS[@]}"
echo "Selected networks: ${NETWORKS[*]}  (NUMCLIENTS=${NUMCLIENTS})"

network_to_int() {
  local net="$1"
  case "$net" in
    mainnet) echo 0 ;;
    testnet) echo 1 ;;
    canary)  echo 2 ;;
    *)
      echo "Unknown network: $net" >&2
      return 1
      ;;
  esac
}

destroy_infrastructure() {
  echo "Destroying infrastructure..."
  cd "$PARENT_DIR/terraform"
  terraform destroy -auto-approve -parallelism=50 \
    -var="volume_size=${VOLUME_SIZE}" \
    -var="devnet_name=${STACK_NAME}"
}

if [[ "${DESTROY_ONLY}" -eq 1 ]]; then
  echo "Destroy-only mode requested (--destroy)."
  destroy_infrastructure
  exit 0
fi

cleanup() {
  echo "An error occurred or finished. Destroying infrastructure to avoid unnecessary costs..."
  if [[ -z "${TF_APPLY_ARGS}" ]]; then
    read -r -p "Press ENTER to destroy the infrastructure or CTRL+C to cancel..."
  fi
  destroy_infrastructure
}

set_devnet_vars() {
  DEVNET_NAME=$(cd "$PARENT_DIR/terraform" && TF_CLI_ARGS="-no-color" terraform output -raw devnet_name)
  export DEVNET_NAME
  echo "devnet_name : $DEVNET_NAME"
}

init_and_apply_terraform() {
  cd "$PARENT_DIR/terraform"
  terraform init \
    --reconfigure \
    -backend-config="bucket=${TFSTATE_BUCKET}" \
    -backend-config="key=${TFSTATE_KEY}"

  echo "Applying Terraform with volume_size=${VOLUME_SIZE}"
  cmd=(terraform apply)
  if [[ -n "${TF_APPLY_ARGS:-}" ]]; then
    cmd+=("${TF_APPLY_ARGS}")        # e.g. "-auto-approve"
  fi
  cmd+=(-var="volume_size=${VOLUME_SIZE}")
  cmd+=(-var="devnet_name=${STACK_NAME}")

  "${cmd[@]}"

  terraform output -raw snarkos_lb_dns_name > "$LB_FILE"
  LB_URL=$(cat "$LB_FILE")
  set_devnet_vars || exit 1

  if [ "$(uname)" == "Darwin" ]; then
    say "Finished running Terraform"
  fi
}

trap cleanup ERR
set -euo pipefail

KEY_NAME="devnet-key"
if [ ! -f "${KEY_NAME}" ]; then
  echo "Generating SSH key..."
  ssh-keygen -t rsa -b 4096 -f "${KEY_NAME}" -N ''
  chmod 400 "${KEY_NAME}"
else
  echo "SSH key already exists. Skipping generation..."
fi

cp "$PARENT_DIR/terraform/variables.tf.template" "$PARENT_DIR/terraform/variables.tf"
if [[ "$(uname)" == "Darwin" ]]; then
  sed -i '' "s/NUMCLIENTS/${NUMCLIENTS}/g" "$PARENT_DIR/terraform/variables.tf"
  sed -i '' "s/NETWORK/${TERRAFORM_NETWORK_FOR_TEMPLATE}/g" "$PARENT_DIR/terraform/variables.tf"
else
  sed -i "s/NUMCLIENTS/${NUMCLIENTS}/g" "$PARENT_DIR/terraform/variables.tf"
  sed -i "s/NETWORK/${TERRAFORM_NETWORK_FOR_TEMPLATE}/g" "$PARENT_DIR/terraform/variables.tf"
fi
echo "Updated variables.tf with ${NUMCLIENTS} clients for load_ledger test."

init_and_apply_terraform
LB_URL=$(cat "$LB_FILE")
set_devnet_vars || exit 1

# Create a dynamic inventory for this devnet
INV_FILE="$PARENT_DIR/playbooks/inventory_load_ledger.aws_ec2.yml"
cat > "$INV_FILE" <<EOF
plugin: amazon.aws.aws_ec2

regions: us-east-2,us-west-2
profile: ephnet

keyed_groups:
  - key: tags.Role
    prefix: ""
    separator: ""
  - key: tags.Name
    prefix: ""
    separator: ""

filters:
  instance-state-name: running
  "tag:Devnet": "${DEVNET_NAME}"
  "tag:Role":
    - "prometheus-server"
    - "snarkos-client"

compose:
  ansible_host: public_ip_address
EOF

cd "$PARENT_DIR/playbooks"

# --- Refresh inventory/host facts for THIS devnet ---
ansible-playbook -i "$INV_FILE" ips.yml \
  --extra-vars "devnet_name=${DEVNET_NAME}" \
  --extra-vars "test_network_url=${LB_URL}" \
  --extra-vars "snarkos_network=mainnet snarkos_network_int=0" \
  --extra-vars "load_ledger_testing=true" \
  --extra-vars "@vars.yml"

# --- Robust extraction of 'snarkos_client' hosts ---
tmp_json="$(mktemp)"
tmp_list="$(mktemp)"

if ! ansible-inventory -i "$INV_FILE" --list >"$tmp_json"; then
  echo "ERROR: ansible-inventory failed for inventory: $INV_FILE" >&2
  rm -f "$tmp_json" "$tmp_list"
  exit 1
fi

python3 - "$tmp_json" >"$tmp_list" <<'PY'
import json, sys

path = sys.argv[1]
try:
    raw = open(path).read().strip()
    if not raw:
        sys.exit(0)
    data = json.loads(raw)
except Exception:
    sys.exit(0)

hosts = []
grp = data.get("snarkos_client")
if isinstance(grp, dict) and isinstance(grp.get("hosts"), list):
    hosts = grp["hosts"]

if not hosts:
    for k, v in data.items():
        if k == "snarkos_client" and isinstance(v, dict):
            hs = v.get("hosts")
            if isinstance(hs, list):
                hosts = hs
                break

for h in hosts:
    if isinstance(h, str):
        print(h)
PY

CLIENTS=()
while IFS= read -r line; do
  [ -n "$line" ] && CLIENTS+=("$line")
done <"$tmp_list"

rm -f "$tmp_json" "$tmp_list"

EXPECTED="${#NETWORKS[@]}"
if [ "${#CLIENTS[@]}" -lt "${EXPECTED}" ]; then
  echo "Waiting for snarkos_client hosts to appear in inventory… (need ${EXPECTED})"
  for _ in {1..10}; do
    sleep 6
    tmp_json="$(mktemp)"
    tmp_list="$(mktemp)"
    ansible-inventory -i "$INV_FILE" --list >"$tmp_json" 2>/dev/null || true
    python3 - "$tmp_json" >"$tmp_list" <<'PY'
import json, sys
try:
    data = json.load(open(sys.argv[1]))
except Exception:
    sys.exit(0)
grp = data.get("snarkos_client")
hosts = grp.get("hosts") if isinstance(grp, dict) else []
for h in hosts or []:
    print(h)
PY
    CLIENTS=()
    while IFS= read -r line; do
      [ -n "$line" ] && CLIENTS+=("$line")
    done <"$tmp_list"
    rm -f "$tmp_json" "$tmp_list"
    [ "${#CLIENTS[@]}" -ge "${EXPECTED}" ] && break
  done
fi

if [ "${#CLIENTS[@]}" -lt "${EXPECTED}" ]; then
  echo "ERROR: Expected at least ${EXPECTED} hosts in group 'snarkos_client', got ${#CLIENTS[@]}."
  echo "Debug: show inventory graph for $INV_FILE:"
  ansible-inventory -i "$INV_FILE" --graph || true
  exit 1
fi

cd "$PARENT_DIR/playbooks"

VENV_DIR="$PARENT_DIR/.ansible_venv"
if [ ! -x "$VENV_DIR/bin/python" ]; then
  python3 -m venv "$VENV_DIR"
  "$VENV_DIR/bin/pip" install --upgrade pip setuptools wheel
  "$VENV_DIR/bin/pip" install boto3 botocore
fi

if ! ansible-galaxy collection list 2>/dev/null | grep -q '^amazon\.aws '; then
  ansible-galaxy collection install amazon.aws
fi

LOCAL_INV="$PARENT_DIR/playbooks/local.inventory"
cat > "$LOCAL_INV" <<EOF
localhost ansible_connection=local ansible_python_interpreter=${VENV_DIR}/bin/python
EOF

for idx in "${!NETWORKS[@]}"; do
  NETWORK="${NETWORKS[$idx]}"
  TARGET_HOST="${CLIENTS[$idx]}"
  SNARKOS_NETWORK_INT="$(network_to_int "$NETWORK")" || exit 1

  SNAPSHOT_FILE_DEST="$PARENT_DIR/playbooks/snapshot_urls_${STACK_NAME}.txt"

  if [[ "$USE_LATEST_SNAPSHOT" -eq 1 ]]; then
    # Use latest uncompressed snapshot directory in GCS
    SNAPSHOT_URL="gs://snarkos-${NETWORK}/uncompressed"
    echo "Using latest uncompressed snapshot for ${NETWORK}: ${SNAPSHOT_URL}"
    printf '%s\n' "$SNAPSHOT_URL" > "$SNAPSHOT_FILE_DEST"
  else
    # Legacy behavior: copy from per-network file
    SNAPSHOT_FILE_SRC="$PARENT_DIR/playbooks/snapshot_url_load_test_${NETWORK}.txt"
    echo "Using snapshot file ${SNAPSHOT_FILE_SRC} for ${NETWORK}"
    cp "$SNAPSHOT_FILE_SRC" "$SNAPSHOT_FILE_DEST"
  fi

  echo "Running Ansible setup for ${NETWORK} on host ${TARGET_HOST}"

  ansible-playbook -i "$INV_FILE" -i "$LOCAL_INV" setup.yml \
    --limit "localhost,${TARGET_HOST}" \
    --extra-vars="devnet_name=${DEVNET_NAME}" \
    --extra-vars="test_network_url=${LB_URL} snarkos_network_int=${SNARKOS_NETWORK_INT}" \
    --extra-vars="base_workspace_folder=${PARENT_DIR}/playbooks" \
    --extra-vars="snarkos_network=${NETWORK}" \
    --extra-vars="load_ledger_testing=true" \
    --extra-vars="snapshot_urls_path=${SNAPSHOT_FILE_DEST}" \
    --extra-vars="@vars.yml"
done

if [ "$(uname)" == "Darwin" ]; then
  say "Finished running load_ledger setup"
fi

if [[ -z "${TF_APPLY_ARGS}" ]]; then
  read -r -p "Press ENTER to destroy the infrastructure or CTRL+C to cancel..."
  destroy_infrastructure
fi
