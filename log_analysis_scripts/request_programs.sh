#!/bin/bash

# Variables for block heights
start_height=0
end_height=50

# Base URL
base_url="http://$1:3030/mainnet"

echo using base_url: $base_url

# Function to fetch blocks and process ALEO matches
fetch_blocks_and_process_aleo() {
  # Make the curl request for blocks
  response=$(curl -s "$base_url/blocks?start=$start_height&end=$end_height")

  # Extract .aleo matches but exclude credits.aleo
  matches=$(echo "$response" | grep -oE '\b\w+\.aleo\b' | grep -v 'credits\.aleo')

  # Loop through the matches and make requests for programID
  for programID in $matches; do
    echo "Fetching program for: $programID" at heights $start_height-$end_height
    curl "$base_url/program/$programID"
  done
}

# Loop to continuously fetch blocks and process them
while true; do
  fetch_blocks_and_process_aleo

  # Increment the heights for the next batch
  start_height=$((end_height + 1))
  end_height=$((start_height + 49))

  # Break condition if you want to stop at a certain block height
  if [ "$start_height" -gt 100000 ]; then  # Set a condition for max height
    break
  fi

  # Sleep for a short period to avoid spamming requests
  sleep 2
done

