#!/bin/bash

cd ../../terraform_tx_cannon
# Add tx-cannon nodes.
echo "Adding transaction sender nodes"
terraform init
terraform apply -auto-approve -var="deployment_mode=tx-sender" -var="owner=$OWNER" -var="tx_sender_instance_count=1" -var="tx_sender_instance_type=m7i.4xlarge" | grep -E 'Plan|Resources'
