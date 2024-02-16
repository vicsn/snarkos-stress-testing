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

provider "aws" {
  alias  = "us-west-1"
  region = "us-west-1"
}

module "snarkos_node_setup_us-west-1" {
  providers = {
    aws = aws.us-west-1
  }
  source        = "./modules/snarkos_node_setup"
  region        = "us-west-1"
  instance_count = var.instance_count
  instance_type = var.instance_type
  key_pair_name = var.key_pair_name
  region_index = 0
}


provider "aws" {
  alias  = "us-west-2"
  region = "us-west-2"
}

module "snarkos_node_setup_us-west-2" {
  providers = {
    aws = aws.us-west-2
  }
  source        = "./modules/snarkos_node_setup"
  region        = "us-west-2"
  instance_count = var.instance_count
  instance_type = var.instance_type
  key_pair_name = var.key_pair_name
  region_index = 1
}

