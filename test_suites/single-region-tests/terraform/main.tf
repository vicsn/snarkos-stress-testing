terraform {
  backend "local" {}
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

resource "null_resource" "noop" {}

# ------------------------------------------------
# Generated key to be used for ssh access to the nodes

resource "aws_key_pair" "generated_key" {
  key_name   = "${var.owner}-${var.devnet_name}-devnet-key"
  public_key = file("../${path.module}/devnet-key.pub")
}

# ------------------------------------------------
# Modules

module "stress_base_ami" {
  source = "./modules/stress_base_ami"
}

module "sg" {
  source      = "./modules/security_group"
  name        = "${var.owner}-${var.devnet_name}-sg"
  description = "Security group for all nodes in ${var.devnet_name}"
}

variable "add_tx_cannons" {
  default = false
}

variable "tx_cannon_instance_count" {
  description = "Number of tx-cannon nodes"
  default     = 4
}

variable "tx_cannon_instance_type" {
  description = "Instance type for tx-cannon nodes"
  default     = "m5.2xlarge"
}

module "tx-cannon" {
  source = "./modules/tx-cannon"
  count  = var.add_tx_cannons ? 1 : 0
  ami_id = module.stress_base_ami.ami_id
  key_name = aws_key_pair.generated_key.key_name
  sec_group_name = module.sg.security_group_name
  devnet_name = var.devnet_name
  owner = var.owner
  tx_cannon_instance_count = var.tx_cannon_instance_count
  tx_cannon_instance_type = var.tx_cannon_instance_type
}

# ------------------------------------------------
# snarkOS validators

resource "aws_instance" "snarkos_validator" {
  count         = var.validator_instance_count
  ami           = module.stress_base_ami.ami_id
  instance_type = var.validator_instance_type
  key_name      = aws_key_pair.generated_key.key_name
  iam_instance_profile = aws_iam_instance_profile.snarkos_ec2_instance_profile.name

  security_groups = [module.sg.security_group_name]

  ebs_block_device {
    device_name = "/dev/sda1"
    volume_size = 1000
    volume_type = "gp3"
  }

  tags = {
    Name = "${var.owner}-${var.devnet_name}-snarkos-validator-${count.index}",
    Role = "snarkos-validator",
    Dev = count.index,
    Owner = "${var.owner}"
    Devnet = var.devnet_name
  }
}

# ------------------------------------------------
# snarkOS clients

resource "aws_instance" "snarkos_client" {
  for_each = { for client in local.snarkos_clients : "val${client.validator}-client${client.index}" => client }

  ami           = module.stress_base_ami.ami_id
  instance_type = each.value.type
  key_name      = aws_key_pair.generated_key.key_name
  iam_instance_profile = aws_iam_instance_profile.snarkos_ec2_instance_profile.name

  security_groups = [module.sg.security_group_name]

  ebs_block_device {
    device_name = "/dev/sda1"
    volume_size = 1000
    volume_type = "gp3"
  }

  tags = {
    Name      = "${var.owner}-${var.devnet_name}-snarkos-client-${each.key}",
    Role      = "snarkos-client",
    Dev       = each.value.index,
    Owner     = "${var.owner}",
    Type      = each.value.type,
    Validator = each.value.validator,
    Devnet    = var.devnet_name
  }
}

# ------------------------------------------------
# snarkOS provers

resource "aws_instance" "snarkos_prover" {
  count         = var.prover_instance_count
  ami           = module.stress_base_ami.ami_id
  instance_type = var.prover_instance_type
  key_name      = aws_key_pair.generated_key.key_name
  iam_instance_profile = aws_iam_instance_profile.snarkos_ec2_instance_profile.name

  security_groups = [module.sg.security_group_name]

  ebs_block_device {
    device_name = "/dev/sda1"
    volume_size = 1000
    volume_type = "gp3"
  }

  tags = {
    Name = "${var.owner}-${var.devnet_name}-snarkos-prover-${count.index}",
    Role = "snarkos-prover",
    Dev = count.index,
    Owner = "${var.owner}"
    Devnet = var.devnet_name
  }
}

# Load Balancer for snarkOS clients
data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  sanitized_devnet_name = lower(replace(var.devnet_name, "/[^a-zA-Z0-9-]/", "-"))
}

locals {
  sanitized_owner = lower(replace(var.owner, "/[^a-zA-Z0-9-]/", "-"))
}

resource "aws_elb" "snarkos_lb" {
  name               = "${substr(local.sanitized_owner, 0, 6)}-${substr(local.sanitized_devnet_name, 0, 10)}-snarkos-lb"
  security_groups    = [module.sg.security_group_id]
  availability_zones = data.aws_availability_zones.available.names

  listener {
    instance_port     = 3030
    instance_protocol = "http"
    lb_port           = 3030
    lb_protocol       = "http"
  }

  health_check {
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 3
    interval            = 30
    target              = "HTTP:3030/${local.snarkos_network}/block/height/latest"
  }

  instances = [for i in aws_instance.snarkos_validator : i.id]

  tags = {
    Name   = "${var.owner}-${var.devnet_name}-snarkos-lb"
    Owner  = "${var.owner}"
    Devnet = var.devnet_name
  }
}

output "snarkos_lb_dns_name" {
  value = aws_elb.snarkos_lb.dns_name
}

output "instance_ips" {
  value = aws_instance.snarkos_validator.*.public_ip
}

# ------------------------------------------------
# Prometheus Server used to collect metrics from snarkOS nodes

resource "aws_instance" "prometheus_server" {
  ami           = module.stress_base_ami.ami_id
  instance_type = var.client_instance_type
  key_name      = aws_key_pair.generated_key.key_name
  security_groups = [module.sg.security_group_name]

  ebs_block_device {
    device_name = "/dev/sda1"
    volume_size = 80
    volume_type = "gp3"
  }

  tags = {
    Name   = "${var.owner}-${var.devnet_name}-prometheus-server"
    Role   = "prometheus-server"
    Owner  = "${var.owner}"
    Devnet = var.devnet_name
  }
}

output "snarkos_network" {
  value = local.snarkos_network
  description = "The snarkos network name"
  depends_on  = [null_resource.noop]
}

output "devnet_name" {
  value = var.devnet_name
  description = "The devnet_name name"
  depends_on  = [null_resource.noop]
}

# ------------------------------------------------
# Ephemeral builder machine for compiling snarkOS

variable "add_builder" {
  default = false
}

variable "builder_instance_type" {
  description = "Instance type for the ephemeral snarkOS builder"
  default     = "c7i.8xlarge"
}

resource "aws_instance" "snarkos_builder" {
  count                = var.add_builder ? 1 : 0
  ami                  = module.stress_base_ami.ami_id
  instance_type        = var.builder_instance_type
  key_name             = aws_key_pair.generated_key.key_name
  iam_instance_profile = aws_iam_instance_profile.snarkos_ec2_instance_profile.name
  security_groups      = [module.sg.security_group_name]

  ebs_block_device {
    device_name = "/dev/sda1"
    volume_size = 128
    volume_type = "gp3"
  }

  tags = {
    Name   = "${var.owner}-${var.devnet_name}-snarkos-builder"
    Role   = "builder"
    Owner  = var.owner
    Devnet = var.devnet_name
  }
}

output "snarkos_builder_ip" {
  value       = length(aws_instance.snarkos_builder) > 0 ? aws_instance.snarkos_builder[0].public_ip : ""
  description = "Public IP of the ephemeral snarkOS builder instance (empty when not provisioned)"
}
