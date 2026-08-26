# ------------------------------------------------
# Static external IP for the STM.
# Reserving a static IP means the STM keeps the same public address across
# stop/start / instance rebuilds, so users don't need to re-cache SSH host
# keys or update the IP in scripts.

resource "google_compute_address" "stm_ip" {
  name    = "${local.instance_name}-ip"
  region  = var.gcp_region
  project = var.gcp_project
}

# ------------------------------------------------
# Convenience IP file.
# Writes the STM's static external IP to ./stress-testing-manager-ip.txt in
# the terraform working directory. The file contains ONLY the raw IP address
# (no trailing newline) so external tooling can consume it with a simple
# `cat` — no `terraform output` shell-out required.

resource "local_file" "stm_ip" {
  filename        = "${path.module}/../../stress-testing-manager-ip.txt"
  content         = google_compute_address.stm_ip.address
  file_permission = "0644"
}

# ------------------------------------------------
# The Stress Testing Manager instance.
#
# - c3d-standard-4 (4 vCPU / 16 GB) on pd-ssd, size configurable.
# - OS Login enabled — all SSH access via IAM, no key files on disk.
# - `role=stress-testing-manager` in both metadata (for full_run.sh
#   detection via the metadata server) and labels (for logs/monitoring
#   filtering).

resource "google_compute_instance" "stm" {
  name         = local.instance_name
  machine_type = var.machine_type
  zone         = var.gcp_zone
  project      = var.gcp_project

  tags = [local.network_tag]

  labels = {
    role      = "stress-testing-manager"
    workspace = local.stm_workspace
    devnet    = "stress-testing-manager"
  }

  metadata = {
    role           = "stress-testing-manager"
    owner          = var.owner
    enable-oslogin = "TRUE"
  }

  boot_disk {
    initialize_params {
      image = data.google_compute_image.base.self_link
      size  = var.disk_size_gb
      type  = var.disk_type
    }
  }

  network_interface {
    subnetwork = module.network.subnet_self_links[var.gcp_region]

    access_config {
      nat_ip = google_compute_address.stm_ip.address
    }
  }

  service_account {
    email  = google_service_account.stm_sa.email
    scopes = ["cloud-platform"]
  }

  # Ensure all SA bindings are in place before the instance boots so
  # full_run.sh can use the attached SA immediately on first start.
  depends_on = [
    module.network,
    module.firewall,
    google_project_iam_member.stm_compute_admin,
    google_project_iam_member.stm_service_account_admin,
    google_project_iam_member.stm_project_iam_admin,
    google_project_iam_member.stm_storage_admin,
    google_project_iam_member.stm_tfstate_admin,
    google_project_iam_member.stm_oslogin,
    google_project_iam_member.stm_sauser,
  ]
}
