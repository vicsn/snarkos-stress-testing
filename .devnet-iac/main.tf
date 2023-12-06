# main.tf
resource "aws_instance" "snarkos_node" {
  count         = var.instance_count
  ami           = data.aws_ami.latest_ubuntu.id
  instance_type = var.instance_type
  key_name      = var.key_pair_name

  security_groups = [aws_security_group.snarkos_sg.name]

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

resource "aws_security_group" "snarkos_sg" {
  name        = "snarkos_sg"
  description = "Security group for snarkOS nodes"

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 3033
    to_port     = 3033
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 4133
    to_port     = 4133
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

data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_elb" "snarkos_lb" {
  name               = "snarkos-lb"
  security_groups    = [aws_security_group.snarkos_sg.id]
  availability_zones = data.aws_availability_zones.available.names

  listener {
    instance_port     = 3033
    instance_protocol = "http"
    lb_port           = 3033
    lb_protocol       = "http"
  }

  health_check {
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 3
    interval            = 30
    target              = "HTTP:3033/testnet3/latest/height"
  }

  instances = [for i in aws_instance.snarkos_node : i.id]

  tags = {
    Name = "snarkos-lb"
  }
}
