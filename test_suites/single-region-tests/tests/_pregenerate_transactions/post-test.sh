#!/bin/bash

# We should be cd-ed into the test folder

cd ../../terraform_tx_cannon
# Remove tx-cannon nodes.
echo "Removing tx-sender nodes"
terraform destroy -parallelism=50 -var="deployment_mode=tx-sender" -var="owner=$OWNER" -auto-approve | grep -E 'Plan|Resources'
