#!/bin/bash

network_id=$1
network_name=$2
port=$3

checkpoint_interval=1000000
jwt_secret="ZGJjaGVja3BvaW50dGVzdA=="
jwt_ts=1749116345
jwt="eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJhbGVvMXJoZ2R1NzdoZ3lxZDN4amo4dWN1M2pqOXIya3J3ejZtbnp5ZDgwZ25jcjVmeGN3bGg1cnN2enA5cHgiLCJpYXQiOjE3NDkxMTYzNDUsImV4cCI6MjA2NDQ3NjM0NX0.qm2idfIm4ZTFOsyT19lH9pcWzzAtP5mbymkN4oL6_sc"

# Example command to start a syncing snarkOS node
# snarkos start --nodisplay --network $network_id --client --jwt-secret $jwt_secret --jwt-timestamp $jwt_ts --rest 127.0.0.1:$port

last_height_seen=0
height_reached() {
  height=$(curl -s "http://127.0.0.1:$port/$network_name/block/height/latest" || echo "0")
  echo reached height $height
  if [[ "$height" =~ ^[0-9]+$ ]] && [ $height -ge $1 ]; then
    return 0
  fi
  if [[ "$height" =~ ^[0-9]+$ ]] && [ $last_height_seen -ge $height ]; then
    echo did not advance anymore
    exit 1
  fi
  return 1
}


echo generating checkpoint at start
curl -s -X "POST" -H "Authorization: Bearer $jwt" "http://127.0.0.1:$port/$network_name/db_backup?path=/tmp/checkpoint_${network_name}_start"

last_checkpoint_height=0
next_checkpoint_height=$checkpoint_interval
while true; do
  if height_reached "$next_checkpoint_height"; then
    echo generating checkpoint at $next_checkpoint_height
    curl -s -X "POST" -H "Authorization: Bearer $jwt" "http://127.0.0.1:$port/$network_name/db_backup?path=/tmp/checkpoint_${network_name}_${next_checkpoint_height}"
    last_checkpoint_height=$next_checkpoint_height
    next_checkpoint_height=$((next_checkpoint_height + $checkpoint_interval))
  fi
  echo sleeping for 30 seconds
  sleep 30
done

