#! /usr/bin/env bash

ulimit -n 4096

PARENT_DIR=$(cd "$(dirname "$0")" && pwd)
SCRIPT_DIR=$(pwd)

bold=$(tput bold)
normal=$(tput sgr0)

export AWS_REGION="${TF_STATE_REGION:-us-west-2}"
export TF_STATE_BUCKET="${TF_STATE_BUCKET:-ephnet-terraform-state-bucket-eq}"
export TF_VAR_state_bucket="$TF_STATE_BUCKET"
RELEASE_BUCKET="${RELEASE_BUCKET:-provable-binaries-releases}"
export TF_VAR_RELEASE_BUCKET=$RELEASE_BUCKET
export OWNER=$USER
export ANSIBLE_ENABLE_PLUGINS=amazon.aws.aws_ec2
export TF_VAR_devnet_name="${DEVNET_NAME:-single-region-tests}"
INVENTORY_DIR="$PARENT_DIR/inventory/"

# Bucket for the logs:
RESULTS_AND_LOGS_BUCKET="${RESULTS_AND_LOGS_BUCKET:-provable-logs-results}"
DATE_OF_RUN=$(date -u '+%Y%m%dT%H%M%SZ')
BASE_BUCKET_PATH="manual_test_runs/$USER/$DATE_OF_RUN"

# When set (e.g. by the Rust harness via `RUNNER_MANAGES_LOGS=1`), the external
# caller owns log collection and S3: it downloads logs itself (one
# `--utility=download_logs_*` per call, accumulating in log_files/), runs
# analysis itself (`--utility=analyze_logs`), and uploads to S3 itself. In this
# mode the script must NOT auto-collect logs after each test, must NOT upload to
# S3, and must NOT wipe log_files between the caller's separate download calls.
runner_manages_logs() { [ "${RUNNER_MANAGES_LOGS:-}" = "1" ]; }

# Prepares a clean "$PARENT_DIR/log_files" directory.
# Interactive runs are prompted before overwriting; non-interactive runs
# (e.g. invoked by the Rust runner, where stdin is not a TTY) default to
# overwriting so that analysis always runs against a fresh set of logs.
# Set OVERWRITE_LOG_FILES=n to force keeping existing logs in that case.
prepare_log_files_dir() {
  if [ -d "$PARENT_DIR/log_files" ]; then
    local _ans
    if [ -t 0 ]; then
      read -r -p "The folder '$PARENT_DIR/log_files' exists. Delete and overwrite it? [y/N]: " _ans || _ans="n"
    else
      _ans="${OVERWRITE_LOG_FILES:-y}"
      echo "Non-interactive run: log_files overwrite = $_ans"
    fi
    case "$_ans" in
      [yY])
        rm -rf "$PARENT_DIR/log_files"
        ;;
      *)
        echo "Keeping existing 'log_files' (new logs may merge with old ones)."
        ;;
    esac
  fi
  mkdir -p "$PARENT_DIR/log_files"
}

download_and_upload_logs() {
  # The external runner downloads logs, runs analysis, and uploads to S3 itself,
  # so this bundled CLI helper must do nothing under it (avoids redundant
  # downloads during `--test=...` and any S3 upload).
  if runner_manages_logs; then
    echo "RUNNER_MANAGES_LOGS set: external caller handles log download, analysis, and S3; skipping bundled collection."
    return 0
  fi

  echo "Downloading test logs..."

  # If no tests were ran:
  if [ -z "${SELECTED+x}" ]; then
    SELECTED=""
  fi

  local test_ran="${SELECTED:-download_and_upload_logs}"

  # Cleanup old logs:
  prepare_log_files_dir

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

  # Analyse the downloaded prover/tx_runner logs to produce landing_stats.json.
  # This is best-effort: a failure here (e.g. a missing archive because an
  # upstream download failed, or while running from the EXIT trap) must not
  # abort the run or mask the real exit code, hence the explicit guard.
  export SELECTED=analyze_logs
  run_utility || echo "WARNING: analyze_logs utility failed; continuing without landing stats."

  echo "Uploading test logs to S3..."

  if test -d "$PARENT_DIR/log_files"; then
    for log_file in "$PARENT_DIR/log_files/"*
    do
        if test -f "$log_file"
        then
          local destination
          destination="s3://$RESULTS_AND_LOGS_BUCKET/$BASE_BUCKET_PATH/$test_ran/$(basename "$log_file")"
          echo "Copying $log_file to $destination ..."
          aws s3 cp "$log_file" "$destination" --profile ephnet
        fi
    done
  fi

  if test -f "$PARENT_DIR/observability_runner.log"; then
    local destination
    destination="s3://$RESULTS_AND_LOGS_BUCKET/$BASE_BUCKET_PATH/$test_ran/observability_runner.log"
    aws s3 cp "$PARENT_DIR/observability_runner.log" "$destination" --profile ephnet

    rm -f "$PARENT_DIR/observability_runner.log"
  fi

  echo "Log files uploaded to https://console.aws.amazon.com/s3/buckets/$RESULTS_AND_LOGS_BUCKET?prefix=$BASE_BUCKET_PATH/$test_ran/"
}

