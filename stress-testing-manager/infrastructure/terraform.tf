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

variable "STRESS_TESTING_BRANCH" {
  type    = string
  default = "main"
}

terraform {
  backend "s3" {
    bucket               = "ephnet-terraform-state-bucket-stm"
    workspace_key_prefix = "terraform/state/stm"
    key                  = "terraform.tfstate"
    region               = "us-west-2"
    profile              = "ephnet"
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.7"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
  }
}

provider "aws" {
  region  = var.AWS_REGION
  profile = "ephnet"
}

