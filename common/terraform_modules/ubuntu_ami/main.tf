variable "owners" {
  description = "List of AMI owners"
  type        = list(string)
  default     = ["099720109477"] # Canonical's owner ID for Ubuntu images by default
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

  owners = var.owners
}

output "ami_id" {
  value = data.aws_ami.latest_ubuntu.id
}