react_on_exit() {
  rc=$?
  echo "EXIT (rc: $rc)"

  # If the exit code is not 0 (i.e. an error occurred), grab the logs.
  # When the external runner manages logs it does its own collection, so skip.
  if [ $rc -ne 0 ] && ! runner_manages_logs; then
      echo "Error detected! Downloading and uploading logs before exiting..."
      local _do_collect="y"
      if [ -t 0 ]; then
        read -r -p "Download and upload logs now? (y/n): " _do_collect || _do_collect="n"
      fi
      if [[ "$_do_collect" == "y" || "$_do_collect" == "Y" ]]; then
        download_and_upload_logs || echo "WARNING: failed to collect/upload logs during EXIT trap; preserving original rc=$rc"
      else
        echo "Skipping log collection."
      fi
  fi

  exit $rc
}

set_network_vars() {
  NETWORK=$(cd "$PARENT_DIR/terraform" && TF_CLI_ARGS="-no-color" terraform output -raw snarkos_network)
  export NETWORK

  if [[ -z "${NETWORK}" || "$NETWORK" == *"No outputs found"* ]]; then
    echo "Output 'snarkos_network' not found. Applying noop target to generate it..."

    cp "$PARENT_DIR/terraform/variables.tf.light" "$PARENT_DIR/terraform/variables.tf"

    cd "$PARENT_DIR/terraform"
    terraform init > /dev/null
    terraform apply -target=null_resource.noop -var="owner=$OWNER" -auto-approve > /dev/null
    NETWORK=$(TF_CLI_ARGS="-no-color" terraform output -raw snarkos_network)
    export NETWORK
    cd "$PARENT_DIR"
  fi

  DEVNET_NAME=$(cd "$PARENT_DIR/terraform" && TF_CLI_ARGS="-no-color" terraform output -raw devnet_name)
  export DEVNET_NAME

  # Sanitize for Ansible dynamic inventory
  export ANSIBLE_DEVNET_GROUP="${DEVNET_NAME//-/_}"
  export ANSIBLE_OWNER_GROUP="${OWNER//-/_}"
  export TARGET_PATTERN="devnet_${ANSIBLE_DEVNET_GROUP}:&owner_${ANSIBLE_OWNER_GROUP}"
  export LIMIT="${TARGET_PATTERN}"

  # Put localhost into both intersected groups so it survives the devnet&owner
  # --limit intersection. Ansible's :& operator applies to the whole union, so
  # a bare ":localhost" suffix gets filtered out; membership in both groups is
  # the only reliable fix. This file is regenerated on every set_network_vars
  # call so it always reflects the current owner and devnet.
  #
  # INI format with no file extension is used so Ansible's directory-inventory
  # auto-detection routes directly to the ini plugin. Files with a .yml
  # extension cause the yaml inventory plugin to be used; if that plugin fails
  # (observed on some CI environments) localhost is silently dropped from the
  # inventory. Files with a .ini extension are skipped entirely by the auto
  # plugin in directory-scan mode. A bare filename (no extension) is parsed by
  # the ini plugin in all environments and Ansible versions.
  cat > "$PARENT_DIR/inventory/local" <<EOF
[local]
localhost ansible_connection=local

[devnet_${ANSIBLE_DEVNET_GROUP}]
localhost ansible_connection=local

[owner_${ANSIBLE_OWNER_GROUP}]
localhost ansible_connection=local
EOF

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
    cd "$PARENT_DIR/terraform"
    terraform init

    terraform apply -auto-approve -var="owner=$OWNER"
    # Save the load balancer DNS name
    terraform output -raw snarkos_lb_dns_name > "$PARENT_DIR/lb_url.txt"
    LB_URL=$(cat "$PARENT_DIR/lb_url.txt")
    set_network_vars || exit 1

    echo "Terraform finished; giving the AWS API some time to sync the tags..."

    MAX_RETRIES=20
    SLEEP_INTERVAL=5
    RETRY_COUNT=0

    while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
        # Use Ansible to count matched hosts.
        # (Redirects stderr to /dev/null to hide the noisy warnings while it fails)
        HOST_COUNT=$(ansible -i "$INVENTORY_DIR" "$TARGET_PATTERN" --list-hosts 2>/dev/null | grep -o 'hosts ([0-9]*)' | grep -o '[0-9]*')

        # If we got a valid number back and it's greater than 0, the tags are synced!
        if [[ -n "$HOST_COUNT" ]] && [[ "$HOST_COUNT" -gt 0 ]]; then
            echo "Success! AWS synced the tags. Ansible sees $HOST_COUNT matching hosts."
            break
        fi

        echo "Waiting for tags to sync... (Attempt $((RETRY_COUNT+1))/$MAX_RETRIES)"
        sleep $SLEEP_INTERVAL
        RETRY_COUNT=$((RETRY_COUNT+1))
    done

    if [ $RETRY_COUNT -eq $MAX_RETRIES ]; then
        echo "ERROR: Timeout waiting for AWS tags to propagate. Ansible cannot find the target hosts."
        exit 1 # Abort the script so we don't run empty playbooks
    fi

    echo "AWS and Ansible vars:"
    env | grep -iE "aws|ansible|profile"

    echo "Ansible inventory graph:"
    ansible-inventory -i "$INVENTORY_DIR" --graph

    # Save updated IP addresses
    cd "$PARENT_DIR/playbooks"
    ansible-playbook -i "$INVENTORY_DIR" ips.yml \
      --limit "$LIMIT" \
      --extra-vars="devnet_name=${DEVNET_NAME}" \
      --extra-vars="snarkos_network=${NETWORK}" \
      --extra-vars="snarkos_network_int=${NETWORK_INT}" \
      --extra-vars "test_network_url=${LB_URL}" \
      --extra-vars="@${VARS}.yml"

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

    set_network_vars || exit 1

    # Run the test
    cd "$PARENT_DIR/playbooks"
    ansible-playbook -i "$INVENTORY_DIR" run_test.yml \
      --limit "$LIMIT" \
      --extra-vars="devnet_name=${DEVNET_NAME}" \
      --extra-vars="snarkos_network=${NETWORK}" \
      --extra-vars="snarkos_network_int=${NETWORK_INT}" \
      --extra-vars="test_name=$SELECTED" \
      --extra-vars="test_network_url=${LB_URL}" \
      --extra-vars="base_workspace_folder=${PARENT_DIR}/playbooks" \
      --extra-vars="@${VARS}.yml"

    # Run a check script if available
    if [ -x "$PARENT_DIR/tests/$SELECTED/check.sh" ]; then
        cd "$PARENT_DIR/tests/$SELECTED/"
        ./check.sh "$NETWORK"
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

    set_network_vars || exit 1

    # Run the utility
    cd "$PARENT_DIR/playbooks"
    ansible-playbook -i "$INVENTORY_DIR" run_utility.yml \
      --limit "$LIMIT" \
      --extra-vars="devnet_name=${DEVNET_NAME}" \
      --extra-vars="snarkos_network=${NETWORK}" \
      --extra-vars="snarkos_network_int=${NETWORK_INT}" \
      --extra-vars="utility_name=$SELECTED" \
      --extra-vars="test_network_url=${LB_URL}" \
      --extra-vars="base_workspace_folder=${PARENT_DIR}/playbooks" \
      --extra-vars="@${VARS}.yml"

    # Run a check script if available
    if [ -x "$PARENT_DIR/utils/$SELECTED/check.sh" ]; then
        cd "$PARENT_DIR/utils/$SELECTED/"
        ./check.sh "$NETWORK"
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

# ---- Parse command line arguments ----
ARG_PROVISION=""
ARG_RUN_SETUP=""
ARG_NO_SETUP=""
ARG_NO_UTILITY=""
ARG_TEST=""
ARG_NO_TEST=""
ARG_UTILITY=""
ARG_VARS=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --help|-h)
            echo "Usage: $(basename "$0") [COMMAND] [OPTIONS]"
            echo ""
            echo "Commands:"
            echo "  destroy                    Destroy provisioned infrastructure"
            echo ""
            echo "Options:"
            echo "  --provision-machines=MODE  Provision machines (light, heavy, prerelease)"
            echo "  --no-provision             Skip provisioning"
            echo "  --run-setup                Run setup for validators and clients"
            echo "  --no-setup                 Skip setup"
            echo "  --test=NAME                Run a specific test, comma-separated list, 'all', or 'prerelease'"
            echo "  --no-test                  Skip tests"
            echo "  --utility=NAME             Run a specific utility"
            echo "  --no-utility               Skip utilities"
            echo "  --vars=NAME                Ansible vars file name without extension (default: vars)"
            echo "  -h, --help                 Show this help message"
            exit 0
            ;;
        destroy)
            echo "Destroying infrastructure..."
            RUN_TERRAFORM="n"
            RUN_SETUP="n"
            RUN_TESTS="n"
            RUN_UTILITIES="n"
            cd "$SCRIPT_DIR"
            # shellcheck source=/dev/null
            source destroy_infra.sh
            exit $?
            ;;
        --provision-machines=*)
            ARG_PROVISION="${1#*=}"
            shift
            ;;
        --no-provision)
            ARG_PROVISION="n"
            shift
            ;;
        --run-setup)
            ARG_RUN_SETUP="y"
            shift
            ;;
        --no-setup)
            ARG_NO_SETUP="y"
            shift
            ;;
        --no-utility)
            ARG_NO_UTILITY="y"
            shift
            ;;
        --utility=*)
            ARG_UTILITY="${1#*=}"
            shift
            ;;
        --test=*)
            ARG_TEST="${1#*=}"
            shift
            ;;
        --no-test)
            ARG_NO_TEST="y"
            shift
            ;;
        --vars=*)
            ARG_VARS="${1#*=}"
            shift
            ;;
        *)
            echo "Unknown argument: $1"
            exit 1
            ;;
    esac
