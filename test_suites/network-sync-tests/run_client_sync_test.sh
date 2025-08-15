#!/bin/bash

ulimit -n 2048

PARENT_DIR=$(cd "$(dirname "$0")" && pwd)
bold=$(tput bold)
normal=$(tput sgr0)

TFSTATE_BUCKET="${TF_STATE_BUCKET:-ephnet-terraform-state-bucket-eq}"
export AWS_REGION="${TF_STATE_REGION:-us-west-2}"
RELEASE_BUCKET="${RELEASE_BUCKET:-provable-binaries-releases}"
export TF_RELEASE_BUCKET=$RELEASE_BUCKET

# Function to get highest height from snapshot URLs
get_highest_snapshot_height() {
    local snapshot_file="$1"
    local highest_height=0

    # Read the file line by line, ensuring the last line is processed
    while IFS= read -r line || [ -n "$line" ]; do
        if [[ $line =~ mainnet-([0-9]+)\.tar ]] || [[ $line =~ testnet-([0-9]+)\.tar ]]; then
            local height="${BASH_REMATCH[1]}"
            if [ "$height" -gt "$highest_height" ]; then
                highest_height=$height
            fi
        fi

        if [[ $line =~ testnet\/checkpoint_([0-9]+)\.zip ]] || [[ $line =~ mainnet\/checkpoint_([0-9]+)\.zip ]]; then
            local height="${BASH_REMATCH[1]}"
            if [ "$height" -gt "$highest_height" ]; then
                highest_height=$height
            fi
        fi
    done < "$snapshot_file"

    echo "$highest_height"
}

# Function to get current network height
get_current_network_height() {
    local network="$1"
    local height_url="https://api.explorer.provable.com/v1/${network}/latest/height"
    curl -s "$height_url"
}

# Function to check if snapshots are outdated
check_snapshot_freshness() {
    local network="$1"
    local snapshot_height="$2"
    local current_height="$3"

    # Note: we use snapshots from block heights every 5 days, with the goal that the test takes
    # about 1 day to complete. Thus, the snapshot links in `snapshot_urls_mainnet.txt` and
    # `snapshot_urls_testnet.txt` will be incomplete after ~5 days. This function triggers a
    # warning mesage in such cases. The spacing between the snapshot block heights differs
    # (since they were retrieved time based instead of block height based), but was recently up
    # to ~200k for mainnet and up to ~300k for testnet. Here, we use 1.5x these thresholds for
    # triggering the warnings, a somewhat arbitrary value.
    local threshold=300000  # Default for mainnet
    
    if [ "$network" == "testnet" ]; then
        threshold=450000
    fi
    
    local height_diff=$((current_height - snapshot_height))
    
    if [ "$height_diff" -gt "$threshold" ]; then
        echo "WARNING: The snapshots are significantly outdated!"
        echo "Current ${network} height: ${current_height}"
        echo "Latest snapshot height: ${snapshot_height}"
        echo "Difference: ${height_diff} blocks"
        echo "Threshold: ${threshold} blocks"
        
        while true; do
            read -p "Do you want to continue anyway? (y/n) " response
            case "$response" in
                [Yy]* ) return 0;;
                [Nn]* ) return 1;;
                * ) echo "Please answer y or n.";;
            esac
        done
    fi
    return 0
}

# Function to destroy infrastructure
destroy_infrastructure() {
    echo "Destroying infrastructure..."
    cd "$PARENT_DIR/terraform"
    terraform destroy -auto-approve -parallelism=50
}

# Function to clean up resources using Terraform
cleanup() {
    echo "An error occurred or finished. Destroying infrastructure to avoid unnecessary costs..."

    read -p "Press ENTER to destroy the infrastructure or CTRL+C to cancel..."

    destroy_infrastructure
}

set_devnet_vars() {
  export DEVNET_NAME=$(cd "$PARENT_DIR/terraform" && TF_CLI_ARGS="-no-color" terraform output -raw devnet_name)

  echo "devnet_name : $DEVNET_NAME"
}

