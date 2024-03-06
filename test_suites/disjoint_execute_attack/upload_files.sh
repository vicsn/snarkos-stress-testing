#!/bin/bash

# Path to the file to be uploaded
FILE_TO_UPLOAD="attack_manifest.toml"

# Destination path on the remote server where the file will be stored
# This now targets the home directory of the 'ubuntu' user
REMOTE_DESTINATION_PATH="~/"

# SSH Private key for authentication
SSH_PRIVATE_KEY="devnet-key"

# Read IP addresses from ip_addresses_tx_cannon.txt
IP_ADDRESSES=()
while IFS= read -r line; do
    IP_ADDRESSES+=("$line")
done < ip_addresses_tx_cannon.txt

echo "Uploading file to ${#IP_ADDRESSES[@]} servers."

# Define a function to upload a file to a node
upload_file() {
  local IP_ADDRESS=$1
  local FILE_TO_UPLOAD=$2
  local REMOTE_DESTINATION_PATH=$3
  local SSH_PRIVATE_KEY=$4

  # Upload the file directly using scp with the specified SSH private key
  scp -o StrictHostKeyChecking=no -i "$SSH_PRIVATE_KEY" "$FILE_TO_UPLOAD" "ubuntu@$IP_ADDRESS:$REMOTE_DESTINATION_PATH"

  # Check the exit status of the SCP command
  if [ $? -eq 0 ]; then
    echo "File $FILE_TO_UPLOAD uploaded successfully to $IP_ADDRESS."
  else
    echo "Failed to upload $FILE_TO_UPLOAD to $IP_ADDRESS."
  fi
}

# Loop through IPs and upload the file in parallel
for IP_ADDRESS in "${IP_ADDRESSES[@]}"; do
  upload_file "$IP_ADDRESS" "$FILE_TO_UPLOAD" "$REMOTE_DESTINATION_PATH" "$SSH_PRIVATE_KEY" &
done

# Wait for all background jobs to finish
wait

echo "File upload process completed."
