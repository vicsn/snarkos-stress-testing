#!/usr/bin/env bash
# full_run.sh — compose the fine-grained entrypoints into a whole run.
#
#   full_run.sh --mode=light --vars=vars --tests=all
#   full_run.sh --mode=heavy --tests=t1,t2,t3 --queue --group=devnet --parallel=3
#
# Without --queue it runs phases sequentially in this shell (old behaviour).
# With --queue it enqueues each phase into pueue, wiring dependencies so tests
# only start once setup succeeds, and a failed provision cancels everything.
set -euo pipefail
BIN="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/bin"
# shellcheck source=/dev/null
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

MODE="light"; TESTS_ARG="all"; UTIL=""; QUEUE=0; GROUP="default"; PARALLEL=1
for arg in "$@"; do
  case "$arg" in
    --mode=*)     MODE="${arg#*=}" ;;
    --vars=*)     VARS="${arg#*=}"; export VARS ;;
    --tests=*)    TESTS_ARG="${arg#*=}" ;;
    --utility=*)  UTIL="${arg#*=}" ;;
    --queue)      QUEUE=1 ;;
    --group=*)    GROUP="${arg#*=}" ;;
    --parallel=*) PARALLEL="${arg#*=}" ;;
    *) die "Unknown argument: $arg" ;;
  esac
done

# Resolve the test list once, here, where discovery lives. The fine-grained
# jobs each take a single --test.
discover_tests
resolve_tests() {
  case "$TESTS_ARG" in
    all)        printf '%s\n' "${TESTS[@]}" | grep -v '^_' ;;
    prerelease) printf '%s\n' "${TESTS[@]}" | grep '^prerelease_' ;;
    *)          tr ',' '\n' <<<"$TESTS_ARG" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' ;;
  esac
}
mapfile -t RUN_TESTS < <(resolve_tests)

# RUN_ID is exported by common.sh and (crucially) snapshotted by pueue at
# `pueue add` time, so every enqueued job shares this run's S3 prefix.
echo "RUN_ID=$RUN_ID  mode=$MODE  vars=$VARS  tests=${RUN_TESTS[*]:-none}"
notify_run_banner "🚀 Run \`$RUN_ID\` — mode=$MODE vars=$VARS tests=${RUN_TESTS[*]:-none}"

if (( ! QUEUE )); then
  # ---- Sequential, in-process. Each entrypoint opens/closes its own thread. ----
  "$BIN/provision.sh" --mode="$MODE" --vars="$VARS"
  "$BIN/setup.sh" --vars="$VARS"
  for t in "${RUN_TESTS[@]}"; do "$BIN/run-test.sh" --test="$t" --vars="$VARS"; done
  [[ -n "$UTIL" ]] && "$BIN/run-utility.sh" --utility="$UTIL" --vars="$VARS"
  echo "Done. Remember: $BIN/destroy.sh when finished."
  exit 0
fi

# ---- Enqueue into pueue ----
command -v pueue >/dev/null || die "pueue not found on PATH."
pueue group add "$GROUP" 2>/dev/null || true
pueue parallel --group "$GROUP" "$PARALLEL" || true

# Enqueue one job. pueue runs each task through the system shell (sh -c), so we
# build a single, shell-escaped command string with `printf %q` and hand that to
# `pueue add`. This is robust to spaces/metacharacters in $BIN or args — passing
# the words "raw" after -- wouldn't be, since pueue re-joins them with plain
# spaces before the shell re-parses them.
#
# We open the job's Slack thread first, then carry its ts into the task's
# environment so the task threads its own start/finish messages.
# `--print-task-id` prints just the numeric id (recent pueue); older versions
# print "New task added (id N)" — parse that instead if needed.
#
#   enqueue <label> [pueue-opts...] -- <cmd> [args...]
enqueue() {
  local label="$1"; shift
  local -a opts=() cmd=()
  while (($#)); do                      # split pueue options from the argv on `--`
    if [[ "$1" == "--" ]]; then shift; cmd=("$@"); break; fi
    opts+=("$1"); shift
  done
  local cmd_str; printf -v cmd_str '%q ' "${cmd[@]}"   # shell-safe command string
  local ts; ts="$(notify_open_for_enqueue "$label")"
  SLACK_THREAD_TS="$ts" SLACK_JOB_NAME="$label" \
    pueue add --print-task-id --group "$GROUP" ${opts[@]+"${opts[@]}"} -- "$cmd_str"
}

PROV=$(enqueue  "provision:$MODE"          -- "$BIN/provision.sh" "--mode=$MODE" "--vars=$VARS")
SETUP=$(enqueue "setup"   --after "$PROV"  -- "$BIN/setup.sh" "--vars=$VARS")
for t in "${RUN_TESTS[@]}"; do
  enqueue "run-test:$t"   --after "$SETUP" -- "$BIN/run-test.sh" "--test=$t" "--vars=$VARS" >/dev/null
done
[[ -n "$UTIL" ]] && enqueue "run-utility:$UTIL" --after "$SETUP" -- "$BIN/run-utility.sh" "--utility=$UTIL" "--vars=$VARS" >/dev/null

echo "Enqueued provision($PROV) -> setup($SETUP) -> ${#RUN_TESTS[@]} test job(s) in group '$GROUP' (parallel=$PARALLEL)."
echo "Watch with: pueue status --group $GROUP"
