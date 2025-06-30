#!/bin/bash

set -e

# Ensure TALISKER_API_PORT is set
PORT="${TALISKER_API_PORT:-3030}"

if [ -z "$1" ]; then
  echo "Usage: $0 <method> [key1=value1 key2=value2 ...]"
  exit 1
fi

METHOD="$1"
shift


# Build the params object
PARAMS=""

for ARG in "$@"; do
  KEY="${ARG%%=*}"
  VALUE="${ARG#*=}"
  # Add quotes around value, and escape any double quotes inside the value
  VALUE_ESCAPED=$(printf '%s' "$VALUE" | sed 's/"/\\"/g')
  PARAMS+="\"$KEY\":\"$VALUE_ESCAPED\","
done

# Remove trailing comma if present
PARAMS="${PARAMS%,}"

# Construct JSON payload
if [ -z "$PARAMS" ]; then
  PARAMS_JSON="{}"
else
  PARAMS_JSON="{${PARAMS}}"
fi

PAYLOAD=$(cat <<EOF
{
  "jsonrpc": "2.0",
  "method": "$METHOD",
  "params": $PARAMS_JSON,
  "id": 1
}
EOF
)

# Make the request
curl -s -X POST "http://localhost:$PORT/rpc" \
  -H "Content-Type: application/json" \
  -d "$PAYLOAD" | jq
