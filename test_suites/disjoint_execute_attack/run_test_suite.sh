#!/bin/bash
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
    terraform destroy -auto-approve -parallelism=200
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

# Initialize Terraform
echo "Initializing Terraform..."
terraform init

# Apply Terraform configuration
echo "Creating infrastructure..."
terraform apply -auto-approve -parallelism=200

# Get the load balancer DNS name
LB_URL=$(terraform output -raw west1-lb)

# Output snarkos IPs
echo "Outputting snarkos IPs..."
terraform output -json snarkos_node_public_ips > output_snarkos_nodes.json && jq -r '.[]' output_snarkos_nodes.json > ip_addresses_snarkos_nodes.txt

# Output tx-cannon IPs
echo "Outputting tx-cannon IPs..."
terraform output -json tx_cannon_node_public_ips > output_tx_cannon.json && jq -r '.[]' output_tx_cannon.json > ip_addresses_tx_cannon.txt

# Run Ansible playbook to configure the nodes
echo "Configuring nodes with Ansible..."
echo "Running command: ansible-playbook -i dynamic_inventory.aws_ec2.yml playbook_setup.yml --extra-vars test_network_url=${LB_URL} -f 50"
ansible-playbook -i dynamic_inventory.aws_ec2.yml playbook_setup.yml --extra-vars "test_network_url=${LB_URL}" -f 50

# Run tx-cannon to deploy the program
echo "Deploying program large_bhp_256_150.aleo with tx-cannon..."
tx-cannon deploy -p large_bhp_256_150.aleo -k APrivateKey1zkp8CZNn3yeCseEtxuVPbDCwSyhGW6yZKUYKfgXmcpoGPWH -e http://${LB_URL}:3030

echo "Sleeping 60 seconds to allow the program to deploy..."
sleep 60

# Check http://${LB_URL}:3030/mainnet/program/large_bhp_256_150.aleo if the program is deployed
echo "Checking if the program is deployed..."
# if the curl response starts with "Something went wrong: Missing program for ID", then the program is not deployed. Otherwise, it is deployed
if [[ $(curl -s http://${LB_URL}:3030/mainnet/program/large_bhp_256_150.aleo) == "Something went wrong: Missing program for ID"* ]]; then
    echo "Program not deployed. Exiting... Please destroy the infrastructure manually using:"
    echo "terraform destroy -auto-approve -parallelism=200"
    exit 1
else
    echo "Program deployed successfully!"
fi

# upload attack_manifest.toml to tx-cannon
echo "Uploading attack_manifest.toml to the tx-cannons..."
./upload_files.sh

# print block height before the attack
echo "Block height before the attack:"
curl -s http://${LB_URL}:3030/mainnet/latest/height
echo ""

# execute the attack
echo "Executing the attack..."
ansible-playbook -i dynamic_inventory.aws_ec2.yml playbook_attack.yml --extra-vars "test_network_url=${LB_URL}" --user ubuntu --private-key ./devnet-key -f 50

echo "Now, please wait and see what happens to block production on Grafana ..."
echo "If you'd like to restart the nodes, you can run this command: ansible-playbook -i dynamic_inventory.aws_ec2.yml stop_and_restart_snarkos.yml --user ubuntu --private-key ./devnet-key -f 50"

# Optionally, wait for user input before destroying the infrastructure
read -p "Press ENTER to destroy the infrastructure or CTRL+C to cancel..."

# Destroy the infrastructure
echo "Destroying infrastructure..."
terraform destroy -auto-approve -parallelism=200
