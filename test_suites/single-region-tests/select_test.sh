#!/bin/bash

isuint() { [[ "$1" =~ ^[0-9]+$ ]]; }

function select_test() {
  NUM_TESTS=${#TESTS[@]}

  echo "" >&2
  echo "=============================" >&2
  echo "Select group of tests to run:" >&2
  echo "0) all tests" >&2
  echo "1) prerelease tests (prefixed with 'prerelease_' below)" >&2

  echo "" >&2
  echo "Select individual test to run:" >&2

  index=2
  MAPPED_TESTS=()

  for test in "${TESTS[@]}"; do
    # Skip the utility ones in the first group:
    [[ "$test" == _* ]] && continue

    echo "${index}) ${test}" >&2
    MAPPED_TESTS+=("$test")
    ((index++))
  done

  NUM_OPTIONS=$((index - 1))

  # Prompt and validate
  TEST_NUM=""
  while true; do
    if ! isuint "$TEST_NUM" || ((TEST_NUM < 0 || TEST_NUM > NUM_OPTIONS)); then
      # Only print error message if this is not the first iteration
      [[ -n "$TEST_NUM" ]] && echo "Invalid input. Please enter a number from 0 to $NUM_OPTIONS." >&2

      read -p "Enter the number of the test to run: " TEST_NUM
    else
      break
    fi
  done

  if [[ "$TEST_NUM" -eq 0 ]]; then
    echo "all"
  elif [[ "$TEST_NUM" -eq 1 ]]; then
    echo "prerelease"
  else
    echo "${MAPPED_TESTS[$((TEST_NUM - 2))]}"
  fi
}

SELECTED=$(select_test)
export SELECTED
