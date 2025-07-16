variable "PUBLIC_KEY_PATH" {
}

data "aws_ami" "ubuntu_ami" {
  most_recent = true

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  owners = ["099720109477"]
}

output "ami_id" {
  value = data.aws_ami.ubuntu_ami.id
}

resource "aws_key_pair" "main_key" {
    key_name   = "single-machine-with-ssh-forwarding-main-key"
    public_key = file("${var.PUBLIC_KEY_PATH}")
}

resource "aws_security_group" "single_machine_with_ssh_forwarding_sg" {
  name        = "single_machine_with_ssh_forwarding_sg"
  description = "Security group for the single machine with ssh forwarding"
}

resource "aws_vpc_security_group_ingress_rule" "allow_ssh_ipv4" {
  security_group_id = aws_security_group.single_machine_with_ssh_forwarding_sg.id
  from_port         = 22
  to_port           = 22
  ip_protocol       = "tcp"
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_egress_rule" "allow_all_traffic_ipv4" {
  security_group_id = aws_security_group.single_machine_with_ssh_forwarding_sg.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

resource "aws_instance" "single_machine_with_ssh_forwarding" {
  ami                         = data.aws_ami.ubuntu_ami.id
  instance_type               = "m7i.16xlarge"
  associate_public_ip_address = true
  key_name                    = aws_key_pair.main_key.key_name

  ebs_block_device {
    device_name = "/dev/sda1"
    volume_size = 2000
    volume_type = "gp2"
  }

  vpc_security_group_ids      = [
    aws_security_group.single_machine_with_ssh_forwarding_sg.id
  ]

  tags = {
    Name = "Single Machine With SSH Forwarding"
  }
}

output "public_ip" {
  value = aws_instance.single_machine_with_ssh_forwarding.public_ip
}

provider "aws" {
  profile = "ephnet"
}

