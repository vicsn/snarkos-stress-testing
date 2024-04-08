#!/bin/bash
parent_dir=$(pwd)
ulimit -n 2000
# Function to load environment variables from .env file
load_env() {
    if [ -f "../.env" ]; then
        echo "Loading environment variables from .env file..."
        set -a  # Automatically export all variables
        source ../.env
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
    cd "$parent_dir/terraform" && terraform destroy -auto-approve -parallelism=200
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
if [ ! -f "${KEY_NAME}" ]; then
    echo "Generating SSH key..."
    ssh-keygen -t rsa -b 4096 -f "${KEY_NAME}" -N '' # -N '' specifies no passphrase
    chmod 400 "${KEY_NAME}"
else
    echo "SSH key already exists. Skipping generation..."
fi

cd ./terraform 
# Initialize Terraform
echo "Initializing Terraform..."
terraform init

# Apply Terraform configuration
echo "Creating infrastructure..."
terraform apply -auto-approve -parallelism=200

# Get the load balancer DNS name
LB_URL=$(terraform output -raw snarkos_lb_dns_name)
echo "Load balancer URL: ${LB_URL}"

# Get validator IP addresses
echo "Getting validator IP addresses..."
terraform output -json validator_ips > output.json && jq -r '.[]' output.json > validator_ips.txt

# Run Ansible playbook to configure the nodes
echo "Configuring nodes with Ansible..."
echo "Running command: ansible-playbook -i dynamic_inventory.aws_ec2.yml snarkos_setup.yml -f 200 --extra-vars 'test_network_url=${LB_URL}' --private-key=../devnet-key"
cd ../ansible_commands && ansible-playbook -i dynamic_inventory.aws_ec2.yml snarkos_setup.yml -f 200 --extra-vars "test_network_url=${LB_URL}" --private-key=../devnet-key

# Run the attack
echo "Running the attack..."
echo "Running command: ansible-playbook -i dynamic_inventory.aws_ec2.yml attack.yml -f 200 --extra-vars 'test_network_url=${LB_URL}' --private-key=../devnet-key"
cd ../ansible_commands && ansible-playbook -i dynamic_inventory.aws_ec2.yml attack.yml -f 200 --extra-vars "test_network_url=${LB_URL}" --private-key=../devnet-key

# Optionally, wait for user input before destroying the infrastructure
read -p "Press ENTER to destroy the infrastructure or CTRL+C to cancel..."

# Destroy the infrastructure
echo "Destroying infrastructure..."
cd "$parent_dir/terraform" && terraform destroy -auto-approve -parallelism=200