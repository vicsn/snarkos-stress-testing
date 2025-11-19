terraform {
  backend "s3" {
    key            = "terraform/state/network-sync-tests/terraform.tfstate"
    region         = "us-west-2"
    profile        = "ephnet"
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

# ------------------------------------------------
# snarkOS clients

resource "aws_instance" "snarkos_client" {
  for_each = { for idx, client in local.snarkos_clients : "${client.index}" => client }

  ami           = module.stress_base_ami.ami_id
  instance_type = each.value.type
  key_name      = aws_key_pair.generated_key.key_name
  iam_instance_profile = aws_iam_instance_profile.snarkos_ec2_instance_profile.name

  security_groups = [module.sg.security_group_name]

  ebs_block_device {
    device_name = "/dev/sda1"
    volume_size = var.volume_size
    volume_type = "gp3"
  }

  tags = {
    Name      = "${var.devnet_name}-snarkos-sync-client-${each.value.index}",
    Role      = "snarkos-client",
    Index     = each.value.index,
    Type      = each.value.type,
    Devnet    = var.devnet_name
  }
}

# Load Balancer for snarkOS clients
data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  sanitized_devnet_name = lower(replace(var.devnet_name, "/[^a-zA-Z0-9-]/", "-"))

  # Dynamically create client list based on client_count variable
  snarkos_clients = [
    for i in range(var.client_count) : {
      type = var.client_instance_type, 
      index = i 
    }
  ]
}

# ------------------------------------------------
# Prometheus Server used to collect metrics from snarkOS nodes

resource "aws_instance" "prometheus_server" {
  ami           = module.stress_base_ami.ami_id
  instance_type = "t2.medium"
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

resource "aws_elb" "snarkos_lb" {
  name               = "${substr(local.sanitized_devnet_name, 0, 10)}-snarkos-lb"
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
    target              = "HTTP:3030/${var.snarkos_network}/block/height/latest"
  }

  instances = [for i in aws_instance.snarkos_client : i.id]

  tags = {
    Name   = "${var.devnet_name}-snarkos-lb"
    Devnet = var.devnet_name
  }
}

output "devnet_name" {
  value = var.devnet_name
  description = "The devnet_name name"
}

output "snarkos_lb_dns_name" {
  value = aws_elb.snarkos_lb.dns_name
}
