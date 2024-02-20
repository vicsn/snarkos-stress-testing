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

resource "aws_security_group" "tx_cannon_sg" {
  name        = "tx_cannon_sg"
  description = "Security group for tx cannon"

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 9090
    to_port     = 9090
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 9000
    to_port     = 9000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # This is for the prometheus process exporter
  ingress {
    from_port   = 9256
    to_port     = 9256
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 3030
    to_port     = 3030
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 4130
    to_port     = 4230
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 5000
    to_port     = 5000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 5601
    to_port     = 5601
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 9200
    to_port     = 9600
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"  # -1 means all protocols
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Add variables for tx-cannon instance configuration
variable "tx_cannon_instance_type" {
  description = "Instance type for tx-cannon nodes"
  default     = "m5.2xlarge"
}

variable "tx_cannon_instance_count" {
  description = "Number of tx-cannon nodes"
  default     = 2
}

# Resource block for tx-cannon instances
resource "aws_instance" "tx_cannon_node" {
  count         = var.tx_cannon_instance_count
  ami           = data.aws_ami.latest_ubuntu.id
  instance_type = var.tx_cannon_instance_type
  key_name      = var.key_pair_name

  security_groups = [aws_security_group.tx_cannon_sg.name]

  ebs_block_device {
    device_name = "/dev/sda1"
    volume_size = 20  # Adjust the volume size if needed
  }

  tags = {
    Name = "tx-cannon-node-${count.index}",
    Role = "tx-cannon-node",
    Dev = count.index
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

cat >> "$output_file" <<- 'EOF'
output "west1-lb" {
  value       = module.snarkos_node_setup_us-west-1.snarkos_lb_dns_name
  description = "Public dns of west1 lb"
}
EOF

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
