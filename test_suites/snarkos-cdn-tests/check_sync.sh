#!/usr/bin/env bash
# Periodically check sync progress for each URL in network_info.json and persist state.
# Usage: check_sync.sh [-n NETWORK] [-f JSON_FILE] [-i MINUTES] [-t TIMEOUT] [-w SECONDS] [-S SECONDS] [-D DELTA] [-O] [-v]
#   -n network (mainnet|testnet|canary); default: from playbooks/.network if set by run_client_sync_test.sh, else testnet
#   -f path to JSON (default: ./playbooks/network_info.json)
#   -i minutes between checks (default: 1)
#   -t curl max-time seconds (default: 6) [connect timeout is 3s]
#   -w seconds to fail when endpoint is unavailable or current<initial (default: 7200 = 2h)
#   -S seconds to fail when no progress (stall window, default: 600 = 10m)
#   -D success delta (height increase from initial to declare success, default: 1000000)
#   -O run once and exit
#   -v verbose (bash -x)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
JSON_FILE="./playbooks/network_info.json"
INTERVAL_MIN=1
CURL_TIMEOUT=6
CONNECT_TIMEOUT=3
UNAVAILABLE_FAIL_SECS=7200
STALL_FAIL_SECS=600
SUCCESS_DELTA=1000000
RUN_ONCE=0
VERBOSE=0
# Default NETWORK: from playbooks/.network (set by run_client_sync_test.sh) or testnet
if [[ -f "${SCRIPT_DIR}/playbooks/.network" ]]; then
  NETWORK="$(tr -d '[:space:]' < "${SCRIPT_DIR}/playbooks/.network")"
fi
[[ -z "${NETWORK:-}" ]] && NETWORK=testnet

while getopts ":n:f:i:t:w:S:D:Ovh" opt; do
  case "$opt" in
    n) NETWORK="$OPTARG" ;;
    f) JSON_FILE="$OPTARG" ;;
    i) INTERVAL_MIN="$OPTARG" ;;
    t) CURL_TIMEOUT="$OPTARG" ;;
    w) UNAVAILABLE_FAIL_SECS="$OPTARG" ;;
    S) STALL_FAIL_SECS="$OPTARG" ;;
    D) SUCCESS_DELTA="$OPTARG" ;;
    O) RUN_ONCE=1 ;;
    v) VERBOSE=1 ;;
    h) echo "Usage: $0 [-n NETWORK] [-f JSON_FILE] [-i MINUTES] [-t TIMEOUT] [-w SECONDS] [-S SECONDS] [-D DELTA] [-O] [-v]"; exit 0 ;;
    \?) echo "Invalid option: -$OPTARG" >&2; exit 2 ;;
    :)  echo "Option -$OPTARG requires an argument." >&2; exit 2 ;;
  esac
done
[[ "$VERBOSE" -eq 1 ]] && set -x

num() { case "$1" in (""|*[!0-9]*) return 1;; esac; }
num "$UNAVAILABLE_FAIL_SECS" || { echo "Invalid -w '$UNAVAILABLE_FAIL_SECS' (must be seconds)"; exit 2; }
num "$STALL_FAIL_SECS"       || { echo "Invalid -S '$STALL_FAIL_SECS' (must be seconds)"; exit 2; }
num "$SUCCESS_DELTA"         || { echo "Invalid -D '$SUCCESS_DELTA' (must be integer delta)"; exit 2; }
num "$INTERVAL_MIN"          || { echo "Invalid -i '$INTERVAL_MIN' (must be minutes)"; exit 2; }
num "$CURL_TIMEOUT"          || { echo "Invalid -t '$CURL_TIMEOUT' (must be seconds)"; exit 2; }

require() { command -v "$1" >/dev/null 2>&1 || { echo "Missing dependency: $1"; exit 2; }; }
require jq
require curl
require date

log() { echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] $*"; }

iso_now() { date -u +"%Y-%m-%dT%H:%M:%SZ"; }
iso_to_epoch() {
  local iso="$1"
  if date -u -d "$iso" +%s >/dev/null 2>&1; then
    date -u -d "$iso" +%s
  elif command -v gdate >/dev/null 2>&1; then
    gdate -u -d "$iso" +%s
  else
    date -u -j -f "%Y-%m-%dT%H:%M:%SZ" "$iso" +%s
  fi
}

