# ------------------------------------------------
# Service Account attached to the STM instance.
#
# account_id is limited to 30 characters; we take the first 23 chars of the
# workspace name and suffix with "-stm-sa" (7 chars) to stay under the cap.

resource "google_service_account" "stm_sa" {
  account_id   = "${substr(local.stm_workspace, 0, 23)}-stm-sa"
  display_name = "Stress Testing Manager SA (${local.stm_workspace})"
  project      = var.gcp_project

  depends_on = [google_project_service.iam_api]
}

# ------------------------------------------------
# Compute — full compute.admin so `terraform apply` in test-suite Terraform
# can create VPC, subnet, firewall rules, target-pool LB, and instances.
# Subsumes compute.instanceAdmin.v1.

resource "google_project_iam_member" "stm_compute_admin" {
  project = var.gcp_project
  role    = "roles/compute.admin"
  member  = "serviceAccount:${google_service_account.stm_sa.email}"
}

# ------------------------------------------------
# OS Login — SSH into test nodes as the SA

resource "google_project_iam_member" "stm_oslogin" {
  project = var.gcp_project
  role    = "roles/compute.osLogin"
  member  = "serviceAccount:${google_service_account.stm_sa.email}"
}

resource "google_project_iam_member" "stm_sauser" {
  project = var.gcp_project
  role    = "roles/iam.serviceAccountUser"
  member  = "serviceAccount:${google_service_account.stm_sa.email}"
}

# ------------------------------------------------
# IAM — create the snarkos_sa service account in test-suite Terraform

resource "google_project_iam_member" "stm_service_account_admin" {
  project = var.gcp_project
  role    = "roles/iam.serviceAccountAdmin"
  member  = "serviceAccount:${google_service_account.stm_sa.email}"
}

# ------------------------------------------------
# IAM — grant project-level IAM bindings.
#
# Needed so `terraform apply` in test-suite Terraform can create the
# `google_project_iam_member` bindings that attach roles to snarkos_sa
# (6 bindings) and to admin_users (default: group:gcp-engineering-viewer@provable.com,
# 4 bindings). Broad project-wide grant matches the laptop's terraform SA
# posture; blast radius = full project IAM control if STM is compromised,
# accepted trade-off for a single-purpose automation node.

resource "google_project_iam_member" "stm_project_iam_admin" {
  project = var.gcp_project
  role    = "roles/resourcemanager.projectIamAdmin"
  member  = "serviceAccount:${google_service_account.stm_sa.email}"
}

# ------------------------------------------------
# Ops Agent — logging + metrics from the STM host

resource "google_project_iam_member" "stm_log_writer" {
  project = var.gcp_project
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.stm_sa.email}"
}

resource "google_project_iam_member" "stm_metric_writer" {
  project = var.gcp_project
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.stm_sa.email}"
}

# ------------------------------------------------
# GCS — read+write on releases, results, and compiler cache buckets.
# IAM conditions restrict the scope to those bucket names.

resource "google_project_iam_member" "stm_gcs_object_admin" {
  project = var.gcp_project
  role    = "roles/storage.objectAdmin"
  member  = "serviceAccount:${google_service_account.stm_sa.email}"

  condition {
    title       = "stm_managed_buckets"
    description = "Read+write on releases, results, and compiler cache buckets"
    expression  = <<-EOT
      resource.name.startsWith("projects/_/buckets/${var.releases_bucket}") ||
      resource.name.startsWith("projects/_/buckets/${var.results_bucket}") ||
      resource.name.startsWith("projects/_/buckets/${var.cache_bucket}")
    EOT
  }
}

# ------------------------------------------------
# GCS — read+write on the shared Terraform state bucket — needed because
# full_run.sh runs `terraform apply` against test-suite state from the STM.

resource "google_project_iam_member" "stm_tfstate_admin" {
  project = var.gcp_project
  role    = "roles/storage.objectAdmin"
  member  = "serviceAccount:${google_service_account.stm_sa.email}"

  condition {
    title       = "stm_tfstate_bucket_admin"
    description = "Read+write on shared Terraform state bucket (needed for terraform init/apply/destroy on the STM)"
    expression  = <<-EOT
      resource.name.startsWith("projects/_/buckets/tfstate-snarkos-stress-testing")
    EOT
  }
}

# ------------------------------------------------
# Storage — create/manage GCS buckets from test-suite Terraform.
#
# Currently only used when `create_compiler_cache_bucket=true` in the
# test-suite tfvars (default false; bucket exists out-of-band). Grant is
# broad rather than resource-conditioned so the flag can be flipped without
# further IAM changes. The existing `stm_gcs_object_admin` binding on
# releases/results/cache remains — it grants OBJECT-level access and stays
# in force whether or not this project-level grant is used.

resource "google_project_iam_member" "stm_storage_admin" {
  project = var.gcp_project
  role    = "roles/storage.admin"
  member  = "serviceAccount:${google_service_account.stm_sa.email}"
}

# ------------------------------------------------
# Secret Manager — Slack credentials.
#
# Pre-requisite: the secrets stress-testing-manager-slack-token and
# stress-testing-manager-slack-channel-id MUST exist in ${var.gcp_project}
# before terraform apply. Create them with:
#
#   echo -n "<xoxb-...>"    | gcloud secrets create stress-testing-manager-slack-token      \
#     --data-file=- --project=${var.gcp_project}
#   echo -n "<C0XXXXXXX>"   | gcloud secrets create stress-testing-manager-slack-channel-id \
#     --data-file=- --project=${var.gcp_project}
#
# See GCP_MIGRATION.md "Phase 4: Secret Manager Setup".

resource "google_secret_manager_secret_iam_member" "stm_slack_token" {
  project   = var.gcp_project
  secret_id = "stress-testing-manager-slack-token"
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.stm_sa.email}"
}

resource "google_secret_manager_secret_iam_member" "stm_slack_channel_id" {
  project   = var.gcp_project
  secret_id = "stress-testing-manager-slack-channel-id"
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.stm_sa.email}"
}
