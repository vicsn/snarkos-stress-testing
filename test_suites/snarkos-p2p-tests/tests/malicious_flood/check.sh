#!/bin/bash

# Define the file containing IP addresses
ipFile="../../ip_addresses.txt"

# Error if no argument was passed.
if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <network>"
    exit 1
fi
# Set network from first argument.
network=$1

# Initialize maximum block height variable
maxBlockHeight=0

echo "Fetching the maximum block height from each node..."
while IFS= read -r ip
do
    # Fetch the latest block height from each IP
    blockHeight=$(curl -s "http://$ip:3030/$network/block/height/latest")

    # Update maxBlockHeight if the current block height is greater
    if [[ "$blockHeight" -gt "$maxBlockHeight" ]]; then
        maxBlockHeight=$blockHeight
    fi
done < "$ipFile"

echo "Maximum block height: $maxBlockHeight"

echo "Waiting for a minute to allow all nodes to reach the maximum block height..."
sleep 60

# Check that all nodes have reached the height of maxBlockHeight
echo "Verifying that all nodes have reached the maximum block height..."
allNodesUpdated=true
while IFS= read -r ip
do
    currentHeight=$(curl -s "http://$ip:3030/$network/block/height/latest")
    if [[ "$currentHeight" -lt "$maxBlockHeight" ]]; then
        allNodesUpdated=false
        echo "Node $ip has not reached the maximum block height of $maxBlockHeight. Current height: $currentHeight"
        break
    fi
done < "$ipFile"

if $allNodesUpdated; then
    echo "All nodes have reached the maximum block height."
else
    echo "Not all nodes have reached the maximum block height. Network did not pass the test. Aborting the hash check."
    exit 1
fi

# Initialize variable to store block hashes
blockHashes=""

echo "Fetching the block hash at the maximum block height from each node..."
while IFS= read -r ip
do
    # Fetch the block for the maxBlockHeight
    response=$(curl -s "http://$ip:3030/$network/block/$maxBlockHeight")
    blockHash=$(echo "$response" | jq -r '.block_hash')

    # Append the block hash to the blockHashes string
    blockHashes+="$blockHash "
done < "$ipFile"

# Use unique sorting of hashes to check if all are identical
uniqueHash=$(echo "$blockHashes" | tr ' ' '\n' | sort -u | tr '\n' ' ')

# Count unique hashes
uniqueCount=$(echo "$uniqueHash" | wc -w)

# Compare the number of unique hashes to determine if a fork has occurred
if [ "$uniqueCount" -eq 1 ]; then
    echo "No fork found, network passed the test"
else
    echo "Fork found, network did not pass the test"
fi
