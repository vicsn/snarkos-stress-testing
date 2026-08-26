# ------------------------------------------------
# GCS bucket for test run logs and results
#
# full_run.sh and collect-logs.sh upload zipped logs here after each test run.
# Path: gs://provable-logs-results/manual_test_runs/<user>/<RUN_ID>/<test>/
#
# The bucket already exists in GCS (managed out-of-band); this declares it in
# Terraform so lifecycle rules and IAM bindings are tracked as code. The STM
# service account already receives objectAdmin via a project-level conditional
# binding in iam.tf; this file adds bucket-scoped bindings for the pre-existing
# terraform SA (data source) and read access for project viewers.

# ------------------------------------------------
# Pre-existing terraform service account — looked up as a data source.
# Created out-of-band by:
#   https://github.com/ProvableHQ/infrastructure/tree/main/gcs/protocol-development-sandbox/workload

data "google_service_account" "terraform" {
  account_id = "snarkos-stress-testing"
  project    = var.gcp_project
}

# ------------------------------------------------
# Results bucket

resource "google_storage_bucket" "results" {
  name     = var.results_bucket
  location = var.gcp_region
  project  = var.gcp_project

  force_destroy               = false
  uniform_bucket_level_access = true

  versioning {
    enabled = false
  }

  lifecycle_rule {
    condition {
      age = 180 # clean up logs older than 6 months
    }
    action {
      type = "Delete"
    }
  }

  labels = {
    purpose = "test-logs"
    service = "stress-testing-manager"
  }
}

# Pre-existing terraform SA can upload logs from test runs
resource "google_storage_bucket_iam_member" "sa_results_admin" {
  bucket = google_storage_bucket.results.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${data.google_service_account.terraform.email}"
}

# All project viewers can download logs
resource "google_storage_bucket_iam_member" "results_viewer" {
  bucket = google_storage_bucket.results.name
  role   = "roles/storage.objectViewer"
  member = "projectViewer:${var.gcp_project}"
}
