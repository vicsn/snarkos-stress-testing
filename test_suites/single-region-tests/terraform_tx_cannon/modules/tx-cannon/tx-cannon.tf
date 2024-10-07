variable "tx_cannon_instance_type" {
  description = "Instance type for tx-cannon nodes"
  default     = "m5.2xlarge"
}

variable "tx_cannon_instance_count" {
  description = "Number of tx-cannon nodes"
  default     = 4
}

variable "ami_id" {
  description = "The ami id"
}

variable "key_name" {
  description = "The key name"
}

variable "sec_group_name" {
  description = "The security group"
}

variable "devnet_name" {
  description = "The devnet"
}

resource "aws_instance" "tx_cannon_node" {
  count         = var.tx_cannon_instance_count
  ami           = var.ami_id
  instance_type = var.tx_cannon_instance_type
  key_name      = var.key_name

  security_groups = [var.sec_group_name]

  ebs_block_device {
    device_name = "/dev/sda1"
    volume_size = 20  # Adjust the volume size if needed
  }

  tags = {
    Name = "tx-cannon-node-${count.index}",
    Role = "tx-cannon-node",
    Dev = count.index
    Devnet = var.devnet_name
  }
}
