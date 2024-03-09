# main.tf

# General AWS configs
variable "aws_region" {
  default     = "us-east-2"
}

provider "aws" {
  region = var.aws_region
}

resource "aws_key_pair" "generated_key" {
  key_name   = "devnet-key-${var.aws_region}"
  public_key = file("${path.module}/devnet-key.pub")
}

# Instance types and counts for various roles in the setup
variable "standard_node_instance_type" {
  description = "Instance type for standard snarkOS nodes"
  default     = "m5.4xlarge"
}

variable "standard_node_count" {
  description = "Number of standard snarkOS nodes"
  default     = 9
}

variable "malicious_node_instance_type" {
  description = "Instance type for malicious snarkOS nodes"
  default     = "m5.4xlarge"
}

variable "malicious_node_count" {
  description = "Number of malicious snarkOS nodes"
  default     = 1
}

variable "default_instance_type" {
  description = "Instance type for client nodes"
  default     = "m5.4xlarge"
}

variable "tx_cannon_instance_type" {
  description = "Instance type for tx-cannon nodes"
  default     = "t2.medium"
}

variable "tx_cannon_instance_count" {
  description = "Number of tx-cannon nodes"
  default     = 2
}

# Resource block for standard snarkOS nodes
resource "aws_instance" "snarkos_node_standard" {
  count         = var.standard_node_count
  ami           = data.aws_ami.latest_ubuntu.id
  instance_type = var.standard_node_instance_type
  key_name      = aws_key_pair.generated_key.key_name

  security_groups = [aws_security_group.snarkos_sg.name]

  ebs_block_device {
    device_name = "/dev/sda1"
    volume_size = 80
  }

  tags = {
    Name = "snarkos-node-standard-${count.index}",
    Role = "snarkos-node-standard",
    Dev = count.index
  }
}

# Resource block for malicious snarkOS nodes
resource "aws_instance" "snarkos_node_malicious" {
  count         = var.malicious_node_count
  ami           = data.aws_ami.latest_ubuntu.id
  instance_type = var.malicious_node_instance_type
  key_name      = aws_key_pair.generated_key.key_name

  security_groups = [aws_security_group.snarkos_sg.name]

  ebs_block_device {
    device_name = "/dev/sda1"
    volume_size = 80
  }

  tags = {
    Name = "snarkos-node-malicious-${count.index}",
    Role = "snarkos-node-malicious",
    Dev = var.standard_node_count + count.index
  }
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

# Security group for snarkOS nodes
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

# Load balancer for standard snarkOS nodes
# Uncomment this block if you want a separate load balancer for standard snarkOS nodes
# resource "aws_elb" "snarkos_lb_standard" {
#   name               = "snarkos-lb-standard"
#   security_groups    = [aws_security_group.snarkos_sg.id]
#   availability_zones = data.aws_availability_zones.available.names
#
#   listener {
#     instance_port     = 3030
#     instance_protocol = "http"
#     lb_port           = 3030
#     lb_protocol       = "http"
#   }
#
#   health_check {
#     healthy_threshold   = 2
#     unhealthy_threshold = 2
#     timeout             = 3
#     interval            = 30
#     target              = "HTTP:3030/mainnet/latest/height"
#   }
#
#   instances = [for i in aws_instance.snarkos_node_standard.*: i.id]
#
#   tags = {
#     Name = "snarkos-lb-standard"
#   }
# }
#
# output "snarkos_lb_standard_dns_name" {
#   value = aws_elb.snarkos_lb_standard.dns_name
# }

# Load balancer for malicious snarkOS nodes
# Uncomment this block if you want a separate load balancer for malicious snarkOS nodes
# resource "aws_elb" "snarkos_lb_malicious" {
#   name               = "snarkos-lb-malicious"
#   security_groups    = [aws_security_group.snarkos_sg.id]
#   availability_zones = data.aws_availability_zones.available.names
#
#   listener {
#     instance_port     = 3030
#     instance_protocol = "http"
#     lb_port           = 3030
#     lb_protocol       = "http"
#   }
#
#   health_check {
#     healthy_threshold   = 2
#     unhealthy_threshold = 2
#     timeout             = 3
#     interval            = 30
#     target              = "HTTP:3030/mainnet/latest/height"
#   }
#
#   instances = [for i in aws_instance.snarkos_node_malicious.*: i.id]
#
#   tags = {
#     Name = "snarkos-lb-malicious"
#   }
# }
#
# output "snarkos_lb_malicious_dns_name" {
#   value = aws_elb.snarkos_lb_malicious.dns_name
# }

# Load balancer for all snarkOS nodes
resource "aws_elb" "snarkos_lb_all" {
  name               = "snarkos-lb-all"
  security_groups    = [aws_security_group.snarkos_sg.id]
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

  instances = concat([for i in aws_instance.snarkos_node_standard.*: i.id], [for i in aws_instance.snarkos_node_malicious.*: i.id])

  tags = {
    Name = "snarkos-lb-all"
  }
}

output "snarkos_lb_all_dns_name" {
  value = aws_elb.snarkos_lb_all.dns_name
}

# snarkOS instance IPs
output "all_instance_ips" {
  value = concat(aws_instance.snarkos_node_standard.*.public_ip, aws_instance.snarkos_node_malicious.*.public_ip)
}

output "standard_instance_ips" {
  value = aws_instance.snarkos_node_standard.*.public_ip
}

output "malicious_instance_ips" {
  value = aws_instance.snarkos_node_malicious.*.public_ip
}

# Security group for Prometheus
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

  # Allow SSH traffic on port 22 (add this rule)
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

# Resource block for Prometheus
resource "aws_instance" "prometheus_server" {
  ami           = data.aws_ami.latest_ubuntu.id
  instance_type = var.default_instance_type
  key_name      = aws_key_pair.generated_key.key_name
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

# Prometheus server IP
output "prometheus_server_ip" {
  value = aws_instance.prometheus_server.public_ip
}
