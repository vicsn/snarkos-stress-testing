terraform {
  backend "gcs" {
    bucket = "tfstate-snarkos-stress-testing"
    prefix = "single-region-tests"
  }

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 7.32.0"
    }
  }
}

provider "google" {
  project = var.gcp_project
  region  = var.gcp_region
}
