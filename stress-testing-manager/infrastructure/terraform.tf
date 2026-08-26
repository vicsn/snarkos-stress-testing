# ------------------------------------------------
# Terraform backend + providers for the GCP Stress Testing Manager.
#
# State lives in GCS bucket "tfstate-snarkos-stress-testing" under
# prefix "stress-testing-manager". Workspaces (default, staging)
# map to state files "<prefix>/default.tfstate", "<prefix>/staging.tfstate".
#
# The GCS bucket is provisioned separately by
# test_suites/single-region-tests/terraform_init/.

terraform {
  required_version = ">= 1.10"

  backend "gcs" {
    bucket = "tfstate-snarkos-stress-testing"
    prefix = "stress-testing-manager"
  }

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 7.32.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.7"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }
  }
}

provider "google" {
  project = var.gcp_project
  region  = var.gcp_region
}
