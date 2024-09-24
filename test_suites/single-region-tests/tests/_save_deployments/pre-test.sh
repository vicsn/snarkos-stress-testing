#!/bin/bash

# We should be cd-ed into the test folder

cd ../../terraform
# Add tx-cannon nodes.
echo "Adding tx-cannon nodes"
terraform apply -auto-approve -var="add_tx_cannons=true" -var="tx_cannon_instance_count=5" -var="tx_cannon_instance_type=c5.4xlarge" | grep -E 'Plan|Resources'
