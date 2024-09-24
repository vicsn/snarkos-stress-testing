#!/bin/bash

# We should be cd-ed into the test folder

cd ../../terraform
# Add tx-cannon nodes.
echo "Adding tx-cannon nodes"
terraform apply -auto-approve -var="add_tx_cannons=true" | grep -E 'Plan|Resources'
