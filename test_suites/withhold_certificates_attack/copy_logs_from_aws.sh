# run these 2 commands first from the other repo:
# terraform output -json instance_ips > output.json
# jq -r '.[]' output.json > ip_addresses.txt

#!/bin/bash

# Directory to store remote logs
LOCAL_LOG_DIR="aws-logs"

# Create the local log directory if it does not exist
mkdir -p "$LOCAL_LOG_DIR"

# Read IP addresses from ip_addresses.txt
IP_ADDRESSES=()
while IFS= read -r line; do
    IP_ADDRESSES+=("$line")
done < ip_addresses.txt

echo "Copying logs from ${#IP_ADDRESSES[@]} AWS EC2 instances."

# Define a function to copy logs from a node
copy_logs() {
  local IP_ADDRESS=$1
  local LOG_INDEX=$2
  local LOCAL_LOG_DIR=$3

  # Path to the log file on the remote server
  REMOTE_LOG_FILE="/tmp/snarkos.log"

  # Copy the log file directly using scp
  scp -o StrictHostKeyChecking=no "ubuntu@$IP_ADDRESS:$REMOTE_LOG_FILE" "$LOCAL_LOG_DIR/val-$LOG_INDEX.log"

  # Check the exit status of the SCP command
  if [ $? -eq 0 ]; then
    echo "val.log from $IP_ADDRESS copied successfully to val-$LOG_INDEX.log."
  else
    echo "Failed to copy val.log from $IP_ADDRESS."
  fi
}

# Loop through IPs and copy logs in parallel
for INDEX in "${!IP_ADDRESSES[@]}"; do
  copy_logs "${IP_ADDRESSES[$INDEX]}" "$INDEX" "$LOCAL_LOG_DIR" &
done

# Wait for all background jobs to finish
wait