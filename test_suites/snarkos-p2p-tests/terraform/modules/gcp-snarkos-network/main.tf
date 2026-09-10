# -----------------------------------------------------------------------------
#
# Create VPC
# https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_network
# https://cloud.google.com/vpc/docs/create-modify-vpc-networks#terraform_1
#
# -----------------------------------------------------------------------------

resource "google_compute_network" "vpc" {
  project                 = var.project_id
  name                    = var.vpc_name
  auto_create_subnetworks = false
}

# -----------------------------------------------------------------------------
#
# Create subnets
# https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_subnetwork
#
# -----------------------------------------------------------------------------

resource "google_compute_subnetwork" "subnets" {
  for_each = var.subnets

  name          = "${data.google_project.project.name}-subnet-${each.key}"
  ip_cidr_range = each.value.cidr
  region        = each.key
  network       = google_compute_network.vpc.id

  # log_config {
  #   aggregation_interval = "INTERVAL_5_SEC"
  #   flow_sampling        = 0.5
  #   metadata             = "INCLUDE_ALL_METADATA"
  # }
}

# ------------------------------------------------
#  Ops Agent Service Account and IAM (optional)
# ------------------------------------------------

resource "google_service_account" "ops_agent" {
  count        = var.enable_ops_agent_sa && var.ops_agent_service_account_email == "" ? 1 : 0
  account_id   = var.ops_agent_service_account_id
  display_name = "Ops Agent Service Account"
}

resource "google_project_iam_member" "ops_agent_monitoring_viewer" {
  count   = var.enable_ops_agent_sa ? 1 : 0
  project = var.project_id
  role    = "roles/monitoring.viewer"
  member  = "serviceAccount:${local.ops_agent_sa_email}"
}

resource "google_project_iam_member" "ops_agent_monitoring_alertpolicyviewer" {
  count   = var.enable_ops_agent_sa ? 1 : 0
  project = var.project_id
  role    = "roles/monitoring.alertPolicyViewer"
  member  = "serviceAccount:${local.ops_agent_sa_email}"
}

resource "google_project_iam_member" "ops_agent_logging_writer" {
  count   = var.enable_ops_agent_sa ? 1 : 0
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${local.ops_agent_sa_email}"
}

resource "google_project_iam_member" "ops_agent_metric_writer" {
  count   = var.enable_ops_agent_sa ? 1 : 0
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${local.ops_agent_sa_email}"
}

resource "google_project_iam_member" "ops_agent_trace_agent" {
  count   = var.enable_ops_agent_sa && var.ops_agent_enable_traces ? 1 : 0
  project = var.project_id
  role    = "roles/cloudtrace.agent"
  member  = "serviceAccount:${local.ops_agent_sa_email}"
}
