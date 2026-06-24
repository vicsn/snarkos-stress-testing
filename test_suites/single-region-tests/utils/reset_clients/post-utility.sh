#!/bin/bash

# We should be cd-ed into the test folder

cd ../../terraform || exit
terraform init -input=false >/dev/null
terraform apply -auto-approve -var="owner=$OWNER" | grep -E 'Plan|Resources'
