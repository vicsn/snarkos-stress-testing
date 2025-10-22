packer {
  required_plugins {
    amazon = {
      source  = "github.com/hashicorp/amazon"
      version = "~> 1"
    }
    ansible = {
      source  = "github.com/hashicorp/ansible"
      version = "~> 1"
    }
  }
}

variable "aws_access_key" {
  type    = string
  default = "${env("AWS_ACCESS_KEY_ID")}"
}

variable "aws_secret_key" {
  type    = string
  default = "${env("AWS_SECRET_ACCESS_KEY")}"
}

variable "aws_region" {
  type    = string
  default = "${env("AWS_REGION")}"
}

data "amazon-ami" "stress-testing-manager-base" {
  filters = {
    name                = "ubuntu/images/hvm-ssd/ubuntu-*-22.04-amd64-server-*"
    root-device-type    = "ebs"
    virtualization-type = "hvm"
  }
  most_recent = true
  owners      = ["099720109477"]
  region      = "${var.aws_region}"
}

locals { timestamp = regex_replace(timestamp(), "[- TZ:]", "") }

source "amazon-ebs" "stress-testing-manager-base" {
  #access_key    = "${var.aws_access_key}"
  #secret_key    = "${var.aws_secret_key}"
  ami_name      = "stress-testing-manager-base-${local.timestamp}"
  instance_type = "m5.4xlarge"
  region        = "${var.aws_region}"
  source_ami    = "${data.amazon-ami.stress-testing-manager-base.id}"
  ssh_username  = "ubuntu"

  launch_block_device_mappings {
    device_name = "/dev/sda1"
    volume_size = 100
    volume_type = "gp2"
    delete_on_termination = true
  }

  ami_regions = ["${var.aws_region}"]

  ami_groups = ["all"]
}

build {
  sources = ["source.amazon-ebs.stress-testing-manager-base"]

  provisioner "ansible" {
    extra_arguments = ["--scp-extra-args", "'-O'"]
    playbook_file   = "dependencies.yml"
  }
}
