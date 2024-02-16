#!/bin/bash

# Define the input Terraform configuration file
output_file="main.tf"
var_file="variables.tf"

# Initialize the output file with the Prometheus setup block
cat > "$output_file" <<- 'EOF'
# Terraform for the prometheus setup 
data "aws_ami" "latest_ubuntu" {
  most_recent = true

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["099720109477"]  # Canonical's owner ID for Ubuntu images
}

provider "aws" {
  region = "us-west-2"
}

resource "aws_security_group" "prometheus_sg" {
  name_prefix = "prometheus-sg-"
  description = "Security group for Prometheus server"
  
  # Allow incoming HTTP traffic on port 80
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow incoming HTTPS traffic on port 443
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow SSH traffic on port 22
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow outgoing traffic to any destination
  egress {
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  # Allow DNS queries
  egress {
    from_port   = 53
    to_port     = 53
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_instance" "prometheus_server" {
  ami           = data.aws_ami.latest_ubuntu.id
  instance_type = var.instance_type
  key_name      = var.key_pair_name
  security_groups = [aws_security_group.prometheus_sg.name]

  ebs_block_device {
    device_name = "/dev/sda1"
    volume_size = 80
  }

  tags = {
    Name = "prometheus-server"
    Role = "prometheus-server"
  }
}
EOF

# Loop through the regions and generate provider and module blocks
index=0

IFS=',' read -r -a regions <<< "$REGION_LIST"

for region in "${regions[@]}"; do
    echo "$region"
    cat >> "$output_file" <<EOF

provider "aws" {
  alias  = "$region"
  region = "$region"
}

module "snarkos_node_setup_$region" {
  providers = {
    aws = aws.$region
  }
  source        = "./modules/snarkos_node_setup"
  region        = "$region"
  instance_count = var.instance_count
  instance_type = var.instance_type
  key_pair_name = var.key_pair_name
  region_index = $index
}

EOF
    ((index++))
done


# Loop through the regions and concatenate them
for ((i=0; i<${#regions[@]}; i++)); do
    region_list+="\"${regions[i]}\""
    # Add a comma if it's not the last element
    if [ $i -lt $((${#regions[@]} - 1)) ]; then
        region_list+=", "
    fi
done



cat > "$var_file" <<- EOF
variable "regions" {
  description = "List of regions for deployment"
  default     = [$region_list]
}

variable "instance_count" {
  description = "Number of instances to create in each region"
  default     = $INSTANCES_PER_REGION
}

variable "instance_type" {
  description = "Type of instance to deploy"
  default     = "m5.4xlarge"
}

variable "key_pair_name" {
  description = "Name of the AWS key pair"
  default     = "devnet-key"
}
EOF

echo "Terraform configuration generated in $output_file"
