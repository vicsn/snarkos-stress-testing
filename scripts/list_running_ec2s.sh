#!/bin/bash

# List of all AWS regions starting with 'us'
regions=$(aws ec2 describe-regions --query 'Regions[?starts_with(RegionName, `us`)].RegionName' --output text)

# Iterate through each region and list running EC2 instances
for region in $regions; do
  echo "Instances in region: $region"

  # Get instance details including tags
  instances=$(aws ec2 describe-instances --region $region --query 'Reservations[*].Instances[*].[InstanceId,Tags]' --filters Name=instance-state-name,Values=running --output json)

  # Loop through each instance and display its name, tags, and instance ID
  for instance in $(echo "$instances" | jq -r '.[][] | @base64'); do
    _jq() {
      echo ${instance} | base64 --decode | jq -r ${1}
    }

    instance_id=$(_jq '.[0]')
    tags=$(_jq '.[1]')

    name=$(echo $tags | jq -r '.[] | select(.Key=="Name") | .Value' || echo "No Name tag")

    echo "Instance ID: $instance_id, Name: $name"
  done

  echo "----------------------------------"
done
