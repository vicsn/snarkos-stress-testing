#!/usr/bin/env bash
# Probe STANDARD GCE stock by attempting a real insert (then immediate delete).
# Capacity Advisor / machine-types list only say a type is *offered*, not that
# an on-demand VM will actually boot — insert is the signal Terraform hits.
#
# Usage:
#   scripts/stock-probe.sh
#   PROJECT=protocol-development-sandbox REGION=us-central1 scripts/stock-probe.sh
#
# Optional env:
#   PROJECT, REGION, NETWORK, SUBNET, MACHINE_TYPES (space-separated)

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/lib/bash_err_trap.sh"

PROJECT="${PROJECT:-protocol-development-sandbox}"
REGION="${REGION:-us-central1}"
NETWORK="${NETWORK:-default-stress-testing-manager-vpc}"
SUBNET="${SUBNET:-protocol-development-sandbox-subnet-us-central1}"

# Suites we actually run (8/16/30/60 vCPU) plus close substitutes.
DEFAULT_MACHINE_TYPES=(
  c3d-highcpu-8 c3d-highcpu-16 c3d-highcpu-30 c3d-highcpu-60
  c3d-standard-8 c3d-standard-16 c3d-standard-30 c3d-standard-60
  c3-highcpu-22 c3-standard-22
  n2d-highcpu-8 n2d-highcpu-16 n2d-highcpu-32 n2d-highcpu-64
  n2-highcpu-32
  c4-highcpu-32
  c2d-highcpu-16 c2d-highcpu-32
)

if [[ -n "${MACHINE_TYPES:-}" ]]; then
  # shellcheck disable=SC2206
  TYPES=(${MACHINE_TYPES})
else
  TYPES=("${DEFAULT_MACHINE_TYPES[@]}")
fi

PREFIX="stock-probe-$(date -u +%Y%m%d%H%M%S)-$$"
RES_DIR="$(mktemp -d)"

cleanup() {
  local name zone
  while IFS=$'\t' read -r name zone; do
    [[ -n "$name" ]] || continue
    gcloud compute instances delete "$name" \
      --project="$PROJECT" --zone="$zone" --quiet >/dev/null 2>&1 || true
  done < <(
    gcloud compute instances list \
      --project="$PROJECT" \
      --filter="name~^${PREFIX}" \
      --format='value(name,zone)' 2>/dev/null || true
  )
  rm -rf "$RES_DIR"
}
trap cleanup EXIT

classify() {
  local msg="$1"
  case "$msg" in
    *"ZONE_RESOURCE_POOL_EXHAUSTED"*|*"does not have enough resources"*|*"currently unavailable"*)
      echo stockout ;;
    *"QUOTA_EXCEEDED"*|*"Quota"*"exceeded"*)
      echo quota ;;
    *"is not available in zone"*|*"Invalid value for field 'resource.machineType'"*|*"not found"*)
      echo not-offered ;;
    *)
      echo error ;;
  esac
}

probe_one() {
  local type="$1" zone="$2"
  local name out rc class result
  name="${PREFIX}-${type}-${zone}"
  name="$(echo "$name" | tr '[:upper:]' '[:lower:]' | tr '_' '-' | cut -c1-63)"
  result="${RES_DIR}/${type}__${zone}"

  rc=0
  out="$(gcloud compute instances create "$name" \
    --project="$PROJECT" \
    --zone="$zone" \
    --machine-type="$type" \
    --image-family=ubuntu-2204-lts \
    --image-project=ubuntu-os-cloud \
    --boot-disk-size=10GB \
    --boot-disk-type=pd-ssd \
    --network="$NETWORK" \
    --subnet="$SUBNET" \
    --no-address \
    --quiet \
    --verbosity=error \
    --labels="stock-probe=true,owner=${OWNER:-$USER}" \
    --metadata=enable-oslogin=FALSE \
    2>&1)" || rc=$?

  if ((rc == 0)); then
    gcloud compute instances delete "$name" \
      --project="$PROJECT" --zone="$zone" --quiet >/dev/null 2>&1 || true
    printf '%s\t%s\tin-stock\n' "$type" "$zone" >"$result"
    return 0
  fi

  class="$(classify "$out")"
  printf '%s\t%s\t%s\t%s\n' "$type" "$zone" "$class" "$(echo "$out" | tr '\n' ' ' | tail -c 220)" >"$result"
}

mapfile -t ZONES < <(
  gcloud compute zones list \
    --project="$PROJECT" \
    --filter="region:${REGION}" \
    --format='value(name)' | sort
)

if ((${#ZONES[@]} == 0)); then
  echo "No zones found for region ${REGION} in project ${PROJECT}" >&2
  exit 1
fi

echo "stock-probe  project=${PROJECT}  region=${REGION}"
echo "network=${NETWORK}  subnet=${SUBNET}"
echo "zones: ${ZONES[*]}"
echo "types: ${TYPES[*]}"
echo

for type in "${TYPES[@]}"; do
  echo "Probing ${type}..."
  pids=()
  for zone in "${ZONES[@]}"; do
    probe_one "$type" "$zone" &
    pids+=($!)
  done
  for pid in "${pids[@]}"; do
    wait "$pid" || true
  done
done

RESULTS_FILE="${RES_DIR}/all.tsv"
cat "${RES_DIR}"/*__* >"$RESULTS_FILE"

echo
printf '%-22s %-16s %-12s %s\n' TYPE ZONE RESULT DETAIL
printf '%s\n' "--------------------------------------------------------------------------------"
sort -k1,1 -k2,2 "$RESULTS_FILE" | while IFS=$'\t' read -r type zone result detail; do
  printf '%-22s %-16s %-12s %s\n' "$type" "$zone" "$result" "${detail:-}"
done

echo
echo "Summary (in-stock zones per type):"
echo "--------------------------------------------------------------------------------"
for type in "${TYPES[@]}"; do
  instock="$(awk -F'\t' -v t="$type" '$1==t && $3=="in-stock" {print $2}' "$RESULTS_FILE" | paste -sd, -)"
  stockout="$(awk -F'\t' -v t="$type" '$1==t && $3=="stockout" {print $2}' "$RESULTS_FILE" | paste -sd, -)"
  other="$(awk -F'\t' -v t="$type" '$1==t && $3!="in-stock" && $3!="stockout" {printf "%s:%s ", $2, $3}' "$RESULTS_FILE")"
  printf '%-22s in-stock=[%s]  stockout=[%s]  other=[%s]\n' "$type" "${instock:-}" "${stockout:-}" "${other:-}"
done
