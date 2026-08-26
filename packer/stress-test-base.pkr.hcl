packer {
  required_plugins {
    googlecompute = {
      source  = "github.com/hashicorp/googlecompute"
      version = "~> 1"
    }
    ansible = {
      source  = "github.com/hashicorp/ansible"
      version = "~> 1"
    }
  }
}

variable "gcp_project" {
  type    = string
  default = "protocol-development-sandbox"
}

variable "gcp_zone" {
  type    = string
  default = "us-central1-b"
}

variable "machine_type" {
  type    = string
  default = "c3d-standard-8"
}

variable "image_family" {
  type        = string
  default     = "stress-test-base"
  description = "Image family name for the output image"
}

variable "source_image_family" {
  type        = string
  default     = "ubuntu-2204-lts"
  description = "Image family name for the source image"
}

variable "disk_size" {
  type        = number
  default     = 50
  description = "Size of disk (gigabytes) for GCE packer instance"
}

variable "ssh_username" {
  type        = string
  default     = "ubuntu"
  description = "Username for ssh access to GCE packer instance"
}

variable "network" {
  type        = string
  default     = "vpc-protocol-development-sandbox"
  description = "VPC network name or self_link for the builder instance. Empty = default network."
}

variable "subnetwork" {
  type        = string
  default     = ""
  description = "Subnet name or self_link for the builder instance. Empty = auto-select."
}

locals {
  timestamp = regex_replace(timestamp(), "[- TZ:]", "")
}

source "googlecompute" "stress-test-base" {
  project_id              = var.gcp_project
  zone                    = var.gcp_zone
  source_image_family     = var.source_image_family
  source_image_project_id = ["ubuntu-os-cloud"]
  image_name              = "${var.image_family}-${local.timestamp}"
  image_family            = var.image_family
  image_description       = "Stress-test base image with Docker, monitoring, and dependencies"
  machine_type            = var.machine_type
  disk_size               = var.disk_size
  disk_type               = "pd-ssd"
  ssh_username            = var.ssh_username
  use_os_login            = false
  network                 = var.network
  subnetwork              = var.subnetwork

  image_labels = {
    managed-by = "packer"
    purpose    = "stress-testing"
  }
}

build {
  sources = ["source.googlecompute.stress-test-base"]

  provisioner "ansible" {
    user            = "ubuntu"
    extra_arguments = ["--scp-extra-args", "'-O'"]
    playbook_file   = "playbooks/dependencies.yml"
  }

  provisioner "shell" {
    inline = [
      "for home in $(getent passwd | cut -d: -f6 | sort -u); do [ -d \"$home/.ansible\" ] && sudo rm -rf \"$home/.ansible\" || true; done",
    ]
  }
}