done
# ---- End argument parsing ----

# Set vars file name (defaults to "vars")
VARS="${ARG_VARS:-vars}"

echo "About to run setup/tests for user $OWNER"

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
if [[ -n "$ARG_PROVISION" ]]; then
    RUN_TERRAFORM="$ARG_PROVISION"
else
    read -r -p "Do you want to provision machines? (h)eavy / (l)ight / (pr)erelease / (n)o ): " RUN_TERRAFORM
fi

# Normalize full-length provision values to short form
case "$RUN_TERRAFORM" in
    heavy)      RUN_TERRAFORM="h"  ;;
    light)      RUN_TERRAFORM="l"  ;;
    prerelease) RUN_TERRAFORM="pr" ;;
    no)         RUN_TERRAFORM="n"  ;;
esac

[[ -n "$ARG_PROVISION" ]] && echo "Will provision machines in \"$ARG_PROVISION\" configuration."

# Ask if the nodes should be setup.
if [[ -n "$ARG_NO_SETUP" ]]; then
    RUN_SETUP="n"
    echo "Will skip setup."
elif [[ -n "$ARG_RUN_SETUP" ]]; then
    RUN_SETUP="y"
    echo "Will run setup for validators and clients."
else
    read -r -p "Do you want to run setup for validators and clients? (y/n): " RUN_SETUP
