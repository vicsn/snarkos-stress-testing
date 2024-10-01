#!/bin/bash

ulimit -n 2048

PARENT_DIR=$(cd "$(dirname "$0")" && pwd)
bold=$(tput bold)
normal=$(tput sgr0)

# Function to clean up resources using Terraform
cleanup() {
    echo "An error occurred. Destroying infrastructure to avoid unnecessary costs..."
    read -p "Press ENTER to destroy the infrastructure or CTRL+C to cancel..."
    cd "$PARENT_DIR/terraform"
    terraform destroy -auto-approve
}

# Function to init and apply Terraform
init_and_apply_terraform() {
    cd $PARENT_DIR/terraform
    terraform init
    terraform apply -auto-approve
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
    ansible-playbook run_test.yml --extra-vars="test_name=$SELECTED" --extra-vars="test_network_url=${LB_URL}" --extra-vars="@vars.yml"

    # Run a check script if available
    if [ -x "$PARENT_DIR/tests/$SELECTED/check.sh" ]; then
        cd "$PARENT_DIR/tests/$SELECTED/"
        "./check.sh"
    fi

    # Run any post-test script
    if [ -x "$PARENT_DIR/tests/$SELECTED/post-test.sh" ]; then
        echo "Running post-test script..."
        cd "$PARENT_DIR/tests/$SELECTED/"
        "./post-test.sh"
    fi
}

# Set up trap to call cleanup function on any error
trap cleanup ERR

# Exit immediately if a command exits with a non-zero status.
set -e

# Optional: Exit if an undefined variable is used.
set -u

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

# Find and list all tests
TESTS=($(find tests -maxdepth 1 -mindepth 1 -type d | while read f; do basename "$f"; done | sort))
export TESTS

# Optionally a test name was passed as first argument.
if [ $# -eq 1 ]; then
    SELECTED=$1
    if [ ! -d "$PARENT_DIR/tests/$SELECTED" ]; then
        echo "Invalid test: $SELECTED"
        exit 1
    fi
else
    # first select the test to run
    source select_test.sh
fi

# Ask if terraform should be run
read -p "Do you want to run Terraform? (h)eavy / (l)ight / (n)o ): " RUN_TERRAFORM
# Ask if the nodes should be setup.
read -p "Do you want to run setup of all services? (y/n): " RUN_SETUP

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

# Get the load balancer DNS name and ip addresses
cd $PARENT_DIR/terraform
LB_URL=$(terraform output -raw snarkos_lb_dns_name)
terraform output -json instance_ips > output.json && jq -r '.[]' output.json > ../ip_addresses.txt

# Optionally run Ansible playbook to setup services
if [ "$RUN_SETUP" == "y" ]; then
    cd "$PARENT_DIR/playbooks"
    ansible-playbook setup.yml --extra-vars "test_network_url=${LB_URL}" --extra-vars="@vars.yml"
elif [ "$RUN_SETUP" == "n" ]; then
    echo "Skipping setup..."
else
    echo "Invalid option. Exiting..."
    exit 1
fi

# If running all tests, run them in series
if [ "$SELECTED" == "all" ]; then
    echo "Running all tests... (skipping '_save_deployments' and '_reset_all')"
    for test in "${TESTS[@]}"; do
        # Skip the '_save_deployments' and '_reset_all'
        if [ "$test" == "_save_deployments" ] || [ "$test" == "_reset_all" ]; then
            continue
        fi
        export SELECTED=$test
        run_test
    done
# Else run the selected test
else
    run_test
fi

# Wait for user input before destroying the infrastructure
read -p "Press ENTER to destroy the infrastructure or CTRL+C to cancel..."

# Destroy the infrastructure
echo "Destroying infrastructure..."
cd "$PARENT_DIR/terraform"
terraform destroy -auto-approve -parallelism=200
