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

provider "aws" {
  alias  = "ap-southeast-1"
  region = "ap-southeast-1"
}

provider "aws" {
  alias  = "ap-southeast-2"
  region = "ap-southeast-2"
}

provider "aws" {
  alias  = "ap-northeast-1"
  region = "ap-northeast-1"
}

provider "aws" {
  alias  = "ca-central-1"
  region = "ca-central-1"
}

provider "aws" {
  alias  = "eu-central-1"
  region = "eu-central-1"
}

provider "aws" {
  alias  = "eu-west-1"
  region = "eu-west-1"
}

provider "aws" {
  alias  = "eu-west-2"
  region = "eu-west-2"
}

provider "aws" {
  alias  = "eu-west-3"
  region = "eu-west-3"
}

provider "aws" {
  alias  = "eu-north-1"
  region = "eu-north-1"
}

provider "aws" {
  alias  = "sa-east-1"
  region = "sa-east-1"
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

# Potential region to add more tx-cannons - use requires updates in Ansible code
# useful if desired tx-cannon count is not a multiple of the number of regions
module "snarkos_node_setup_west2" {
  providers = {
    aws = aws.west2
  }
  source             = "./modules/tx_cannon_node_setup"
  instance_type = "m5.2xlarge"
  instance_count = 0
  key_pair_name      = var.key_pair_name
}

module "snarkos_node_setup_east1" {
  providers = {
    aws = aws.east1
  }
  source        = "./modules/attacker_tx_cannon_setup"
  region        = "us-east-1"
  instance_count = var.attacker_tx_cannon_count
  instance_type = var.instance_type_attacker_tx_cannon
  key_pair_name = var.key_pair_name
  region_index = 2
  validator_count = var.validator_count
}

module "snarkos_node_setup_east2" {
  providers = {
    aws = aws.east2
  }
  source        = "./modules/attacker_tx_cannon_setup"
  region        = "us-east-2"
  instance_count = var.attacker_tx_cannon_count
  instance_type = var.instance_type_attacker_tx_cannon
  key_pair_name = var.key_pair_name
  region_index = 3
  validator_count = var.validator_count
}

module "snarkos_node_setup_ap-southeast-1" {
  providers = {
    aws = aws.ap-southeast-1
  }
  source        = "./modules/attacker_tx_cannon_setup"
  region        = "ap-southeast-1"
  instance_count = var.attacker_tx_cannon_count
  instance_type = var.instance_type_attacker_tx_cannon
  key_pair_name = var.key_pair_name
  region_index = 4
  validator_count = var.validator_count
}

module "snarkos_node_setup_ap-southeast-2" {
  providers = {
    aws = aws.ap-southeast-2
  }
  source        = "./modules/attacker_tx_cannon_setup"
  region        = "ap-southeast-2"
  instance_count = var.attacker_tx_cannon_count
  instance_type = var.instance_type_attacker_tx_cannon
  key_pair_name = var.key_pair_name
  region_index = 4
  validator_count = var.validator_count
}

module "snarkos_node_setup_ap-northeast-1" {
  providers = {
    aws = aws.ap-northeast-1
  }
  source        = "./modules/attacker_tx_cannon_setup"
  region        = "ap-northeast-1"
  instance_count = var.attacker_tx_cannon_count
  instance_type = var.instance_type_attacker_tx_cannon
  key_pair_name = var.key_pair_name
  region_index = 5
  validator_count = var.validator_count
}

module "snarkos_node_setup_ca-central-1" {
  providers = {
    aws = aws.ca-central-1
  }
  source        = "./modules/attacker_tx_cannon_setup"
  region        = "ca-central-1"
  instance_count = var.attacker_tx_cannon_count
  instance_type = var.instance_type_attacker_tx_cannon
  key_pair_name = var.key_pair_name
  region_index = 6
  validator_count = var.validator_count
}

module "snarkos_node_setup_eu-central-1" {
  providers = {
    aws = aws.eu-central-1
  }
  source        = "./modules/attacker_tx_cannon_setup"
  region        = "eu-central-1"
  instance_count = var.attacker_tx_cannon_count
  instance_type = var.instance_type_attacker_tx_cannon
  key_pair_name = var.key_pair_name
  region_index = 7
  validator_count = var.validator_count
}

module "snarkos_node_setup_eu-west-1" {
  providers = {
    aws = aws.eu-west-1
  }
  source        = "./modules/attacker_tx_cannon_setup"
  region        = "eu-west-1"
  instance_count = var.attacker_tx_cannon_count
  instance_type = var.instance_type_attacker_tx_cannon
  key_pair_name = var.key_pair_name
  region_index = 8
  validator_count = var.validator_count
}

module "snarkos_node_setup_eu-west-2" {
  providers = {
    aws = aws.eu-west-2
  }
  source        = "./modules/attacker_tx_cannon_setup"
  region        = "eu-west-2"
  instance_count = var.attacker_tx_cannon_count
  instance_type = var.instance_type_attacker_tx_cannon
  key_pair_name = var.key_pair_name
  region_index = 9
  validator_count = var.validator_count
}

module "snarkos_node_setup_eu-west-3" {
  providers = {
    aws = aws.eu-west-3
  }
  source        = "./modules/attacker_tx_cannon_setup"
  region        = "eu-west-3"
  instance_count = var.attacker_tx_cannon_count
  instance_type = var.instance_type_attacker_tx_cannon
  key_pair_name = var.key_pair_name
  region_index = 10
  validator_count = var.validator_count
}

module "snarkos_node_setup_eu-north-1" {
  providers = {
    aws = aws.eu-north-1
  }
  source        = "./modules/attacker_tx_cannon_setup"
  region        = "eu-north-1"
  instance_count = var.attacker_tx_cannon_count
  instance_type = var.instance_type_attacker_tx_cannon
  key_pair_name = var.key_pair_name
  region_index = 11
  validator_count = var.validator_count
}

module "snarkos_node_setup_sa-east-1" {
  providers = {
    aws = aws.sa-east-1
  }
  source        = "./modules/attacker_tx_cannon_setup"
  region        = "sa-east-1"
  instance_count = var.attacker_tx_cannon_count
  instance_type = var.instance_type_attacker_tx_cannon
  key_pair_name = var.key_pair_name
  region_index = 12
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

output "validator_ips" {
  value = module.snarkos_node_setup_west1.instance_ips
}

output "snarkos_lb_dns_name" {
  value = module.snarkos_node_setup_west1.snarkos_lb_dns_name
}