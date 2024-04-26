#!/bin/bash

# Define an array of US regions
us_regions=("us-east-1" "us-east-2" "us-west-1" "us-west-2")

# Loop through each US region
for region in "${us_regions[@]}"; do
    echo "Region: $region"
    # List specific quota for EC2 in each US region
    aws service-quotas list-service-quotas --service-code ec2 --region $region --output json | \
    jq '.Quotas[] | select(.QuotaName | contains("On-Demand Standard (A, C, D, H, I, M, R, T, Z) instances")) | {QuotaCode, QuotaName, Value}'
done
