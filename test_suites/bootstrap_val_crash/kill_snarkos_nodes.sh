#!/bin/bash

# Read IP addresses from file into an array
i=0
while IFS= read -r line; do
    ip_addresses[i]="$line"
    ((i++))
done < ip_addresses.txt

# Get the length of the array
n=${#ip_addresses[@]}

# Compute b as per given formula
b=$(( (n+1)*3/10 - 1 ))
b=${b%.*} # Taking the floor of b

echo "Stopping snarkos on the last $b nodes..."

# Specify the private key file for SSH
key_file="devnet-key"

# Loop through the last b IP addresses
for (( i=n-b; i<n; i++ )); do
  ip=${ip_addresses[$i]}
  
  # Connect to the server and execute the command
  echo "Connecting to $ip and stopping snarkos..."
  ssh -o StrictHostKeyChecking=no -i "$key_file" -t "ubuntu@$ip" "sudo systemctl stop snarkos.service"
done

echo "All snarkos nodes stopped successfully."