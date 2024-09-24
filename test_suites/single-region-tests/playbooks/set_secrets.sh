#!/bin/bash

# AWS profile to use
AWS_PROFILE="ephnet"

# Function to create or update a secret
create_or_update_secret() {
    local secret_name=$1
    local secret_value=$2

    if aws secretsmanager describe-secret --secret-id "$secret_name" --profile "$AWS_PROFILE" >/dev/null 2>&1; then
        # Secret exists, update it
        aws secretsmanager put-secret-value \
            --secret-id "$secret_name" \
            --secret-string "$secret_value" \
            --profile "$AWS_PROFILE"
        echo "Secret '$secret_name' has been updated."
    else
        # Secret doesn't exist, create it
        aws secretsmanager create-secret \
            --name "$secret_name" \
            --secret-string "$secret_value" \
            --profile "$AWS_PROFILE"
        echo "Secret '$secret_name' has been created."
    fi
}

# Set GitHub token
read -p "Enter GitHub token: " github_token
create_or_update_secret "github_token" "$github_token"

# Set cloud ID
read -p "Enter cloud ID: " cloud_id
create_or_update_secret "cloud_id" "$cloud_id"

# Set Elastic API key
read -p "Enter Elastic API key: " elastic_api_key
create_or_update_secret "elastic_api_key" "$elastic_api_key"

# Set Grafana Cloud API key
read -p "Enter Grafana Cloud API key: " grafana_cloud_api_key
create_or_update_secret "grafana_cloud_api_key" "$grafana_cloud_api_key"

echo "All secrets have been set in AWS Secrets Manager using the $AWS_PROFILE profile."