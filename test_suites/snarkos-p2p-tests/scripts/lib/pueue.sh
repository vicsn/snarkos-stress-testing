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

# Separate from `default` so destroy can start immediately (it blocks on
# `pueue wait`) without taking a default-group slot, and so it is not gated
# by `--after` (which only fires on success).
PUEUE_TEARDOWN_GROUP="${PUEUE_TEARDOWN_GROUP:-teardown}"

pueue_ensure_group() {
  local g="$1"
  pueue group add "$g" >/dev/null 2>&1 || true
  pueue parallel -g "$g" 1 >/dev/null 2>&1 || true
}

# Build a shell-safe command string for `pueue add -- …`.
pueue_cmd_str() {
  local -a parts=(env PUEUE_WORKER=1 "PATH=${PATH}")
  parts+=("$@")
  printf -v PUEUE_CMD_STR '%q ' "${parts[@]}"
  PUEUE_CMD_STR=${PUEUE_CMD_STR% }
}

# pueue_enqueue <label> [pueue-opts...] -- <cmd> [args...]
# Echoes the new task id. Reuses SLACK_THREAD_TS when the run already
# opened a thread (full_run banner); otherwise notify_open_for_enqueue
# starts one.
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

# Run a full build → provision → setup → tests → destroy pipeline.
# tests_arg is the raw --tests= value from full_run.sh (e.g. "prerelease",
# "all", or "t1,t2"); we forward it to setup.sh so the ops-agent config gets
# stable `mode`/`tests` labels rather than an expanded per-run test list.
# Build runs first so a cache miss compiles on an ephemeral builder without
# paying for the validator fleet; a cache hit is a no-op.
run_pipeline() {
  local mode="$1" vars="$2" util="$3" tests_arg="$4"; shift 4
  local -a run_tests=("$@")
  local bin="$BIN"
  local -a tx_flags=()
  tx_run_flag_args tx_flags
  local -a prov_flags=()
  if [[ "${ADD_MASTER:-0}" == 1 ]]; then
    prov_flags+=("--add-master")
  fi

  local delay="${DELAY_BETWEEN_TESTS:-0}"

  if ! pueue_enabled; then
    local rc=0
    (
      "$bin/build.sh" --vars="$vars" --mode="$mode"
      "$bin/provision.sh" --mode="$mode" --vars="$vars" ${prov_flags[@]+"${prov_flags[@]}"}
      "$bin/setup.sh" --vars="$vars" --mode="$mode" --tests="$tests_arg"
      for t in "${run_tests[@]}"; do
        if (( delay > 0 )); then
          echo "Waiting ${delay}s between tests..."
          sleep "$delay"
        fi
        "$bin/run-test.sh" --test="$t" --vars="$vars" ${tx_flags[@]+"${tx_flags[@]}"}
      done
      if (( delay > 0 )); then
        echo "Waiting ${delay}s after tests..."
        sleep "$delay"
      fi
      [[ -n "$util" ]] && "$bin/run-utility.sh" --utility="$util" --vars="$vars" ${tx_flags[@]+"${tx_flags[@]}"}
    ) || rc=$?
    "$bin/destroy.sh" || true
    [[ $rc -eq 0 ]] || return "$rc"
    echo "Done (run=$RUN_ID)."
    return 0
  fi

  pueue_require
  pueue_ensure_group "$PUEUE_TEARDOWN_GROUP"

  local build prov setup dest
  local -a pipeline_ids=()
  build="$(pueue_enqueue "build" -- "$bin/build.sh" "--vars=$vars" "--mode=$mode")"
  pipeline_ids+=("$build")
  prov="$(pueue_enqueue "provision:$mode" --after "$build" -- "$bin/provision.sh" "--mode=$mode" "--vars=$vars" ${prov_flags[@]+"${prov_flags[@]}"})"
  pipeline_ids+=("$prov")
  setup="$(pueue_enqueue "setup" --after "$prov" -- "$bin/setup.sh" "--vars=$vars" "--mode=$mode" "--tests=$tests_arg")"
  pipeline_ids+=("$setup")

  local -a test_ids=() t
  if (( delay > 0 )); then
    local prev="$setup" first=1
    for t in "${run_tests[@]}"; do
      if (( first == 0 )); then
        prev="$(pueue_enqueue "wait-between-tests:${delay}s" --after "$prev" -- sleep "$delay")"
        pipeline_ids+=("$prev")
      fi
      first=0
      prev="$(pueue_enqueue "run-test:$t" --after "$prev" -- \
        "$bin/run-test.sh" "--test=$t" "--vars=$vars" ${tx_flags[@]+"${tx_flags[@]}"})"
      test_ids+=("$prev")
    done
  else
    for t in "${run_tests[@]}"; do
      test_ids+=("$(pueue_enqueue "run-test:$t" --after "$setup" -- \
        "$bin/run-test.sh" "--test=$t" "--vars=$vars" ${tx_flags[@]+"${tx_flags[@]}"})")
    done
  fi
  ((${#test_ids[@]})) && pipeline_ids+=("${test_ids[@]}")

  local util_id=""
  [[ -n "$util" ]] && util_id="$(pueue_enqueue "run-utility:$util" --after "$setup" \
    -- "$bin/run-utility.sh" "--utility=$util" "--vars=$vars" ${tx_flags[@]+"${tx_flags[@]}"})"
  [[ -n "$util_id" ]] && pipeline_ids+=("$util_id")

  # Teardown group: start now, block until pipeline ids are terminal (success,
  # failed, or dependency-failed). `--after` would skip destroy on any failure.
  # "$0"/$@ expand inside the worker, not at enqueue time.
  # shellcheck disable=SC2016
  dest="$(pueue_enqueue "destroy" --group "$PUEUE_TEARDOWN_GROUP" -- \
    bash -c 'pueue wait "$@" || true; exec "$0"' "$bin/destroy.sh" "${pipeline_ids[@]}")"

  echo "Enqueued build($build) -> provision($prov) -> setup($setup) -> ${#run_tests[@]} test job(s); destroy($dest) in group '$PUEUE_TEARDOWN_GROUP'."
  echo "Watch with: pueue status"
}
