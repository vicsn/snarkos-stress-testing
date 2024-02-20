provider "aws" {
  alias  = "west1"
  region = "us-west-1"
}

provider "aws" {
  alias  = "west2"
  region = "us-west-2"
}

provider "aws" {
  alias  = "east1"
  region = "us-east-1"
}

provider "aws" {
  alias  = "east2"
  region = "us-east-2"
}

module "snarkos_node_setup_west1" {
  providers = {
    aws = aws.west1
  }
  source        = "./modules/snarkos_node_setup"
  region        = "us-west-1"
  instance_count = var.validator_count
  instance_type = var.instance_type
  key_pair_name = var.key_pair_name
  region_index = 0
}

output "west1-lb" {
  value       = module.snarkos_node_setup_west1.snarkos_lb_dns_name
  description = "Public dns of west1 lb"
}

module "snarkos_node_setup_west2" {
  providers = {
    aws = aws.west2
  }
  source        = "./modules/snarkos_client_node_setup"
  region        = "us-west-2"
  instance_count = var.client_count
  instance_type = var.instance_type_client
  key_pair_name = var.key_pair_name
  region_index = 1
  validator_count = var.validator_count
}

module "snarkos_node_setup_east1" {
  providers = {
    aws = aws.east1
  }
  source        = "./modules/snarkos_client_node_setup"
  region        = "us-east-1"
  instance_count = var.client_count
  instance_type = var.instance_type_client
  key_pair_name = var.key_pair_name
  region_index = 2
  validator_count = var.validator_count
}

module "snarkos_node_setup_east2" {
  providers = {
    aws = aws.east2
  }
  source        = "./modules/snarkos_client_node_setup"
  region        = "us-east-2"
  instance_count = var.client_count
  instance_type = var.instance_type_client
  key_pair_name = var.key_pair_name
  region_index = 3
  validator_count = var.validator_count
}

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

# Add variables for network driver instance configuration
variable "network_driver_instance_type" {
  description = "Instance type for tx-cannon nodes"
  default     = "m5.2xlarge"
}

variable "network_driver_instance_count" {
  description = "Number of tx-cannon nodes"
  default     = 1
}

# Resource block for tx-cannon instances
resource "aws_instance" "network_driver_node" {
  count         = var.network_driver_instance_count
  ami           = data.aws_ami.latest_ubuntu.id
  instance_type = var.network_driver_instance_type
  key_name      = var.key_pair_name

  security_groups = [aws_security_group.tx_cannon_sg.name]

  ebs_block_device {
    device_name = "/dev/sda1"
    volume_size = 20  # Adjust the volume size if needed
  }

  tags = {
    Name = "network-driver-node",
    Role = "network-driver-node",
    Dev = count.index
  }
}
