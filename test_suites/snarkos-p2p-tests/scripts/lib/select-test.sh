#!/usr/bin/env bash
# lib/select-test.sh — interactive menu that LAUNCHES a test rather than running
# inline. Picks a name, then enqueues bin/run-test.sh (or runs inline when
# PUEUE_DISABLED=1). The menu prints to stderr; only invoked at a TTY.
#
# The menu itself stays local — each run-test.sh it launches delegates to the
# manager on its own.
set -euo pipefail
# shellcheck source=/dev/null
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

for arg in "$@"; do
  parse_tx_run_flag "$arg" || die "Unknown argument: $arg"
done
tx_flags=()
tx_run_flag_args tx_flags

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
  if [[ "$t" == "load_saved_transactions" ]]; then
    require_load_saved_transactions_flags
  fi
  "$BIN/run-test.sh" --test="$t" ${tx_flags[@]+"${tx_flags[@]}"}
done
echo "Launched ${#SELECTED_TESTS[@]} test job(s). (Assumes infra is already provisioned + set up.)"
