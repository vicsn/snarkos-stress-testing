#!/bin/bash

# We should be cd-ed into the test folder

cd ../../terraform_tx_cannon
# Remove tx-cannon nodes.
echo "Removing tx-cannon nodes"
terraform destroy -var="owner=$OWNER" -parallelism=50 -auto-approve | grep -E 'Plan|Resources'
