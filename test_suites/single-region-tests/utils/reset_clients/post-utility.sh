#!/bin/bash

# We should be cd-ed into the test folder

cd ../../terraform || exit
terraform apply -auto-approve -var="owner=$OWNER" | grep -E 'Plan|Resources'
