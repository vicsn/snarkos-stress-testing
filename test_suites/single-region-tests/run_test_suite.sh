#!/bin/bash

ulimit -n 2048

PARENT_DIR=$(cd "$(dirname "$0")" && pwd)
SCRIPT_DIR=$(pwd)

bold=$(tput bold)
normal=$(tput sgr0)

export AWS_REGION="${TF_STATE_REGION:-us-west-2}"
RELEASE_BUCKET="${RELEASE_BUCKET:-provable-binaries-releases}"
export TF_VAR_RELEASE_BUCKET=$RELEASE_BUCKET
export OWNER=$USER
export TF_VAR_devnet_name="${DEVNET_NAME:-single-region-tests}"

echo "About to run setup/tests for user $OWNER"

# Bucket for the logs:
RESULTS_AND_LOGS_BUCKET="${RESULTS_AND_LOGS_BUCKET:-provable-logs-results}"
TEST_RUNNER="${STRESS_TEST_RUNNER:-$USER}"
DATE_OF_RUN=$(date -u '+%Y%m%dT%H%M%SZ')
BASE_BUCKET_PATH="manual_test_runs/$USER/$DATE_OF_RUN"

download_and_upload_logs() {
  echo "Downloading test logs..."

  # If no tests were ran:
  if [ -z "${SELECTED+x}" ]; then
    SELECTED=""
  fi

  local test_ran="${SELECTED:-download_and_upload_logs}"

  # Cleanup old logs:
  rm -rf $PARENT_DIR/log_files

  # Download client logs:
  export SELECTED=download_logs_clients
  run_utility

  # Download prover logs:
  export SELECTED=download_logs_provers
  run_utility

  # Download validator logs:
  export SELECTED=download_logs_validators
  run_utility

  # Download tx_runner logs:
  export SELECTED=download_logs_tx_runner
  run_utility

  echo "Uploading test logs to S3..."

  if test -d $PARENT_DIR/log_files; then
    for log_file in $PARENT_DIR/log_files/*
    do
        if test -f "$log_file"
        then
          local destination="s3://$RESULTS_AND_LOGS_BUCKET/$BASE_BUCKET_PATH/$test_ran/$(basename ${log_file})"
          echo "Copying $log_file to $destination ..."
          aws s3 cp $log_file $destination --profile ephnet
        fi
    done
  fi

  if test -f $PARENT_DIR/observability_runner.log; then
    local destination="s3://$RESULTS_AND_LOGS_BUCKET/$BASE_BUCKET_PATH/$test_ran/observability_runner.log"
    aws s3 cp "$PARENT_DIR/observability_runner.log" $destination --profile ephnet

    rm -f $PARENT_DIR/observability_runner.log
  fi

  echo "Log files uploaded to https://console.aws.amazon.com/s3/buckets/$RESULTS_AND_LOGS_BUCKET?prefix=$BASE_BUCKET_PATH/$test_ran/"
}

# Function to clean up resources using Terraform
cleanup() {
    cd "$SCRIPT_DIR"
    source destroy_infra.sh
}

set_network_vars() {
  export NETWORK=$(cd "$PARENT_DIR/terraform" && TF_CLI_ARGS="-no-color" terraform output -raw snarkos_network)

  if [[ -z "${NETWORK}" || "$NETWORK" == *"No outputs found"* ]]; then
    echo "Output 'snarkos_network' not found. Applying noop target to generate it..."

    cp $PARENT_DIR/terraform/variables.tf.light $PARENT_DIR/terraform/variables.tf

    cd "$PARENT_DIR/terraform"
    terraform init > /dev/null
    terraform apply -target=null_resource.noop -var="owner=$OWNER" -auto-approve > /dev/null
    export NETWORK=$(TF_CLI_ARGS="-no-color" terraform output -raw snarkos_network)
    cd $PARENT_DIR
  fi

  export DEVNET_NAME=$(cd "$PARENT_DIR/terraform" && TF_CLI_ARGS="-no-color" terraform output -raw devnet_name)

  echo "devnet_name : $DEVNET_NAME"

  case "$NETWORK" in
    mainnet)
      export NETWORK_INT=0
      ;;
    testnet)
      export NETWORK_INT=1
      ;;
    canary)
      export NETWORK_INT=2
      ;;
    *)
      echo "Error: Unknown network '$NETWORK'" >&2
      return 1
      ;;
  esac
}

# Function to init and apply Terraform
init_and_apply_terraform() {
    cd $PARENT_DIR/terraform
    terraform init

    # Store the currently loaded tx-cannon services
    replace_args="" 
    terraform state list | grep 'aws_ecs_service.tx_cannon_services' | \
        while read instance; do
            replace_args+=" -replace=$instance"
        done
    # Always replace the tx-cannon ECS cluster, because they have a state root cached.
    terraform apply $replace_args -var="owner=$OWNER"
    # Save the load balancer DNS name
    terraform output -raw snarkos_lb_dns_name > $PARENT_DIR/lb_url.txt
    LB_URL=$(cat $PARENT_DIR/lb_url.txt)
    set_network_vars || exit 1

    # Save updated IP addresses
    cd "$PARENT_DIR/playbooks"
    ansible-playbook ips.yml --extra-vars="devnet_name=${DEVNET_NAME}" --extra-vars="snarkos_network=${NETWORK}" --extra-vars="snarkos_network_int=${NETWORK_INT}" --extra-vars "test_network_url=${LB_URL}" --extra-vars="@vars.yml"

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

    (cd "$PARENT_DIR/terraform" && terraform init -input=false)
    set_network_vars || exit 1

    # Run the test
    cd "$PARENT_DIR/playbooks"
    ansible-playbook run_test.yml \
      --extra-vars="devnet_name=${DEVNET_NAME}" \
      --extra-vars="snarkos_network=${NETWORK}" \
      --extra-vars="snarkos_network_int=${NETWORK_INT}" \
      --extra-vars="test_name=$SELECTED" \
      --extra-vars="test_network_url=${LB_URL}" \
      --extra-vars="base_workspace_folder=${PARENT_DIR}/playbooks" \
      --extra-vars="@vars.yml"

    # Run a check script if available
    if [ -x "$PARENT_DIR/tests/$SELECTED/check.sh" ]; then
        cd "$PARENT_DIR/tests/$SELECTED/"
        ./check.sh $NETWORK
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

run_utility() {
    echo "${bold}$(date +"%T") - Running utility: $SELECTED${normal}"

    # Run any pre-utility script
    if [ -x "$PARENT_DIR/utils/$SELECTED/pre-utility.sh" ]; then
        echo "Running pre-utility script..."
        cd "$PARENT_DIR/utils/$SELECTED/"
        "./pre-utility.sh"
    fi

    (cd "$PARENT_DIR/terraform" && terraform init -input=false)
    set_network_vars || exit 1

    # Run the utility
    cd "$PARENT_DIR/playbooks"
    ansible-playbook run_utility.yml \
      --extra-vars="devnet_name=${DEVNET_NAME}" \
      --extra-vars="snarkos_network=${NETWORK}" \
      --extra-vars="snarkos_network_int=${NETWORK_INT}" \
      --extra-vars="utility_name=$SELECTED" \
      --extra-vars="test_network_url=${LB_URL}" \
      --extra-vars="base_workspace_folder=${PARENT_DIR}/playbooks" \
      --extra-vars="@vars.yml"

    # Run a check script if available
    if [ -x "$PARENT_DIR/utils/$SELECTED/check.sh" ]; then
        cd "$PARENT_DIR/utils/$SELECTED/"
        ./check.sh $NETWORK
    fi

    # Run any post-utility script
    if [ -x "$PARENT_DIR/utils/$SELECTED/post-utility.sh" ]; then
        echo "Running post-utility script..."
        cd "$PARENT_DIR/utils/$SELECTED/"
        "./post-utility.sh"
    fi

    # Tell it like it is
    if [ "$(uname)" == "Darwin" ]; then
        say "Finished running utility $SELECTED"
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
read -p "Do you want to provision machines? (h)eavy / (l)ight / (pr)erelease / (n)o ): " RUN_TERRAFORM
# Ask if the nodes should be setup.
read -p "Do you want to run setup for validators and clients? (y/n): " RUN_SETUP
# Ask if any tests should be run
read -p "Do you want to select a test to run? (y/n): " RUN_TESTS
# Ask if any tests should be run
read -p "Do you want to select a utility to run? (y/n): " RUN_UTILITIES

# Find and list all tests
TESTS=($(find tests -maxdepth 1 -mindepth 1 -type d | while read f; do basename "$f"; done | sort))
export TESTS

UTILITIES=($(find utils -maxdepth 1 -mindepth 1 -type d | while read f; do basename "$f"; done | sort))
export UTILITIES

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
elif [ "$RUN_TERRAFORM" == "pr" ]; then
    cp $PARENT_DIR/terraform/variables.tf.prerelease $PARENT_DIR/terraform/variables.tf
    init_and_apply_terraform
elif [ "$RUN_TERRAFORM" == "n" ]; then
    echo "Skipping Terraform..."
else
    echo "Invalid option. Exiting..."
    exit 1
fi

# Read the load balancer DNS name from lb_url.txt
LB_URL=$(cat $PARENT_DIR/lb_url.txt)

# Optionally run Ansible playbook to setup services
if [ "$RUN_SETUP" == "y" ]; then
    cd "$PARENT_DIR/playbooks"
    set_network_vars || exit 1

    ansible-playbook setup.yml \
      --extra-vars="devnet_name=${DEVNET_NAME}" \
      --extra-vars="snarkos_network=${NETWORK}" \
      --extra-vars="snarkos_network_int=${NETWORK_INT}" \
      --extra-vars "test_network_url=${LB_URL}" \
      --extra-vars="base_workspace_folder=${PARENT_DIR}/playbooks" \
      --extra-vars="@vars.yml"

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

            run_test | tee -a "$PARENT_DIR/observability_runner.log"
        done

    # We have a special case for the prerelease ones too:
    elif [ "$SELECTED" == "prerelease" ]; then
        echo Running prerelease tests...

        PRERELEASE_TESTS=($(printf "%s\n" "${TESTS[@]}" | grep '^prerelease_'))
        for test in "${PRERELEASE_TESTS[@]}"; do
            export SELECTED=$test
            run_test
        done

    # Else run the selected test
    else
        run_test | tee -a "$PARENT_DIR/observability_runner.log"
    fi
fi

# Optionally select test to run
if [ "$RUN_UTILITIES" == "y" ]; then
    # first select the test to run
    source $PARENT_DIR/select_utility.sh
fi

# Optionally run utilities
if [ "$RUN_UTILITIES" == "y" ]; then
    if [ "$SELECTED" == "upload_logs_to_s3" ]; then
        mkdir "$PARENT_DIR/log_files" || true

        echo "Uploading logs (final pass)..."

        download_and_upload_logs

        if [ "$(uname)" == "Darwin" ]; then
            say "Finished running utility upload logs to s3"
        fi
    else
        run_utility | tee -a "$PARENT_DIR/observability_runner.log"
    fi
fi

# Wait for user input before destroying the infrastructure
read -p "Press ENTER to destroy the infrastructure or CTRL+C to cancel..."

# Destroy the infrastructure
echo "Destroying infrastructure..."

cd "$PARENT_DIR/terraform"
terraform destroy -auto-approve -parallelism=50 -var="owner=$OWNER"

cd "$PARENT_DIR/terraform_tx_cannon"
# Init the terraform_tx_cannon as if it is not used in this test run, we'll see 'Error: Module not installed' without an init.
terraform init
terraform destroy -auto-approve -parallelism=50 -var="owner=$OWNER"
