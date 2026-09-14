#!/usr/bin/env bash
# bin/fetch-job-log.sh --job=ID
# Saves the full output of one pueue task to a temporary file and prints its
# path on stdout, so a long run's log can be opened or grepped instead of
# flooding the terminal:
#
#   less "$(scripts/bin/fetch-job-log.sh --job=7)"
#
# Task ids come from `pueue status` (scripts/lib/stm.sh pueue status), and are
# also echoed by every enqueue. Unlike the other bin/ entrypoints this neither
# delegates itself nor enqueues: it is a read, so it runs the `pueue log` on
# the manager but writes the file here, where you want to read it.
set -euo pipefail
# shellcheck source=/dev/null
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"

JOB=""
for arg in "$@"; do
  case "$arg" in
    --job=*) JOB="${arg#*=}" ;;
    *) die "Unknown argument: $arg (usage: $(basename "$0") --job=ID)" ;;
  esac
done
[[ -n "$JOB" ]] || die "--job=ID is required — the pueue task id from 'pueue status'."
isuint "$JOB" || die "--job must be a pueue task id (a number), got: $JOB"

# Timestamped rather than mktemp'd: re-fetching a still-running task gives a
# new file each time instead of silently overwriting the previous snapshot.
TMP_DIR="${TMPDIR:-/tmp}"
OUT="${TMP_DIR%/}/pueue-job-${JOB}-$(date -u +%Y%m%dT%H%M%SZ).log"

stm_run pueue log --full "$JOB" >"$OUT" \
  || { rm -f "$OUT"; die "Could not read pueue task $JOB — check 'pueue status' for the id."; }

if [[ -s "$OUT" ]]; then
  echo "Task $JOB: $(wc -l <"$OUT" | tr -d ' ') lines." >&2
else
  echo "Task $JOB produced no output yet (queued, or not started)." >&2
fi
echo "$OUT"
