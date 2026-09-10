variable "owners" {
  description = "List of AMI owners"
  type        = list(string)
  default     = [
    "637423331354",
  ]
}

data "aws_ami" "latest_stress_test_base_ubuntu" {
  most_recent = true

  filter {
    name   = "name"
    values = ["stress-test-base-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = var.owners
}

output "ami_id" {
  value = data.aws_ami.latest_stress_test_base_ubuntu.id
}
