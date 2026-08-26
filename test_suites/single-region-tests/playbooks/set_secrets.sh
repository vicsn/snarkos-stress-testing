#!/bin/bash

# GCP Secret Manager integration for snarkOS stress testing
# Uses GCP Secret Manager

set -euo pipefail

# Default project - override with GOOGLE_CLOUD_PROJECT env var
PROJECT_ID="${GOOGLE_CLOUD_PROJECT:-protocol-development-sandbox}"
SECRET_PREFIX="snarkos-stress-testing"

# Function to create or update a secret
create_or_update_secret() {
    local secret_name="$1"
    local secret_value="$2"
    local full_secret_name="${SECRET_PREFIX}-${secret_name}"
    
    echo "Setting secret: ${full_secret_name}"
    
    # Check if secret exists
    if gcloud secrets describe "$full_secret_name" --project="$PROJECT_ID" >/dev/null 2>&1; then
        echo "  Secret exists, adding new version..."
        echo -n "$secret_value" | gcloud secrets versions add "$full_secret_name" \
            --data-file=- --project="$PROJECT_ID"
    else
        echo "  Creating new secret..."
        echo -n "$secret_value" | gcloud secrets create "$full_secret_name" \
            --data-file=- --project="$PROJECT_ID"
    fi
}

# Function to get a secret value
get_secret() {
    local secret_name="$1"
    local full_secret_name="${SECRET_PREFIX}-${secret_name}"
    
    gcloud secrets versions access latest --secret="$full_secret_name" \
        --project="$PROJECT_ID" 2>/dev/null || {
        echo "ERROR: Secret ${full_secret_name} not found" >&2
        return 1
    }
}

# Function to list all secrets with our prefix
list_secrets() {
    echo "Secrets in project ${PROJECT_ID} with prefix ${SECRET_PREFIX}:"
    gcloud secrets list --filter="name:${SECRET_PREFIX}" \
        --format="table(name.basename():label=SECRET_NAME,createTime:label=CREATED)" \
        --project="$PROJECT_ID"
}

# Function to delete a secret
delete_secret() {
    local secret_name="$1"
    local full_secret_name="${SECRET_PREFIX}-${secret_name}"
    
    echo "Deleting secret: ${full_secret_name}"
    gcloud secrets delete "$full_secret_name" --project="$PROJECT_ID" --quiet
}

# Main command dispatcher
case "${1:-}" in
    "set")
        if [[ $# -ne 3 ]]; then
            echo "Usage: $0 set <secret_name> <secret_value>"
            echo "Example: $0 set github-token ghp_abc123..."
            exit 1
        fi
        create_or_update_secret "$2" "$3"
        ;;
    "get")
        if [[ $# -ne 2 ]]; then
            echo "Usage: $0 get <secret_name>"
            echo "Example: $0 get github-token"
            exit 1
        fi
        get_secret "$2"
        ;;
    "list")
        list_secrets
        ;;
    "delete")
        if [[ $# -ne 2 ]]; then
            echo "Usage: $0 delete <secret_name>"
            echo "Example: $0 delete github-token"
            exit 1
        fi
        delete_secret "$2"
        ;;
    "init")
        echo "Initializing secrets for snarkOS stress testing..."
        echo ""
        echo "Required secrets:"
        echo "  - grafana-cloud-api-key: Grafana Cloud API key for Prometheus remote_write"
        echo "  - github-token: GitHub personal access token for repository access"
        echo ""
        echo "To set a secret:"
        echo "  $0 set grafana-cloud-api-key 'your_grafana_api_key_here'"
        echo "  $0 set github-token 'ghp_your_github_token_here'"
        echo ""
        echo "Current secrets:"
        list_secrets
        ;;
    *)
        echo "GCP Secret Manager utility for snarkOS stress testing"
        echo ""
        echo "Usage: $0 <command> [args...]"
        echo ""
        echo "Commands:"
        echo "  init                     Show setup instructions"
        echo "  set <name> <value>       Create or update a secret"
        echo "  get <name>               Retrieve a secret value"
        echo "  list                     List all secrets"
        echo "  delete <name>            Delete a secret"
        echo ""
        echo "Environment:"
        echo "  GOOGLE_CLOUD_PROJECT     GCP project ID (default: ${PROJECT_ID})"
        echo "  SECRET_PREFIX           Secret name prefix (current: ${SECRET_PREFIX})"
        echo ""
        echo "Secret names used by playbooks:"
        echo "  - grafana-cloud-api-key"
        echo "  - github-token"
        exit 1
        ;;
esac