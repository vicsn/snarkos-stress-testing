#!/usr/bin/env bash
# lib/pueue.sh — pueue dispatch helpers (sourced by common.sh).
#
# Queueing is on by default. Set PUEUE_DISABLED=1 to run jobs inline in the
# current shell. Enqueued tasks run with PUEUE_WORKER=1 so they do not re-enqueue.

[[ -n "${_PUEUE_SH_SOURCED:-}" ]] && return 0
_PUEUE_SH_SOURCED=1

BIN="${SCRIPTS_DIR}/bin"

pueue_enabled() { [[ "${PUEUE_DISABLED:-0}" != 1 ]]; }

pueue_require() {
  pueue_enabled || return 0
  command -v pueue >/dev/null || die "pueue not found on PATH."
}

# Build a shell-safe command string for `pueue add -- …`.
pueue_cmd_str() {
  local -a parts=(env PUEUE_WORKER=1 "PATH=${PATH}")
  parts+=("$@")
  printf -v PUEUE_CMD_STR '%q ' "${parts[@]}"
  PUEUE_CMD_STR=${PUEUE_CMD_STR% }
}

# pueue_enqueue <label> [pueue-opts...] -- <cmd> [args...]
# Echoes the new task id. Opens a Slack thread when notifications are enabled.
pueue_enqueue() {
  pueue_enabled || die "pueue_enqueue called while PUEUE_DISABLED=1"
  local label="$1"; shift
  local -a opts=() cmd=()
  while (($#)); do
    if [[ "$1" == "--" ]]; then shift; cmd=("$@"); break; fi
    opts+=("$1"); shift
  done
  pueue_cmd_str "${cmd[@]}"
  local ts; ts="$(notify_open_for_enqueue "$label")"
  SLACK_THREAD_TS="$ts" SLACK_JOB_NAME="$label" \
    pueue add --print-task-id ${opts[@]+"${opts[@]}"} -- "$PUEUE_CMD_STR"
}

# Enqueue this script unless queueing is disabled or we are already the worker.
# Usage: pueue_dispatch_self <label> [--after id...] -- "$0" [original args...]
pueue_dispatch_self() {
  pueue_enabled || return 0
  [[ "${PUEUE_WORKER:-0}" == 1 ]] && return 0

  local label="$1"; shift
  local -a opts=() cmd=()
  while (($#)); do
    if [[ "$1" == "--" ]]; then shift; cmd=("$@"); break; fi
    opts+=("$1"); shift
  done

  pueue_require
  local id; id="$(pueue_enqueue "$label" ${opts[@]+"${opts[@]}"} -- "${cmd[@]}")"
  echo "Enqueued $label (task $id). Watch: pueue status"
  exit 0
}

# Run a full provision → setup → tests → destroy pipeline.
run_pipeline() {
  local mode="$1" vars="$2" util="$3"; shift 3
  local -a run_tests=("$@")
  local bin="$BIN"

  if ! pueue_enabled; then
    "$bin/provision.sh" --mode="$mode" --vars="$vars"
    "$bin/setup.sh" --vars="$vars"
    local t
    for t in "${run_tests[@]}"; do "$bin/run-test.sh" --test="$t" --vars="$vars"; done
    [[ -n "$util" ]] && "$bin/run-utility.sh" --utility="$util" --vars="$vars"
    "$bin/destroy.sh"
    echo "Done (run=$RUN_ID)."
    return 0
  fi

  pueue_require
  local prov setup dest
  prov="$(pueue_enqueue "provision:$mode" -- "$bin/provision.sh" "--mode=$mode" "--vars=$vars")"
  setup="$(pueue_enqueue "setup" --after "$prov" -- "$bin/setup.sh" "--vars=$vars")"

  local -a test_ids=() t
  for t in "${run_tests[@]}"; do
    test_ids+=("$(pueue_enqueue "run-test:$t" --after "$setup" -- "$bin/run-test.sh" "--test=$t" "--vars=$vars")")
  done

  local util_id=""
  [[ -n "$util" ]] && util_id="$(pueue_enqueue "run-utility:$util" --after "$setup" \
    -- "$bin/run-utility.sh" "--utility=$util" "--vars=$vars")"

  if [[ ${#test_ids[@]} -eq 0 && -z "$util_id" ]]; then
    dest="$(pueue_enqueue "destroy" --after "$setup" -- "$bin/destroy.sh")"
  else
    local -a after=()
    ((${#test_ids[@]})) && after+=("${test_ids[@]}")
    [[ -n "$util_id" ]] && after+=("$util_id")
    dest="$(pueue_enqueue "destroy" --after "${after[@]}" -- "$bin/destroy.sh")"
  fi

  echo "Enqueued provision($prov) -> setup($setup) -> ${#run_tests[@]} test job(s) -> destroy($dest)."
  echo "Watch with: pueue status"
}
