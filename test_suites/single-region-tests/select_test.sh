#!/bin/bash

function isuint() {
  [ "$1" ] && [ -z "${1//[0-9]/}" ]
}

function select_test() {
  NUM_TESTS=${#TESTS[@]}
  echo "Select test to run:" >&2
  echo "0) all tests" >&2
  for i in "${!TESTS[@]}"; do
    echo "$((i + 1))) ${TESTS[$i]}" >&2
  done
  read -p "Enter the number of the test to run: " TEST_NUM

  while ! isuint "$TEST_NUM" || ((TEST_NUM > NUM_TESTS)) ; do
    echo "Invalid input. Please enter a number." >&2
    read -p "Enter the number of the test to run: " TEST_NUM
  done
  # If using 0, then all tests should run in series.
  if [ "$TEST_NUM" -eq 0 ]; then
    echo "all"
  # Else return the selected test.
  else
    echo "${TESTS[$((TEST_NUM - 1))]}"
  fi
}

SELECTED=$(select_test)
export SELECTED
