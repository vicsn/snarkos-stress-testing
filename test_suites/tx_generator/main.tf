# main.tf
variable "aws_region" {
  default     = "us-west-2"
}

resource "aws_key_pair" "generated_key" {
  key_name   = "devnet-key-${var.aws_region}"
  public_key = file("${path.module}/devnet-key.pub")
}

# Add variables for tx-cannon instance configuration
variable "tx_cannon_instance_type" {
  description = "Instance type for tx-cannon nodes"
  default     = "c5.24xlarge"
}

variable "tx_cannon_instance_count" {
  description = "Number of tx-cannon nodes"
  default     = 5
}

# Resource block for tx-cannon instances
resource "aws_instance" "tx_cannon_node" {
  count         = var.tx_cannon_instance_count
  ami           = data.aws_ami.latest_ubuntu.id
  instance_type = var.tx_cannon_instance_type
  key_name      = aws_key_pair.generated_key.key_name

  security_groups = [aws_security_group.snarkos_sg.name]

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
