#!/bin/bash

set -uo pipefail

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

get_ip() {
  if [[ -f .builder_ip ]]; then
    cat .builder_ip
  else
    local ip
    ip=$(aws ec2 describe-instances \
      --filters "Name=tag:Name,Values=Aleo Builder" "Name=instance-state-name,Values=running" \
      --query "Reservations[].Instances[].PublicIpAddress" \
      --output text)
    echo "$ip" > .builder_ip
    echo "$ip"
  fi
}

refresh_ip() {
  rm -f .builder_ip
  get_ip
}

BUILDER_IP="$(get_ip)"
if [[ -z "$BUILDER_IP" ]]; then
  echo "ERROR: Could not get Builder IP from AWS." >&2
  exit 1
fi

echo "Will call the API on the Builder machine @$BUILDER_IP"

# Make the request
ssh ubuntu@$BUILDER_IP "PORT=$PORT PAYLOAD='$PAYLOAD' bash -s" <<'EOF'
curl -s -X POST "http://localhost:$PORT/rpc" \
  -H "Content-Type: application/json" \
  -v \
  -d "$PAYLOAD" | jq
EOF

if [[ $? -ne 0 ]]; then
  echo "Error accessing the Builder machine @$BUILDER_IP, invalidating the IP cache and trying again..."

  BUILDER_IP="$(refresh_ip)"
  echo "Will call the API on the Builder machine @$BUILDER_IP"

  ssh ubuntu@$BUILDER_IP "PORT=$PORT PAYLOAD='$PAYLOAD' bash -s" <<'EOF'
curl -s -X POST "http://localhost:$PORT/rpc" \
  -H "Content-Type: application/json" \
  -v \
  -d "$PAYLOAD" | jq
EOF
fi
