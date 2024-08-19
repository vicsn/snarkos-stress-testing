#!/bin/bash

# Directory to store remote ledger directories
LOCAL_LEDGER_DIR="aws-ledgers"

# Create the local ledger directory if it does not exist
mkdir -p "$LOCAL_LEDGER_DIR"

# Read IP addresses from validator_ips.txt
IP_ADDRESSES=()
while IFS= read -r line; do
    IP_ADDRESSES+=("$line")
done < validator_ips.txt

echo "Copying ledger directories from ${#IP_ADDRESSES[@]} AWS EC2 instances."

# Define a function to copy ledger directories from a node
copy_ledger() {
  local IP_ADDRESS=$1
  local LEDGER_INDEX=$2
  local LOCAL_LEDGER_DIR=$3

  # Find the ledger directory on the remote server
  REMOTE_LEDGER_DIR=$(ssh -o StrictHostKeyChecking=no "ubuntu@$IP_ADDRESS" "find /home/ubuntu/ -type d -name '.ledger-0-*'")

  # Check if the remote ledger directory was found
  if [ -z "$REMOTE_LEDGER_DIR" ]; then
    echo "Ledger directory not found on $IP_ADDRESS."
    return 1
  fi

  # Copy the ledger directory directly using scp
  scp -o StrictHostKeyChecking=no -r "ubuntu@$IP_ADDRESS:$REMOTE_LEDGER_DIR" "$LOCAL_LEDGER_DIR/ledger-$LEDGER_INDEX/"

  # Check the exit status of the SCP command
  if [ $? -eq 0 ]; then
    echo "Ledger directory from $IP_ADDRESS copied successfully to ledger-$LEDGER_INDEX."
  else
    echo "Failed to copy ledger directory from $IP_ADDRESS."
  fi
}

# Loop through IPs and copy ledger directories in parallel
for INDEX in "${!IP_ADDRESSES[@]}"; do
  copy_ledger "${IP_ADDRESSES[$INDEX]}" "$INDEX" "$LOCAL_LEDGER_DIR" &
done

# Wait for all background jobs to finish
wait