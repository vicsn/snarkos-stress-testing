#!/usr/bin/env bash
# bin/select-test.sh — interactive menu that LAUNCHES a test rather than running
# inline. Picks a name, then enqueues run-test.sh (or runs inline when
# PUEUE_DISABLED=1). The menu prints to stderr; only invoked at a TTY.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$HERE/../lib/common.sh"

discover_tests
echo "Select a test to run:" >&2
echo "0) all (visible) tests" >&2
echo "1) prerelease tests" >&2
i=2; MAP=()
for t in "${TESTS[@]}"; do
  [[ "$t" == _* ]] && continue
  echo "$i) $t" >&2; MAP+=("$t"); ((i++))
done
N=$((i-1))

CHOICE=""
while ! isuint "$CHOICE" || (( CHOICE < 0 || CHOICE > N )); do
  [[ -n "$CHOICE" ]] && echo "Enter a number 0..$N." >&2
  read -r -p "Test number: " CHOICE
done

case "$CHOICE" in
  0) TESTS_ARG="all" ;;
  1) TESTS_ARG="prerelease" ;;
  *) TESTS_ARG="${MAP[$((CHOICE-2))]}" ;;
esac

mapfile -t SELECTED_TESTS < <(resolve_tests "$TESTS_ARG")

for t in "${SELECTED_TESTS[@]}"; do
  "$HERE/run-test.sh" --test="$t"
done
echo "Launched ${#SELECTED_TESTS[@]} test job(s). (Assumes infra is already provisioned + set up.)"
