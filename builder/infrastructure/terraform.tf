# Have `export TF_VAR_AWS_ACCESS_KEY=<val>` and `export TF_VAR_AWS_SECRET_KEY=<val>` to specify these
# if you don't want to input them

variable "AWS_REGION" {
  type    = string
  default = "us-west-2"
}
variable "ARDBEG_SECRET" {
  type    = string
  default = "deprecated"
}

variable "RELEASES_BUCKET" {
  default = "provable-binaries-releases"
}

variable "RESULTS_BUCKET" {
  default = "provable-logs-results"
}

# Can be overwritten with setting `TF_VAR_PUBLIC_KEY_PATH=...` before `terraform apply`
variable "PUBLIC_KEY_PATH" {
  default = "~/.ssh/id_ed25519.pub"
}

variable github_token {
  sensitive = true
}

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region  = var.AWS_REGION
  profile = "ephnet"
}

