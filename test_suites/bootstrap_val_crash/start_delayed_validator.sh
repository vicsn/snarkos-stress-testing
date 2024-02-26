#!/bin/bash

# Extract the delayed IP address
delayed_ip_address=$(head -n 1 delayed_ip_addresses.txt)

# Extract the first node IP address
first_node_ip_address=$(head -n 1 ip_addresses.txt)

# Count the number of non-empty lines in ip_addresses.txt
number_of_lines_in_file=$(grep -cve '^\s*$' ip_addresses.txt)

# Calculate number_of_lines_in_file + 1
number_of_lines_in_file_plus_one=$((number_of_lines_in_file + 1))

# Connect to the server and run the commands in the background
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ubuntu@$delayed_ip_address << EOF
sudo -i <<'EOSUDO'
nohup /root/.cargo/bin/snarkos start --metrics --nodisplay --bft 0.0.0.0:5000 --rest 0.0.0.0:3030 --peers $first_node_ip_address:4130 --validators $first_node_ip_address:5000 --verbosity 1 --dev $number_of_lines_in_file --dev-num-validators $number_of_lines_in_file_plus_one --validator > /dev/null 2>&1 &
EOSUDO
EOF