# Function to init and apply Terraform
init_and_apply_terraform() {
    cd $PARENT_DIR/terraform
    terraform init -backend-config="bucket=${TFSTATE_BUCKET}"
    terraform apply

    # Save the load balancer DNS name
    terraform output -raw snarkos_lb_dns_name > $PARENT_DIR/lb_url.txt
    LB_URL=$(cat $PARENT_DIR/lb_url.txt)
    set_devnet_vars || exit 1

    # Save updated IP addresses
    cd "$PARENT_DIR/playbooks"
    ansible-playbook ips.yml --extra-vars="devnet_name=${DEVNET_NAME}" --extra-vars "test_network_url=${LB_URL} --extra-vars="snarkos_network=${NETWORK}" snarkos_network_int=${SNARKOS_NETWORK_INT}" --extra-vars="@vars.yml"

    if [ "$(uname)" == "Darwin" ]; then
        say "Finished running Terraform"
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

# Ask the user which network they want to run or if they want to skip
while true; do
    read -p "Do you want to run the network for testnet (t), mainnet (m), or skip and destroy (s)? " NETWORK_TYPE
    if [ "$NETWORK_TYPE" == "t" ] || [ "$NETWORK_TYPE" == "m" ] || [ "$NETWORK_TYPE" == "s" ]; then
        break
    else
        echo "Invalid option. Please enter 't' for testnet, 'm' for mainnet, or 's' to skip and destroy."
    fi
done

# Check if the user wants to skip
if [ "$NETWORK_TYPE" == "s" ]; then
    echo "Skipping network setup and proceeding to infrastructure destruction..."
    read -p "Press ENTER to destroy the infrastructure or CTRL+C to cancel..."
    destroy_infrastructure
    exit 0
fi

# Set the snarkos_network_int value based on user selection
if [ "$NETWORK_TYPE" == "t" ]; then
    SNARKOS_NETWORK_INT=1
    cp "$PARENT_DIR/playbooks/snapshot_urls_testnet.txt" "$PARENT_DIR/playbooks/snapshot_urls.txt"
    echo "Using testnet snapshot URLs."
    NETWORK="testnet"
else
    SNARKOS_NETWORK_INT=0
    cp "$PARENT_DIR/playbooks/snapshot_urls_mainnet.txt" "$PARENT_DIR/playbooks/snapshot_urls.txt"
    echo "Using mainnet snapshot URLs."
    NETWORK="mainnet"
fi

# Get highest snapshot height
SNAPSHOT_HEIGHT=$(get_highest_snapshot_height "$PARENT_DIR/playbooks/snapshot_urls.txt")
# Get current network height
CURRENT_HEIGHT=$(get_current_network_height "$NETWORK")

# Check if snapshots are outdated
if ! check_snapshot_freshness "$NETWORK" "$SNAPSHOT_HEIGHT" "$CURRENT_HEIGHT"; then
    echo "Exiting due to outdated snapshots."
    exit 1
fi

# Count ALL lines in the snapshot_urls.txt file (including empty ones)
# Use grep with a pattern that matches empty lines too
SNAPSHOT_COUNT=$(grep -c "^" "$PARENT_DIR/playbooks/snapshot_urls.txt" || echo "0")
echo "Number of snapshots: $SNAPSHOT_COUNT"

# Copy the variables template and replace NUMCLIENTS with the snapshot count
cp "$PARENT_DIR/terraform/variables.tf.template" "$PARENT_DIR/terraform/variables.tf"

# Handle sed differences between macOS and Linux
if [[ "$(uname)" == "Darwin" ]]; then
    # macOS (BSD) sed requires an extension parameter with -i
    sed -i '' "s/NUMCLIENTS/$SNAPSHOT_COUNT/g" "$PARENT_DIR/terraform/variables.tf"
    sed -i '' "s/NETWORK/$NETWORK/g" "$PARENT_DIR/terraform/variables.tf"
else
    # Linux (GNU) sed
    sed -i "s/NUMCLIENTS/$SNAPSHOT_COUNT/g" "$PARENT_DIR/terraform/variables.tf"
    sed -i "s/NETWORK/$NETWORK/g" "$PARENT_DIR/terraform/variables.tf"
fi

echo "Updated variables.tf with $SNAPSHOT_COUNT clients."

# Initialize and apply Terraform
init_and_apply_terraform

# Read the load balancer DNS name from lb_url.txt
LB_URL=$(cat $PARENT_DIR/lb_url.txt)

set_devnet_vars || exit 1

cd "$PARENT_DIR/playbooks"

ansible-playbook setup.yml \
  --extra-vars="devnet_name=${DEVNET_NAME}" \
  --extra-vars "test_network_url=${LB_URL} snarkos_network_int=${SNARKOS_NETWORK_INT}" \
  --extra-vars="base_workspace_folder=${PARENT_DIR}/playbooks" \
  --extra-vars="snarkos_network=${NETWORK}" \
  --extra-vars="@vars.yml"

if [ "$(uname)" == "Darwin" ]; then
    say "Finished running setup"
fi

# Wait for user input before destroying the infrastructure
read -p "Press ENTER to destroy the infrastructure or CTRL+C to cancel..."

# Call destroy_infrastructure function directly instead of cleanup
destroy_infrastructure
