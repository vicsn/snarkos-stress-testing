# ------------------------------------------------
# terraform_init — bootstraps shared GCS buckets + IAM bindings
#
# The tfstate bucket and service account are managed externally:
#   https://github.com/ProvableHQ/infrastructure/tree/main/gcs/protocol-development-sandbox/workload
#
# Run ONCE before the main terraform/ stack:
#   cd terraform_init && terraform init && terraform apply
#
# Created by this module:
#   Release bucket : ${release_bucket_name}  (snarkOS binaries)
#
# Pre-existing (data sources):
#   SA             : ${service_name}@${gcp_project}.iam.gserviceaccount.com
#   State bucket   : tfstate-${service_name}

locals {
  tfstate_bucket = "tfstate-${var.service_name}"
  sa_email       = "${var.service_name}@${var.gcp_project}.iam.gserviceaccount.com"
}

# ------------------------------------------------
# Pre-existing resources — looked up as data sources
#
# Created by: https://github.com/ProvableHQ/infrastructure/tree/main/gcs/protocol-development-sandbox/workload
# Do NOT create or destroy these from here.

data "google_storage_bucket" "tfstate" {
  name = local.tfstate_bucket
}

data "google_service_account" "terraform" {
  account_id = var.service_name
  project    = var.gcp_project
}

# ------------------------------------------------
# IAM bindings for pre-existing service account

# SA can read/write state objects in the bucket
resource "google_storage_bucket_iam_member" "sa_state_admin" {
  bucket = data.google_storage_bucket.tfstate.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${data.google_service_account.terraform.email}"
}

# SA needs compute/IAM permissions to manage infrastructure
resource "google_project_iam_member" "sa_compute_admin" {
  project = var.gcp_project
  role    = "roles/compute.admin"
  member  = "serviceAccount:${data.google_service_account.terraform.email}"
}

resource "google_project_iam_member" "sa_iam_user" {
  project = var.gcp_project
  role    = "roles/iam.serviceAccountUser"
  member  = "serviceAccount:${data.google_service_account.terraform.email}"
}

resource "google_project_iam_member" "sa_storage_admin" {
  project = var.gcp_project
  role    = "roles/storage.admin"
  member  = "serviceAccount:${data.google_service_account.terraform.email}"
}

# ------------------------------------------------
# GCS bucket for snarkOS release binaries
#
# Ephemeral builder uploads compiled binaries here; setup.yml downloads them
# to /usr/bin/snarkos on all nodes. Keyed by release_name (<hash>[_<features>]).

resource "google_storage_bucket" "releases" {
  name     = var.release_bucket_name
  location = var.gcp_region
  project  = var.gcp_project

  force_destroy               = false
  uniform_bucket_level_access = true

  versioning {
    enabled = false
  }

  lifecycle_rule {
    condition {
      age = 90 # clean up binaries older than 90 days
    }
    action {
      type = "Delete"
    }
  }

  lifecycle_rule {
    condition {
      age            = 14 # clean up stress-testing/*Z.tar.gz snapshots older than 14 days
      matches_prefix = ["stress-testing/stress-testing-20"]
      matches_suffix = ["Z.tar.gz"]
    }
    action {
      type = "Delete"
    }
  }

  labels = {
    purpose = "release-binaries"
    service = replace(var.service_name, "/[^a-z0-9-]/", "-")
  }
}

# SA can upload + download binaries
resource "google_storage_bucket_iam_member" "sa_releases_admin" {
  bucket = google_storage_bucket.releases.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${data.google_service_account.terraform.email}"
}

# All compute instances (via their SA) can read binaries
resource "google_storage_bucket_iam_member" "releases_viewer" {
  bucket = google_storage_bucket.releases.name
  role   = "roles/storage.objectViewer"
  member = "projectViewer:${var.gcp_project}"
}

# ------------------------------------------------
# Additional state admins (human users, groups, other SAs)

resource "google_storage_bucket_iam_member" "extra_state_admins" {
  for_each = toset(var.state_admins)
  bucket   = data.google_storage_bucket.tfstate.name
  role     = "roles/storage.objectAdmin"
  member   = each.value
}
