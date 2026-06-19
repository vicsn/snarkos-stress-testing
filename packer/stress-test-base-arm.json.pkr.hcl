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

data "amazon-ami" "stress-test-base" {
  access_key = "${var.aws_access_key}"
  filters = {
    name                = "ubuntu/images/hvm-ssd/ubuntu-*-22.04-*-server-*"
    architecture        = "arm64"
    root-device-type    = "ebs"
    virtualization-type = "hvm"

  }
  most_recent = true
  owners      = ["amazon"]
  region      = "us-east-1"
  secret_key  = "${var.aws_secret_key}"
}

locals { timestamp = regex_replace(timestamp(), "[- TZ:]", "") }

source "amazon-ebs" "stress-test-base" {
  access_key    = "${var.aws_access_key}"
  ami_name      = "stress-test-base-arm-${local.timestamp}"
  instance_type = "c7g.4xlarge"
  region        = "us-east-1"
  secret_key    = "${var.aws_secret_key}"
  source_ami    = "${data.amazon-ami.stress-test-base.id}"
  ssh_username  = "ubuntu"

  ami_regions = ["us-east-1", "us-east-2", "us-west-1", "us-west-2"]

  ami_groups = ["all"]
}

build {
  sources = ["source.amazon-ebs.stress-test-base"]

  provisioner "ansible" {
    extra_arguments = ["--scp-extra-args", "'-O'"]
    playbook_file   = "../common/ansible_playbooks/dependencies.yml"
  }

  provisioner "shell" {
    inline = [
      "for home in $(getent passwd | cut -d: -f6); do [ -d \"$home/.ansible\" ] && sudo rm -rf \"$home/.ansible\"; done",
    ]
  }
}
