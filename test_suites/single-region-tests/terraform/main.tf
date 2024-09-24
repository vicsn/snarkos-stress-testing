terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
  }
}

# ------------------------------------------------
# Generated key to be used for ssh access to the nodes

resource "aws_key_pair" "generated_key" {
  key_name   = "${var.devnet_name}-devnet-key"
  public_key = file("../${path.module}/devnet-key.pub")
}

# ------------------------------------------------
# Modules

module "stress_base_ami" {
  source = "./modules/stress_base_ami"
}

module "sg" {
  source      = "./modules/security_group"
  name        = "${var.devnet_name}-sg"
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
  tx_cannon_instance_count = var.tx_cannon_instance_count
  tx_cannon_instance_type = var.tx_cannon_instance_type
}

# ------------------------------------------------
# snarkOS validators

resource "aws_instance" "snarkos_validator" {
  count         = var.instance_count
  ami           = module.stress_base_ami.ami_id
  instance_type = var.instance_type
  key_name      = aws_key_pair.generated_key.key_name

  security_groups = [module.sg.security_group_name]

  ebs_block_device {
    device_name = "/dev/sda1"
    volume_size = 1000
    volume_type = "gp3"
  }

  tags = {
    Name = "${var.devnet_name}-snarkos-validator-${count.index}",
    Role = "snarkos-validator",
    Dev = count.index,
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

  security_groups = [module.sg.security_group_name]

  ebs_block_device {
    device_name = "/dev/sda1"
    volume_size = 1000
    volume_type = "gp3"
  }

  tags = {
    Name      = "${var.devnet_name}-snarkos-client-${each.key}",
    Role      = "snarkos-client",
    Dev       = each.value.index,
    Type      = each.value.type,
    Validator = each.value.validator,
    Devnet     = var.devnet_name
  }
}

# Load Balancer for snarkOS clients
data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  sanitized_devnet_name = lower(replace(var.devnet_name, "/[^a-zA-Z0-9-]/", "-"))
}

resource "aws_elb" "snarkos_lb" {
  name               = "${substr(local.sanitized_devnet_name, 0, 15)}-snarkos-lb"
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
    target              = "HTTP:3030/mainnet/latest/height"
  }

  instances = [for i in aws_instance.snarkos_client : i.id]

  tags = {
    Name = "${var.devnet_name}-snarkos-lb"
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
  instance_type = var.instance_type
  key_name      = aws_key_pair.generated_key.key_name
  security_groups = [module.sg.security_group_name]

  ebs_block_device {
    device_name = "/dev/sda1"
    volume_size = 80
    volume_type = "gp3"
  }

  tags = {
    Name = "${var.devnet_name}-prometheus-server"
    Role = "prometheus-server"
    Devnet = var.devnet_name
  }
}