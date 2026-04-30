#!/bin/bash

# We should be cd-ed into the test folder

cd ../../terraform_tx_cannon || exit
# Add tx-cannon nodes.
echo "Adding tx-cannon nodes"
terraform init -migrate-state
terraform apply -auto-approve -var="owner=$OWNER" -var="tx_cannon_instance_count=2" | grep -E 'Plan|Resources'