jq_inplace() {
  # Pretty, atomic, hidden temp file; cleanup on error/signals
  local dir base tmp
  dir="$(dirname "$JSON_FILE")"
  base="$(basename "$JSON_FILE")"

  # Hidden temp file in the same directory for atomic mv
  tmp="$(mktemp "$dir/.${base}.tmp.XXXXXX")" || exit 2

  _cleanup_tmp() { rm -f "$tmp" 2>/dev/null || true; }
  trap _cleanup_tmp EXIT INT TERM

  if jq --indent 2 "$@" "$JSON_FILE" > "$tmp"; then
    mv -f "$tmp" "$JSON_FILE"
    trap - EXIT INT TERM   # disarm cleanup (we moved it)
  else
    _cleanup_tmp
    trap - EXIT INT TERM
    return 1
  fi
}

[[ -f "$JSON_FILE" ]] || { echo "JSON not found: $JSON_FILE"; exit 2; }
jq empty "$JSON_FILE" >/dev/null 2>&1 || { echo "Invalid JSON in $JSON_FILE"; exit 2; }

_cleanup_stale_tmps() {
  local dir base
  dir="$(dirname "$JSON_FILE")"
  base="$(basename "$JSON_FILE")"
  rm -f "$dir/${base}.tmp."* "$dir/.${base}.tmp."* 2>/dev/null || true
}
_cleanup_stale_tmps

# Single-instance lock (prevents two concurrent writers)
LOCKDIR="${JSON_FILE}.lockdir"
if ! mkdir "$LOCKDIR" 2>/dev/null; then
  echo "Another instance appears to be running (lock: $LOCKDIR)."; exit 3
fi
trap 'rmdir "'"$LOCKDIR"'" 2>/dev/null || true' EXIT INT TERM

get_keys() { jq -r 'keys[]' "$JSON_FILE"; }

