#!/bin/bash

# See the README.md in the slack folder for detailed documentation.

DEFAULT_CHANNEL=$CHANNEL_ID

log_error() {
    echo "ERROR: $1" >&2
}

send_slack_message() {
    local message="$1"
    local channel="$2"
    local thread_ts="$3"
    local format="$4"
    local color="$5"
    local mentions="$6"

    # Process mentions
    if [[ -n "$mentions" ]]; then
        IFS=',' read -ra tokens <<< "$mentions"
        for token in "${tokens[@]}"; do
            case "$token" in
                "@here" | "@channel" | "@everyone")
                    message+=" <!${token:1}>"
                    ;;
                *)
                    message+=" <@${token}>"
                    ;;
            esac
        done
    fi

    # Apply formatting
    case "$format" in
        bold) message="*${message}*" ;;
        code) message="\`\`\`${message}\`\`\`" ;;
    esac

    # Build JSON payload
    if [[ -n "$color" ]]; then
        payload="{\"channel\":\"$channel\",\"attachments\":[{\"color\":\"$color\",\"text\":\"$message\"}]"
        [[ -n "$thread_ts" ]] && payload+=", \"thread_ts\":\"$thread_ts\""
        payload+="}"
    else
        payload="{\"channel\":\"$channel\",\"text\":\"$message\""
        [[ -n "$thread_ts" ]] && payload+=", \"thread_ts\":\"$thread_ts\""
        payload+="}"
    fi

    # Send message
    response=$(curl -s -X POST "https://slack.com/api/chat.postMessage" \
        -H "Authorization: Bearer $SLACK_TOKEN" \
        -H "Content-type: application/json; charset=utf-8" \
        --data "$payload")

    # Check API success
    if [[ $(echo "$response" | jq -r '.ok') != "true" ]]; then
        log_error "Slack API call failed: $(echo "$response" | jq -r '.error')"
        return 1
    fi

    # If no thread_ts was provided, this is an initial message, return thread_ts
    if [[ -z "$thread_ts" ]]; then
        echo "$response" | jq -r '.ts'
    fi

    return 0
}

# CLI Argument Parsing
usage() {
    echo "Usage: $0 -m MESSAGE [-c CHANNEL] [-t THREAD_TS] [-f FORMAT] [-o COLOR] [-n MENTIONS] [-k SLACK_TOKEN]"
    echo
    echo "  -m  Message text (required)"
    echo "  -c  Channel ID (default: $DEFAULT_CHANNEL)"
    echo "  -t  Thread timestamp (to reply in a thread)"
    echo "  -f  Format: plain | bold | code (default: plain)"
    echo "  -o  Color for block (good, warning, danger, or hex color)"
    echo "  -n  Mentions (comma-separated user IDs or @here,@channel,@everyone)"
    echo "  -k  Slack Bot Token (override default)"
    echo "  -h  Show help"
    exit 1
}

channel="$DEFAULT_CHANNEL"
format="plain"

while getopts ":m:c:t:f:o:n:k:h" opt; do
    case ${opt} in
        m) message="$OPTARG" ;;
        c) channel="$OPTARG" ;;
        t) thread_ts="$OPTARG" ;;
        f) format="$OPTARG" ;;
        o) color="$OPTARG" ;;
        n) mentions="$OPTARG" ;;
        k) SLACK_TOKEN="$OPTARG" ;;
        h) usage ;;
        *) usage ;;
    esac
done

[[ -z "$message" ]] && usage

# Execute and handle return value properly
result=$(send_slack_message "$message" "$channel" "$thread_ts" "$format" "$color" "$mentions")
if [[ $? -eq 0 && -z "$thread_ts" ]]; then
    # Output the new thread_ts when it's an initial message
    echo "$result"
fi
