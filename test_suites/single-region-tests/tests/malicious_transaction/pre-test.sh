#!/bin/bash

# We should be cd-ed into the test folder

cd ../../terraform_tx_cannon
# Add tx-cannon nodes.
echo "Adding tx-cannon nodes"
terraform init -migrate-state
terraform apply -auto-approve -var="owner=$OWNER" | grep -E 'Plan|Resources'
