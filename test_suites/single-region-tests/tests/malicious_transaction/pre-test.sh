#!/bin/bash

# We should be cd-ed into the test folder

cd ../../terraform_tx_cannon
# Add tx-cannon nodes.
echo "Adding tx-cannon nodes"
terraform apply -auto-approve | grep -E 'Plan|Resources'
