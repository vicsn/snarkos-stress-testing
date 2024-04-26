#!/bin/bash

# Define an array of US regions
us_regions=("us-east-1" "us-east-2" "us-west-1" "us-west-2")

# Quota code for "Running On-Demand Standard (A, C, D, H, I, M, R, T, Z) instances"
quota_code="L-1216C47A"

# Desired quota value, change as necessary
desired_value=3000

# Loop through each US region
for region in "${us_regions[@]}"; do
    echo "Requesting quota increase in Region: $region"
    # Request quota increase for EC2 in each US region
    response=$(aws service-quotas request-service-quota-increase \
        --service-code ec2 \
        --quota-code $quota_code \
        --desired-value $desired_value \
        --region $region \
        --output json)

    echo "Response: $response"
    echo "----------------------------------"
done