fi

# Ask if any tests should be run
if [[ -n "$ARG_NO_TEST" ]]; then
    RUN_TESTS="n"
    echo "Will skip tests."
elif [[ -n "$ARG_TEST" ]]; then
    RUN_TESTS="y"
    echo "Will run test \"$ARG_TEST\"."
else
    read -r -p "Do you want to select a test to run? (y/n): " RUN_TESTS
fi

# Ask if any utility should be run
if [[ -n "$ARG_NO_UTILITY" ]]; then
    RUN_UTILITIES="n"
    echo "Will skip utilities."
elif [[ -n "$ARG_UTILITY" ]]; then
    RUN_UTILITIES="y"
    echo "Will run utility \"$ARG_UTILITY\"."
else
    read -r -p "Do you want to select a utility to run? (y/n): " RUN_UTILITIES
fi

# Find and list all tests
mapfile -t TESTS < <(find tests -maxdepth 1 -mindepth 1 -type d | while read -r f; do basename "$f"; done | sort)
export TESTS

mapfile -t UTILITIES < <(find utils -maxdepth 1 -mindepth 1 -type d | while read -r f; do basename "$f"; done | sort)
export UTILITIES

# Optionally select test to run
if [ "$RUN_TESTS" == "y" ]; then
    if [[ -n "$ARG_TEST" ]]; then
        export SELECTED="$ARG_TEST"
    else
        # shellcheck source=./select_test.sh
        source select_test.sh
    fi
