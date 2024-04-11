# ------------------------------------------------
# Generated key to be used for ssh access to the nodes

resource "aws_key_pair" "generated_key" {
  key_name   = "devnet-key"
  public_key = file("../${path.module}/devnet-key.pub")
}

# ------------------------------------------------
# Modules

module "stress_base_ami" {
  source = "../../../common/terraform_modules/stress_base_ami"
  # source = "../../../common/terraform_modules/ubuntu_ami"
}

module "sg" {
  source      = "../../../common/terraform_modules/security_group"
  name        = "sg"
  description = "Security group for all nodes"
}

# ------------------------------------------------
# snarkOS nodes

resource "aws_instance" "snarkos_node" {
  count         = var.instance_count
  ami           = module.stress_base_ami.ami_id
  instance_type = var.instance_type
  key_name      = aws_key_pair.generated_key.key_name

  security_groups = [module.sg.security_group_name]

  ebs_block_device {
    device_name = "/dev/sda1"
    volume_size = 80
  }

  tags = {
    Name = "snarkos-node-${count.index}",
    Role = "snarkos-node",
    Dev = count.index
  }
}

# Load Balancer for snarkOS nodes
data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_elb" "snarkos_lb" {
  name               = "snarkos-lb"
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

  instances = [for i in aws_instance.snarkos_node : i.id]

  tags = {
    Name = "snarkos-lb"
  }
}

output "snarkos_lb_dns_name" {
  value = aws_elb.snarkos_lb.dns_name
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
  }

  tags = {
    Name = "prometheus-server"
    Role = "prometheus-server"
  }
}

# ------------------------------------------------
# tx-cannon nodes

resource "aws_instance" "tx_cannon_bond_node" {
  count         = var.tx_cannon_bond_instance_count
  ami           = module.stress_base_ami.ami_id
  instance_type = var.tx_cannon_instance_type
  key_name      = aws_key_pair.generated_key.key_name

  security_groups = [module.sg.security_group_name]

  ebs_block_device {
    device_name = "/dev/sda1"
    volume_size = 20
  }

  tags = {
    Name = "tx-cannon-bond-node-${count.index}",
    Role = "tx-cannon-bond-node",
    Dev = count.index
  }
}


resource "aws_instance" "tx_cannon_unbond_node" {
  count         = var.tx_cannon_unbond_instance_count
  ami           = module.stress_base_ami.ami_id
  instance_type = var.tx_cannon_instance_type
  key_name      = aws_key_pair.generated_key.key_name

  security_groups = [module.sg.security_group_name]

  ebs_block_device {
    device_name = "/dev/sda1"
    volume_size = 20
  }

  tags = {
    Name = "tx-cannon-unbond-node-${count.index}",
    Role = "tx-cannon-unbond-node",
    Dev = count.index
  }
}