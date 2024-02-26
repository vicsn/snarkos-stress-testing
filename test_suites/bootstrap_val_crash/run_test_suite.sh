#!/bin/bash

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
    terraform destroy -auto-approve -parallelism=50
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
terraform apply -auto-approve -parallelism=50

# Get the load balancer DNS name
LB_URL=$(terraform output -raw snarkos_lb_dns_name)

# Output snarkos IPs
echo "Outputting snarkos IPs..."
terraform output -json instance_ips > output.json && jq -r '.[]' output.json > ip_addresses.txt
FIRST_NODE_IP=$(head -n 1 ip_addresses.txt)
terraform output -json delayed_instance_ips > delayed_output.json && jq -r '.[]' delayed_output.json > delayed_ip_addresses.txt

# Run Ansible playbook to configure the nodes
echo "Configuring nodes with Ansible..."
echo "Using command: ansible-playbook -i dynamic_inventory.aws_ec2.yml snarkos_setup.yml -f 50 --extra-vars \"test_network_url=${LB_URL} first_node_ip=${FIRST_NODE_IP}\""
ansible-playbook -i dynamic_inventory.aws_ec2.yml snarkos_setup.yml -f 50 --extra-vars "test_network_url=${LB_URL} first_node_ip=${FIRST_NODE_IP}"


# Kill snarkos on certain nodes
echo "Killing snarkos on certain nodes..."
./kill_snarkos_nodes.sh

Delayed_NODE_IP=$(head -n 1 delayed_ip_addresses.txt)
# ensure that http://delayed_node_ip:3030/mainnet/latest/height is not reachable and store it in a boolean variable
delayed_node_reachable=false
if curl -s --head --request GET http://$Delayed_NODE_IP:3030/mainnet/latest/height | grep "200 OK" > /dev/null; then
    delayed_node_reachable=true
fi
echo "Delayed node reachable: $delayed_node_reachable, expected: false"

# Start delayed validator
echo "Starting delayed validator..."
./start_delayed_validator.sh

echo "Delayed validator started successfully."

echo "Sleep for 60 seconds to allow the delayed validator to catch up..."
sleep 60

# Wait for delayed validator to catch up
echo "Waiting for delayed validator to catch up..."
# wait till heights are the same or absolute difference is less than 1
tries=0
max_tries=360 # one hour
echo "Before loop"
while true; do
    delayed_height=$(curl -s --request GET http://$Delayed_NODE_IP:3030/mainnet/latest/height)
    first_node_height=$(curl -s --request GET http://$FIRST_NODE_IP:3030/mainnet/latest/height)
    echo "Delayed height: $delayed_height, First node height: $first_node_height"
    
    difference=$((delayed_height - first_node_height))
    if [ "${difference#-}" -le 1 ]; then
        break
    fi

    tries=$((tries+1))
    if [ "$tries" -ge "$max_tries" ]; then
        echo "Timed out waiting for delayed validator to catch up."
        exit 1
    fi
    
    sleep 10
done

# if tries is < than max_tries, and the old delayed_node_reachable is false, the experiment is successful. Otherwise, it is not.
if [ $delayed_node_reachable = false ]; then
    echo "Experiment successful, network passed the delayed validator test."
else
    echo "Experiment failed, network did not pass the delayed validator test."
    exit 1
fi

# Optionally, wait for user input before destroying the infrastructure
read -p "Press ENTER to destroy the infrastructure or CTRL+C to cancel..."

# Destroy the infrastructure
echo "Destroying infrastructure..."
terraform destroy -auto-approve -parallelism=50