fi

# All prompts answered — from here on, errors should trigger log collection.
trap react_on_exit EXIT

# Optionally initialize and apply Terraform
if [ "$RUN_TERRAFORM" == "h" ]; then
    cp "$PARENT_DIR/terraform/variables.tf.heavy" "$PARENT_DIR/terraform/variables.tf"
    init_and_apply_terraform
elif [ "$RUN_TERRAFORM" == "l" ]; then
    cp "$PARENT_DIR/terraform/variables.tf.light" "$PARENT_DIR/terraform/variables.tf"
    init_and_apply_terraform
elif [ "$RUN_TERRAFORM" == "pr" ]; then
    cp "$PARENT_DIR/terraform/variables.tf.prerelease" "$PARENT_DIR/terraform/variables.tf"
    init_and_apply_terraform
elif [ "$RUN_TERRAFORM" == "n" ]; then
    echo "Skipping Terraform..."
else
    echo "Invalid option. Exiting..."
    exit 1
fi

# Read the load balancer DNS name from lb_url.txt
LB_URL=$(cat "$PARENT_DIR/lb_url.txt")

# Optionally run Ansible playbook to setup services
if [ "$RUN_SETUP" == "y" ]; then
    cd "$PARENT_DIR/playbooks"
    set_network_vars || exit 1

    # Check if the desired snarkOS binary is present in S3. If it is not, create
    # an ephemeral builder machine, build the binary, upload it, then tear the
    # builder down before continuing with setup.
    VARS_FILE="$PARENT_DIR/playbooks/${VARS}.yml"
    SNARKOS_GIT_HASH=$(grep -E '^snarkos_git_hash:' "$VARS_FILE" | awk '{print $2}' | tr -d '"' | tr -d "'")
    FEATURES=$(grep -E '^features:' "$VARS_FILE" | awk '{print $2}' | tr -d '"' | tr -d "'" || true)
    S3_BUCKET=$(grep -E '^s3_bucket:' "$VARS_FILE" | awk '{print $2}' | tr -d '"' | tr -d "'" || true)
    S3_BUCKET="${S3_BUCKET:-$RELEASE_BUCKET}"

    # Mirror the release_name Jinja2 expression from vars.yml:
    # snarkos_git_hash[_features]
    RELEASE_NAME="$SNARKOS_GIT_HASH"
    [[ -n "$FEATURES" ]] && RELEASE_NAME="${RELEASE_NAME}_${FEATURES}"

    if aws s3api head-object --bucket "$S3_BUCKET" --key "$RELEASE_NAME" \
         --profile ephnet &>/dev/null; then
        echo "snarkOS binary '$RELEASE_NAME' found in S3, skipping build."
    else
        echo "snarkOS binary '$RELEASE_NAME' not found in S3 bucket $S3_BUCKET. Creating ephemeral builder machine..."

        cd "$PARENT_DIR/terraform"
        terraform apply \
            -target=aws_iam_policy.snarkos_s3_access \
            -target=aws_iam_role_policy_attachment.snarkos_s3_access_attach \
            -target=aws_instance.snarkos_builder \
            -var="owner=$OWNER" -var="add_builder=true" -auto-approve

        echo "Waiting for builder EC2 instance to reach running state..."
        # NOTE: polling using the aws-cli may have different behaviour and
        # should only be re-attempted after we unified the usage of --profile on
        # local v.s. remote invocations.
        sleep 30

        BUILDER_IP=$(cd "$PARENT_DIR/terraform" && TF_CLI_ARGS="-no-color" terraform output -raw snarkos_builder_ip)
        if [[ -z "$BUILDER_IP" ]]; then
            echo "ERROR: Could not retrieve builder public IP from Terraform output."
            exit 1
        fi
        echo "Builder instance is running at $BUILDER_IP"

        # Use a one-shot static inventory so the playbook is never subject to
        # EC2 tag-propagation delays in the dynamic inventory.
        BUILDER_INVENTORY="$PARENT_DIR/builder_inventory.tmp"
        cat > "$BUILDER_INVENTORY" <<BUILDERINV
