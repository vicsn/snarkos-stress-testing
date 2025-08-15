#!/usr/bin/env bash

set -u

BUCKET="${1:-aleo-snapshots}"
BASE_DIR="${2:-/tmp}"

NETWORKS=("canary" "testnet" "mainnet")
STATE_FILE="${HOME}/.checkpoint_uploader_state"
TMP_DIR="/tmp/checkpoint_zips"

mkdir -p "$TMP_DIR"
touch "$STATE_FILE"

have_cmd() { command -v "$1" >/dev/null 2>&1; }
have_cmd aws || { echo "aws CLI not found (sudo apt-get install awscli)"; exit 1; }
have_cmd zip || { echo "zip not found (sudo apt-get install zip)"; exit 1; }

log() { printf '[%s] %s\n' "$(date +'%F %T')" "$*"; }

in_state() { grep -Fx -- "$1" "$STATE_FILE" >/dev/null 2>&1; }
mark_state() { in_state "$1" || echo "$1" >> "$STATE_FILE"; }

s3_exists() { aws s3api head-object --bucket "$BUCKET" --key "$1" >/dev/null 2>&1; }

s3_key_for() {
  local net="$1" suf="$2"
  echo "${net}/checkpoint_${suf}.zip"
}

# A checkpoint dir is “complete” if it has CURRENT and at least one MANIFEST-*
is_complete() {
  local dir="$1"
  [[ -f "$dir/CURRENT" ]] || return 1
  find "$dir" -maxdepth 1 -type f -name 'MANIFEST-*' | grep -q . || return 1
  return 0
}

process_one() {
  local net="$1" suf="$2" dir="$3"

  local key; key="$(s3_key_for "$net" "$suf")"
  local state_key="${BUCKET}|${net}|${suf}"

  if in_state "$state_key"; then
    log "SKIP (state): $net $suf -> s3://$BUCKET/$key"
    return 0
  fi

  if s3_exists "$key"; then
    log "SKIP (exists on S3): $net $suf -> s3://$BUCKET/$key"
    mark_state "$state_key"
    return 0
  fi

  local bn zip_path
  bn="$(basename "$dir")"
  zip_path="${TMP_DIR}/checkpoint_${net}_${suf}.zip"

  log "ZIPPING: $dir -> $zip_path"
  ( cd "$(dirname "$dir")" && zip -qr "$zip_path" "$bn" ) || {
    log "ERROR: zip failed for $dir"
    return 1
  }

  log "UPLOADING: $zip_path -> s3://$BUCKET/$key"
  if aws s3 cp "$zip_path" "s3://${BUCKET}/${key}"; then
    log "UPLOADED: s3://$BUCKET/$key"
    mark_state "$state_key"
    rm -f "$zip_path"
  else
    log "ERROR: upload failed for $zip_path"
    return 1
  fi
}

process_network() {
  local net="$1"
  local lines
  lines="$(find "$BASE_DIR" -maxdepth 1 -type d -name "checkpoint_${net}_*" -printf '%f\n' \
    | while read -r name; do
        suf="${name#checkpoint_${net}_}"
        if [[ "$suf" == "start" ]]; then val=0
        elif [[ "$suf" =~ ^[0-9]+$ ]]; then val="$suf"
        else continue
        fi
        printf "%s\t%s\t%s/%s\n" "$val" "$suf" "$BASE_DIR" "$name"
      done \
    | sort -n -k1,1 )"

  [[ -z "$lines" ]] && { log "No checkpoints for $net under $BASE_DIR"; return 0; }

  local count; count="$(printf "%s\n" "$lines" | wc -l | tr -d ' ')"

  # Process all but latest
  local idx=0
  while IFS=$'\t' read -r val suf dir; do
    idx=$((idx+1))
    if (( idx < count )); then
      process_one "$net" "$suf" "$dir"
    else
      # Latest: upload only if complete
      if is_complete "$dir"; then
        log "LATEST for $net is complete (suffix=$suf, height=$val) — uploading."
        process_one "$net" "$suf" "$dir"
      else
        log "LATEST for $net is NOT complete yet (suffix=$suf) — skipping for now."
      fi
    fi
  done <<< "$lines"
}

main_loop() {
  while true; do
    log "Scan start (bucket=$BUCKET, base_dir=$BASE_DIR)"
    for net in "${NETWORKS[@]}"; do
      process_network "$net"
    done
    log "Scan complete. Sleeping 3600s."
    sleep 3600
  done
}

main_loop
