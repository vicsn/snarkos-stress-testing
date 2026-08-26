# ------------------------------------------------
# GCP Service APIs required for STM operations.
#
# `iam.googleapis.com` — enables managing service accounts and IAM
# policies. Required for `google_service_account.stm_sa` (below) and
# transitively for `terraform apply` in test-suite Terraform, which
# creates `google_service_account.snarkos_sa` from the STM.
#
# `disable_on_destroy = false` so tearing down the STM stack does NOT
# disable the API — other tenants in this project rely on it.

resource "google_project_service" "iam_api" {
  project = var.gcp_project
  service = "iam.googleapis.com"

  disable_on_destroy = false
}
