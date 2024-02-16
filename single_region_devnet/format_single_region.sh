#!/bin/bash

# Define the input Terraform configuration file
var_file="variables.tf"

cat > "$var_file" <<- EOF
variable "aws_region" {
  default     = "$REGION"
}

variable "instance_type" {
  default = "m5.4xlarge"
}

variable "instance_count" {
  default = $INSTANCES
}

variable "key_pair_name" {
  default     = "devnet-key"
}
EOF

echo "Terraform configuration generated in $var_file"