[builder]
${BUILDER_IP} ansible_user=ubuntu
BUILDERINV

        cd "$PARENT_DIR/playbooks"
        ansible-playbook -i "$BUILDER_INVENTORY" build_binary.yml \
            --extra-vars="devnet_name=${DEVNET_NAME}" \
            --extra-vars="snarkos_network=${NETWORK}" \
            --extra-vars="snarkos_network_int=${NETWORK_INT}" \
            --extra-vars="base_workspace_folder=${PARENT_DIR}/playbooks" \
            --extra-vars="@${VARS}.yml"
        rm -f "$BUILDER_INVENTORY"

        echo "Build complete. Destroying ephemeral builder..."
        cd "$PARENT_DIR/terraform"
        terraform destroy -target=aws_instance.snarkos_builder \
            -var="owner=$OWNER" -var="add_builder=true" -auto-approve
        cd "$PARENT_DIR/playbooks"
    fi

    ansible-playbook -i "$INVENTORY_DIR" setup.yml \
      --limit "$LIMIT" \
      --extra-vars="devnet_name=${DEVNET_NAME}" \
      --extra-vars="snarkos_network=${NETWORK}" \
      --extra-vars="snarkos_network_int=${NETWORK_INT}" \
      --extra-vars "test_network_url=${LB_URL}" \
      --extra-vars="base_workspace_folder=${PARENT_DIR}/playbooks" \
      --extra-vars="@${VARS}.yml"

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
            rc=${PIPESTATUS[0]}

            # Download + analyse this test's logs (as the old script did per test)
            download_and_upload_logs
            (( rc == 0 )) || exit "$rc"
        done

    # We have a special case for the prerelease ones too:
    elif [ "$SELECTED" == "prerelease" ]; then
        echo Running prerelease tests...

        mapfile -t PRERELEASE_TESTS < <(printf "%s\n" "${TESTS[@]}" | grep '^prerelease_')
        for test in "${PRERELEASE_TESTS[@]}"; do
            export SELECTED=$test
            run_test

            echo "Test finished successfully : $test"

            # Download + analyse this test's logs (as the old script did per test)
            download_and_upload_logs
        done

    # Run a comma-separated list of tests in sequence
    elif [[ "$SELECTED" == *,* ]]; then
        echo "Running tests in sequence: $SELECTED"
        IFS=',' read -ra SELECTED_TESTS <<< "$SELECTED"
        for test in "${SELECTED_TESTS[@]}"; do
            # Trim surrounding whitespace so "test1, test2" works as well as "test1,test2"
            test=$(echo "$test" | xargs)
            export SELECTED=$test
            run_test | tee -a "$PARENT_DIR/observability_runner.log"
            rc=${PIPESTATUS[0]}

            # Download + analyse this test's logs (as the old script did per test)
            download_and_upload_logs
            (( rc == 0 )) || exit "$rc"
        done

    # Else run the selected test
    else
        run_test | tee -a "$PARENT_DIR/observability_runner.log"
        rc=${PIPESTATUS[0]}

        # Download + analyse this test's logs (as the old script did per test)
        download_and_upload_logs
        (( rc == 0 )) || exit "$rc"
    fi
fi

# Optionally select utility to run
if [ "$RUN_UTILITIES" == "y" ]; then
    if [[ -n "$ARG_UTILITY" ]]; then
        export SELECTED="$ARG_UTILITY"
    else
        # shellcheck source=./select_utility.sh
        source "$PARENT_DIR/select_utility.sh"
    fi
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
        if [[ "$SELECTED" == download_* ]]; then
            if runner_manages_logs; then
                # The external runner issues one download utility per invocation
                # and expects them to accumulate, so never wipe between calls;
                # it clears/rotates log_files itself between test cases.
                mkdir -p "$PARENT_DIR/log_files"
            else
                prepare_log_files_dir
            fi
        fi


        run_utility | tee -a "$PARENT_DIR/observability_runner.log"
    fi
fi

# Remind of cleanup the infrastructure
echo "Please remember to destroy the infrastructure with './run_test_suite.sh destroy' after testing work is done..."
