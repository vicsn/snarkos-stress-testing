#!/bin/bash

isuint() { [[ "$1" =~ ^[0-9]+$ ]]; }

function select_utility() {
  echo "" >&2
  echo "=============================" >&2
  echo "" >&2
  echo "Select utility to run:" >&2

  index=0
  MAPPED_UTILITIES=()

  for utility in "${UTILITIES[@]}"; do
    echo "${index}) ${utility}" >&2
    MAPPED_UTILITIES+=("$utility")
    ((index++))
  done

  MAPPED_UTILITIES+=("upload_logs_to_s3")
  echo "${index}) upload_logs_to_s3" >&2

  NUM_OPTIONS=$((index))

  # Prompt and validate
  UTILITY_NUM=""
  while true; do
    if ! isuint "$UTILITY_NUM" || ((UTILITY_NUM < 0 || UTILITY_NUM > NUM_OPTIONS)); then
      # Only print error message if this is not the first iteration
      [[ -n "$UTILITY_NUM" ]] && echo "Invalid input. Please enter a number from 0 to $NUM_OPTIONS." >&2

      read -r -p "Enter the number of the utility to run: " UTILITY_NUM
    else
      break
    fi
  done

  echo "${MAPPED_UTILITIES[$((UTILITY_NUM))]}"
}

SELECTED=$(select_utility)
export SELECTED
