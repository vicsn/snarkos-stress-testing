#!/bin/bash

ulimit -n 2048

PARENT_DIR=$(cd "$(dirname "$0")" && pwd)
export OWNER="${OWNER:-$USER}"

cd "$PARENT_DIR/terraform" || exit
terraform init -input=false
terraform destroy -auto-approve -parallelism=50 -var="owner=$OWNER" -var="add_builder=true"
