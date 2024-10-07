#!/bin/bash

# We should be cd-ed into the test folder

cd ../../terraform_tx_cannon
# Add tx-cannon nodes.
echo "Adding tx-cannon nodes"
terraform apply -auto-approve -var="tx_cannon_instance_count=2" | grep -E 'Plan|Resources'
