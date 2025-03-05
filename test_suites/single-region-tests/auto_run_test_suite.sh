#!/bin/bash

ulimit -n 2048

PARENT_DIR=$(cd "$(dirname $0)" && pwd)
bold=$(tput bold)
normal=$(tput sgr0)

TFSTATE_BUCKET="${TF_STATE_BUCKET:-ephnet-terraform-state-bucket-builder}"
export AWS_REGION="${TF_STATE_REGION:-eu-central-1}"
RELEASE_BUCKET="${RELEASE_BUCKET:snarkos-releases-for-testing}"
export TF_RELEASE_BUCKET=$RELEASE_BUCKET

TF_VAR_ecr_repository_url=148761683502.dkr.ecr.eu-central-1.amazonaws.com/tx-cannon

# Function to clean up resources using Terraform
cleanup() {
    echo "An error occurred or finished. Destroying infrastructure to avoid unnecessary costs..."

    cd "$PARENT_DIR/terraform"
    terraform destroy -auto-approve -parallelism=50

    cd "$PARENT_DIR/terraform_tx_cannon"
    terraform destroy -auto-approve -parallelism=50
}

# Function to init and apply Terraform
init_and_apply_terraform() {
    cd $PARENT_DIR/terraform

    terraform init -migrate-state -backend-config="bucket=${TFSTATE_BUCKET}"
    terraform apply -auto-approve

    # Save the load balancer DNS name
    terraform output -raw snarkos_lb_dns_name > $PARENT_DIR/lb_url.txt
    LB_URL=$(cat $PARENT_DIR/lb_url.txt)

    # Save updated IP addresses
    cd "$PARENT_DIR/playbooks"
    ansible-playbook ips.yml --extra-vars "test_network_url=${LB_URL}" --extra-vars="@${VARS}.yml"
}

run_test() {
    echo "${bold}$(date +"%T") - Running test: $SELECTED${normal}"

    # Run any pre-test script
    if [ -x "$PARENT_DIR/tests/$SELECTED/pre-test.sh" ]; then
        echo "Running pre-test script..."
        cd "$PARENT_DIR/tests/$SELECTED/"
        "./pre-test.sh"
    fi

    # Run the test
    cd "$PARENT_DIR/playbooks"
    ansible-playbook run_test.yml --extra-vars="test_name=$SELECTED" --extra-vars="test_network_url=${LB_URL}" --extra-vars="@${VARS}.yml"

    # Run a check script if available
    if [ -x "$PARENT_DIR/tests/$SELECTED/check.sh" ]; then
        cd "$PARENT_DIR/tests/$SELECTED/"
        echo "Running check script in folder `pwd`"
        ./check.sh $NETWORK
    fi

    # Run any post-test script
    if [ -x "$PARENT_DIR/tests/$SELECTED/post-test.sh" ]; then
        echo "Running post-test script..."
        cd "$PARENT_DIR/tests/$SELECTED/"
        "./post-test.sh"
    fi
}

trap cleanup ERR
trap 'rc=$?; echo "ERR at line ${LINENO} (rc: $rc)"; exit $rc' ERR

trap cleanup EXIT
trap 'rc=$?; echo "EXIT (rc: $rc)"; exit $rc' EXIT

# Exit immediately if a command exits with a non-zero status.
set -e

# Exit if an undefined variable is used.
set -u

# export trap to functions
set -E

# Define key name
KEY_NAME="devnet-key"

# Check if the SSH key already exists, generate if not
if [ ! -f "${KEY_NAME}" ]; then
    echo "Generating SSH key..."
    ssh-keygen -t rsa -b 4096 -f "${KEY_NAME}" -N '' # -N '' specifies no passphrase
    chmod 400 "${KEY_NAME}"
else
    echo "SSH key already exists. Skipping generation..."
fi

# Configuration:
RUN_TERRAFORM="${1:-l}"
RUN_SETUP="${2:-y}"
RUN_TESTS="${3:-y}"
SELECTED="${4:-unbond_bond_validators}"
VARS="${5:-vars}"

# Optionally initialize and apply Terraform
if [ "$RUN_TERRAFORM" == "h" ]; then
    cp $PARENT_DIR/terraform/variables.tf.heavy $PARENT_DIR/terraform/variables.tf
    init_and_apply_terraform
elif [ "$RUN_TERRAFORM" == "l" ]; then
    cp $PARENT_DIR/terraform/variables.tf.light $PARENT_DIR/terraform/variables.tf
    init_and_apply_terraform
elif [ "$RUN_TERRAFORM" == "n" ]; then
    echo "Skipping Terraform..."
else
    echo "Invalid option. Exiting..."
    exit 1
fi

# Read the load balancer DNS name from lb_url.txt
LB_URL=$(cat $PARENT_DIR/lb_url.txt)
# Read the network from $PARENT_DIR/playbooks/vars.yml
export NETWORK=$(grep "network:" $PARENT_DIR/playbooks/vars.yml | cut -d " " -f2)

# Optionally run Ansible playbook to setup services
if [ "$RUN_SETUP" == "y" ]; then
    cd "$PARENT_DIR/playbooks"
    ansible-playbook setup.yml --extra-vars "test_network_url=${LB_URL}" --extra-vars="@${VARS}.yml"
elif [ "$RUN_SETUP" == "n" ]; then
    echo "Skipping setup..."
else
    echo "Invalid option. Exiting..."
    exit 1
fi

# Optionally run tests
if [ "$RUN_TESTS" == "y" ]; then
  run_test
fi

# Download client logs:
export SELECTED=_download_logs_clients
run_test

# Download validator logs:
export SELECTED=_download_logs_validators
run_test

# Destroy the infrastructure
echo "Destroying infrastructure..."
cd "$PARENT_DIR/terraform"
terraform destroy -auto-approve -parallelism=50
cd "$PARENT_DIR/terraform_tx_cannon"
terraform destroy -auto-approve -parallelism=50
