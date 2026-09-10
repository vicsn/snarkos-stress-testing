#!/usr/bin/env bash
set -euo pipefail

# --- Config ---
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
IP_FILE="$SCRIPT_DIR/client_ip_addresses.txt"
KEY_FILE="$SCRIPT_DIR/devnet-key"

OUT_DIR="$SCRIPT_DIR/load_ledger_results"
mkdir -p "$OUT_DIR"

POLL_INTERVAL=300          # 5 minutes
MAX_HOURS=10
MAX_SECS=$((MAX_HOURS * 3600))

# Remote stats file path on each client
STATS_REMOTE="${STATS_REMOTE:-/home/ubuntu/load_ledger_stats.json}"

start_time="$(date +%s)"

echo "watch_load_ledger_stats: using IP list: $IP_FILE"
echo "Results will be stored in: $OUT_DIR"
echo "Max duration: ${MAX_HOURS}h, poll every ${POLL_INTERVAL}s"

# --- Load IPs (compatible with macOS bash 3.2) ---
if [[ ! -f "$IP_FILE" ]]; then
  echo "ERROR: IP file not found: $IP_FILE" >&2
  exit 1
fi

IPS=()
while IFS= read -r line; do
  # Trim leading whitespace
  line="${line#"${line%%[![:space:]]*}"}"
  # Trim trailing whitespace
  line="${line%"${line##*[![:space:]]}"}"

  [[ -z "$line" ]] && continue

  # Simple IPv4 check
  if [[ "$line" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    IPS+=("$line")
  fi
done < "$IP_FILE"

if [[ ${#IPS[@]} -eq 0 ]]; then
  echo "ERROR: No IPs found in $IP_FILE" >&2
  exit 1
fi

echo "Found ${#IPS[@]} IP(s): ${IPS[*]}"

# We consider "done" when each IP has a stats file.
all_ips_collected() {
  local ip
  for ip in "${IPS[@]}"; do
    local tag="${ip//./_}"
    local f="${OUT_DIR}/stats_${tag}.json"
    [[ -f "$f" ]] || return 1
  done
  return 0
}

while true; do
  now="$(date +%s)"
  elapsed=$((now - start_time))
  if (( elapsed > MAX_SECS )); then
    echo "Timeout: ${MAX_HOURS} hours elapsed without collecting stats from all IPs."
    exit 1
  fi

  echo "Polling stats at $(date -u +%Y-%m-%dT%H:%M:%SZ) (elapsed ${elapsed}s)…"

  for ip in "${IPS[@]}"; do
    tag="${ip//./_}"
    out_json="${OUT_DIR}/stats_${tag}.json"
    tmp_json="${OUT_DIR}/stats_${tag}.json.tmp"

    # Skip if we already have a result for this IP
    if [[ -f "$out_json" ]]; then
      echo "  [$ip] stats already present → skipping."
      continue
    fi

    echo "  [$ip] checking for $STATS_REMOTE"

    # Try to fetch over SSH; failures are non-fatal.
    if ssh -i "$KEY_FILE" -o StrictHostKeyChecking=no -o ConnectTimeout=10 "ubuntu@${ip}" \
         "test -f '$STATS_REMOTE' && cat '$STATS_REMOTE'" >"$tmp_json" 2>/dev/null; then

      if [[ -s "$tmp_json" ]]; then
        echo "  [$ip] received stats, validating JSON…"

        # Quick JSON validation and normalization via python
        if python3 - <<PY 2>/dev/null
import json, sys
path = "$tmp_json"
with open(path, "r", encoding="utf-8") as f:
    data = json.load(f)
for key in ("startup_time", "number_of_deployments", "snarkos_network"):
    if key not in data:
        raise SystemExit("missing key: %s" % key)
with open(path, "w", encoding="utf-8") as f:
    json.dump(data, f, sort_keys=True, indent=2)
PY
        then
          mv "$tmp_json" "$out_json"
          chmod 0644 "$out_json"
          echo "  [$ip] stored normalized stats at $out_json"
        else
          echo "  [$ip] invalid JSON received, discarding." >&2
          rm -f "$tmp_json"
        fi
      else
        echo "  [$ip] remote file empty or not accessible." >&2
        rm -f "$tmp_json"
      fi
    else
      rm -f "$tmp_json" 2>/dev/null || true
      echo "  [$ip] stats not available yet."
    fi
  done

  if all_ips_collected; then
    echo "All IPs have stats files. Aggregating…"

    python3 - <<PY
import json, glob, os

out_dir = r"$OUT_DIR"
files = sorted(glob.glob(os.path.join(out_dir, "stats_*.json")))

records = []
for path in files:
    try:
        with open(path, "r", encoding="utf-8") as f:
            data = json.load(f)
            data["_source_file"] = os.path.basename(path)
            records.append(data)
    except Exception:
        pass

records.sort(key=lambda r: r.get("snarkos_network", 999))

with open(os.path.join(out_dir, "load_ledger_merged.json"), "w", encoding="utf-8") as f:
    json.dump(records, f, ensure_ascii=False, indent=2, sort_keys=True)
PY

    echo "Merged stats written to: ${OUT_DIR}/load_ledger_merged.json"
    echo "Done."
    exit 0
  fi

  echo "Not all IPs reported yet. Sleeping ${POLL_INTERVAL}s…"
  sleep "$POLL_INTERVAL"
done

