#!/bin/bash
parent_dir=$(pwd)
# Function to load environment variables from .env file
load_env() {
    if [ -f ".env" ]; then
        echo "Loading environment variables from .env file..."
        set -a  # Automatically export all variables
        source .env
        set +a
    else
        echo ".env file not found. Exiting..."
        exit 1
    fi
}

# Function to clean up resources using Terraform
cleanup() {
    echo "An error occurred. Destroying infrastructure to avoid unnecessary costs..."
    read -p "Press ENTER to destroy the infrastructure or CTRL+C to cancel..."
    cd "$parent_dir/single_region_devnet" && terraform destroy -auto-approve
}

# Set up trap to call cleanup function on any error
trap cleanup ERR

# Exit immediately if a command exits with a non-zero status.
set -e

# Optional: Exit if an undefined variable is used.
set -u

# Load environment variables
load_env

# Define key name
KEY_NAME="devnet-key"

# Check if the SSH key already exists, generate if not
cd single_region_devnet
if [ ! -f "${KEY_NAME}" ]; then
    echo "Generating SSH key..."
    ssh-keygen -t rsa -b 4096 -f "${KEY_NAME}" -N '' # -N '' specifies no passphrase
    chmod 400 "${KEY_NAME}"
    ssh-add "${KEY_NAME}"
    cp "${KEY_NAME}" "$parent_dir/multi_region_devnet/${KEY_NAME}"
    cp "${KEY_NAME}.pub" "$parent_dir/multi_region_devnet/${KEY_NAME}.pub"
    cp "${KEY_NAME}" "$parent_dir/ansible_commands/${KEY_NAME}"
    cp "${KEY_NAME}.pub" "$parent_dir/ansible_commands/${KEY_NAME}.pub"
    cp "${KEY_NAME}" "$parent_dir/150_client_devnet/${KEY_NAME}"
    cp "${KEY_NAME}.pub" "$parent_dir/150_client_devnet/${KEY_NAME}.pub"
else
    echo "SSH key already exists. Skipping generation..."
fi

# format variable file
chmod +x format_single_region.sh && ./format_single_region.sh

# Initialize Terraform
echo "Initializing Terraform..."
terraform init

# Apply Terraform configuration
echo "Creating infrastructure..."
terraform apply -auto-approve

# Get the load balancer DNS name
LB_URL=$(terraform output -raw snarkos_lb_dns_name)

# Run Ansible playbook to configure the nodes
echo "Configuring nodes with Ansible..."
cd ../ansible_commands && ansible-playbook -i dynamic_inventory.aws_ec2.yml snarkos_setup.yml -f 14

# Optionally, wait for user input before destroying the infrastructure
read -p "Press ENTER to destroy the infrastructure or CTRL+C to cancel..."

# Destroy the infrastructure
echo "Destroying infrastructure..."
cd "$parent_dir/single_region_devnet" && terraform destroy -auto-approve