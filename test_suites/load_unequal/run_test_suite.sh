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

num_validators=$(wc -l < validator_ips.txt)

# Get client IP addresses
echo "Getting client IP addresses..."
terraform output -json client_public_ips > output.json && jq -r '.[]' output.json > client_ips.txt
CLIENT_IPS=$(cat client_ips.txt)

# Limit client IPs to the first 100
First_100_CLIENT_IPS=$(echo $CLIENT_IPS | cut -d ' ' -f 1-100)

# Get tx_cannon_public_ips
terraform output -json tx_cannon_public_ips > output.json && jq -r '.[]' output.json > tx_cannon_ips.txt
terraform output -json attacker_tx_cannon_public_ips > output.json && jq -r '.[]' output.json > attacker_tx_cannon_ips.txt

# Run Ansible playbook to configure the nodes
echo "Configuring nodes with Ansible..."
echo "Running command: ansible-playbook -i dynamic_inventory.aws_ec2.yml snarkos_setup_clients.yml -f 250 --extra-vars 'test_network_url=${LB_URL} client_ips=${First_100_CLIENT_IPS}' --private-key=../devnet-key"
cd ../ansible_commands && ansible-playbook -i dynamic_inventory.aws_ec2.yml snarkos_setup_clients.yml -f 250 --extra-vars "test_network_url=${LB_URL} client_ips='${First_100_CLIENT_IPS}'" --private-key=../devnet-key

# Get client IP addresses and ports
PORT_START=$((3030 + num_validators))
PORT=$PORT_START
CLIENT_IPS_AND_PORTS=""
for IP in $CLIENT_IPS; do
    if [ -z "$CLIENT_IPS_AND_PORTS" ]; then
        CLIENT_IPS_AND_PORTS="${IP}:${PORT}"
    else
        CLIENT_IPS_AND_PORTS="${CLIENT_IPS_AND_PORTS} ${IP}:${PORT}"
    fi
    PORT=$((PORT + 1))
done

cd ..

# Write IPs and ports to file
echo "$CLIENT_IPS_AND_PORTS" | tr ' ' '\n' > client_ips_and_ports.txt
echo "Client IPs and ports: $CLIENT_IPS_AND_PORTS"

# Run the network driver
echo "Running the network driver..."
echo "Running command: ansible-playbook -i dynamic_inventory.aws_ec2.yml network_driver_to_client.yml -f 200 --private-key=../devnet-key"
cd ./ansible_commands && ansible-playbook -i dynamic_inventory.aws_ec2.yml network_driver_to_client.yml -f 200 --private-key=../devnet-key

# Compute f based on num_validators which is 3f+1
f=$(( (num_validators - 1) / 3 ))
# add 1 to f
f=$((f + 1))

echo "Number of Byzantine nodes (f+1): $f"

cd ..
# Create a f_client_ips_and_ports.txt file with the first f client ips and ports
echo "Creating f_client_ips_and_ports.txt with the first $f client IPs and ports..."
head -n $f client_ips_and_ports.txt > f_client_ips_and_ports.txt

echo "f_client_ips_and_ports.txt created."

# Run the attack
echo "Running the attack..."
echo "Running command: ansible-playbook -i dynamic_inventory.aws_ec2.yml attack_to_client.yml -f 200 --private-key=../devnet-key"
cd ./ansible_commands && ansible-playbook -i dynamic_inventory.aws_ec2.yml attack_to_client.yml -f 200 --private-key=../devnet-key

# Optionally, wait for user input before destroying the infrastructure
read -p "Press ENTER to destroy the infrastructure or CTRL+C to cancel..."

# Destroy the infrastructure
echo "Destroying infrastructure..."
cd "$parent_dir/terraform" && terraform destroy -auto-approve -parallelism=200