# Ensure required fields exist so we can resume cleanly.
init_key() {
  local h="$1"
  # shellcheck disable=SC2016
  jq_inplace \
    --arg h "$h" \
    --argjson init "$h" \
    '(.[$h] //= {})
     | (.[$h].previous_height //= $init)
     | (.[$h].status //= "running")'
}

get_field()     { jq -r --arg h "$1" ".[\$h]$2 // empty" "$JSON_FILE"; }
set_field()     { jq_inplace --arg h "$1" --argjson v "$3" ".[\$h]$2 = \$v"; }
set_field_str() { jq_inplace --arg h "$1" --arg v "$3"      ".[\$h]$2 = \$v"; }

load_heights() {
  # Populate HEIGHTS with keys from JSON. Works on Bash 3.2 (macOS) and newer.
  if type -t mapfile >/dev/null 2>&1; then
    mapfile -t HEIGHTS < <(get_keys || true)
  else
    local out; out="$(get_keys || true)"
    # shellcheck disable=SC2206
    HEIGHTS=($out)
  fi
}

one_iteration() {
  local now_iso now_epoch
  now_iso="$(iso_now)"
  now_epoch="$(iso_to_epoch "$now_iso")"

  log "=== Iteration @ $now_iso ==="

  local -a HEIGHTS=()
  load_heights
  local count="${#HEIGHTS[@]}"
  log "Loaded ${count} height(s) from $JSON_FILE: ${HEIGHTS[*]:-<none>}"
  if (( count == 0 )); then
    log "No entries found. Exiting iteration."
    return 21
  fi

  local total="$count" n_success=0 n_failed=0

  for h in "${HEIGHTS[@]}"; do
    init_key "$h"

    local url status prev ts_iso ts_epoch init the
    url="$(get_field "$h" '.url')"
    status="$(get_field "$h" '.status')"
    prev="$(get_field "$h" '.previous_height')"
    ts_iso="$(get_field "$h" '.timestamp')"
    ts_epoch=""
    if [[ -n "$ts_iso" ]]; then
        ts_epoch="$(iso_to_epoch "$ts_iso")"
    fi
    init=$((10#$h))
    prev=${prev:-$init}
    the=$((init + SUCCESS_DELTA))

    log "[height=$h] BEGIN status=${status:-<none>} url=${url:-<none>} prev=$prev init=$init threshold=$the ts=${ts_iso:-<none>}"

    # Terminal states skip (still counted)
    if [[ "$status" == "success" ]]; then
      log "[height=$h] Already success → skip."; n_success=$((n_success+1)); continue
    fi
    if [[ "$status" == "failed" ]]; then
      log "[height=$h] Already failed  → skip."; n_failed=$((n_failed+1)); continue
    fi

    # Probe endpoint (log BEFORE hitting it so you see activity immediately)
    local endpoint="" current_raw="" current="" have_current=0
    if [[ -n "$url" ]]; then
      endpoint="http://${url}:3030/${NETWORK}/block/latest"
      log "[height=$h] Checking: $endpoint (timeout=${CURL_TIMEOUT}s, connect=${CONNECT_TIMEOUT}s)"
      if resp="$(
           curl -sS --fail \
                -H 'Accept: application/json' \
                --connect-timeout "$CONNECT_TIMEOUT" \
                --max-time "$CURL_TIMEOUT" \
                "$endpoint" 2>/dev/null
         )"; then
        current_raw="$(jq -r 'try .header.metadata.height // empty' <<<"$resp" 2>/dev/null || true)"
      fi
    else
      log "[height=$h] No URL configured."
    fi

    if [[ "$current_raw" =~ ^[0-9]+$ ]]; then
      have_current=1
      current="$current_raw"
      set_field "$h" '.current_height' "$current"
      log "[height=$h] Probe OK: current=$current"
    else
      log "[height=$h] Probe UNAVAILABLE (no/invalid height)."
    fi

    if [[ $have_current -eq 0 ]]; then
      set_field_str "$h" '.status' "waiting"
      if [[ -z "$ts_iso" ]]; then
        set_field_str "$h" '.timestamp' "$now_iso"
        ts_iso="$now_iso"; ts_epoch="$now_epoch"
        log "[height=$h] Set initial timestamp=$now_iso (unavailable)"
      fi
      if [[ -n "$ts_epoch" && $(( now_epoch - ts_epoch )) -ge UNAVAILABLE_FAIL_SECS ]]; then
        set_field_str "$h" '.status' "failed"
        log "[height=$h] FAIL: endpoint unavailable for ≥${UNAVAILABLE_FAIL_SECS}s since ts=$ts_iso → failed."
        n_failed=$((n_failed+1))
      else
        log "[height=$h] Waiting (unavailable), age=$(( ts_epoch>0 ? now_epoch-ts_epoch : 0 ))s threshold=${UNAVAILABLE_FAIL_SECS}s"
      fi
      log "[height=$h] END"
      continue
    fi

    if (( current < init )); then
      set_field_str "$h" '.status' "waiting"
      log "[height=$h] Regression: current($current) < initial($init) → waiting."
      if [[ -z "$ts_iso" ]]; then
        set_field_str "$h" '.timestamp' "$now_iso"
        ts_iso="$now_iso"; ts_epoch="$now_epoch"
        log "[height=$h] Set initial timestamp=$now_iso (regression)"
      fi
      if [[ -n "$ts_epoch" && $(( now_epoch - ts_epoch )) -ge UNAVAILABLE_FAIL_SECS ]]; then
        set_field_str "$h" '.status' "failed"
        log "[height=$h] FAIL: <initial for ≥${UNAVAILABLE_FAIL_SECS}s since ts=$ts_iso → failed."
        n_failed=$((n_failed+1))
      fi
      log "[height=$h] END"
      continue
    fi

    if (( current > the )); then
      set_field_str "$h" '.status' "success"
      log "[height=$h] SUCCESS: current($current) > threshold($the)."
      n_success=$((n_success+1))
      log "[height=$h] END"
      continue
    fi

    if (( current > prev )); then
      set_field "$h" '.previous_height' "$current"
      set_field_str "$h" '.status' "running"
      set_field_str "$h" '.timestamp' "$now_iso"
      log "[height=$h] ADVANCE: prev $prev → $current; status=running; timestamp=$now_iso"
      log "[height=$h] END"
      continue
    fi

    set_field_str "$h" '.status' "waiting"
    log "[height=$h] STALLED: current($current) <= prev($prev) → waiting."
    if [[ -z "$ts_iso" ]]; then
      set_field_str "$h" '.timestamp' "$now_iso"
      ts_iso="$now_iso"; ts_epoch="$now_epoch"
      log "[height=$h] Set initial timestamp=$now_iso (stalled)"
    fi
    if [[ -n "$ts_epoch" && $(( now_epoch - ts_epoch )) -ge STALL_FAIL_SECS ]]; then
      set_field_str "$h" '.status' "failed"
      log "[height=$h] FAIL: no progress for ≥${STALL_FAIL_SECS}s since ts=$ts_iso → failed."
      n_failed=$((n_failed+1))
    fi
    log "[height=$h] END"
  done

  log "--- Summary: success=${n_success}/${total}, failed=${n_failed}/${total} ---"
  if (( n_success == total )); then
    log "All ${total} succeeded. Exiting 0."; return 20
  fi
  if (( n_failed == total )); then
    log "All ${total} failed. Exiting 1."; return 21
  fi
  return 0
}

# Main loop
while :; do
  if one_iteration; then :; else
    code=$?
    [[ $code -eq 20 ]] && exit 0
    [[ $code -eq 21 ]] && exit 1
  fi
  if [[ "$RUN_ONCE" -eq 1 ]]; then
    log "Run-once mode: exiting after single iteration."; exit 0
  fi
  log "Sleeping ${INTERVAL_MIN} minute(s)…"
  sleep $(( INTERVAL_MIN * 60 ))
done
