#!/bin/bash

# Function to clean up resources using Terraform
cleanup() {
    echo "An error occurred. Destroying infrastructure to avoid unnecessary costs..."
    read -p "Press ENTER to destroy the infrastructure or CTRL+C to cancel..."
    terraform destroy -auto-approve
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

# Initialize Terraform
echo "Initializing Terraform..."
cd terraform
terraform init

# Apply Terraform configuration
echo "Creating infrastructure..."
terraform apply -auto-approve

# Run Ansible playbook to configure the nodes
echo "Configuring nodes with Ansible..."
cd ../playbooks
ansible-playbook main.yml
ansible-playbook tests.yml -e "use_fake_execute=true"

# Sleep for 10 minutes to collect data
echo "Waiting for 10 minutes to collect data..."
sleep 600

# Stop the snarkos nodes
echo "Stopping the snarkos nodes..."
ansible-playbook stop-snarkos.yml

# Sleep for 30 seconds to allow the nodes to finish writing logs
echo "Waiting for 30 seconds to allow the nodes to finish writing logs..."
sleep 30

# Collect logs and ledgers
echo "Starting to collect logs and ledgers..."
cd ../terraform
terraform output -json validator_ips > output.json
jq -r '.[]' output.json > validator_ips.txt
./copy_logs_from_aws.sh
./copy_ledgers_from_aws.sh

# Optionally, wait for user input before destroying the infrastructure
read -p "Press ENTER to destroy the infrastructure or CTRL+C to cancel..."

# Destroy the infrastructure
echo "Destroying infrastructure..."
cd ../terraform
terraform destroy -auto-approve -parallelism=200