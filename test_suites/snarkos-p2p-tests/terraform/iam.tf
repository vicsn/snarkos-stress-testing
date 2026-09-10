# ------------------------------------------------
# Service Account for snarkOS EC2-equivalent instances

resource "google_service_account" "snarkos_sa" {
  account_id   = "${substr(lower(replace(var.owner, "/[^a-z0-9-]/", "-")), 0, 20)}-snarkos-sa"
  display_name = "SnarkOS Node Service Account (${var.owner})"
  project      = var.gcp_project
}

# ------------------------------------------------
# GCS access — release bucket (read + write for binary uploads/downloads)

resource "google_project_iam_member" "snarkos_gcs_object_viewer" {
  project = var.gcp_project
  role    = "roles/storage.objectViewer"
  member  = "serviceAccount:${google_service_account.snarkos_sa.email}"

  condition {
    title       = "release_bucket_only"
    description = "Restrict to the release bucket and compiler cache"
    expression  = <<-EOT
      resource.name.startsWith("projects/_/buckets/${var.release_bucket}") ||
      resource.name.startsWith("projects/_/buckets/${var.compiler_cache_bucket}") ||
      resource.name.startsWith("projects/_/buckets/provable-pregenerated-transactions")
    EOT
  }
}

resource "google_project_iam_member" "snarkos_gcs_object_creator" {
  project = var.gcp_project
  role    = "roles/storage.objectCreator"
  member  = "serviceAccount:${google_service_account.snarkos_sa.email}"

  condition {
    title       = "release_bucket_write"
    description = "Write access to release bucket and compiler cache"
    expression  = <<-EOT
      resource.name.startsWith("projects/_/buckets/${var.release_bucket}") ||
      resource.name.startsWith("projects/_/buckets/${var.compiler_cache_bucket}") ||
      resource.name.startsWith("projects/_/buckets/provable-pregenerated-transactions") ||
      resource.name.startsWith("projects/_/buckets/${data.terraform_remote_state.stm.outputs.results_bucket_name}")
    EOT
  }
}

# ------------------------------------------------
# OS Login — allow SA to use OS Login for SSH access

resource "google_project_iam_member" "snarkos_oslogin" {
  project = var.gcp_project
  role    = "roles/compute.osLogin"
  member  = "serviceAccount:${google_service_account.snarkos_sa.email}"
}

resource "google_project_iam_member" "snarkos_sauser" {
  project = var.gcp_project
  role    = "roles/iam.serviceAccountUser"
  member  = "serviceAccount:${google_service_account.snarkos_sa.email}"
}

# ------------------------------------------------
# Ops Agent — logging + metrics from snarkOS nodes

resource "google_project_iam_member" "snarkos_log_writer" {
  project = var.gcp_project
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.snarkos_sa.email}"
}

resource "google_project_iam_member" "snarkos_log_admin" {
  project = var.gcp_project
  role    = "roles/logging.admin"
  member  = "serviceAccount:${google_service_account.snarkos_sa.email}"
}

resource "google_project_iam_member" "snarkos_metric_writer" {
  project = var.gcp_project
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.snarkos_sa.email}"
}

# NOTE: not necessary
#
# resource "google_project_iam_member" "snarkos_osadminlogin" {
#   project = var.gcp_project
#   role    = "roles/compute.osAdminLogin"
#   member  = "serviceAccount:${google_service_account.snarkos_sa.email}"
# }

# NOTE: not necessary
#
# resource "google_project_iam_member" "snarkos_instanceadmin" {
#   project = var.gcp_project
#   role    = "roles/compute.instanceAdmin"
#   member  = "serviceAccount:${google_service_account.snarkos_sa.email}"
# }

# NOTE: not necessary
#
# resource "google_project_iam_member" "snarkos_instanceadminv1" {
#   project = var.gcp_project
#   role    = "roles/compute.instanceAdmin.v1"
#   member  = "serviceAccount:${google_service_account.snarkos_sa.email}"
# }


#TODO: fix secret accessesor resource
#
# # ------------------------------------------------
# # GCP Secret Manager access
#
# resource "google_project_iam_member" "snarkos_secret_accessor" {
#   project = var.gcp_project
#   role    = "roles/secretmanager.secretAccessor"
#   member  = "serviceAccount:${google_service_account.snarkos_sa.email}"
#
#   condition {
#     title       = "snarkos_secrets_only"
#     description = "Restrict to snarkos-stress-testing secrets"
#     expression  = "resource.name.extract(\"/secrets/([^/]+)\")[0].startsWith(\"snarkos-stress-testing\")"
#   }
# }

# ------------------------------------------------
# Project-level OS Login metadata
# Disabled — SSH access is controlled per-instance via local.ssh_metadata,
# which always sets enable-oslogin=FALSE and injects devnet-key.pub for
# var.ssh_user, plus var.ssh_public_key when set.

# ------------------------------------------------
# Admin Users - Compute and Monitoring Access

resource "google_project_iam_member" "admin_compute_viewer" {
  for_each = toset(var.admin_users)
  project  = var.gcp_project
  role     = "roles/compute.viewer"
  member   = length(regexall("^(user:|group:)", each.value)) > 0 ? each.value : "user:${each.value}"
}

resource "google_project_iam_member" "admin_logging_viewer" {
  for_each = toset(var.admin_users)
  project  = var.gcp_project
  role     = "roles/logging.viewer"
  member   = length(regexall("^(user:|group:)", each.value)) > 0 ? each.value : "user:${each.value}"
}

resource "google_project_iam_member" "admin_monitoring_viewer" {
  for_each = toset(var.admin_users)
  project  = var.gcp_project
  role     = "roles/monitoring.viewer"
  member   = length(regexall("^(user:|group:)", each.value)) > 0 ? each.value : "user:${each.value}"
}

resource "google_project_iam_member" "admin_compute_oslogin" {
  for_each = toset(var.admin_users)
  project  = var.gcp_project
  role     = "roles/compute.osLogin"
  member   = length(regexall("^(user:|group:)", each.value)) > 0 ? each.value : "user:${each.value}"
}

output "snarkos_service_account" {
  value       = google_service_account.snarkos_sa.email
  description = "Service Account email"
}


