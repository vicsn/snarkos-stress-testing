#!/bin/bash

# We should be cd-ed into the test folder

cd ../../terraform
terraform apply -auto-approve | grep -E 'Plan|Resources'
