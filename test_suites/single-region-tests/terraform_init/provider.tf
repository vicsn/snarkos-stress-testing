terraform {
  # This module bootstraps the remote state bucket itself, so it uses local state.
  # After initial apply, the main terraform/ stack uses the GCS backend created here.
  backend "local" {}

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
