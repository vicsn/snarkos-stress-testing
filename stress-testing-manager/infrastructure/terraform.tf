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

# We can put empty strings and then slack integration will be turned off
variable "SLACK_CHANNEL_ID" {}
variable "SLACK_TOKEN" {}

variable "ELASTIC_CLOUD_ID" {
  default = "your_elastic_cloud_id_here"
}

variable "ELASTIC_API_KEY" {
  default = "your_elastic_api_key_here"
}

variable "GRAFANA_CLOUD_API_KEY" {
  default = "your_grafana_cloud_api_key_here"
}

variable "TALISKER_BRANCH" {
  type    = string
  default = "master"
}

variable "STRESS_TESTING_BRANCH" {
  type    = string
  default = "main"
}

variable "PROVISION_RUN_ID" {
  type    = string
  default = ""
}

variable "PRE_RELEASE_PREFIX" {
  type    = string
  default = "prerelease"
}

variable "SYNC_PREFIX" {
  type    = string
  default = "sync"
}

variable "LOAD_LEDGER_PREFIX" {
  type    = string
  default = "load-ledger"
}

variable github_token {
  sensitive = true
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

