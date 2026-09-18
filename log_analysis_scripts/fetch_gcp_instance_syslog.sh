#!/usr/bin/env bash
# Pull Cloud Logging syslog for one GCE instance in a time window.
#
# Cloud Logging `timestamp` is ingest time, which can lag snarkOS event time
# by minutes. Prefer GCS node logs (val-N-*.log.gz) when they exist, and use
# this for a first look or when the fleet is already destroyed.
#
#   fetch_gcp_instance_syslog.sh \
#     --instance victorsintnicolaas-snarkos-p2p-tests-snarkos-validator-0 \
#     --from 2026-09-17T10:49:00Z --to 2026-09-17T10:53:00Z
set -euo pipefail

INSTANCE=""
FROM=""
TO=""
PROJECT="${GCP_PROJECT:-protocol-development-sandbox}"
LIMIT=50000

usage() { sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'; }

while (($#)); do
  case "$1" in
    --instance) INSTANCE="$2"; shift 2 ;;
    --from) FROM="$2"; shift 2 ;;
    --to) TO="$2"; shift 2 ;;
    --project) PROJECT="$2"; shift 2 ;;
    --limit) LIMIT="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage; exit 1 ;;
  esac
done

[[ -n "$INSTANCE" && -n "$FROM" && -n "$TO" ]] \
  || { echo "Need --instance --from --to" >&2; usage; exit 1; }

filter=$(cat <<EOF
logName="projects/${PROJECT}/logs/syslog"
AND labels."compute.googleapis.com/resource_name"="${INSTANCE}"
AND timestamp>="${FROM}"
AND timestamp<="${TO}"
EOF
)

echo "query: $filter" >&2
gcloud logging read "$filter" \
  --project="$PROJECT" \
  --limit="$LIMIT" \
  --format='value(timestamp,severity,jsonPayload.message)'
