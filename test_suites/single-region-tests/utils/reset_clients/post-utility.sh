#!/bin/bash

# We should be cd-ed into the test folder

cd ../../terraform
# Replace tx-cannon ECS cluster.
echo "Resetting tx-cannon ECS cluster"
# Store the currently loaded tx-cannon services
replace_args="" 
terraform state list | grep 'aws_ecs_service.tx_cannon_services' | \
    while read instance; do
        replace_args+=" -replace=$instance"
    done
# Always replace the tx-cannon ECS cluster, because they have a state root cached.
terraform apply -auto-approve $replace_args | grep -E 'Plan|Resources'
