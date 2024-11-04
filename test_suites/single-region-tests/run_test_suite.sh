#!/bin/bash

ulimit -n 2048

PARENT_DIR=$(cd "$(dirname "$0")" && pwd)
bold=$(tput bold)
normal=$(tput sgr0)

# Function to clean up resources using Terraform
cleanup() {
    echo "An error occurred or finished. Destroying infrastructure to avoid unnecessary costs..."

    read -p "Press ENTER to destroy the infrastructure or CTRL+C to cancel..."

    cd "$PARENT_DIR/terraform"
    terraform destroy -auto-approve -parallelism=50

    cd "$PARENT_DIR/terraform_tx_cannon"
    terraform destroy -auto-approve -parallelism=50
}

# Function to init and apply Terraform
init_and_apply_terraform() {
    cd $PARENT_DIR/terraform
    terraform init
    terraform apply -auto-approve
    # Save the load balancer DNS name
    terraform output -raw snarkos_lb_dns_name > $PARENT_DIR/lb_url.txt
    LB_URL=$(cat $PARENT_DIR/lb_url.txt)
    # Save updated IP addresses
    cd "$PARENT_DIR/playbooks"
    ansible-playbook ips.yml --extra-vars "test_network_url=${LB_URL}" --extra-vars="@vars.yml"

    # Tell it like it is
    if [ "$(uname)" == "Darwin" ]; then
        say "Finished running Terraform"
    fi
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
        "./check.sh $NETWORK"
    fi

    # Run any post-test script
    if [ -x "$PARENT_DIR/tests/$SELECTED/post-test.sh" ]; then
        echo "Running post-test script..."
        cd "$PARENT_DIR/tests/$SELECTED/"
        "./post-test.sh"
    fi

    # Tell it like it is
    if [ "$(uname)" == "Darwin" ]; then
        say "Finished running $SELECTED"
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

# Ask if terraform should be run
read -p "Do you want to provision machines? (h)eavy / (l)ight / (n)o ): " RUN_TERRAFORM
# Ask if the nodes should be setup.
read -p "Do you want to run setup for validators and clients? (y/n): " RUN_SETUP
# Ask if any tests should be run
read -p "Do you want to select a test to run? (y/n): " RUN_TESTS

# Find and list all tests
TESTS=($(find tests -maxdepth 1 -mindepth 1 -type d | while read f; do basename "$f"; done | sort))
export TESTS

# Optionally select test to run
if [ "$RUN_TESTS" == "y" ]; then
    # first select the test to run
    source select_test.sh
fi

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
    ansible-playbook setup.yml --extra-vars "test_network_url=${LB_URL}" --extra-vars="@vars.yml"
    if [ "$(uname)" == "Darwin" ]; then
        say "Finished running setup"
    fi
elif [ "$RUN_SETUP" == "n" ]; then
    echo "Skipping setup..."
else
    echo "Invalid option. Exiting..."
    exit 1
fi

# Optionally run tests
if [ "$RUN_TESTS" == "y" ]; then
    # If running all tests, run them in series
    if [ "$SELECTED" == "all" ]; then
        echo Running all tests...
        for test in "${TESTS[@]}"; do
            # Skip if the first letter of "$test" is an underscore
            if [[ "$test" == _* ]]; then
                echo "Skipping $test"
                continue
            fi
            export SELECTED=$test
            run_test
        done
    # Else run the selected test
    else
        run_test
    fi
fi

# Wait for user input before destroying the infrastructure
read -p "Press ENTER to destroy the infrastructure or CTRL+C to cancel..."

# Destroy the infrastructure
echo "Destroying infrastructure..."
cd "$PARENT_DIR/terraform"
terraform destroy -auto-approve -parallelism=50
cd "$PARENT_DIR/terraform_tx_cannon"
terraform destroy -auto-approve -parallelism=50
