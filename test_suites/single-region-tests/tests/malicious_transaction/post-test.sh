#!/bin/bash

# We should be cd-ed into the test folder

cd ../../terraform
# Remove tx-cannon nodes.
echo "Removing tx-cannon nodes"
terraform apply -auto-approve -var="add_tx_cannons=false" | grep -E 'Plan|Resources'
