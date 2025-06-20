#!/bin/bash

ulimit -n 2048

PARENT_DIR=$(cd "$(dirname "$0")" && pwd)
export OWNER=$USER

echo "An error occurred or finished. Destroying infrastructure to avoid unnecessary costs..."

read -p "Press ENTER to destroy the infrastructure or CTRL+C to cancel..."

cd "$PARENT_DIR/terraform"
terraform destroy -auto-approve -parallelism=50 -var="owner=$OWNER"

cd "$PARENT_DIR/terraform_tx_cannon"
terraform destroy -auto-approve -parallelism=50 -var="owner=$OWNER"
