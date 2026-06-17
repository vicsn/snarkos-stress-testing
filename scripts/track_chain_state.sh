#!/usr/bin/env bash
set -euo pipefail

NETWORK="${NETWORK:-mainnet}"
BASE_URL="https://api.provable.com/v2/${NETWORK}"

# Requires: jq
command -v jq >/dev/null 2>&1 || {
  echo "Error: jq is required. Install with: brew install jq" >&2
  exit 1
}

api_get() {
  curl -fsSL "$1"
}

latest_height="$(api_get "${BASE_URL}/block/height/latest" | jq -r '.')"

case "$latest_height" in
  ''|*[!0-9]*)
    echo "Error: latest height was not a plain integer: ${latest_height}" >&2
    exit 1
    ;;
esac

echo "Network: ${NETWORK}"
echo "Latest height: ${latest_height}"
echo
printf "%-18s %-12s %-12s %-8s %-22s %-22s\n" \
  "window" "start" "end" "blocks" "total_puzzle_reward" "avg_puzzle_reward"

fetch_blocks_range() {
  start="$1"
  end="$2"

  # /blocks has a max of 50 blocks per request.
  api_get "${BASE_URL}/blocks?start=${start}&end=${end}"
}

summarize_window() {
  label="$1"
  end_height="$2"

  start_height=$((end_height - 99))
  if [ "$start_height" -lt 0 ]; then
    start_height=0
  fi

  mid_height=$((start_height + 49))

  tmp1="$(mktemp)"
  tmp2="$(mktemp)"
  trap 'rm -f "$tmp1" "$tmp2"' EXIT

  fetch_blocks_range "$start_height" "$mid_height" > "$tmp1"
  fetch_blocks_range "$((mid_height + 1))" "$end_height" > "$tmp2"

  jq -s -r \
    --arg label "$label" \
    --argjson start "$start_height" \
    --argjson end "$end_height" '
      def puzzle_reward:
        (.ratifications // []
          | map(select(.type == "puzzle_reward") | (.amount | tonumber))
          | add) // 0;

      # Combine the two /blocks responses into one block array.
      (map(if type == "array" then . else [.] end) | add) as $blocks
      | ($blocks | length) as $count
      | ($blocks | map(puzzle_reward) | add // 0) as $total
      | ($total / (if $count == 0 then 1 else $count end)) as $avg
      | [$label, $start, $end, $count, $total, $avg]
      | @tsv
    ' "$tmp1" "$tmp2" |
  awk -F '\t' '{
    printf "%-18s %-12s %-12s %-8s %-22s %-22.6f\n", $1, $2, $3, $4, $5, $6
  }'

  rm -f "$tmp1" "$tmp2"
  trap - EXIT
}

summarize_window "latest" "$latest_height"
summarize_window "100000_ago" "$((latest_height - 100000))"
summarize_window "200000_ago" "$((latest_height - 200000))"
summarize_window "300000_ago" "$((latest_height - 300000))"
summarize_window "400000_ago" "$((latest_height - 400000))"

