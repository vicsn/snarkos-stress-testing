#!/bin/bash

ulimit -n 2048

PARENT_DIR=$(cd "$(dirname "$0")" && pwd)
: "${OWNER:?OWNER environment variable must be set (e.g. export OWNER=\$USER) before running destroy_infra.sh}"
export OWNER

cd "$PARENT_DIR/terraform" || exit
terraform init -input=false
terraform destroy -auto-approve -parallelism=50 -var="owner=$OWNER" -var="add_builder=true"
