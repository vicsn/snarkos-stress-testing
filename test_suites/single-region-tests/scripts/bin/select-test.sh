#!/usr/bin/env bash
# bin/select-test.sh [--queue] — interactive menu that LAUNCHES a test rather
# than running inline. Picks a name, then either runs run-test.sh directly or
# enqueues it. The menu prints to stderr; nothing here blocks a headless job
# because this is only ever invoked by a human at a TTY.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$HERE/../lib/common.sh"

QUEUE=0
for arg in "$@"; do [[ "$arg" == "--queue" ]] && QUEUE=1; done

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

# Expand the selection into concrete test names (same logic as full_run.sh).
resolve() {
  case "$1" in
    all)        printf '%s\n' "${TESTS[@]}" | grep -v '^_' ;;
    prerelease) printf '%s\n' "${TESTS[@]}" | grep '^prerelease_' ;;
    *)          echo "$1" ;;
  esac
}
mapfile -t SELECTED_TESTS < <(resolve "$TESTS_ARG")

if (( QUEUE )); then
  command -v pueue >/dev/null || die "pueue not found on PATH."
  for t in "${SELECTED_TESTS[@]}"; do
    pueue add -- "$HERE/run-test.sh --test=$t"
  done
  echo "Enqueued ${#SELECTED_TESTS[@]} test job(s). (Assumes infra is already provisioned + set up.)"
else
  for t in "${SELECTED_TESTS[@]}"; do "$HERE/run-test.sh" --test="$t"; done
fi
