# Have `export TF_VAR_AWS_ACCESS_KEY=<val>` and `export TF_VAR_AWS_SECRET_KEY=<val>` to specify these
# if you don't want to input them

variable "AWS_ACCESS_KEY" {}
variable "AWS_SECRET_KEY" {}
variable "ARDBEG_SECRET" {
  type    = string
  default = "deprecated"
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
  region  = "eu-central-1"
  access_key = var.AWS_ACCESS_KEY
  secret_key = var.AWS_SECRET_KEY
}

